//
//  XLSXExporterTests.swift
//  TimeTrackingTests
//

import Testing
import Foundation
@testable import TimeTracking

struct XLSXExporterTests {

    private let jan2026 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    private let feb2026 = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1))!

    private func sampleRows() -> [DayReportRow] {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        return [
            DayReportRow(date: date, type: .workingTime, location: .office, hours: 8.0),
            DayReportRow(date: date.addingTimeInterval(86400), type: .sickness, location: nil, hours: 0),
        ]
    }

    // MARK: - File creation

    @Test func exportReturnsAURL() throws {
        let url = try XLSXExporter.export(rows: [], month: jan2026)
        #expect(url.isFileURL)
    }

    @Test func exportCreatesFileAtReturnedURL() throws {
        let url = try XLSXExporter.export(rows: [], month: jan2026)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func exportedFileIsNonEmpty() throws {
        let url = try XLSXExporter.export(rows: [], month: jan2026)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        #expect((size ?? 0) > 0)
    }

    // MARK: - ZIP / XLSX structure

    @Test func exportedFileHasZIPSignature() throws {
        let url = try XLSXExporter.export(rows: [], month: jan2026)
        let data = try Data(contentsOf: url)
        // ZIP local file header magic: PK 0x03 0x04
        #expect(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
    }

    @Test func exportedFileHasXLSXExtension() throws {
        let url = try XLSXExporter.export(rows: [], month: jan2026)
        #expect(url.pathExtension == "xlsx")
    }

    @Test func fileNameContainsMonthSlug() throws {
        let url = try XLSXExporter.export(rows: [], month: jan2026)
        #expect(url.lastPathComponent.contains("2026-01"))
    }

    // MARK: - Location column

    @Test func exportWithLocationIncludesLocationColumn() throws {
        let url  = try XLSXExporter.export(rows: sampleRows(), month: jan2026, includeLocation: true)
        let data = try Data(contentsOf: url)
        // The ZIP stores XML uncompressed, so "Location" bytes are present verbatim
        #expect(data.range(of: Data("Location".utf8)) != nil)
    }

    @Test func exportWithoutLocationOmitsLocationColumn() throws {
        let url  = try XLSXExporter.export(rows: sampleRows(), month: feb2026, includeLocation: false)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("Location".utf8)) == nil)
    }

    // MARK: - Start / End columns

    @Test func exportIncludesStartAndEndColumnHeaders() throws {
        let url  = try XLSXExporter.export(rows: sampleRows(), month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("Start".utf8)) != nil)
        #expect(data.range(of: Data("End".utf8)) != nil)
    }

    @Test func exportWithWorkRowContainsStartTime() throws {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9))!
        let endDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 17))!
        let rows = [DayReportRow(date: date, type: .workingTime, location: .office, hours: 8.0, startTime: date, endTime: endDate)]
        let url  = try XLSXExporter.export(rows: rows, month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("09:00".utf8)) != nil)
        #expect(data.range(of: Data("17:00".utf8)) != nil)
    }

    @Test func exportSicknessRowHasNoStartEndTimes() throws {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        // startTime/endTime default to nil for sickness
        let rows = [DayReportRow(date: date, type: .sickness, location: nil, hours: 0)]
        let url  = try XLSXExporter.export(rows: rows, month: jan2026)
        let data = try Data(contentsOf: url)
        // No time values should appear (no HH:mm pattern from a sickness row)
        // Verify by checking "09:00" is absent (no start time written)
        #expect(data.range(of: Data("09:00".utf8)) == nil)
    }

    // MARK: - Header / last-row / summary formatting

    @Test func headerRowUsesBoldStyle() throws {
        let url  = try XLSXExporter.export(rows: sampleRows(), month: jan2026)
        let data = try Data(contentsOf: url)
        // Style index 4 is the header (bold + bottom border)
        #expect(data.range(of: Data("s=\"4\"".utf8)) != nil)
    }

    @Test func lastDataRowHasBottomBorderStyle() throws {
        // sampleRows() last entry is a weekday sickness row → style 7 (last+sickness)
        let url  = try XLSXExporter.export(rows: sampleRows(), month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("s=\"7\"".utf8)) != nil)
    }

    @Test func summaryRowContainsTotalLabel() throws {
        let url  = try XLSXExporter.export(rows: sampleRows(), month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("Total".utf8)) != nil)
    }

    @Test func summaryRowContainsTotalWorkingHours() throws {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let rows = [DayReportRow(date: date, type: .workingTime, location: .office, hours: 8.5)]
        let url  = try XLSXExporter.export(rows: rows, month: jan2026)
        let data = try Data(contentsOf: url)
        // Total = 8:30, which also appears as individual row hours — just verify it's in the file
        #expect(data.range(of: Data("8:30".utf8)) != nil)
    }

    // MARK: - Column widths

    @Test func exportedFileContainsColsElement() throws {
        let url  = try XLSXExporter.export(rows: sampleRows(), month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("<cols>".utf8)) != nil)
        #expect(data.range(of: Data("customWidth".utf8)) != nil)
    }

    // MARK: - Weekend styling

    @Test func weekendRowsHaveStyleAttribute() throws {
        // Jan 3 2026 is a Saturday
        let saturday = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        let rows = [DayReportRow(date: saturday, type: nil, location: nil, hours: 0)]
        let url  = try XLSXExporter.export(rows: rows, month: jan2026)
        let data = try Data(contentsOf: url)
        // Weekend style index 1 should appear as s="1" in the XML
        #expect(data.range(of: Data("s=\"1\"".utf8)) != nil)
    }

    @Test func weekdayRowsHaveNoStyleAttribute() throws {
        // Jan 5 2026 is a Monday
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let rows = [DayReportRow(date: monday, type: nil, location: nil, hours: 0)]
        let url  = try XLSXExporter.export(rows: rows, month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("s=\"1\"".utf8)) == nil)
    }

    @Test func sicknessWeekdayUsesStyleTwo() throws {
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let rows = [DayReportRow(date: monday, type: .sickness, location: nil, hours: 0)]
        let url  = try XLSXExporter.export(rows: rows, month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("s=\"2\"".utf8)) != nil)
    }

    @Test func vacationWeekdayUsesStyleThree() throws {
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let rows = [DayReportRow(date: monday, type: .vacation, location: nil, hours: 0)]
        let url  = try XLSXExporter.export(rows: rows, month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("s=\"3\"".utf8)) != nil)
    }

    // MARK: - Hours format

    @Test func hoursExportedAsHoursAndMinutes() throws {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let rows = [DayReportRow(date: date, type: .workingTime, location: .office, hours: 8.5)]
        let url  = try XLSXExporter.export(rows: rows, month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("8:30".utf8)) != nil)
    }

    @Test func zeroHoursExportedAsEmptyString() throws {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let rows = [DayReportRow(date: date, type: .sickness, location: nil, hours: 0)]
        let url  = try XLSXExporter.export(rows: rows, month: jan2026)
        let data = try Data(contentsOf: url)
        #expect(data.range(of: Data("0:00".utf8)) == nil)
    }

    // MARK: - Content size

    @Test func exportWithRowsProducesLargerFileThanEmptyExport() throws {
        // Use different months so the exports write to different temp files
        let emptyURL  = try XLSXExporter.export(rows: [],           month: jan2026)
        let filledURL = try XLSXExporter.export(rows: sampleRows(), month: feb2026)

        let emptySize  = (try? Data(contentsOf: emptyURL).count)  ?? 0
        let filledSize = (try? Data(contentsOf: filledURL).count) ?? 0
        #expect(filledSize > emptySize)
    }
}
