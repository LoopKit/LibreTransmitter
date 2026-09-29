//
//  LibreSensorLifecycle+Display.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LibreTransmitter
import LoopKitUI

/// A settings-row-friendly status derived from `LibreSensorLifecycle` plus the
/// live BLE connection state. `LibreSensorLifecycle` alone can't distinguish
/// "paired but not yet reconnected since app launch" from "truly no sensor" -
/// that distinction only exists once you also know whether there's a live
/// link right now, which is why this lives one layer above the pure lifecycle
/// enum. Mirrors SyaiKit's `SyaiSensorStatusDisplay`.
enum LibreSensorStatusDisplay: Equatable {
    case noSensor
    case connecting
    case ok
    case warmingUp
    case expired
    case malfunction
    case notActivated
    case signalLost
    /// Sensor is otherwise reporting normally, but its most recent measurement carried
    /// one or more non-fatal firmware error/quality bits (e.g. temperature out of range,
    /// rate of change too fast). Distinct from - and lower priority than - the lifecycle
    /// states above, which all take precedence when active.
    case measurementIssue([MeasurementError])

    enum Severity { case neutral, good, warning, critical }

    var severity: Severity {
        switch self {
        case .connecting, .noSensor, .warmingUp: return .neutral
        case .ok: return .good
        case .signalLost, .measurementIssue: return .warning
        case .expired, .malfunction, .notActivated: return .critical
        }
    }

    var iconName: String {
        switch self {
        case .noSensor: return "plus.circle"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .ok: return "checkmark.circle.fill"
        case .warmingUp: return "hourglass"
        case .signalLost: return "antenna.radiowaves.left.and.right.slash"
        case .expired, .malfunction, .notActivated: return "exclamationmark.triangle.fill"
        case .measurementIssue: return "exclamationmark.triangle"
        }
    }

    func iconColor(_ guidanceColors: GuidanceColors) -> Color {
        switch severity {
        case .neutral: return .secondary
        case .good: return .green
        case .warning: return guidanceColors.warning
        case .critical: return guidanceColors.critical
        }
    }

    var title: Text {
        switch self {
        case .noSensor: return Text("No Sensor", comment: "status no sensor")
        case .connecting: return Text("Connecting", comment: "status connecting")
        case .ok: return Text("Sensor OK", comment: "status ok")
        case .warmingUp: return Text("Warming Up", comment: "status warming up")
        case .expired: return Text("Sensor Expired", comment: "status expired")
        case .malfunction: return Text("Sensor Malfunction", comment: "status malfunction")
        case .notActivated: return Text("Sensor Not Detected", comment: "status sensor not activated")
        case .signalLost: return Text("Signal Loss", comment: "status signal lost")
        case .measurementIssue: return Text("Sensor Issues", comment: "status measurement issue")
        }
    }

    var message: Text {
        switch self {
        case .noSensor:
            return Text("Pair a sensor to start receiving readings.", comment: "msg no sensor")
        case .connecting:
            return Text("Establishing a connection to your sensor.", comment: "msg connecting")
        case .ok:
            return Text("Your sensor is functioning normally.", comment: "msg ok")
        case .warmingUp:
            return Text("Your sensor is warming up.", comment: "msg warming up")
        case .expired:
            return Text("Your sensor has expired. Replace it as soon as possible.", comment: "msg expired")
        case .malfunction:
            return Text("Your sensor is malfunctioning. Replace it as soon as possible.", comment: "msg malfunction")
        case .notActivated:
            return Text(
                "Your sensor is not detected or reports as invalid. If this continues, remove and re-pair it.",
                comment: "msg sensor not activated"
            )
        case .signalLost:
            return Text(
                "Signal lost. Check that your sensor is nearby and Bluetooth is on.",
                comment: "msg signal lost"
            )
        case let .measurementIssue(errors):
            return Text(errors.map(\.localizedDescription).joined(separator: "\n"))
        }
    }

    /// Combines the pairing/data-driven `LibreSensorLifecycle` with a live BLE
    /// connection flag - and, critically, with `isDeviceSelected` checked
    /// *first* and independently of the lifecycle. `sensorLifecycle` can
    /// resolve past its `.noSensor` default from persisted state restored at
    /// launch (`LibreCGMManagerState` via `init(rawState:)`) just as well as
    /// from a live data exchange this session - but a persisted resolution
    /// can be stale until a live connection is reestablished, so gating on
    /// `lifecycle != .noSensor` alone would show whatever the last-known
    /// state was as if it were current for the entire window from app launch
    /// until the first successful read - collapsing straight from a
    /// possibly-stale resolved state to whatever the freshly resolved state
    /// turns out to be, with no "Connecting" in between. Checking
    /// `isDeviceSelected` first (backed by persisted UserDefaults pairing
    /// state, available synchronously, independent of any BLE data) is what
    /// actually makes "Connecting"
    /// reachable. Not-currently-connected wins over a stale lifecycle read
    /// (e.g. `.expired`); without a live link there's no way to be sure the last-known state still holds,
    /// and it resolves itself the moment the link comes back.
    static func compute(
        lifecycle: LibreSensorLifecycle,
        isDeviceSelected: Bool,
        isConnected: Bool,
        measurementErrors: [MeasurementError] = []
    ) -> LibreSensorStatusDisplay {
        guard isDeviceSelected else {
            return .noSensor
        }
        guard isConnected else {
            return .connecting
        }
        switch lifecycle {
        case .noSensor:
            // Connected, but no data has been parsed into a resolved lifecycle yet.
            return .connecting
        case .warmup:
            return .warmingUp
        case .active:
            let issues = measurementErrors.filter { $0 != .OK }
            return issues.isEmpty ? .ok : .measurementIssue(issues)
        case .expired:
            return .expired
        case .signalLost:
            return .signalLost
        case .failed:
            return .malfunction
        case .unactivated:
            return .notActivated
        }
    }
}
