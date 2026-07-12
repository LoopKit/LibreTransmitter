//
//  Userdefaults+Alarmsettings.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 20/04/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

extension UserDefaults {
    private enum Key: String {
        case mmAlertLowBatteryWarning = "com.loopkit.libreLowBatteryWarning"
        case mmAlertInvalidSensorDetected = "com.loopkit.libreInvalidSensorDetected"
        case mmAlertNewSensorDetected = "com.loopkit.libreNewSensorDetected"
        case mmAlertNoSensorDetected = "com.loopkit.libreNoSensorDetected"
        case mmAlertSensorSoonExpire = "com.loopkit.libreAlertSensorSoonExpire"
        case mmDangerMode = "com.loopkit.libreDangerModeActivated"
    }
   
    public func optionalBool(forKey defaultName: String) -> Bool? {
        if let value = value(forKey: defaultName) {
            return value as? Bool
        }
        return nil
    }

    var mmAlertLowBatteryWarning: Bool {
        get {
            optionalBool(forKey: Key.mmAlertLowBatteryWarning.rawValue) ?? true
        }
        set {
            set(newValue, forKey: Key.mmAlertLowBatteryWarning.rawValue)
        }
    }
    var mmAlertInvalidSensorDetected: Bool {
        get {
            optionalBool(forKey: Key.mmAlertInvalidSensorDetected.rawValue) ?? true
        }
        set {
            set(newValue, forKey: Key.mmAlertInvalidSensorDetected.rawValue)
        }
    }

    var mmAlertNewSensorDetected: Bool {
        get {
            optionalBool(forKey: Key.mmAlertNewSensorDetected.rawValue) ?? true
        }
        set {
            set(newValue, forKey: Key.mmAlertNewSensorDetected.rawValue)
        }
    }

    var mmAlertNoSensorDetected: Bool {
        get {
            optionalBool(forKey: Key.mmAlertNoSensorDetected.rawValue) ?? true
        }
        set {
            set(newValue, forKey: Key.mmAlertNoSensorDetected.rawValue)
        }
    }

    var mmAlertWillSoonExpire: Bool {
        get {
            optionalBool(forKey: Key.mmAlertSensorSoonExpire.rawValue) ?? true
        }
        set {
            set(newValue, forKey: Key.mmAlertSensorSoonExpire.rawValue)
        }
    }

    

    var dangerModeActivated: Bool {
        get {
            optionalBool(forKey: Key.mmDangerMode.rawValue) ?? false
        }
        set {
            set(newValue, forKey: Key.mmDangerMode.rawValue)
        }
    }

}
