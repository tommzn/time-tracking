//
//  TimeTrackingApp.swift
//  TimeTracking
//
//  Created by Thomas Schenker on 03.04.26.
//

import SwiftUI
import SwiftData

@main
struct TimeTrackingApp: App {
    let sharedModelContainer: ModelContainer
    let locationManager: LocationManager
    let mqttManager: MQTTManager

    init() {
        let schema = Schema([
            TimeEntry.self,
            AppSettings.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.de.tommzn.TimeTracking")
        )
        func makeContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [modelConfiguration])
        }

        let container: ModelContainer
        do {
            container = try makeContainer()
        } catch {
            // The local SQLite store couldn't be opened or migrated (typically after
            // a schema change in an update that predates versioned migrations).
            // Because all records are backed by CloudKit, it is safe to delete the
            // local cache and let it re-sync from iCloud on the next open.
            let storeURL = modelConfiguration.url
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
            }
            do {
                container = try makeContainer()
            } catch {
                fatalError("Could not create ModelContainer after store reset: \(error)")
            }
        }

        sharedModelContainer = container
        locationManager = LocationManager()
        locationManager.setup(modelContainer: container)
        mqttManager = MQTTManager()
        mqttManager.setup(modelContainer: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationManager)
                .environment(mqttManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
