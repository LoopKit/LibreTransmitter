//
//  Userdefaults+Alarmsettings.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 20/04/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

/// How readings are smoothed before they are reported. One kind at a time, never both,
/// so the lag of one doesn't add to the other.
enum GlucoseSmoothingMode: String, CaseIterable {
    /// Nothing is smoothed
    case off
    /// Sensor temperature is low pass filtered before temperature compensation; glucose is not averaged
    case temperature
    /// Trend readings are averaged over about five minutes, as before the temperature filter existed
    case glucose

    var smoothsTemperature: Bool {
        self == .temperature
    }

    var smoothsGlucose: Bool {
        self == .glucose
    }
}

extension UserDefaults {
    private enum Key: String {
        case mmSyncToNS = "com.loopkit.libreSyncToNs"
        case mmBackfillFromHistory = "com.loopkit.libreBackfillFromHistory"
        case glucoseSmoothingEnabled = "com.loopkit.libreGlucoseSmoothingEnabled"
        case glucoseSmoothingMode = "com.loopkit.libreGlucoseSmoothingMode"
    }

    var mmSyncToNs: Bool {
        get {
             optionalBool(forKey: Key.mmSyncToNS.rawValue) ?? true
        }
        set {
            set(newValue, forKey: Key.mmSyncToNS.rawValue)
        }
    }

    var mmBackfillFromHistory: Bool {
        get {
             optionalBool(forKey: Key.mmBackfillFromHistory.rawValue) ?? true
        }
        set {
            set(newValue, forKey: Key.mmBackfillFromHistory.rawValue)
        }
    }

    /// Before the mode existed there was only glucose smoothing, on by default; whoever had
    /// it on or off keeps it that way
    var glucoseSmoothingMode: GlucoseSmoothingMode {
        get {
            if let mode = string(forKey: Key.glucoseSmoothingMode.rawValue).flatMap(GlucoseSmoothingMode.init(rawValue:)) {
                return mode
            }
            return optionalBool(forKey: Key.glucoseSmoothingEnabled.rawValue) == false ? .off : .glucose
        }
        set {
            set(newValue.rawValue, forKey: Key.glucoseSmoothingMode.rawValue)
        }
    }

    var glucoseSmoothingEnabled: Bool {
        glucoseSmoothingMode.smoothsGlucose
    }

    var temperatureSmoothingEnabled: Bool {
        glucoseSmoothingMode.smoothsTemperature
    }

}
