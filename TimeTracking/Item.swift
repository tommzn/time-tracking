//
//  Item.swift
//  TimeTracking
//
//  Created by Thomas Schenker on 03.04.26.
//

import Foundation
import SwiftData

enum EntryType: String, Codable, CaseIterable {
    case workingTime = "workingTime"
    case sickness    = "sickness"
    case vacation    = "vacation"

    var label: String {
        switch self {
        case .workingTime: "Working Time"
        case .sickness:    "Sickness"
        case .vacation:    "Vacation"
        }
    }

    var systemImage: String {
        switch self {
        case .workingTime: "deskclock.fill"
        case .sickness:    "cross.fill"
        case .vacation:    "sun.max.fill"
        }
    }
}

enum WorkLocation: String, Codable, CaseIterable {
    case homeOffice = "homeOffice"
    case office     = "office"

    var label: String {
        switch self {
        case .homeOffice: "Home Office"
        case .office:     "Office"
        }
    }
}

@Model
final class TimeEntry {
    var timestamp: Date = Date()
    var type: EntryType = EntryType.workingTime
    var location: WorkLocation?   // nil for sickness / vacation

    init(timestamp: Date, type: EntryType, location: WorkLocation? = nil) {
        self.timestamp = timestamp
        self.type = type
        self.location = (type == .workingTime) ? location : nil
    }
}
