//
//  TimeEntryStoreTests.swift
//  TimeTrackingTests
//

import Testing
import SwiftData
import Foundation
@testable import TimeTracking

struct TimeEntryStoreTests {

    private func makeStore() throws -> TimeEntryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TimeEntry.self, configurations: config)
        return TimeEntryStore(modelContext: ModelContext(container))
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: - Fetch by day

    @Test func fetchReturnsEntriesForGivenDay() throws {
        let store = try makeStore()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        try store.add(timestamp: today.addingTimeInterval(3600),     type: .workingTime, location: .office)
        try store.add(timestamp: today.addingTimeInterval(7200),     type: .workingTime, location: .homeOffice)
        try store.add(timestamp: yesterday.addingTimeInterval(3600), type: .sickness)

        let result = try store.entries(for: today)
        #expect(result.count == 2)
        #expect(result.allSatisfy { Calendar.current.isDate($0.timestamp, inSameDayAs: today) })
    }

    @Test func fetchReturnsEmptyForDayWithNoEntries() throws {
        let store = try makeStore()
        let result = try store.entries(for: today)
        #expect(result.isEmpty)
    }

    @Test func fetchResultsSortedByTimestamp() throws {
        let store = try makeStore()
        try store.add(timestamp: today.addingTimeInterval(7200), type: .workingTime, location: .office)
        try store.add(timestamp: today.addingTimeInterval(1800), type: .workingTime, location: .homeOffice)
        try store.add(timestamp: today.addingTimeInterval(3600), type: .sickness)

        let result = try store.entries(for: today)
        #expect(result.count == 3)
        #expect(result[0].timestamp <= result[1].timestamp)
        #expect(result[1].timestamp <= result[2].timestamp)
    }

    // MARK: - Add

    @Test func addPersistsEntry() throws {
        let store = try makeStore()
        try store.add(timestamp: today, type: .vacation)

        let result = try store.entries(for: today)
        #expect(result.count == 1)
        #expect(result[0].type == .vacation)
        #expect(result[0].location == nil)
    }

    @Test func addWorkingTimeWithLocation() throws {
        let store = try makeStore()
        try store.add(timestamp: today, type: .workingTime, location: .homeOffice)

        let result = try store.entries(for: today)
        #expect(result[0].location == .homeOffice)
    }

    @Test func addMultipleEntriesOnSameDay() throws {
        let store = try makeStore()
        for i in 0..<5 {
            try store.add(timestamp: today.addingTimeInterval(Double(i) * 1800), type: .workingTime, location: .office)
        }
        #expect(try store.entries(for: today).count == 5)
    }

    // MARK: - Day boundaries

    @Test func fetchIncludesEntryAtStartOfDay() throws {
        let store = try makeStore()
        // Exactly at midnight = start of day — must be included
        try store.add(timestamp: today, type: .sickness)

        let result = try store.entries(for: today)
        #expect(result.count == 1)
    }

    @Test func fetchIncludesEntryOneSecondBeforeEndOfDay() throws {
        let store = try makeStore()
        let lastSecond = today.addingTimeInterval(24 * 3600 - 1)
        try store.add(timestamp: lastSecond, type: .vacation)

        let result = try store.entries(for: today)
        #expect(result.count == 1)
    }

    @Test func fetchExcludesEntryAtStartOfNextDay() throws {
        let store = try makeStore()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        try store.add(timestamp: tomorrow, type: .workingTime, location: .office)

        let result = try store.entries(for: today)
        #expect(result.isEmpty)
    }

    @Test func fetchIsolatesAdjacentDays() throws {
        let store = try makeStore()
        let calendar = Calendar.current
        let yesterday  = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow   = calendar.date(byAdding: .day, value:  1, to: today)!

        try store.add(timestamp: yesterday.addingTimeInterval(3600), type: .sickness)
        try store.add(timestamp: today.addingTimeInterval(3600),     type: .workingTime, location: .office)
        try store.add(timestamp: tomorrow.addingTimeInterval(3600),  type: .vacation)

        #expect(try store.entries(for: yesterday).count == 1)
        #expect(try store.entries(for: today).count    == 1)
        #expect(try store.entries(for: tomorrow).count == 1)
    }

    // MARK: - Location enforcement via store

    @Test func addSicknessIgnoresSuppliedLocation() throws {
        let store = try makeStore()
        try store.add(timestamp: today, type: .sickness, location: .office)

        let entry = try #require(try store.entries(for: today).first)
        #expect(entry.location == nil)
    }

    @Test func addVacationIgnoresSuppliedLocation() throws {
        let store = try makeStore()
        try store.add(timestamp: today, type: .vacation, location: .homeOffice)

        let entry = try #require(try store.entries(for: today).first)
        #expect(entry.location == nil)
    }

    @Test func addWorkingTimeWithNoLocationStoredAsNil() throws {
        let store = try makeStore()
        try store.add(timestamp: today, type: .workingTime)

        let entry = try #require(try store.entries(for: today).first)
        #expect(entry.location == nil)
    }

    // MARK: - All entry types

    @Test func allEntryTypesCanBeAdded() throws {
        let store = try makeStore()
        let calendar = Calendar.current

        for (offset, type) in EntryType.allCases.enumerated() {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            try store.add(timestamp: day, type: type)
        }

        for (offset, type) in EntryType.allCases.enumerated() {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let entries = try store.entries(for: day)
            #expect(entries.count == 1)
            #expect(entries[0].type == type)
        }
    }

    // MARK: - Fetch by month

    @Test func fetchByMonthReturnsAllEntriesInThatMonth() throws {
        let store = try makeStore()
        let cal = Calendar.current
        let jan = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        for day in [1, 15, 31] {
            let ts = cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: 9))!
            try store.add(timestamp: ts, type: .workingTime, location: .office)
        }

        let result = try store.entries(forMonth: jan)
        #expect(result.count == 3)
    }

    @Test func fetchByMonthExcludesEntryInPreviousMonth() throws {
        let store = try makeStore()
        let cal = Calendar.current
        let jan = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let dec31 = cal.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 9))!

        try store.add(timestamp: dec31, type: .workingTime, location: .office)

        #expect(try store.entries(forMonth: jan).isEmpty)
    }

    @Test func fetchByMonthExcludesEntryInNextMonth() throws {
        let store = try makeStore()
        let cal = Calendar.current
        let jan = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let feb1 = cal.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 9))!

        try store.add(timestamp: feb1, type: .workingTime, location: .office)

        #expect(try store.entries(forMonth: jan).isEmpty)
    }

    @Test func fetchByMonthIncludesEntryOnFirstDayOfMonth() throws {
        let store = try makeStore()
        let jan = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0))!

        try store.add(timestamp: jan, type: .sickness)

        #expect(try store.entries(forMonth: jan).count == 1)
    }

    @Test func fetchByMonthIncludesEntryOnLastDayOfMonth() throws {
        let store = try makeStore()
        let jan = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let jan31 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 23, minute: 59))!

        try store.add(timestamp: jan31, type: .vacation)

        #expect(try store.entries(forMonth: jan).count == 1)
    }

    @Test func fetchByMonthReturnsEmptyForMonthWithNoEntries() throws {
        let store = try makeStore()
        let jan = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        #expect(try store.entries(forMonth: jan).isEmpty)
    }

    // MARK: - Delete

    @Test func deleteRemovesEntry() throws {
        let store = try makeStore()
        try store.add(timestamp: today, type: .sickness)

        let entry = try #require(try store.entries(for: today).first)
        try store.delete(entry)

        #expect(try store.entries(for: today).isEmpty)
    }

    @Test func deleteOneOfMultipleEntries() throws {
        let store = try makeStore()
        try store.add(timestamp: today.addingTimeInterval(3600), type: .workingTime, location: .office)
        try store.add(timestamp: today.addingTimeInterval(7200), type: .workingTime, location: .homeOffice)

        let entries = try store.entries(for: today)
        try store.delete(entries[0])

        #expect(try store.entries(for: today).count == 1)
    }
}
