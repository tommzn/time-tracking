//
//  TimeEntryTests.swift
//  TimeTrackingTests
//

import Testing
import SwiftData
import Foundation
@testable import TimeTracking

struct TimeEntryTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TimeEntry.self, configurations: config)
        return ModelContext(container)
    }

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    // MARK: - Insert & Fetch

    @Test func insertAndFetchEntry() throws {
        let context = try makeContext()
        let entry = TimeEntry(timestamp: Date(), type: .workingTime, location: .homeOffice)
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(fetched.count == 1)
        #expect(fetched[0].type == .workingTime)
        #expect(fetched[0].location == .homeOffice)
    }

    @Test func timestampIsPreserved() throws {
        let context = try makeContext()
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(TimeEntry(timestamp: ts, type: .workingTime, location: .office))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(fetched[0].timestamp == ts)
    }

    // MARK: - Location Rules

    @Test func locationNilForSickness() {
        let entry = TimeEntry(timestamp: Date(), type: .sickness, location: .office)
        #expect(entry.location == nil)
    }

    @Test func locationNilForVacation() {
        let entry = TimeEntry(timestamp: Date(), type: .vacation, location: .homeOffice)
        #expect(entry.location == nil)
    }

    @Test func locationPreservedForWorkingTime() {
        let home = TimeEntry(timestamp: Date(), type: .workingTime, location: .homeOffice)
        #expect(home.location == .homeOffice)

        let office = TimeEntry(timestamp: Date(), type: .workingTime, location: .office)
        #expect(office.location == .office)
    }

    // MARK: - Multiple Entries Per Day

    @Test func multipleEntriesPerDay() throws {
        let context = try makeContext()
        let base = Date()

        let timestamps = [
            base,
            base.addingTimeInterval(3600),   // +1h
            base.addingTimeInterval(7200),   // +2h
        ]
        for ts in timestamps {
            context.insert(TimeEntry(timestamp: ts, type: .workingTime, location: .office))
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(fetched.count == 3)
    }

    // MARK: - Query By Day

    @Test func queryByDayReturnsOnlyThatDay() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        context.insert(TimeEntry(timestamp: today.addingTimeInterval(3600),     type: .workingTime, location: .office))
        context.insert(TimeEntry(timestamp: today.addingTimeInterval(7200),     type: .workingTime, location: .homeOffice))
        context.insert(TimeEntry(timestamp: yesterday.addingTimeInterval(3600), type: .sickness))
        context.insert(TimeEntry(timestamp: tomorrow.addingTimeInterval(3600),  type: .vacation))
        try context.save()

        let (start, end) = dayBounds(for: today)
        let predicate = #Predicate<TimeEntry> { $0.timestamp >= start && $0.timestamp < end }
        let result = try context.fetch(FetchDescriptor<TimeEntry>(predicate: predicate))

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.type == .workingTime })
    }

    @Test func queryByDayWithNoEntries() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: Date())
        let (start, end) = dayBounds(for: today)

        let predicate = #Predicate<TimeEntry> { $0.timestamp >= start && $0.timestamp < end }
        let result = try context.fetch(FetchDescriptor<TimeEntry>(predicate: predicate))

        #expect(result.isEmpty)
    }

    @Test func queryByDaySortedByTimestamp() throws {
        let context = try makeContext()
        let base = Calendar.current.startOfDay(for: Date())

        // Insert out of order
        context.insert(TimeEntry(timestamp: base.addingTimeInterval(7200), type: .workingTime, location: .office))
        context.insert(TimeEntry(timestamp: base.addingTimeInterval(1800), type: .workingTime, location: .homeOffice))
        context.insert(TimeEntry(timestamp: base.addingTimeInterval(3600), type: .sickness))
        try context.save()

        let (start, end) = dayBounds(for: base)
        let predicate = #Predicate<TimeEntry> { $0.timestamp >= start && $0.timestamp < end }
        var descriptor = FetchDescriptor<TimeEntry>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        let result = try context.fetch(descriptor)

        #expect(result.count == 3)
        #expect(result[0].timestamp < result[1].timestamp)
        #expect(result[1].timestamp < result[2].timestamp)
    }

    // MARK: - Delete

    @Test func deleteEntry() throws {
        let context = try makeContext()
        let entry = TimeEntry(timestamp: Date(), type: .workingTime, location: .office)
        context.insert(entry)
        try context.save()

        context.delete(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(fetched.isEmpty)
    }
}
