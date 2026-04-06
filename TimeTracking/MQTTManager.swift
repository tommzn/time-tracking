//
//  MQTTManager.swift
//  TimeTracking
//
//  Pure-Swift MQTT 3.1.1 client built on Network.framework — no third-party packages.
//

import Foundation
import Network
import SwiftData
import SwiftUI
import Observation

// MARK: - Connection state

enum MQTTConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected:    "Not connected"
        case .connecting:      "Connecting…"
        case .connected:       "Connected"
        case .error(let msg):  msg
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected:  "wifi.slash"
        case .connecting:    "antenna.radiowaves.left.and.right"
        case .connected:     "checkmark.circle.fill"
        case .error:         "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .disconnected:  .secondary
        case .connecting:    .orange
        case .connected:     .green
        case .error:         .red
        }
    }
}

// MARK: - Manager

@Observable
final class MQTTManager {

    // MARK: Observable state

    var connectionState: MQTTConnectionState = .disconnected

    // MARK: Private

    @ObservationIgnored private var client: MQTTClient?
    @ObservationIgnored private var modelContainer: ModelContainer?

    // MARK: Setup

    func setup(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: Public control

    func updateConnection(for settings: AppSettings) {
        // Tear down any existing connection first.
        let old = client
        client = nil
        if let old { Task { await old.disconnect() } }

        guard settings.mqttEnabled, settings.hasMQTTConfiguration else {
            connectionState = .disconnected
            return
        }

        connectionState = .connecting
        let c = MQTTClient()
        client = c

        Task {
            await c.connect(
                host:     settings.mqttHost,
                port:     settings.mqttPort,
                topic:    settings.mqttTopic,
                username: KeychainStore.get(.mqttUsername),
                password: KeychainStore.get(.mqttPassword),
                useTLS:   settings.mqttUseTLS,
                onConnect: { [weak self] accepted in
                    Task { @MainActor [weak self] in
                        self?.connectionState = accepted ? .connected : .error("Broker refused connection")
                    }
                },
                onMessage: { [weak self] payload in
                    Task { @MainActor [weak self] in
                        self?.handlePayload(payload)
                    }
                },
                onDisconnect: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.connectionState = error.map { .error($0.localizedDescription) } ?? .disconnected
                    }
                }
            )
        }
    }

    func disconnect() {
        let old = client
        client = nil
        connectionState = .disconnected
        if let old { Task { await old.disconnect() } }
    }

    // MARK: Private

    private func handlePayload(_ payload: String) {
        guard let data      = payload.data(using: .utf8),
              let msg       = try? JSONDecoder().decode(IoTMessage.self, from: data),
              let type      = msg.entryType,
              let container = modelContainer else { return }
        let timestamp = ISO8601DateFormatter().date(from: msg.timestamp) ?? Date()
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        ctx.insert(TimeEntry(timestamp: timestamp, type: type))
        try? ctx.save()
    }
}

// MARK: - IoT message model

struct IoTMessage: Decodable {
    let action: String
    let timestamp: String

    var entryType: EntryType? {
        switch action {
        case "single_tap": .workingTime
        case "double_tap": .sickness
        case "long_tap":   .vacation
        default:           nil
        }
    }
}

// MARK: - Minimal MQTT 3.1.1 client (Network.framework)
//
// Implemented as a Swift actor so that all mutable state — including `buffer` —
// is guaranteed to be accessed on the actor's serial executor.  NWConnection
// delivers its callbacks on an arbitrary GCD queue; each callback hops back
// into the actor with `Task { await self.method() }`.

