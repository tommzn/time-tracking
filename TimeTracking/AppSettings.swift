//
//  AppSettings.swift
//  TimeTracking
//

import Foundation
import SwiftData

/// Single-record settings model. Always access through SettingsStore,
/// which guarantees exactly one instance exists in the container.
@Model
final class AppSettings {

    /// Default working hours per day (e.g. 8.0).
    var defaultWorkingHours: Double = 8.0

    /// Whether automatic office-location detection is active.
    var officeLocationEnabled: Bool = false

    /// Geographic coordinates of the office. Both are nil when no location is set.
    var officeLatitude: Double?
    var officeLongitude: Double?

    /// Whether the MQTT IoT source is active.
    var mqttEnabled: Bool = false
    /// MQTT broker hostname (e.g. "xxx.s2.eu.hivemq.cloud").
    var mqttHost: String = ""
    /// MQTT broker port (1883 plain, 8883 TLS).
    var mqttPort: Int = 8883
    /// Topic the device publishes time events to.
    var mqttTopic: String = ""
    var mqttUseTLS: Bool = true
    // Credentials are stored in the keychain via KeychainStore, not here.

    init(
        defaultWorkingHours: Double = 8.0,
        officeLocationEnabled: Bool = false,
        officeLatitude: Double? = nil,
        officeLongitude: Double? = nil,
        mqttEnabled: Bool = false,
        mqttHost: String = "",
        mqttPort: Int = 8883,
        mqttTopic: String = "",
        mqttUseTLS: Bool = true
    ) {
        self.defaultWorkingHours   = defaultWorkingHours
        self.officeLocationEnabled = officeLocationEnabled
        self.officeLatitude        = officeLatitude
        self.officeLongitude       = officeLongitude
        self.mqttEnabled           = mqttEnabled
        self.mqttHost              = mqttHost
        self.mqttPort              = mqttPort
        self.mqttTopic             = mqttTopic
        self.mqttUseTLS            = mqttUseTLS
    }

    /// True only when both coordinates are present.
    var hasOfficeLocation: Bool {
        officeLatitude != nil && officeLongitude != nil
    }

    /// True when the minimum MQTT fields (host + topic) are filled in.
    var hasMQTTConfiguration: Bool {
        !mqttHost.isEmpty && !mqttTopic.isEmpty
    }

    /// Set or replace the office coordinates.
    func setOfficeLocation(latitude: Double, longitude: Double) {
        officeLatitude  = latitude
        officeLongitude = longitude
    }

    /// Clear stored coordinates and disable location detection.
    func clearOfficeLocation() {
        officeLatitude         = nil
        officeLongitude        = nil
        officeLocationEnabled  = false
    }
}
