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

    static public var logSubsystem = "com.loopkit.libre"

    static public var allowsEditingFactoryCalibrationData = false
    static public var allowOneMinuteReadings = false

    static var phoneNFCAvailable: Bool {
        return NFCNDEFReaderSession.readingAvailable
    }
}
