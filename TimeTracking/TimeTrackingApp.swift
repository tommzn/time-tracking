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
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            sharedModelContainer = container
            locationManager = LocationManager()
            locationManager.setup(modelContainer: container)
            mqttManager = MQTTManager()
            mqttManager.setup(modelContainer: container)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
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
