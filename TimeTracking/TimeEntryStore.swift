//
//  TimeEntryStore.swift
//  TimeTracking
//

import Foundation
import SwiftData

final class TimeEntryStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch

    func entries(for date: Date) throws -> [TimeEntry] {
        let (start, end) = dayBounds(for: date)
        let predicate = #Predicate<TimeEntry> { $0.timestamp >= start && $0.timestamp < end }
        let descriptor = FetchDescriptor<TimeEntry>(predicate: predicate, sortBy: [SortDescriptor(\.timestamp)])
        return try modelContext.fetch(descriptor)
    }

    func entries(forMonth month: Date) throws -> [TimeEntry] {
        let start = Calendar.current.startOfMonth(for: month)
        let end   = Calendar.current.date(byAdding: .month, value: 1, to: start)!
        let predicate = #Predicate<TimeEntry> { $0.timestamp >= start && $0.timestamp < end }
        let descriptor = FetchDescriptor<TimeEntry>(predicate: predicate, sortBy: [SortDescriptor(\.timestamp)])
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Write

    func add(timestamp: Date, type: EntryType, location: WorkLocation? = nil) throws {
        modelContext.insert(TimeEntry(timestamp: timestamp, type: type, location: location))
        try modelContext.save()
    }

    func delete(_ entry: TimeEntry) throws {
        modelContext.delete(entry)
        try modelContext.save()
    }

    // MARK: - Private

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let start = Calendar.current.startOfDay(for: date)
        return (start, Calendar.current.date(byAdding: .day, value: 1, to: start)!)
    }
}
