//
//  AppSettingsTests.swift
//  TimeTrackingTests
//

import Testing
import SwiftData
import Foundation
@testable import TimeTracking

struct AppSettingsTests {

    private func makeStore() throws -> SettingsStore {
        let config    = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSettings.self, configurations: config)
        return SettingsStore(modelContext: ModelContext(container))
    }

    // MARK: - Default values

    @Test func loadOrCreateReturnsDefaultWorkingHours() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        #expect(settings.defaultWorkingHours == 8.0)
    }

    @Test func loadOrCreateDefaultsOfficeLocationDisabled() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        #expect(settings.officeLocationEnabled == false)
    }

    @Test func loadOrCreateDefaultsCoordinatesToNil() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        #expect(settings.officeLatitude  == nil)
        #expect(settings.officeLongitude == nil)
    }

    @Test func hasOfficeLocationFalseWithNoCoordinates() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        #expect(settings.hasOfficeLocation == false)
    }

    // MARK: - Singleton behaviour

    @Test func loadOrCreateReturnsSameRecordOnSubsequentCalls() throws {
        let store = try makeStore()
        let first  = try store.loadOrCreate()
        let second = try store.loadOrCreate()
        #expect(first === second)
    }

    @Test func loadOrCreateDoesNotDuplicateRecord() throws {
        let config    = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSettings.self, configurations: config)
        let context   = ModelContext(container)
        let store     = SettingsStore(modelContext: context)

        _ = try store.loadOrCreate()
        _ = try store.loadOrCreate()
        _ = try store.loadOrCreate()

        let all = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(all.count == 1)
    }

    // MARK: - Working hours

    @Test func updatedWorkingHoursPersist() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        settings.defaultWorkingHours = 7.5
        try store.save()

        let reloaded = try store.loadOrCreate()
        #expect(reloaded.defaultWorkingHours == 7.5)
    }

    @Test func workingHoursCanBeSetToPartialHour() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        settings.defaultWorkingHours = 6.0
        try store.save()
        #expect(try store.loadOrCreate().defaultWorkingHours == 6.0)
    }

    // MARK: - Office location

    @Test func setOfficeLocationStoresCoordinates() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        settings.setOfficeLocation(latitude: 48.1351, longitude: 11.5820)
        try store.save()

        let reloaded = try store.loadOrCreate()
        #expect(reloaded.officeLatitude  == 48.1351)
        #expect(reloaded.officeLongitude == 11.5820)
    }

    @Test func hasOfficeLocationTrueAfterSettingCoordinates() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        settings.setOfficeLocation(latitude: 48.1351, longitude: 11.5820)
        #expect(settings.hasOfficeLocation == true)
    }

    @Test func enableOfficeLocationPersists() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        settings.setOfficeLocation(latitude: 48.1351, longitude: 11.5820)
        settings.officeLocationEnabled = true
        try store.save()

        let reloaded = try store.loadOrCreate()
        #expect(reloaded.officeLocationEnabled == true)
    }

    @Test func clearOfficeLocationRemovesCoordinates() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        settings.setOfficeLocation(latitude: 48.1351, longitude: 11.5820)
        settings.officeLocationEnabled = true
        settings.clearOfficeLocation()
        try store.save()

        let reloaded = try store.loadOrCreate()
        #expect(reloaded.officeLatitude        == nil)
        #expect(reloaded.officeLongitude       == nil)
        #expect(reloaded.officeLocationEnabled == false)
        #expect(reloaded.hasOfficeLocation     == false)
    }

    @Test func settingLocationDoesNotAutoEnableDetection() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        settings.setOfficeLocation(latitude: 48.1351, longitude: 11.5820)
        // Coordinates stored but detection must be explicitly enabled
        #expect(settings.officeLocationEnabled == false)
    }

    // MARK: - MQTT defaults

    @Test func loadOrCreateDefaultsMQTTDisabled() throws {
        let settings = try makeStore().loadOrCreate()
        #expect(settings.mqttEnabled == false)
    }

    @Test func loadOrCreateDefaultsMQTTPort() throws {
        let settings = try makeStore().loadOrCreate()
        #expect(settings.mqttPort == 8883)
    }

    @Test func loadOrCreateDefaultsMQTTTLSEnabled() throws {
        let settings = try makeStore().loadOrCreate()
        #expect(settings.mqttUseTLS == true)
    }

    @Test func loadOrCreateDefaultsMQTTHostEmpty() throws {
        let settings = try makeStore().loadOrCreate()
        #expect(settings.mqttHost.isEmpty)
    }

    @Test func loadOrCreateDefaultsMQTTTopicEmpty() throws {
        let settings = try makeStore().loadOrCreate()
        #expect(settings.mqttTopic.isEmpty)
    }

    // MARK: - hasMQTTConfiguration

    @Test func hasMQTTConfigurationFalseByDefault() throws {
        let settings = try makeStore().loadOrCreate()
        #expect(settings.hasMQTTConfiguration == false)
    }

    @Test func hasMQTTConfigurationTrueWhenHostAndTopicSet() throws {
        let settings = try makeStore().loadOrCreate()
        settings.mqttHost  = "broker.example.com"
        settings.mqttTopic = "time/events"
        #expect(settings.hasMQTTConfiguration == true)
    }

    @Test func hasMQTTConfigurationFalseWhenOnlyHostSet() throws {
        let settings = try makeStore().loadOrCreate()
        settings.mqttHost = "broker.example.com"
        #expect(settings.hasMQTTConfiguration == false)
    }

    @Test func hasMQTTConfigurationFalseWhenOnlyTopicSet() throws {
        let settings = try makeStore().loadOrCreate()
        settings.mqttTopic = "time/events"
        #expect(settings.hasMQTTConfiguration == false)
    }

    // MARK: - MQTT persistence

    @Test func mqttSettingsPersist() throws {
        let store = try makeStore()
        let settings = try store.loadOrCreate()
        settings.mqttEnabled = true
        settings.mqttHost    = "broker.example.com"
        settings.mqttPort    = 1883
        settings.mqttTopic   = "time/events"
        settings.mqttUseTLS  = false
        try store.save()

        let reloaded = try store.loadOrCreate()
        #expect(reloaded.mqttEnabled == true)
        #expect(reloaded.mqttHost    == "broker.example.com")
        #expect(reloaded.mqttPort    == 1883)
        #expect(reloaded.mqttTopic   == "time/events")
        #expect(reloaded.mqttUseTLS  == false)
    }

    @Test func canUpdateCoordinatesWithoutChangingEnabledFlag() throws {
        let store    = try makeStore()
        let settings = try store.loadOrCreate()
        settings.setOfficeLocation(latitude: 48.1351, longitude: 11.5820)
        settings.officeLocationEnabled = true
        settings.setOfficeLocation(latitude: 52.5200, longitude: 13.4050)
        try store.save()

        let reloaded = try store.loadOrCreate()
        #expect(reloaded.officeLatitude        == 52.5200)
        #expect(reloaded.officeLongitude       == 13.4050)
        #expect(reloaded.officeLocationEnabled == true)
    }
}
