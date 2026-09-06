//
//  LibreCGMManagerState.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Persisted across app launches via `CGMManager.rawState`/`init(rawState:)`,
/// same as almost every other LoopKit CGM driver (e.g. `G7CGMManagerState`).
/// Without this, the plugin previously had nothing to show until the first
/// live BLE read of a session landed - every launch started from a blank
/// slate, unable to even say "we're paired to sensor X, expiring at Y" while
/// reconnecting.
public struct LibreCGMManagerState: RawRepresentable, Equatable {
    public typealias RawValue = CGMManager.RawStateValue

    public var activatedAt: Date?
    public var sensorMaxMinutesWearTime: Int
    public var sensorSerial: String?
    public var sensorType: String?
    public var latestReadingTimestamp: Date?
    public var lastConnected: Date?

    public init(
        activatedAt: Date? = nil,
        sensorMaxMinutesWearTime: Int = 0,
        sensorSerial: String? = nil,
        sensorType: String? = nil,
        latestReadingTimestamp: Date? = nil,
        lastConnected: Date? = nil
    ) {
        self.activatedAt = activatedAt
        self.sensorMaxMinutesWearTime = sensorMaxMinutesWearTime
        self.sensorSerial = sensorSerial
        self.sensorType = sensorType
        self.latestReadingTimestamp = latestReadingTimestamp
        self.lastConnected = lastConnected
    }

    public init(rawValue: RawValue) {
        self.activatedAt = rawValue["activatedAt"] as? Date
        self.sensorMaxMinutesWearTime = rawValue["sensorMaxMinutesWearTime"] as? Int ?? 0
        self.sensorSerial = rawValue["sensorSerial"] as? String
        self.sensorType = rawValue["sensorType"] as? String
        self.latestReadingTimestamp = rawValue["latestReadingTimestamp"] as? Date
        self.lastConnected = rawValue["lastConnected"] as? Date
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [:]
        rawValue["activatedAt"] = activatedAt
        rawValue["sensorMaxMinutesWearTime"] = sensorMaxMinutesWearTime
        rawValue["sensorSerial"] = sensorSerial
        rawValue["sensorType"] = sensorType
        rawValue["latestReadingTimestamp"] = latestReadingTimestamp
        rawValue["lastConnected"] = lastConnected
        return rawValue
    }

    /// `activatedAt + wear time`, matching how `SensorInfo.expiresAt` is
    /// computed live in `setObservables` (`now + minutesLeft`, which is
    /// algebraically the same thing once you substitute `minutesLeft =
    /// maxMinutesWearTime - minutesSinceStart` and `activatedAt = now -
    /// minutesSinceStart`).
    public var expiresAt: Date? {
        guard let activatedAt, sensorMaxMinutesWearTime > 0 else {
            return nil
        }
        return activatedAt.addingTimeInterval(TimeInterval(minutes: Double(sensorMaxMinutesWearTime)))
    }
}
