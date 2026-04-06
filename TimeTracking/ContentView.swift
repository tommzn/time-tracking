//
//  ContentView.swift
//  TimeTracking
//

import SwiftUI
import SwiftData

// MARK: - EntryType appearance

extension EntryType {
    var color: Color {
        switch self {
        case .workingTime: .green
        case .sickness:    .red
        case .vacation:    .yellow
        }
    }
}

// MARK: - Calendar helpers

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let c = dateComponents([.year, .month], from: date)
        return self.date(from: c)!
    }
}

// MARK: - Root View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) private var locationManager
    @Environment(MQTTManager.self) private var mqttManager
    @State private var selectedDate    = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth  = Calendar.current.startOfMonth(for: Date())
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var reportURL: URL?
    @State private var reportError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MonthCalendarView(
                    displayedMonth: $displayedMonth,
                    selectedDate: $selectedDate
                )

                Divider()

                ZStack(alignment: .bottomTrailing) {
                    DayEntriesView(date: selectedDate)

                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(.tint, in: Circle())
                            .shadow(radius: 4, y: 2)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(
                selectedDate.formatted(.dateTime.day().month(.wide).year())
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let url = reportURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    } else {
                        Button { generateReport() } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEntryView(defaultDate: selectedDate)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .task {
            if let settings = try? SettingsStore(modelContext: modelContext).loadOrCreate() {
                locationManager.updateMonitoring(for: settings)
                mqttManager.updateConnection(for: settings)
            }
        }
        .task(id: displayedMonth) {
            generateReport()
        }
        .alert("Export Failed", isPresented: Binding(get: { reportError != nil }, set: { _ in reportError = nil })) {
            Button("OK") {}
        } message: {
            Text(reportError ?? "")
        }
    }

    private func generateReport() {
        do {
            let settings = try SettingsStore(modelContext: modelContext).loadOrCreate()
            let store = TimeEntryStore(modelContext: modelContext)
            let entries = try store.entries(forMonth: displayedMonth)
            let rows = MonthReportGenerator.generate(
                entries: entries,
                month: displayedMonth,
                defaultHours: settings.defaultWorkingHours
            )
            reportURL = try XLSXExporter.export(
                rows: rows,
                month: displayedMonth,
                includeLocation: settings.officeLocationEnabled && settings.hasOfficeLocation
            )
        } catch {
            reportError = error.localizedDescription
        }
    }
}

// MARK: - Month Calendar View