private actor MQTTClient {

    private var onConnect:    ((Bool) -> Void)?
    private var onMessage:    ((String) -> Void)?
    private var onDisconnect: ((Error?) -> Void)?

    private var connection: NWConnection?
    private var buffer:    [UInt8] = []   // [UInt8] always has startIndex == 0;
                                          // Data.removeFirst can produce a slice
                                          // with a non-zero internal offset,
                                          // making buffer[0] trap on bounds check.
    private var topic      = ""
    private var packetID:  UInt16 = 0
    private var pingTask:  Task<Void, Never>?

    // MARK: Connect

    func connect(host: String, port: Int, topic: String,
                 username: String?, password: String?, useTLS: Bool,
                 onConnect:    @escaping (Bool)    -> Void,
                 onMessage:    @escaping (String)  -> Void,
                 onDisconnect: @escaping (Error?)  -> Void) {
        self.onConnect    = onConnect
        self.onMessage    = onMessage
        self.onDisconnect = onDisconnect
        self.topic        = topic
        self.buffer       = []

        let params: NWParameters = useTLS ? .tls : .tcp
        let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? 1883
        let conn   = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            // Hop into actor isolation for all state access.
            Task {
                switch state {
                case .ready:
                    await self.handleReady(username: username, password: password)
                case .failed(let error):
                    await self.fireOnDisconnect(error)
                case .cancelled:
                    await self.fireOnDisconnect(nil)
                default:
                    break
                }
            }
        }
        conn.start(queue: .global(qos: .utility))
        connection = conn
    }

    // MARK: Disconnect

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        connection?.cancel()
        connection = nil
        buffer     = []
    }

    // MARK: Private — called inside actor

    private func handleReady(username: String?, password: String?) {
        sendConnect(username: username, password: password)
        receiveLoop()
    }

    private func fireOnDisconnect(_ error: Error?) {
        onDisconnect?(error)
    }

    private func receiveLoop() {
        guard let connection else { return }
        // Capture the current connection object so we can detect reconnects.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { await self.handleReceived(data: data, isComplete: isComplete, error: error, from: connection) }
        }
    }

    private func handleReceived(data: Data?, isComplete: Bool, error: Error?, from conn: NWConnection) {
        // Discard if a reconnect happened and `conn` is no longer current.
        guard connection === conn else { return }
        if let data { buffer.append(contentsOf: data) }
        processBuffer()
        if !isComplete && error == nil { receiveLoop() }
    }

    // MARK: Send CONNECT

    private func sendConnect(username: String?, password: String?) {
        // No clean-session flag (0x02 removed) → persistent session.
        // The broker queues QoS ≥ 1 messages while this client is offline
        // and delivers them on the next reconnect.
        var flags: UInt8 = 0x00
        if username != nil { flags |= 0x80 }
        if password != nil { flags |= 0x40 }

        // Stable client ID persisted across launches so the broker can
        // match this device to its stored session.
        let clientID = Self.stableClientID
        let varHeader = Data([0x00, 0x04, 0x4D, 0x51, 0x54, 0x54,  // "MQTT"
                              0x04, flags, 0x00, 0x3C])              // level + flags + keepalive 60 s
        var payload   = mqttStr(clientID)
        if let u = username { payload += mqttStr(u) }
        if let p = password { payload += mqttStr(p) }
        send(type: 0x10, body: varHeader + payload)
    }

    private static var stableClientID: String {
        let key = "mqtt.clientID"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let id = "TimeTracking-\(UUID().uuidString)"
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // MARK: Send SUBSCRIBE + start ping loop

    private func sendSubscribe() {
        packetID &+= 1
        if packetID == 0 { packetID = 1 }
        var body = Data([UInt8((packetID >> 8) & 0xFF), UInt8(packetID & 0xFF)])
        body += mqttStr(topic)
        body += Data([0x01])   // QoS 1 — broker queues messages while offline
        send(type: 0x82, body: body)

        // Keep-alive: send PINGREQ every 50 s using a Swift concurrency task
        // (avoids any RunLoop / GCD dependency).
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(50))
                guard !Task.isCancelled else { break }
                await self?.sendPing()
            }
        }
    }

    private func sendPing() {
        send(type: 0xC0, body: Data())
    }

    // MARK: Process inbound buffer

    private func processBuffer() {
        while buffer.count >= 2 {
            let headerByte: UInt8  = buffer[0]
            let packetType: UInt8  = headerByte & 0xF0

            // Decode variable-length remaining-length field (MQTT spec §2.2.3)
            var multiplier: Int = 1
            var remaining:  Int = 0
            var headerLen:  Int = 1     // counts the fixed-header type byte
            var decoded         = false
            for i in 1..<min(buffer.count, 5) {
                let b: Int = Int(buffer[i])
                remaining  += (b & 0x7F) * multiplier
                multiplier *= 128
                headerLen  += 1
                if b & 0x80 == 0 { decoded = true; break }
            }
            guard decoded else { return }   // need more bytes

            let total = headerLen + remaining
            guard total > 0, buffer.count >= total else { return }

            let body = Array(buffer[headerLen..<total])
            buffer.removeFirst(total)

            switch packetType {
            case 0x20:   // CONNACK
                let accepted = body.count >= 2 && body[1] == 0x00
                if accepted { sendSubscribe() }
                onConnect?(accepted)

            case 0x30:   // PUBLISH — QoS is in bits 2-1 of headerByte, not packetType
                guard body.count >= 2 else { break }
                let topicLen = Int(body[0]) << 8 | Int(body[1])
                guard body.count >= 2 + topicLen else { break }

                // Extract QoS from the original header byte (lower nibble, bits 2-1).
                let qos = (headerByte >> 1) & 0x03
                if qos >= 1 {
                    // QoS 1: send PUBACK containing the 2-byte packet identifier
                    // that immediately follows the topic name.
                    guard body.count >= 2 + topicLen + 2 else { break }
                    let pktHigh = body[2 + topicLen]
                    let pktLow  = body[2 + topicLen + 1]
                    send(type: 0x40, body: Data([pktHigh, pktLow]))
                }

                // Payload starts after topic (2 bytes length + topicLen bytes)
                // and, for QoS ≥ 1, an additional 2-byte packet identifier.
                let payloadStart = 2 + topicLen + (qos >= 1 ? 2 : 0)
                guard body.count >= payloadStart else { break }
                let payloadSlice = body[payloadStart...]
                if let str = String(bytes: payloadSlice, encoding: .utf8) {
                    onMessage?(str)
                }

            default: break   // SUBACK, PINGRESP, etc. — no action needed
            }
        }
    }

    // MARK: Helpers

    private func send(type: UInt8, body: Data) {
        var packet = Data([type])
        packet.append(contentsOf: encodeVarInt(body.count))
        packet.append(body)
        connection?.send(content: packet, completion: .idempotent)
    }

    private func mqttStr(_ s: String) -> Data {
        let b = Data(s.utf8)
        return Data([UInt8((b.count >> 8) & 0xFF), UInt8(b.count & 0xFF)]) + b
    }

    private func encodeVarInt(_ n: Int) -> [UInt8] {
        var x = n, out: [UInt8] = []
        repeat {
            var byte = UInt8(x % 128)
            x /= 128
            if x > 0 { byte |= 0x80 }
            out.append(byte)
        } while x > 0
        return out
    }
}
