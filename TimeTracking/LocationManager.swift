//
//  LocationManager.swift
//  TimeTracking
//

import Foundation
import CoreLocation
import SwiftData
import Observation

@Observable
final class LocationManager: NSObject {

    // MARK: - Observable state

    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isMonitoring = false
    /// Set after a requestWorkLocationDetection() call resolves. Nil while pending or if detection failed.
    var detectedWorkLocation: WorkLocation? = nil

    // MARK: - Private

    @ObservationIgnored private let clManager = CLLocationManager()
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var pendingOfficeCoordinate: CLLocationCoordinate2D?

    static let regionIdentifier = "de.tommzn.TimeTracking.officeRegion"
    static let regionRadius: CLLocationDistance = 100   // metres

    // MARK: - Init

    override init() {
        super.init()
        clManager.delegate = self
        authorizationStatus = clManager.authorizationStatus
        isMonitoring = clManager.monitoredRegions
            .contains { $0.identifier == Self.regionIdentifier }
    }

    // MARK: - Setup

    /// Call once at app startup with the shared ModelContainer.
    func setup(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Permission

    func requestAlwaysPermission() {
        clManager.requestAlwaysAuthorization()
    }

    // MARK: - One-shot location detection

    /// Requests the current location once and resolves `detectedWorkLocation`
    /// by comparing against the given office coordinates.
    func requestWorkLocationDetection(officeLatitude: Double, officeLongitude: Double) {
        detectedWorkLocation = nil
        pendingOfficeCoordinate = CLLocationCoordinate2D(latitude: officeLatitude, longitude: officeLongitude)
        clManager.requestLocation()
    }

    // MARK: - Monitoring

    /// Starts or stops region monitoring to match the current settings state.
    func updateMonitoring(for settings: AppSettings) {
        stopMonitoring()
        guard settings.officeLocationEnabled,
              let lat = settings.officeLatitude,
              let lon = settings.officeLongitude,
              authorizationStatus == .authorizedAlways else { return }
        startMonitoring(latitude: lat, longitude: lon)
    }

    // MARK: - Private helpers

    private func startMonitoring(latitude: Double, longitude: Double) {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: Self.regionRadius,
            identifier: Self.regionIdentifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit  = true
        clManager.startMonitoring(for: region)
        isMonitoring = true
    }

    private func stopMonitoring() {
        clManager.monitoredRegions
            .filter { $0.identifier == Self.regionIdentifier }
            .forEach { clManager.stopMonitoring(for: $0) }
        isMonitoring = false
    }

    private func createEntry(type: EntryType, location: WorkLocation) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(TimeEntry(timestamp: Date(), type: type, location: location))
        try? context.save()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    /// User enters the office region → log start of office work.
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.regionIdentifier else { return }
        createEntry(type: .workingTime, location: .office)
    }

    /// User leaves the office region → log return to home office.
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.regionIdentifier else { return }
        createEntry(type: .workingTime, location: .homeOffice)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        defer { pendingOfficeCoordinate = nil }
        guard let current = locations.last,
              let office = pendingOfficeCoordinate else { return }
        let officeLocation = CLLocation(latitude: office.latitude, longitude: office.longitude)
        detectedWorkLocation = Self.workLocation(for: current.distance(from: officeLocation))
    }

    /// Pure mapping used by the delegate and testable in isolation.
    static func workLocation(for distanceMetres: CLLocationDistance) -> WorkLocation {
        distanceMetres <= regionRadius ? .office : .homeOffice
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pendingOfficeCoordinate = nil
    }

    func locationManager(_ manager: CLLocationManager,
                         monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        isMonitoring = false
    }
}