struct MonthCalendarView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    @Query private var allEntries: [TimeEntry]

    // Map from start-of-day → set of entry types present that day
    private var entryTypesByDay: [Date: Set<EntryType>] {
        allEntries.reduce(into: [:]) { map, entry in
            let day = Calendar.current.startOfDay(for: entry.timestamp)
            map[day, default: []].insert(entry.type)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayLabels
            dayGrid
        }
    }

    // MARK: Month header

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                let today = Calendar.current.startOfDay(for: Date())
                displayedMonth = Calendar.current.startOfMonth(for: today)
                selectedDate   = today
            } label: {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: Weekday labels

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], id: \.self) { label in
                Text(label)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: Day grid

    private var dayGrid: some View {
        let days = gridDays()
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
            spacing: 2
        ) {
            ForEach(0..<days.count, id: \.self) { i in
                if let date = days[i] {
                    CalendarDayCell(
                        date: date,
                        isSelected: date == selectedDate,
                        entryTypes: entryTypesByDay[date] ?? []
                    ) {
                        selectedDate = date
                        displayedMonth = Calendar.current.startOfMonth(for: date)
                    }
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    // MARK: Helpers

    private func shiftMonth(_ value: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth)!
    }

    private func gridDays() -> [Date?] {
        let calendar    = Calendar.current
        let range       = calendar.range(of: .day, in: .month, for: displayedMonth)!
        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let offset      = (firstWeekday + 5) % 7   // Mon = 0 … Sun = 6

        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in 0..<range.count {
            days.append(calendar.date(byAdding: .day, value: day, to: displayedMonth))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let entryTypes: Set<EntryType>
    let onTap: () -> Void

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    private var isWeekend: Bool {
        let w = Calendar.current.component(.weekday, from: date)
        return w == 1 || w == 7
    }
    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }
    private var textColor: Color {
        if isSelected { return .white }
        if isToday    { return .blue }
        if isWeekend  { return .secondary }
        return .primary
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                ZStack {
                    if isSelected {
                        Circle().fill(.tint)
                    } else if isToday {
                        Circle().strokeBorder(.tint, lineWidth: 1.5)
                    }

                    Text("\(dayNumber)")
                        .font(.callout)
                        .fontWeight(isToday || isSelected ? .semibold : .regular)
                        .foregroundStyle(textColor)
                }
                .frame(width: 30, height: 30)

                // One dot per entry type present that day
                HStack(spacing: 2) {
                    ForEach(
                        EntryType.allCases.filter { entryTypes.contains($0) },
                        id: \.self
                    ) { type in
                        Circle()
                            .fill(type.color)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Day Entries View

struct DayEntriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [TimeEntry]

    init(date: Date) {
        let start = Calendar.current.startOfDay(for: date)
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        _entries = Query(
            filter: #Predicate<TimeEntry> { $0.timestamp >= start && $0.timestamp < end },
            sort: \.timestamp
        )
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "clock",
                    description: Text("Tap + to log an entry for this day.")
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        EntryRow(entry: entry)
                    }
                    .onDelete { indexSet in
                        for i in indexSet { modelContext.delete(entries[i]) }
                        try? modelContext.save()
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Entry Row

struct EntryRow: View {
    let entry: TimeEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.type.systemImage)
                .font(.title3)
                .foregroundStyle(entry.type.color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.label)
                if let location = entry.location {
                    Text(location.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.timestamp.formatted(.dateTime.hour().minute()))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Entry View

struct AddEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationManager.self) private var locationManager

    @State private var timestamp: Date
    @State private var type: EntryType     = .workingTime
    @State private var location: WorkLocation = .homeOffice

    init(defaultDate: Date) {
        let calendar  = Calendar.current
        let timeNow   = calendar.dateComponents([.hour, .minute], from: Date())
        var parts     = calendar.dateComponents([.year, .month, .day], from: defaultDate)
        parts.hour    = timeNow.hour
        parts.minute  = timeNow.minute
        _timestamp = State(initialValue: calendar.date(from: parts) ?? defaultDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    DatePicker(
                        "Date & Time",
                        selection: $timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                }

                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(EntryType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.systemImage).tag(t)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if type == .workingTime {
                    Section("Location") {
                        Picker("Location", selection: $location) {
                            ForEach(WorkLocation.allCases, id: \.self) { l in
                                Text(l.label).tag(l)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            guard let settings = try? SettingsStore(modelContext: modelContext).loadOrCreate(),
                  settings.officeLocationEnabled,
                  let lat = settings.officeLatitude,
                  let lon = settings.officeLongitude else { return }
            locationManager.requestWorkLocationDetection(officeLatitude: lat, officeLongitude: lon)
        }
        .onChange(of: locationManager.detectedWorkLocation) { _, detected in
            if let detected, type == .workingTime {
                location = detected
            }
        }
    }

    private func save() {
        modelContext.insert(TimeEntry(
            timestamp: timestamp,
            type: type,
            location: type == .workingTime ? location : nil
        ))
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let schema = Schema([TimeEntry.self, AppSettings.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    let settings = AppSettings(
        officeLocationEnabled: true,
        officeLatitude: 52.5163,
        officeLongitude: 13.3777
    )
    container.mainContext.insert(settings)

    let cal = Calendar.current
    func date(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 4, day: day, hour: hour))!
    }

    // Week 1: Mon Apr 6 – Fri Apr 10, 9am + 5pm each day
    for day in [6, 7, 8, 9, 10] {
        container.mainContext.insert(TimeEntry(timestamp: date(day, 9),  type: .workingTime, location: .office))
        container.mainContext.insert(TimeEntry(timestamp: date(day, 17), type: .workingTime, location: .office))
    }

    // Week 2: Mon Apr 13 + Tue Apr 14, 9am + 5pm; Wed Apr 15 sickness
    for day in [13, 14] {
        container.mainContext.insert(TimeEntry(timestamp: date(day, 9),  type: .workingTime, location: .office))
        container.mainContext.insert(TimeEntry(timestamp: date(day, 17), type: .workingTime, location: .office))
    }
    container.mainContext.insert(TimeEntry(timestamp: date(15, 8), type: .sickness))

    // Week 3: Mon Apr 20 single working-time entry; Tue Apr 21 vacation
    container.mainContext.insert(TimeEntry(timestamp: date(20, 8), type: .workingTime, location: .office))
    container.mainContext.insert(TimeEntry(timestamp: date(21, 7), type: .vacation))

    // Week 4: Mon Apr 27 – Thu Apr 30 (April ends Thursday), 9am + 5pm each day
    for day in [27, 28, 29, 30] {
        container.mainContext.insert(TimeEntry(timestamp: date(day, 9),  type: .workingTime, location: .office))
        container.mainContext.insert(TimeEntry(timestamp: date(day, 17), type: .workingTime, location: .office))
    }

    return ContentView()
        .modelContainer(container)
        .environment(LocationManager())
        .environment(MQTTManager())
}
