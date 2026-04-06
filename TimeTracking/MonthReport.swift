//
//  MonthReport.swift
//  TimeTracking
//

import Foundation

// MARK: - Data

struct DayReportRow {
    let date: Date
    let type: EntryType?        // nil = no entry for this day
    let location: WorkLocation? // only relevant for workingTime
    let hours: Double
    let startTime: Date?        // nil for sickness / vacation / empty days
    let endTime: Date?          // nil for sickness / vacation / empty days

    init(date: Date, type: EntryType?, location: WorkLocation?, hours: Double,
         startTime: Date? = nil, endTime: Date? = nil) {
        self.date = date
        self.type = type
        self.location = location
        self.hours = hours
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - Generator

struct MonthReportGenerator {

    /// Build one `DayReportRow` per calendar day in `month`.
    /// - Sickness / vacation carry forward to empty days until the next explicit entry of any type.
    /// - Working-time days: duration = last entry timestamp − first entry timestamp.
    ///   If only one entry exists, `defaultHours` is used.
    static func generate(
        entries: [TimeEntry],
        month: Date,
        defaultHours: Double
    ) -> [DayReportRow] {

        let calendar = Calendar.current
        let monthStart = calendar.startOfMonth(for: month)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return []
        }

        // Group entries by start-of-day
        var byDay: [Date: [TimeEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            byDay[day, default: []].append(entry)
        }

        // All calendar days in the month
        var allDays: [Date] = []
        var cursor = monthStart
        while cursor < monthEnd {
            allDays.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }

        var rows: [DayReportRow] = []
        var pendingCarryType: EntryType? = nil   // sickness or vacation to carry forward

        for day in allDays {
            let dayEntries = (byDay[day] ?? []).sorted { $0.timestamp < $1.timestamp }

            if dayEntries.isEmpty {
                // Carry forward sickness/vacation if pending; otherwise emit empty row
                let carry = pendingCarryType
                rows.append(DayReportRow(date: day, type: carry, location: nil, hours: 0))
                continue
            }

            // Any explicit entry stops the carry-forward
            pendingCarryType = nil

            // Check if any workingTime entry exists today
            let hasWork = dayEntries.contains { $0.type == .workingTime }

            if hasWork {
                let workEntries = dayEntries.filter { $0.type == .workingTime }
                // Sum paired durations: (entry[0]→entry[1]) + (entry[2]→entry[3]) + …
                // Unpaired last entry contributes defaultHours
                var hours: Double = 0
                var i = 0
                while i + 1 < workEntries.count {
                    hours += workEntries[i + 1].timestamp.timeIntervalSince(workEntries[i].timestamp) / 3600
                    i += 2
                }
                if workEntries.count % 2 == 1 {
                    hours += defaultHours
                }

                // Dominant location: last work entry's location
                let location = workEntries.last?.location

                let startTime = workEntries.first!.timestamp
                let endTime = workEntries.count == 1
                    ? startTime.addingTimeInterval(defaultHours * 3600)
                    : workEntries.last!.timestamp

                rows.append(DayReportRow(date: day, type: .workingTime, location: location, hours: hours, startTime: startTime, endTime: endTime))

            } else {
                // Only sickness / vacation entries
                // Pick whichever type appears first
                let dominant = dayEntries.first!.type
                pendingCarryType = dominant
                rows.append(DayReportRow(date: day, type: dominant, location: nil, hours: 0))
            }
        }

        return rows
    }
}
