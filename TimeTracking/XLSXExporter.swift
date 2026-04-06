//
//  XLSXExporter.swift
//  TimeTracking
//
//  Minimal XLSX export without third-party dependencies.
//  Produces a valid .xlsx (ZIP of XML files) using stored (uncompressed) ZIP entries.
//

import Foundation

// MARK: - Public entry point

struct XLSXExporter {

    /// Writes an .xlsx file to the temp directory and returns its URL.
    static func export(rows: [DayReportRow], month: Date, includeLocation: Bool = true) throws -> URL {
        let (sheetXML, sharedStringsXML) = buildSheetXML(rows: rows, includeLocation: includeLocation)

        let data = buildZip(files: [
            ("_rels/.rels",                    relsXML),
            ("[Content_Types].xml",            contentTypesXML),
            ("xl/workbook.xml",                workbookXML),
            ("xl/_rels/workbook.xml.rels",     workbookRelsXML),
            ("xl/styles.xml",                  stylesXML),
            ("xl/sharedStrings.xml",           sharedStringsXML),
            ("xl/worksheets/sheet1.xml",       sheetXML),
        ])

        let name = "TimeReport_\(monthSlug(month)).xlsx"
        let url  = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: - XML builders

    private static func buildSheetXML(rows: [DayReportRow], includeLocation: Bool) -> (sheet: String, sharedStrings: String) {
        var strings: [String] = []
        func idx(_ s: String) -> Int {
            if let i = strings.firstIndex(of: s) { return i }
            strings.append(s)
            return strings.count - 1
        }

        let hDate  = idx("Date")
        let hType  = idx("Type")
        let hLoc   = includeLocation ? idx("Location") : -1
        let hStart = idx("Start")
        let hEnd   = idx("End")
        let hHours = idx("Hours")

        let startCol = includeLocation ? "D" : "C"
        let endCol   = includeLocation ? "E" : "D"
        let hoursCol = includeLocation ? "F" : "E"

        var rowsXML = ""

        // Header row — bold + bottom border
        rowsXML += "<row r=\"1\">"
        rowsXML += ssCell("A", 1, hDate,  style: styleHeader)
        rowsXML += ssCell("B", 1, hType,  style: styleHeader)
        if includeLocation { rowsXML += ssCell("C", 1, hLoc, style: styleHeader) }
        rowsXML += ssCell(startCol, 1, hStart, style: styleHeader)
        rowsXML += ssCell(endCol,   1, hEnd,   style: styleHeader)
        rowsXML += ssCell(hoursCol, 1, hHours, style: styleHeader)
        rowsXML += "</row>"

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"

        let calendar = Calendar.current
        for (i, row) in rows.enumerated() {
            let r = i + 2
            let weekday = calendar.component(.weekday, from: row.date)
            let isWeekend = weekday == 1 || weekday == 7  // 1=Sunday, 7=Saturday
            let isLast = i == rows.count - 1
            let style: Int
            switch (isWeekend, row.type, isLast) {
            case (true,  _,          true):  style = styleLastWknd
            case (true,  _,          false): style = styleWeekend
            case (false, .sickness,  true):  style = styleLastSick
            case (false, .sickness,  false): style = styleSickness
            case (false, .vacation,  true):  style = styleLastVac
            case (false, .vacation,  false): style = styleVacation
            case (false, _,          true):  style = styleLastRow
            default:                         style = styleDefault
            }
            rowsXML += "<row r=\"\(r)\">"
            rowsXML += ssCell("A", r, idx(df.string(from: row.date)), style: style)
            rowsXML += ssCell("B", r, idx(row.type?.label ?? ""),     style: style)
            if includeLocation { rowsXML += ssCell("C", r, idx(row.location?.label ?? ""), style: style) }
            rowsXML += ssCell(startCol, r, idx(row.startTime.map { tf.string(from: $0) } ?? ""), style: style)
            rowsXML += ssCell(endCol,   r, idx(row.endTime.map   { tf.string(from: $0) } ?? ""), style: style)
            rowsXML += ssCell(hoursCol, r, idx(hoursString(row.hours)),                           style: style)
            rowsXML += "</row>"
        }

        // Summary row — total working time
        let totalHours = rows.filter { $0.type == .workingTime }.reduce(0.0) { $0 + $1.hours }
        let summaryR = rows.count + 2
        rowsXML += "<row r=\"\(summaryR)\">"
        rowsXML += ssCell("B", summaryR, idx("Total"), style: styleSummary)
        rowsXML += ssCell(hoursCol, summaryR, idx(hoursString(totalHours)), style: styleSummary)
        rowsXML += "</row>"

        // Column widths (in character units) sized to fit content
        // A=Date(10), B=Type("Working Time"=12), C=Location("Home Office"=11) or Start(5),
        // then Start(5), End(5), Hours(5) — +2 padding each
        let colWidths: [(min: Int, max: Int, width: Double)] = includeLocation
            ? [(1,1,12),(2,2,14),(3,3,13),(4,4,7),(5,5,7),(6,6,7)]
            : [(1,1,12),(2,2,14),(3,3,7),(4,4,7),(5,5,7)]
        let colsXML = "<cols>" + colWidths.map {
            "<col min=\"\($0.min)\" max=\"\($0.max)\" width=\"\($0.width)\" customWidth=\"1\"/>"
        }.joined() + "</cols>"

        let sheetXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        \(colsXML)<sheetData>\(rowsXML)</sheetData>
        </worksheet>
        """

        let count = strings.count
        let items = strings.map { "<si><t>\(xmlEscape($0))</t></si>" }.joined()
        let ssXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        count="\(count)" uniqueCount="\(count)">\(items)</sst>
        """

        return (sheetXML, ssXML)
    }

    private static func ssCell(_ col: String, _ row: Int, _ si: Int, style: Int = 0) -> String {
        let s = style > 0 ? " s=\"\(style)\"" : ""
        return "<c r=\"\(col)\(row)\" t=\"s\"\(s)><v>\(si)</v></c>"
    }
    private static func numCell(_ col: String, _ row: Int, _ value: Double) -> String {
        "<c r=\"\(col)\(row)\"><v>\(String(format: "%.2f", value))</v></c>"
    }
    /// Formats a decimal-hours value as "H:mm" (e.g. 8.5 → "8:30", 0.0 → "").
    private static func hoursString(_ hours: Double) -> String {
        guard hours > 0 else { return "" }
        let totalMinutes = Int((hours * 60).rounded())
        return "\(totalMinutes / 60):\(String(format: "%02d", totalMinutes % 60))"
    }
    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Static XML fragments

    private static let relsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
    Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml"  ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/sharedStrings.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
    <Override PartName="/xl/styles.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets><sheet name="Report" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" \
    Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" \
    Target="sharedStrings.xml"/>
    <Relationship Id="rId3" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" \
    Target="styles.xml"/>
    </Relationships>
    """

    // Style index constants for readability
    private static let styleDefault    = 0  // weekday, no type
    private static let styleWeekend    = 1  // weekend gray
    private static let styleSickness   = 2  // sickness light-red
    private static let styleVacation   = 3  // vacation light-orange
    private static let styleHeader     = 4  // bold + bottom border
    private static let styleLastRow    = 5  // bottom border, no fill
    private static let styleLastWknd   = 6  // bottom border + weekend
    private static let styleLastSick   = 7  // bottom border + sickness
    private static let styleLastVac    = 8  // bottom border + vacation
    private static let styleSummary    = 9  // bold (summary row)

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/></font>
    </fonts>
    <fills count="5">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFE8E8E8"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFFFDDDD"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFFFEEDD"/><bgColor indexed="64"/></patternFill></fill>
    </fills>
    <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border><left/><right/><top/><bottom style="thin"><color rgb="FF000000"/></bottom><diagonal/></border>
    </borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="10">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="2" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="4" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
    <xf numFmtId="0" fontId="0" fillId="2" borderId="1" xfId="0" applyBorder="1"/>
    <xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyBorder="1"/>
    <xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyBorder="1"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    </cellXfs>
    </styleSheet>
    """

    // MARK: - ZIP builder (stored / uncompressed entries)

    private static func buildZip(files: [(String, String)]) -> Data {
        struct Entry { let offset: Int; let name: Data; let fileData: Data; let crc: UInt32 }
        var entries: [Entry] = []
        var archive = Data()

        for (name, content) in files {
            let nameData = Data(name.utf8)
            let fileData = Data(content.utf8)
            let crc      = crc32(fileData)
            let offset   = archive.count

            var lh = Data()
            lh += uint32LE(0x04034b50)
            lh += uint16LE(20)
            lh += uint16LE(0)
            lh += uint16LE(0)                             // stored
            lh += uint16LE(0); lh += uint16LE(0)          // mod time / date
            lh += uint32LE(crc)
            lh += uint32LE(UInt32(fileData.count))
            lh += uint32LE(UInt32(fileData.count))
            lh += uint16LE(UInt16(nameData.count))
            lh += uint16LE(0)
            lh += nameData
            lh += fileData

            entries.append(Entry(offset: offset, name: nameData, fileData: fileData, crc: crc))
            archive += lh
        }

        let cdOffset = archive.count
        for e in entries {
            var cd = Data()
            cd += uint32LE(0x02014b50)
            cd += uint16LE(20); cd += uint16LE(20)
            cd += uint16LE(0); cd += uint16LE(0)
            cd += uint16LE(0); cd += uint16LE(0)
            cd += uint32LE(e.crc)
            cd += uint32LE(UInt32(e.fileData.count))
            cd += uint32LE(UInt32(e.fileData.count))
            cd += uint16LE(UInt16(e.name.count))
            cd += uint16LE(0); cd += uint16LE(0)
            cd += uint16LE(0); cd += uint16LE(0)
            cd += uint32LE(0)
            cd += uint32LE(UInt32(e.offset))
            cd += e.name
            archive += cd
        }

        let cdSize = archive.count - cdOffset
        var eocd = Data()
        eocd += uint32LE(0x06054b50)
        eocd += uint16LE(0); eocd += uint16LE(0)
        eocd += uint16LE(UInt16(entries.count))
        eocd += uint16LE(UInt16(entries.count))
        eocd += uint32LE(UInt32(cdSize))
        eocd += uint32LE(UInt32(cdOffset))
        eocd += uint16LE(0)
        archive += eocd

        return archive
    }

    // MARK: - CRC-32

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            var b = UInt32(byte)
            for _ in 0..<8 {
                let mix = (crc ^ b) & 1
                crc >>= 1
                if mix != 0 { crc ^= 0xEDB88320 }
                b >>= 1
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - Little-endian helpers

    private static func uint16LE(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }
    private static func uint32LE(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
              UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }

    private static func monthSlug(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        return df.string(from: date)
    }
}
