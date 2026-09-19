//
//  LibreSensorLifecycle.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// A unified view of sensor lifecycle state across both LibreTransmitter data paths
/// (classic BLE transmitters like MiaoMiao/Bubble, and direct Libre2 BLE).
public enum LibreSensorLifecycle: Equatable {
    case noSensor
    case warmup(progress: Double, remaining: TimeInterval)
    case active(remaining: TimeInterval, total: TimeInterval)
    case expired
    case signalLost(since: Date)
    case failed
    case unactivated

    /// A normalized, cross-data-path representation of a hard sensor fault.
    public enum FaultKind: Equatable {
        case sensorFailure
        case encryptedOrUnsupported
        case noSensorFound
    }

    static let signalLostThreshold: TimeInterval = .minutes(6)

    public static func compute(
        sensorPaired: Bool,
        activatedAt: Date?,
        expiresAt: Date?,
        latestReadingAt: Date?,
        sensorMaxMinutesWearTime: Int,
        sensorState: SensorState?,
        lastFault: FaultKind?,
        now: Date = Date()
    ) -> LibreSensorLifecycle {
        guard sensorPaired else {
            return .noSensor
        }

        switch lastFault {
        case .sensorFailure:
            return .failed
        case .encryptedOrUnsupported, .noSensorFound:
            return .unactivated
        case nil:
            break
        }

        guard let activatedAt, let expiresAt, sensorMaxMinutesWearTime > 0 else {
            return .noSensor
        }

        let age = now.timeIntervalSince(activatedAt)
        let wear = TimeInterval(minutes: Double(sensorMaxMinutesWearTime))

        if age >= wear || now >= expiresAt {
            return .expired
        }

        if sensorState == .starting || sensorState == .notYetStarted {
            return .warmup(progress: age / wear, remaining: wear - age)
        }

        // If we've never received a successful reading yet, treat this as an
        // initial grace period rather than signal loss, to avoid false positives
        // immediately after pairing/activation.
        if let latestReadingAt, now.timeIntervalSince(latestReadingAt) > signalLostThreshold {
            return .signalLost(since: latestReadingAt)
        }

        return .active(remaining: wear - age, total: wear)
    }
}
