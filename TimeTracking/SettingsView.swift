//
//  SettingsView.swift
//  TimeTracking
//

import SwiftUI
import SwiftData
import MapKit

// MARK: - Root

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var settings: AppSettings?

    var body: some View {
        NavigationStack {
            Group {
                if let settings {
                    SettingsFormView(settings: settings)
                } else {
                    ProgressView("Loading…")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            settings = try? SettingsStore(modelContext: modelContext).loadOrCreate()
        }
    }
}

// MARK: - Form

struct SettingsFormView: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) private var locationManager
    @Environment(MQTTManager.self) private var mqttManager
    @State private var showingMapPicker = false
    @State private var mqttUsername: String = ""
    @State private var mqttPassword: String = ""

    var body: some View {
        Form {
            workingTimeSection
            officeLocationSection
            mqttSection
        }
        .onAppear {
            mqttUsername = KeychainStore.get(.mqttUsername) ?? ""
            mqttPassword = KeychainStore.get(.mqttPassword) ?? ""
        }
        .sheet(isPresented: $showingMapPicker) {
            MapLocationPicker(
                latitude:  settings.officeLatitude  ?? 50.1109,
                longitude: settings.officeLongitude ?? 8.6821
            ) { lat, lon in
                settings.setOfficeLocation(latitude: lat, longitude: lon)
                try? modelContext.save()
                locationManager.updateMonitoring(for: settings)
            }
        }
    }

    // MARK: Working time

    private var workingTimeSection: some View {
        Section("Working Time") {
            HStack {
                Text("Hours per Day")
                Spacer()
                Text("\(settings.defaultWorkingHours, specifier: "%.1f") h")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: $settings.defaultWorkingHours,
                in: 4...10,
                step: 0.5
            ) {
                Text("Hours per Day")
            } minimumValueLabel: {
                Text("4 h").font(.caption)
            } maximumValueLabel: {
                Text("10 h").font(.caption)
            }
            .onChange(of: settings.defaultWorkingHours) { _, _ in
                try? modelContext.save()
            }
        }
    }

    // MARK: IoT / MQTT

    private var mqttSection: some View {
        Section("IoT / MQTT") {
            Toggle("Use MQTT Source", isOn: $settings.mqttEnabled)
                .onChange(of: settings.mqttEnabled) { _, _ in
                    save()
                    mqttManager.updateConnection(for: settings)
                }

            if settings.mqttEnabled {
                mqttConnectionStatusRow

                LabeledContent("Host") {
                    TextField("broker.hivemq.cloud", text: $settings.mqttHost)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: settings.mqttHost) { _, _ in save() }
                }

                LabeledContent("Port") {
                    TextField("8883", value: $settings.mqttPort, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .onChange(of: settings.mqttPort) { _, _ in save() }
                }

                LabeledContent("Topic") {
                    TextField("time/events", text: $settings.mqttTopic)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: settings.mqttTopic) { _, _ in save() }
                }

                LabeledContent("Username") {
                    TextField("Optional", text: $mqttUsername)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: mqttUsername) { _, new in
                            new.isEmpty ? KeychainStore.delete(.mqttUsername)
                                        : KeychainStore.set(new, for: .mqttUsername)
                        }
                }

                LabeledContent("Password") {
                    SecureField("Optional", text: $mqttPassword)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: mqttPassword) { _, new in
                            new.isEmpty ? KeychainStore.delete(.mqttPassword)
                                        : KeychainStore.set(new, for: .mqttPassword)
                        }
                }

                Toggle("Use TLS", isOn: $settings.mqttUseTLS)
                    .onChange(of: settings.mqttUseTLS) { _, _ in save() }

                Picker("Message Format", selection: $settings.mqttMessageFormat) {
                    Text(MQTTMessageFormat.default.label)
                        .tag(MQTTMessageFormat.default)
                    Text(MQTTMessageFormat.seedStudioIoTButtonV2.label)
                        .tag(MQTTMessageFormat.seedStudioIoTButtonV2)
                }
                .onChange(of: settings.mqttMessageFormat) { _, _ in save() }

                Button {
                    save()
                    mqttManager.updateConnection(for: settings)
                } label: {
                    Label("Connect", systemImage: "arrow.clockwise")
                }
                .disabled(!settings.hasMQTTConfiguration)

                if !settings.hasMQTTConfiguration {
                    Text("Host and Topic are required to connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var mqttConnectionStatusRow: some View {
        LabeledContent("Status") {
            HStack(spacing: 4) {
                Image(systemName: mqttManager.connectionState.systemImage)
                    .foregroundStyle(mqttManager.connectionState.color)
                Text(mqttManager.connectionState.label)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() { try? modelContext.save() }

    // MARK: Office location

    private var officeLocationSection: some View {
        Section("Office Location") {
            Toggle("Use Office Location", isOn: $settings.officeLocationEnabled)
                .onChange(of: settings.officeLocationEnabled) { _, _ in
                    try? modelContext.save()
                    locationManager.updateMonitoring(for: settings)
                }

            if settings.officeLocationEnabled {
                permissionStatusRow

                if let lat = settings.officeLatitude, let lon = settings.officeLongitude {
                    mapPreview(latitude: lat, longitude: lon)
                    LabeledContent("Latitude") {
                        Text(lat, format: .number.precision(.fractionLength(5)))
                            .monospacedDigit()
                    }
                    LabeledContent("Longitude") {
                        Text(lon, format: .number.precision(.fractionLength(5)))
                            .monospacedDigit()
                    }
                }

                Button {
                    showingMapPicker = true
                } label: {
                    Label(
                        settings.hasOfficeLocation ? "Change Location" : "Set Location",
                        systemImage: "map"
                    )
                }

                if settings.hasOfficeLocation {
                    Button(role: .destructive) {
                        settings.clearOfficeLocation()
                        try? modelContext.save()
                        locationManager.updateMonitoring(for: settings)
                    } label: {
                        Label("Clear Location", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var permissionStatusRow: some View {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            Button {
                locationManager.requestAlwaysPermission()
            } label: {
                Label("Grant Location Permission", systemImage: "location.circle")
            }
        case .authorizedAlways:
            LabeledContent("Location Access") {
                HStack(spacing: 4) {
                    Image(systemName: locationManager.isMonitoring ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill")
                        .foregroundStyle(locationManager.isMonitoring ? .blue : .green)
                    Text(locationManager.isMonitoring ? "Monitoring" : "Granted")
                        .foregroundStyle(.secondary)
                }
            }
        case .authorizedWhenInUse:
            Label("\"Always\" access required — open Settings", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        default:
            Label("Location access denied — enable in Settings", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func mapPreview(latitude: Double, longitude: Double) -> some View {
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        Map(initialPosition: .camera(MapCamera(centerCoordinate: coord, distance: 800))) {
            Marker("Office", coordinate: coord)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }
}

// MARK: - Map Location Picker

struct MapLocationPicker: View {
    let onConfirm: (Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition
    @State private var centerCoordinate: CLLocationCoordinate2D
    @State private var searchText: String = ""
    @State private var searchResults: [MKMapItem] = []

    init(latitude: Double, longitude: Double, onConfirm: @escaping (Double, Double) -> Void) {
        self.onConfirm = onConfirm
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        _centerCoordinate = State(initialValue: coord)
        _cameraPosition   = State(initialValue: .camera(
            MapCamera(centerCoordinate: coord, distance: 800)
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition)
                    .onMapCameraChange(frequency: .continuous) { context in
                        centerCoordinate = context.camera.centerCoordinate
                    }
                    .ignoresSafeArea(edges: .bottom)

                // Stationary crosshair pin — moves with the map centre
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
                    .shadow(radius: 4)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search location…", text: $searchText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { performSearch() }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Search results list
                    if !searchResults.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(searchResults, id: \.self) { item in
                                    Button { selectResult(item) } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name ?? "Unknown")
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            Text(subtitle(for: item.placemark))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    }

                    Spacer()

                    // Live coordinate readout
                    Text(String(format: "%.5f, %.5f",
                                centerCoordinate.latitude,
                                centerCoordinate.longitude))
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Office Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onConfirm(centerCoordinate.latitude, centerCoordinate.longitude)
                        dismiss()
                    }
                }
            }
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        MKLocalSearch(request: request).start { response, _ in
            searchResults = response?.mapItems ?? []
        }
    }

    private func selectResult(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        centerCoordinate = coord
        cameraPosition = .camera(MapCamera(centerCoordinate: coord, distance: 800))
        searchText = ""
        searchResults = []
    }

    private func subtitle(for placemark: MKPlacemark) -> String {
        [placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
