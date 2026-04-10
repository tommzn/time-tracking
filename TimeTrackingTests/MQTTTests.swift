//
//  MQTTTests.swift
//  TimeTrackingTests
//

import Testing
import SwiftUI
@testable import TimeTracking

// MARK: - IoTMessage action mapping

struct IoTMessageTests {

    @Test func singleTapMapsToWorkingTime() {
        let msg = IoTMessage(action: "single_tap", timestamp: "2026-04-04T10:00:00Z")
        #expect(msg.entryType == .workingTime)
    }

    @Test func doubleTapMapsToSickness() {
        let msg = IoTMessage(action: "double_tap", timestamp: "2026-04-04T10:00:00Z")
        #expect(msg.entryType == .sickness)
    }

    @Test func longTapMapsToVacation() {
        let msg = IoTMessage(action: "long_tap", timestamp: "2026-04-04T10:00:00Z")
        #expect(msg.entryType == .vacation)
    }

    @Test func unknownActionReturnsNil() {
        let msg = IoTMessage(action: "triple_tap", timestamp: "2026-04-04T10:00:00Z")
        #expect(msg.entryType == nil)
    }

    @Test func emptyActionReturnsNil() {
        let msg = IoTMessage(action: "", timestamp: "2026-04-04T10:00:00Z")
        #expect(msg.entryType == nil)
    }

    @Test func decodesFromJSON() throws {
        let json = #"{"action":"single_tap","timestamp":"2026-04-04T10:04:39Z"}"#
        let msg = try JSONDecoder().decode(IoTMessage.self, from: Data(json.utf8))
        #expect(msg.action == "single_tap")
        #expect(msg.timestamp == "2026-04-04T10:04:39Z")
        #expect(msg.entryType == .workingTime)
    }

    @Test func allActionsDecodeCorrectly() throws {
        let cases: [(String, EntryType)] = [
            ("single_tap", .workingTime),
            ("double_tap", .sickness),
            ("long_tap",   .vacation),
        ]
        for (action, expected) in cases {
            let json = "{\"action\":\"\(action)\",\"timestamp\":\"2026-01-01T00:00:00Z\"}"
            let msg = try JSONDecoder().decode(IoTMessage.self, from: Data(json.utf8))
            #expect(msg.entryType == expected)
        }
    }
}

// MARK: - SeedStudioIoTMessage action mapping

struct SeedStudioIoTMessageTests {

    @Test func singlePressMapsToWorkingTime() {
        let msg = SeedStudioIoTMessage(action: "single_press", time: "2026-04-09T23:53:10.215566+02:00")
        #expect(msg.entryType == .workingTime)
    }

    @Test func doublePressMapsToSickness() {
        let msg = SeedStudioIoTMessage(action: "double_press", time: "2026-04-09T23:53:10.215566+02:00")
        #expect(msg.entryType == .sickness)
    }

    @Test func longPressMapsToVacation() {
        let msg = SeedStudioIoTMessage(action: "long_press", time: "2026-04-09T23:53:10.215566+02:00")
        #expect(msg.entryType == .vacation)
    }

    @Test func unknownActionReturnsNil() {
        let msg = SeedStudioIoTMessage(action: "triple_press", time: "2026-04-09T23:53:10.215566+02:00")
        #expect(msg.entryType == nil)
    }

    @Test func emptyActionReturnsNil() {
        let msg = SeedStudioIoTMessage(action: "", time: "2026-04-09T23:53:10.215566+02:00")
        #expect(msg.entryType == nil)
    }

    @Test func decodesFromJSON() throws {
        let json = #"{"action":"double_press","entity_id":"switch.iot_button_v2_switch_2","time":"2026-04-09T23:53:10.215566+02:00"}"#
        let msg = try JSONDecoder().decode(SeedStudioIoTMessage.self, from: Data(json.utf8))
        #expect(msg.action == "double_press")
        #expect(msg.time == "2026-04-09T23:53:10.215566+02:00")
        #expect(msg.entryType == .sickness)
    }

