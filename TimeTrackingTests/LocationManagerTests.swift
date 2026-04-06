//
//  LocationManagerTests.swift
//  TimeTrackingTests
//

import Testing
import CoreLocation
import SwiftData
@testable import TimeTracking

struct LocationManagerTests {

    // MARK: - workLocation(for:) distance mapping

    @Test func distanceWithinRadiusReturnsOffice() {
        // 50m is well within the 100m geofence
        let result = LocationManager.workLocation(for: 50)
        #expect(result == .office)
    }

    @Test func distanceExactlyOnBoundaryReturnsOffice() {
        // Exactly 100m — boundary is inclusive (<=)
        let result = LocationManager.workLocation(for: LocationManager.regionRadius)
        #expect(result == .office)
    }

    @Test func distanceOutsideRadiusReturnsHomeOffice() {
        // 101m — just outside the 100m geofence
        let result = LocationManager.workLocation(for: LocationManager.regionRadius + 1)
        #expect(result == .homeOffice)
    }

    @Test func zeroDistanceReturnsOffice() {
        #expect(LocationManager.workLocation(for: 0) == .office)
    }

    @Test func largeDistanceReturnsHomeOffice() {
        #expect(LocationManager.workLocation(for: 50_000) == .homeOffice)
    }

    // MARK: - requestWorkLocationDetection

    @Test func requestWorkLocationDetectionClearsDetectedLocation() {
        let lm = LocationManager()
        lm.detectedWorkLocation = .office
        lm.requestWorkLocationDetection(officeLatitude: 52.5163, officeLongitude: 13.3777)
        #expect(lm.detectedWorkLocation == nil)
    }

    // MARK: - didUpdateLocations

    @Test func didUpdateLocationsAtOfficeCoordinateResolvesToOffice() {
        let lm = LocationManager()
        // Berlin Brandenburg Gate as "office"
        lm.requestWorkLocationDetection(officeLatitude: 52.5163, officeLongitude: 13.3777)

        let here = CLLocation(latitude: 52.5163, longitude: 13.3777)
        lm.locationManager(CLLocationManager(), didUpdateLocations: [here])

        #expect(lm.detectedWorkLocation == .office)
    }

    @Test func didUpdateLocationsDistantFromOfficeResolvesToHomeOffice() {
        let lm = LocationManager()
        lm.requestWorkLocationDetection(officeLatitude: 52.5163, officeLongitude: 13.3777)

        // Munich — ~500 km from Berlin
        let munich = CLLocation(latitude: 48.1351, longitude: 11.5820)
        lm.locationManager(CLLocationManager(), didUpdateLocations: [munich])

        #expect(lm.detectedWorkLocation == .homeOffice)
    }

    @Test func didUpdateLocationsUsesLastLocationInList() {
        let lm = LocationManager()
        lm.requestWorkLocationDetection(officeLatitude: 52.5163, officeLongitude: 13.3777)

        let officeLocation = CLLocation(latitude: 52.5163, longitude: 13.3777)
        let distantLocation = CLLocation(latitude: 48.1351, longitude: 11.5820)
        // Last location (distant) wins
        lm.locationManager(CLLocationManager(), didUpdateLocations: [officeLocation, distantLocation])

        #expect(lm.detectedWorkLocation == .homeOffice)
    }

    @Test func didUpdateLocationsWithEmptyListDoesNotSetDetectedLocation() {
        let lm = LocationManager()
        lm.requestWorkLocationDetection(officeLatitude: 52.5163, officeLongitude: 13.3777)
        lm.locationManager(CLLocationManager(), didUpdateLocations: [])
        #expect(lm.detectedWorkLocation == nil)
    }

    @Test func didUpdateLocationsWithNoPendingCoordinateDoesNotSetDetectedLocation() {
        let lm = LocationManager()
        // No requestWorkLocationDetection call → no pending coordinate
        let here = CLLocation(latitude: 52.5163, longitude: 13.3777)
        lm.locationManager(CLLocationManager(), didUpdateLocations: [here])
        #expect(lm.detectedWorkLocation == nil)
    }

    // MARK: - didFailWithError

