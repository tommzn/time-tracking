//
//  MonthReportTests.swift
//  TimeTrackingTests
//

import Testing
import Foundation
@testable import TimeTracking

struct MonthReportTests {

    // January 2026: Jan 1 = Thursday, Jan 5 = Monday
    private let jan2026 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!

    private func ts(_ day: Int, _ hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private func entry(_ day: Int, _ hour: Int, type: EntryType, location: WorkLocation? = nil) -> TimeEntry {
        TimeEntry(timestamp: ts(day, hour), type: type, location: location)
    }

    private func row(day: Int, in rows: [DayReportRow]) -> DayReportRow? {
        rows.first { Calendar.current.component(.day, from: $0.date) == day }
    }

    // MARK: - Empty input

    @Test func emptyEntriesProducesOneRowPerDay() {
        let rows = MonthReportGenerator.generate(entries: [], month: jan2026, defaultHours: 8.0)
        #expect(rows.count == 31)
        #expect(rows.allSatisfy { $0.type == nil && $0.hours == 0 })
    }

    // MARK: - Working time hours

    @Test func singleWorkEntryUsesDefaultHours() {
        let entries = [entry(5, 9, type: .workingTime, location: .office)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let r = row(day: 5, in: rows)
        #expect(r?.type == .workingTime)
        #expect(r?.hours == 8.0)
    }

    @Test func twoWorkEntriesCalculateDuration() {
        // 9am → 5pm = 8h
        let entries = [
            entry(5, 9, type: .workingTime, location: .office),
            entry(5, 17, type: .workingTime, location: .office),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 6.0)
        #expect(row(day: 5, in: rows)?.hours == 8.0)
    }

    @Test func threeWorkEntriesPairsFirstTwoPlusDefault() {
        // 8am→noon = 4h (pair 1), 6pm unpaired → +defaultHours 8h = 12h total
        let entries = [
            entry(5, 8,  type: .workingTime, location: .office),
            entry(5, 12, type: .workingTime, location: .office),
            entry(5, 18, type: .workingTime, location: .office),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        #expect(row(day: 5, in: rows)?.hours == 12.0)
    }

    @Test func fourWorkEntriesSumsBothPairs() {
        // 8am→noon = 4h, 1pm→5pm = 4h → 8h total
        let entries = [
            entry(5, 8,  type: .workingTime, location: .office),
            entry(5, 12, type: .workingTime, location: .office),
            entry(5, 13, type: .workingTime, location: .office),
            entry(5, 17, type: .workingTime, location: .office),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        #expect(row(day: 5, in: rows)?.hours == 8.0)
    }

    @Test func locationTakenFromLastWorkEntry() {
        let entries = [
            entry(5, 9,  type: .workingTime, location: .homeOffice),
            entry(5, 17, type: .workingTime, location: .office),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        #expect(row(day: 5, in: rows)?.location == .office)
    }

    // MARK: - Sickness / Vacation

    @Test func sicknessRowHasZeroHours() {
        let entries = [entry(5, 8, type: .sickness)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let r = row(day: 5, in: rows)
        #expect(r?.type == .sickness)
        #expect(r?.hours == 0.0)
    }

    @Test func vacationRowHasZeroHours() {
        let entries = [entry(5, 8, type: .vacation)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let r = row(day: 5, in: rows)
        #expect(r?.type == .vacation)
        #expect(r?.hours == 0.0)
    }

    // MARK: - Carry-forward

    @Test func sicknessCarriesForwardToEmptyNextDay() {
        // Jan 5 (Mon) sickness → Jan 6 (Tue) empty → should carry
        let entries = [entry(5, 8, type: .sickness)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let r = row(day: 6, in: rows)
        #expect(r?.type == .sickness)
        #expect(r?.hours == 0.0)
    }

    @Test func vacationCarriesForwardToEmptyNextDay() {
        let entries = [entry(5, 8, type: .vacation)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        #expect(row(day: 6, in: rows)?.type == .vacation)
    }

    @Test func carryForwardStopsWhenWorkingTimeResumes() {
        // Jan 5 sickness, Jan 6 working time → Jan 7 should have a row but nil type (no carry)
        let entries = [
            entry(5, 8, type: .sickness),
            entry(6, 9, type: .workingTime, location: .office),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        #expect(row(day: 7, in: rows)?.type == nil)
    }

    @Test func carryForwardStopsWhenVacationEntryOccurs() {
        // Jan 5 sickness carry → Jan 6 explicit vacation → Jan 7 should have nil (sickness carry stopped)
        // Jan 7 should show vacation carry (vacation also carries forward from day 6)
        let entries = [
            entry(5, 8, type: .sickness),
            entry(6, 9, type: .vacation),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        #expect(row(day: 6, in: rows)?.type == .vacation)
        #expect(row(day: 7, in: rows)?.type == .vacation) // vacation carry from day 6
    }

    @Test func sicknessThenVacationThenWorkClearsAllCarry() {
        // Day 5: sickness, Day 6: vacation (stops sickness carry, starts vacation carry),
        // Day 7: working time (stops vacation carry) → Day 8 should be nil
        let entries = [
            entry(5, 8, type: .sickness),
            entry(6, 8, type: .vacation),
            entry(7, 9, type: .workingTime, location: .office),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        #expect(row(day: 5, in: rows)?.type == .sickness)
        #expect(row(day: 6, in: rows)?.type == .vacation)
        #expect(row(day: 7, in: rows)?.type == .workingTime)
        #expect(row(day: 8, in: rows)?.type == nil)
    }

    @Test func workingTimeTakesPriorityOnDayWithMixedTypes() {
        let entries = [
            entry(5, 8,  type: .sickness),
            entry(5, 9,  type: .workingTime, location: .office),
            entry(5, 17, type: .workingTime, location: .office),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        #expect(row(day: 5, in: rows)?.type == .workingTime)
    }

    @Test func workingTimeAfterSicknessAlsoClearsCarry() {
        // Sickness on day 5, mixed day 6 → day 7 should have nil type (carry cleared)
        let entries = [
            entry(5, 8,  type: .sickness),
            entry(6, 8,  type: .sickness),
            entry(6, 9,  type: .workingTime, location: .office),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        #expect(row(day: 7, in: rows)?.type == nil)
    }

    // MARK: - Row dates

    @Test func allRowDatesAreWithinRequestedMonth() {
        let entries = [
            entry(5,  9, type: .workingTime, location: .office),
            entry(15, 9, type: .sickness),
            entry(25, 9, type: .vacation),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let cal = Calendar.current
        #expect(rows.allSatisfy {
            cal.component(.month, from: $0.date) == 1 &&
            cal.component(.year, from: $0.date) == 2026
        })
    }

    @Test func emptyDayWithNoCarryHasNilType() {
        // Day with no entries and no active carry → row present but type is nil
        let entries = [entry(5, 9, type: .workingTime, location: .office)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        // Jan 7 has no entries and carry was never started
        #expect(row(day: 7, in: rows)?.type == nil)
        #expect(row(day: 7, in: rows)?.hours == 0)
    }

    // MARK: - Start / End times

    @Test func singleWorkEntryStartTimeIsEntryTimestamp() {
        let entries = [entry(5, 9, type: .workingTime, location: .office)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let r = row(day: 5, in: rows)
        #expect(r?.startTime == ts(5, 9))
    }

    @Test func singleWorkEntryEndTimeIsStartPlusDefaultHours() {
        let entries = [entry(5, 9, type: .workingTime, location: .office)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let r = row(day: 5, in: rows)
        let expectedEnd = ts(5, 9).addingTimeInterval(8 * 3600)
        #expect(r?.endTime == expectedEnd)
    }

    @Test func twoWorkEntriesStartAndEndTimesAreFirstAndLast() {
        let entries = [
            entry(5, 9,  type: .workingTime, location: .office),
            entry(5, 17, type: .workingTime, location: .office),
        ]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let r = row(day: 5, in: rows)
        #expect(r?.startTime == ts(5, 9))
        #expect(r?.endTime   == ts(5, 17))
    }

    @Test func sicknessRowHasNilStartAndEndTimes() {
        let entries = [entry(5, 8, type: .sickness)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let r = row(day: 5, in: rows)
        #expect(r?.startTime == nil)
        #expect(r?.endTime   == nil)
    }

    @Test func vacationRowHasNilStartAndEndTimes() {
        let entries = [entry(5, 8, type: .vacation)]
        let rows = MonthReportGenerator.generate(entries: entries, month: jan2026, defaultHours: 8.0)
        let r = row(day: 5, in: rows)
        #expect(r?.startTime == nil)
        #expect(r?.endTime   == nil)
    }

    @Test func emptyRowHasNilStartAndEndTimes() {
        let rows = MonthReportGenerator.generate(entries: [], month: jan2026, defaultHours: 8.0)
        let r = row(day: 5, in: rows)
        #expect(r?.startTime == nil)
        #expect(r?.endTime   == nil)
    }
}
