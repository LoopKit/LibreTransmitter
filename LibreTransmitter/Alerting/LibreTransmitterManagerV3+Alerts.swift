//
//  LibreTransmitterManagerV3+Alerts.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

extension LibreTransmitterManagerV3 {
    /// Diffs the currently-firing lifecycle alert conditions against the previous
    /// evaluation and issues/retracts LoopKit Alerts for the delta.
func evaluateAlerts() {
    // Serialize evaluation + state mutation to avoid races between delegate callbacks and polling.
    delegateQueue.async { [weak self] in
        guard let self else { return }

        let shouldFire = LibreAlertCondition.currentlyFiring(for: self.sensorLifecycle)
        guard shouldFire != self.firingAlertConditions else {
            return
        }

        let delegate = self.cgmManagerDelegate
        let managerIdentifier = Self.pluginIdentifier
        let newlyFiring = shouldFire.subtracting(self.firingAlertConditions)
        let noLongerFiring = self.firingAlertConditions.subtracting(shouldFire)

        for condition in newlyFiring {
            delegate?.issueAlert(condition.alert(managerIdentifier: managerIdentifier))
        }
        for condition in noLongerFiring {
            delegate?.retractAlert(identifier: condition.identifier(managerIdentifier: managerIdentifier))
        }

        self.firingAlertConditions = shouldFire
    }
}
