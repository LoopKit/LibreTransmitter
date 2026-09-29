//
//  LibreTransmitterManager+UI.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit
import LibreTransmitter
import Combine

struct LibreLifecycleProgress: DeviceLifecycleProgress {
    var percentComplete: Double

    var progressState: LoopKit.DeviceLifecycleProgressState
}

struct LibreStatusHighlight: DeviceStatusHighlight {
    var localizedMessage: String
    var imageName: String
    var state: DeviceStatusHighlightState
}

struct LibreStatusBadge: DeviceStatusBadge {
    var image: UIImage?
    var state: DeviceStatusBadgeState
}

extension LibreTransmitterManagerV3: CGMManagerUI {

    public var cgmStatusBadge: DeviceStatusBadge? {
        switch sensorLifecycle {
        case .expired:
            return LibreStatusBadge(image: UIImage(systemName: "exclamationmark.triangle.fill"), state: .critical)
        default:
            return nil
        }
    }

    public static func setupViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, prefersToSkipUserInteraction: Bool) -> SetupUIResult<CGMManagerViewController, CGMManagerUI>
    {
        let cgmManager = self.init()
        let vc = LibreTransmitterSetupViewController(displayGlucosePreference: displayGlucosePreference, cgmManager: cgmManager)

        return .userInteractionRequired(vc)
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> CGMManagerViewController {

        let doneNotifier = GenericObservableObject()
        let wantToTerminateNotifier = GenericObservableObject()

        let wantToResetCGMManagerNotifier = GenericObservableObject()

        let wantToRestablishConnectionNotifier = GenericObservableObject()

        let wantToShowDeviceDetailsNotifier = GenericObservableObject()
        let wantToShowCalibrationsNotifier = GenericObservableObject()

        let settingsView = SettingsView(
            transmitterInfo: self.transmitterInfoObservable,
            sensorInfo: self.sensorInfoObservable,
            glucoseMeasurement: self.glucoseInfoObservable,
            notifyComplete: doneNotifier,
            notifyDelete: wantToTerminateNotifier,
            notifyReset: wantToResetCGMManagerNotifier,
            notifyReconnect:wantToRestablishConnectionNotifier,
            notifyShowDeviceDetails: wantToShowDeviceDetailsNotifier,
            notifyShowCalibrations: wantToShowCalibrationsNotifier,
            pairingService: self.pairingService,
            bluetoothSearcher: self.bluetoothSearcher
        )

        // SettingsView has no NavigationStack/NavigationView, so SwiftUI's own .navigationTitle
        // has nothing to propagate through - neither DismissibleHostingController nor
        // CGMManagerSettingsNavigationViewController bridge that preference into UIKit's
        // navigationItem.title. Titles for this screen and everything it pushes are set
        // directly on navigationItem below instead (matching SyaiKit's SyaiUIController).
        let hostedView = DismissibleHostingController(
            content: settingsView
                .environmentObject(displayGlucosePreference)
        )
        hostedView.navigationItem.title = self.localizedTitle
        hostedView.navigationItem.largeTitleDisplayMode = .always

        let nav = CGMManagerSettingsNavigationViewController(rootViewController: hostedView)
        nav.navigationBar.prefersLargeTitles = true

        wantToShowDeviceDetailsNotifier.listen { [weak self, weak nav] in
            guard let self, let nav else { return }
            let detailHost = DismissibleHostingController(content: DeviceInfoView(transmitterInfo: self.transmitterInfoObservable))
            detailHost.navigationItem.title = LocalizedString("Device Info", comment: "Text describing header for device info section")
            nav.pushViewController(detailHost, animated: true)
        }

        wantToShowCalibrationsNotifier.listen { [weak nav] in
            guard let nav else { return }
            let calibrationHost = DismissibleHostingController(content: CalibrationEditView())
            calibrationHost.navigationItem.title = Features.allowsEditingFactoryCalibrationData
                ? LocalizedString("Calibration Edit", comment: "Title for calibration edit screen")
                : LocalizedString("Calibration Details", comment: "Title for calibration details screen")
            nav.pushViewController(calibrationHost, animated: true)
        }

        wantToResetCGMManagerNotifier.listenOnce { [weak self] in
            self?.logger.debug("CGM wants to reset cgmmanager")
            self?.resetManager()

        }
        
        wantToRestablishConnectionNotifier.listenOnce { [weak self, weak nav] in
            self?.logger.debug("CGM wants to RestablishConnection")
            self?.establishProxy()
            nav?.notifyComplete()
        }
        
        doneNotifier.listenOnce { [weak nav] in
            nav?.notifyComplete()

        }

        wantToTerminateNotifier.listenOnce { [weak self, weak nav] in
            self?.logger.debug("CGM wants to terminate")
            self?.disconnect()

            UserDefaults.standard.preSelectedDevice = nil
            self?.notifyDelegateOfDeletion {
                DispatchQueue.main.async {
                    nav?.notifyComplete()

                }
            }

        }

        return nav
    }

    public var cgmStatusHighlight: DeviceStatusHighlight? {
        switch sensorLifecycle {
        case .warmup:
            return LibreStatusHighlight(localizedMessage: LocalizedString("Sensor\nWarmup", comment: "Status highlight message for sensor warmup"), imageName: "clock", state: .normalCGM)
        case .active:
            return nil
        case .expired:
            return LibreStatusHighlight(localizedMessage: LocalizedString("Sensor\nExpired", comment: "Status highlight message for expired sensor"), imageName: "clock", state: .critical)
        case .signalLost:
            return LibreStatusHighlight(localizedMessage: LocalizedString("Signal\nLoss", comment: "Status highlight message for signal loss"), imageName: "exclamationmark.circle.fill", state: .warning)
        case .failed:
            return LibreStatusHighlight(localizedMessage: LocalizedString("Replace\nSensor", comment: "Status highlight message for a failed sensor"), imageName: "exclamationmark.circle.fill", state: .critical)
        case .unactivated:
            return LibreStatusHighlight(localizedMessage: LocalizedString("Sensor\nNot Detected", comment: "Status highlight message for a sensor that is not detected"), imageName: "exclamationmark.circle.fill", state: .critical)
        case .noSensor:
            return nil
        }
    }

    public var cgmLifecycleProgress: DeviceLifecycleProgress? {
        if self.sensorInfoObservable.activatedAt == nil {
            // This is the initial state before the plugin
            // has connected to the sensor and retrieved its cgmLifecycleProgress
            // We could show 0 here, but UX-wise it's probably wiser to not do so
            return nil
        }

        switch sensorLifecycle {
        case let .warmup(progress, _):
            return LibreLifecycleProgress(percentComplete: progress, progressState: .warning)
        case let .active(remaining, total):
            // Mirrors G7SensorKit's cgmLifecycleProgress exactly: the bar only
            // appears in the final 48h, .warning inside the final 24h,
            // .normalCGM for the 24-48h stretch before that.
            guard remaining < TimeInterval(hours: 48) else {
                return nil
            }
            let percent = 1 - (remaining / total)
            let state: DeviceLifecycleProgressState = remaining < TimeInterval(hours: 24) ? .warning : .normalCGM
            return LibreLifecycleProgress(percentComplete: percent, progressState: state)
        case .expired:
            return LibreLifecycleProgress(percentComplete: 1, progressState: .critical)
        case .signalLost, .failed, .unactivated, .noSensor:
            return nil
        }
    }
}

extension LibreTransmitterManagerV3: DeviceManagerUI {
    public static var onboardingImage: UIImage? {
        nil
    }

    public var smallImage: UIImage? {
       self.getSmallImage()
    }
}
