//
//  AppSchema.swift
//  TimeTracking
//
//  Versioned schema definitions and migration plan.
//  Add a new schema version here whenever an @Model property is added or changed.
//

import SwiftData

// MARK: - V1  (original — no mqttMessageFormat)

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [AppSchemaV1.AppSettings.self, TimeEntry.self]
    }

    @Model
    final class AppSettings {
        var defaultWorkingHours: Double = 8.0
        var officeLocationEnabled: Bool = false
        var officeLatitude: Double?
        var officeLongitude: Double?
        var mqttEnabled: Bool = false
        var mqttHost: String = ""
        var mqttPort: Int = 8883
        var mqttTopic: String = ""
        var mqttUseTLS: Bool = true

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
    }
}

// MARK: - V2  (adds mqttMessageFormat)

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [AppSettings.self, TimeEntry.self]
    }
}

// MARK: - Migration plan

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self]
    }
    static var stages: [MigrationStage] { [migrateV1toV2] }

    // Lightweight migration: SwiftData adds the new mqttMessageFormatRaw String column
    // and fills it with the property-level default ("default").
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self
    )
}