    @Test func allActionsDecodeCorrectly() throws {
        let cases: [(String, EntryType)] = [
            ("single_press", .workingTime),
            ("double_press", .sickness),
            ("long_press",   .vacation),
        ]
        for (action, expected) in cases {
            let json = "{\"action\":\"\(action)\",\"time\":\"2026-04-09T23:53:10.215566+02:00\"}"
            let msg = try JSONDecoder().decode(SeedStudioIoTMessage.self, from: Data(json.utf8))
            #expect(msg.entryType == expected)
        }
    }
}

// MARK: - MQTTMessageFormat

struct MQTTMessageFormatTests {

    @Test func defaultLabel() {
        #expect(MQTTMessageFormat.default.label == "Default")
    }

    @Test func seedStudioLabel() {
        #expect(MQTTMessageFormat.seedStudioIoTButtonV2.label == "Seeed Studio IoT Button V2")
    }

    @Test func rawValues() {
        #expect(MQTTMessageFormat.default.rawValue == "default")
        #expect(MQTTMessageFormat.seedStudioIoTButtonV2.rawValue == "seedStudioIoTButtonV2")
    }
}

// MARK: - MQTTConnectionState labels and images

struct MQTTConnectionStateTests {

    @Test func disconnectedLabel() {
        #expect(MQTTConnectionState.disconnected.label == "Not connected")
    }

    @Test func connectingLabel() {
        #expect(MQTTConnectionState.connecting.label == "Connecting…")
    }

    @Test func connectedLabel() {
        #expect(MQTTConnectionState.connected.label == "Connected")
    }

    @Test func errorLabelContainsMessage() {
        #expect(MQTTConnectionState.error("timeout").label == "timeout")
    }

    @Test func disconnectedSystemImage() {
        #expect(MQTTConnectionState.disconnected.systemImage == "wifi.slash")
    }

    @Test func connectingSystemImage() {
        #expect(MQTTConnectionState.connecting.systemImage == "antenna.radiowaves.left.and.right")
    }

    @Test func connectedSystemImage() {
        #expect(MQTTConnectionState.connected.systemImage == "checkmark.circle.fill")
    }

    @Test func errorSystemImage() {
        #expect(MQTTConnectionState.error("x").systemImage == "xmark.circle.fill")
    }

    @Test func disconnectedColor() {
        #expect(MQTTConnectionState.disconnected.color == Color.secondary)
    }

    @Test func connectingColor() {
        #expect(MQTTConnectionState.connecting.color == Color.orange)
    }

    @Test func connectedColor() {
        #expect(MQTTConnectionState.connected.color == Color.green)
    }

    @Test func errorColor() {
        #expect(MQTTConnectionState.error("x").color == Color.red)
    }
}

// MARK: - MQTTManager state transitions

struct MQTTManagerTests {

    @Test func initialStateIsDisconnected() {
        let manager = MQTTManager()
        #expect(manager.connectionState == .disconnected)
    }

    @Test func disconnectSetsStateToDisconnected() {
        let manager = MQTTManager()
        manager.connectionState = .connecting
        manager.disconnect()
        #expect(manager.connectionState == .disconnected)
    }

    @Test func updateConnectionWithMQTTDisabledSetsDisconnected() {
        let settings = AppSettings(mqttEnabled: false, mqttHost: "broker.test", mqttTopic: "t")
        let manager = MQTTManager()
        manager.connectionState = .connected
        manager.updateConnection(for: settings)
        #expect(manager.connectionState == .disconnected)
    }

    @Test func updateConnectionWithNoHostSetsDisconnected() {
        // mqttHost is empty → hasMQTTConfiguration = false
        let settings = AppSettings(mqttEnabled: true, mqttHost: "", mqttTopic: "t")
        let manager = MQTTManager()
        manager.updateConnection(for: settings)
        #expect(manager.connectionState == .disconnected)
    }

    @Test func updateConnectionWithNoTopicSetsDisconnected() {
        let settings = AppSettings(mqttEnabled: true, mqttHost: "broker.test", mqttTopic: "")
        let manager = MQTTManager()
        manager.updateConnection(for: settings)
        #expect(manager.connectionState == .disconnected)
    }

    @Test func updateConnectionWithValidConfigSetsConnecting() {
        let settings = AppSettings(mqttEnabled: true, mqttHost: "broker.test", mqttTopic: "t")
        let manager = MQTTManager()
        manager.updateConnection(for: settings)
        #expect(manager.connectionState == .connecting)
    }
}