    @Test func didFailWithErrorClearsPendingCoordinateSoSubsequentUpdateIsIgnored() {
        let lm = LocationManager()
        lm.requestWorkLocationDetection(officeLatitude: 52.5163, officeLongitude: 13.3777)

        lm.locationManager(CLLocationManager(),
                            didFailWithError: NSError(domain: "CLError", code: 0))

        // Subsequent update should be ignored because pendingOfficeCoordinate was cleared
        let here = CLLocation(latitude: 52.5163, longitude: 13.3777)
        lm.locationManager(CLLocationManager(), didUpdateLocations: [here])

        #expect(lm.detectedWorkLocation == nil)
    }

    // MARK: - monitoringDidFailFor

    @Test func monitoringFailureSetsIsMonitoringFalse() {
        let lm = LocationManager()
        lm.isMonitoring = true
        lm.locationManager(CLLocationManager(),
                            monitoringDidFailFor: nil,
                            withError: NSError(domain: "CLError", code: 0))
        #expect(lm.isMonitoring == false)
    }

    // MARK: - locationManagerDidChangeAuthorization

    @Test func authorizationChangeMirrorsManagerStatus() {
        let lm = LocationManager()
        let manager = CLLocationManager()
        lm.locationManagerDidChangeAuthorization(manager)
        #expect(lm.authorizationStatus == manager.authorizationStatus)
    }

    // MARK: - updateMonitoring

    @Test func updateMonitoringWithLocationDisabledDoesNotMonitor() {
        let settings = AppSettings(officeLocationEnabled: false,
                                   officeLatitude: 52.5, officeLongitude: 13.4)
        let lm = LocationManager()
        lm.updateMonitoring(for: settings)
        #expect(lm.isMonitoring == false)
    }

    @Test func updateMonitoringWithNoCoordinatesDoesNotMonitor() {
        let settings = AppSettings(officeLocationEnabled: true)  // no coordinates
        let lm = LocationManager()
        lm.updateMonitoring(for: settings)
        #expect(lm.isMonitoring == false)
    }

    @Test func updateMonitoringWithoutAlwaysAuthorizationDoesNotMonitor() {
        // Default authorizationStatus is .notDetermined, not .authorizedAlways
        let settings = AppSettings(officeLocationEnabled: true,
                                   officeLatitude: 52.5, officeLongitude: 13.4)
        let lm = LocationManager()
        lm.updateMonitoring(for: settings)
        #expect(lm.isMonitoring == false)
    }

    // MARK: - didEnterRegion / didExitRegion

    @Test func didEnterRegionWithWrongIdentifierDoesNotCreateEntry() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TimeEntry.self, configurations: config)
        let lm = LocationManager()
        lm.setup(modelContainer: container)

        let wrong = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100, identifier: "wrong.identifier"
        )
        lm.locationManager(CLLocationManager(), didEnterRegion: wrong)

        let entries = try ModelContext(container).fetch(FetchDescriptor<TimeEntry>())
        #expect(entries.isEmpty)
    }

    @Test func didEnterRegionCreatesOfficeWorkingTimeEntry() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TimeEntry.self, configurations: config)
        let lm = LocationManager()
        lm.setup(modelContainer: container)

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100, identifier: LocationManager.regionIdentifier
        )
        lm.locationManager(CLLocationManager(), didEnterRegion: region)

        let entries = try ModelContext(container).fetch(FetchDescriptor<TimeEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].type == .workingTime)
        #expect(entries[0].location == .office)
    }

    @Test func didExitRegionCreatesHomeOfficeWorkingTimeEntry() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TimeEntry.self, configurations: config)
        let lm = LocationManager()
        lm.setup(modelContainer: container)

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100, identifier: LocationManager.regionIdentifier
        )
        lm.locationManager(CLLocationManager(), didExitRegion: region)

        let entries = try ModelContext(container).fetch(FetchDescriptor<TimeEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].type == .workingTime)
        #expect(entries[0].location == .homeOffice)
    }

    @Test func didExitRegionWithWrongIdentifierDoesNotCreateEntry() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TimeEntry.self, configurations: config)
        let lm = LocationManager()
        lm.setup(modelContainer: container)

        let wrong = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100, identifier: "wrong.identifier"
        )
        lm.locationManager(CLLocationManager(), didExitRegion: wrong)

        let entries = try ModelContext(container).fetch(FetchDescriptor<TimeEntry>())
        #expect(entries.isEmpty)
    }
}
