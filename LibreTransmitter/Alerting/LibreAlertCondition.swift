//
//  LibreAlertCondition.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Sensor-lifecycle conditions that are surfaced to the user via LoopKit's native
/// Alert framework (`issueAlert`/`retractAlert`). Glucose-threshold alerting is owned
/// by the app (Trio), not by this plugin.
public enum LibreAlertCondition: String, CaseIterable, Sendable {
    case signalLost
    case expired
    case failed
    case unactivated

    public static func currentlyFiring(for lifecycle: LibreSensorLifecycle) -> Set<LibreAlertCondition> {
        switch lifecycle {
        case .signalLost:
            return [.signalLost]
        case .expired:
            return [.expired]
        case .failed:
            return [.failed]
        case .unactivated:
            return [.unactivated]
        case .active, .noSensor, .warmup:
            return []
        }
    }

    public func identifier(managerIdentifier: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "libre.\(rawValue)")
    }

    private var title: String {
        switch self {
        case .signalLost:
            return LocalizedString("Signal Loss", comment: "Title for signal loss sensor alert")
        case .expired:
            return LocalizedString("Sensor Expired", comment: "Title for sensor expired alert")
        case .failed:
            return LocalizedString("Sensor Malfunction", comment: "Title for sensor malfunction alert")
        case .unactivated:
            return LocalizedString("Sensor Not Detected", comment: "Title for sensor not detected alert")
        }
    }

    private var body: String {
        switch self {
        case .signalLost:
            return LocalizedString("Signal lost. Check that your sensor is nearby and Bluetooth is on.", comment: "Body for signal loss sensor alert")
        case .expired:
            return LocalizedString("Sensor expired. Replace your sensor now.", comment: "Body for sensor expired alert")
        case .failed:
            return LocalizedString("Sensor malfunction. Replace your sensor now.", comment: "Body for sensor malfunction alert")
        case .unactivated:
            return LocalizedString("Sensor not detected or reporting as invalid. If this continues, remove and re-pair it.", comment: "Body for sensor not detected alert")
        }
    }

    private var interruptionLevel: Alert.InterruptionLevel {
        switch self {
        case .signalLost, .expired:
            return .timeSensitive
        case .failed, .unactivated:
            return .critical
        }
    }

    public func alert(managerIdentifier: String) -> Alert {
        let content = Alert.Content(
            title: title,
            body: body,
            acknowledgeActionButtonLabel: LocalizedString("OK", comment: "Alert acknowledge button")
        )
        return Alert(
            identifier: identifier(managerIdentifier: managerIdentifier),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: interruptionLevel
        )
    }
}
