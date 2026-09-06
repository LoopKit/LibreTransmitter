//
//  UserDefaults+Bluetooth.swift
//  MiaomiaoClientUI
//
//  Created by LoopKit Authors on 27/07/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
// import MiaomiaoClient

extension UserDefaults {
    private enum Key: String {
        case bluetoothDeviceUUIDString = "com.loopkit.librebluetoothDeviceUUIDString"
        case libre2UiD = "com.loopkit.libre2uid"
        case dangerMode = "com.loopkit.libreDangerModeActivated"
    }

    public func optionalBool(forKey defaultName: String) -> Bool? {
        if let value = value(forKey: defaultName) {
            return value as? Bool
        }
        return nil
    }

    var dangerModeActivated: Bool {
        get {
            optionalBool(forKey: Key.dangerMode.rawValue) ?? false
        }
        set {
            set(newValue, forKey: Key.dangerMode.rawValue)
        }
    }

    public var preSelectedUid: Data? {
        get {
            return data(forKey: Key.libre2UiD.rawValue)

        }
        set {
            if let newValue {
                set(newValue, forKey: Key.libre2UiD.rawValue)
            } else {
                print("Removing preSelectedUid")
                removeObject(forKey: Key.libre2UiD.rawValue)
            }
        }
    }

    public var preSelectedDevice: String? {
        get {
            if let astr = string(forKey: Key.bluetoothDeviceUUIDString.rawValue) {
                return astr.count > 0 ? astr : nil
            }
            return nil
        }
        set {
            if let newValue {
                set(newValue, forKey: Key.bluetoothDeviceUUIDString.rawValue)
            } else {
                removeObject(forKey: Key.bluetoothDeviceUUIDString.rawValue)
            }
        }
    }
}
