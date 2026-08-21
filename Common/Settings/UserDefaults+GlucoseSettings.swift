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
        case mmSyncToNS = "com.loopkit.libreSyncToNs"
        case mmBackfillFromHistory = "com.loopkit.libreBackfillFromHistory"
        case glucoseSmoothingEnabled = "com.loopkit.libreGlucoseSmoothingEnabled"
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

    var glucoseSmoothingEnabled: Bool {
        get {
            optionalBool(forKey: Key.glucoseSmoothingEnabled.rawValue) ?? true
        }
        set {
            set(newValue, forKey: Key.glucoseSmoothingEnabled.rawValue)
        }
    }

}
