//
//  SettingsStore.swift
//  TimeTracking
//

import Foundation
import SwiftData

final class SettingsStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Load

    /// Returns the single AppSettings record, creating it with defaults if absent.
    func loadOrCreate() throws -> AppSettings {
        let existing = try modelContext.fetch(FetchDescriptor<AppSettings>())
        if let settings = existing.first {
            return settings
        }
        let settings = AppSettings()
        modelContext.insert(settings)
        try modelContext.save()
        return settings
    }

    // MARK: - Save

    func save() throws {
        try modelContext.save()
    }
}
