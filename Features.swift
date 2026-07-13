//
//  Features.swift
//  LibreTransmitter
//
//  Created on 30/08/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

import CoreNFC

public final class Features {

    private static let allowOneMinuteReadingsKey = "com.loopkit.libre.experimentalMinuteByMinuteForwarding"

    static public var logSubsystem = "com.loopkit.libre"
    
    static public var glucoseSettingsRequireAuthentication = false
    
    static public var allowsEditingFactoryCalibrationData = false
    static public var allowOneMinuteReadings: Bool {
        get { UserDefaults.standard.bool(forKey: allowOneMinuteReadingsKey) }
        set { UserDefaults.standard.set(newValue, forKey: allowOneMinuteReadingsKey) }
    }

    static var currentMinimumDirectUpdateInterval: TimeInterval {
        minimumDirectUpdateInterval(oneMinuteReadingsEnabled: allowOneMinuteReadings)
    }

    static func minimumDirectUpdateInterval(oneMinuteReadingsEnabled: Bool) -> TimeInterval {
        (oneMinuteReadingsEnabled ? 0.8 : 4.5) * 60
    }
    
    static var phoneNFCAvailable: Bool {
        return NFCNDEFReaderSession.readingAvailable
    }
}
