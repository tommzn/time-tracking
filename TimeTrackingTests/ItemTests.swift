//
//  ItemTests.swift
//  TimeTrackingTests
//

import Testing
@testable import TimeTracking

// MARK: - EntryType

struct EntryTypeTests {

    @Test func workingTimeLabel() {
        #expect(EntryType.workingTime.label == "Working Time")
    }

    @Test func sicknessLabel() {
        #expect(EntryType.sickness.label == "Sickness")
    }

    @Test func vacationLabel() {
        #expect(EntryType.vacation.label == "Vacation")
    }

    @Test func workingTimeSystemImage() {
        #expect(EntryType.workingTime.systemImage == "deskclock.fill")
    }

    @Test func sicknessSystemImage() {
        #expect(EntryType.sickness.systemImage == "cross.fill")
    }

    @Test func vacationSystemImage() {
        #expect(EntryType.vacation.systemImage == "sun.max.fill")
    }

    @Test func allCasesAreCoveredByLabel() {
        // Ensures no case is accidentally mapped to a default/empty string
        for type in EntryType.allCases {
            #expect(!type.label.isEmpty)
        }
    }

    @Test func allCasesAreCoveredBySystemImage() {
        for type in EntryType.allCases {
            #expect(!type.systemImage.isEmpty)
        }
    }
}

// MARK: - WorkLocation

struct WorkLocationTests {

    @Test func homeOfficeLabel() {
        #expect(WorkLocation.homeOffice.label == "Home Office")
    }

    @Test func officeLabel() {
        #expect(WorkLocation.office.label == "Office")
    }

    @Test func allCasesAreCoveredByLabel() {
        for location in WorkLocation.allCases {
            #expect(!location.label.isEmpty)
        }
    }
}
