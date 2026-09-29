//
//  MeasurementError+Display.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

public extension MeasurementError {
    var localizedDescription: String {
        switch self {
        case .OK:
            return ""
        case .SD14_FIFO_OVERFLOW:
            return LocalizedString("Sensor data buffer overflow.", comment: "Placeholder description for SD14_FIFO_OVERFLOW sensor measurement error")
        case .FILTER_DELTA:
            return LocalizedString("Reading changed too abruptly to trust.", comment: "Placeholder description for FILTER_DELTA sensor measurement error")
        case .WORK_VOLTAGE:
            return LocalizedString("Sensor working voltage out of range.", comment: "Placeholder description for WORK_VOLTAGE sensor measurement error")
        case .PEAK_DELTA_EXCEEDED:
            return LocalizedString("A single reading changed too abruptly to be physiologically plausible and was discarded.", comment: "Description for PEAK_DELTA_EXCEEDED sensor measurement error: one anomalous sample-to-sample spike, rejected as an implausible single-reading jump")
        case .AVG_DELTA_EXCEEDED:
            return LocalizedString("Glucose is changing faster than physiologically plausible; readings are being discarded until it stabilizes.", comment: "Description for AVG_DELTA_EXCEEDED sensor measurement error: rate of change over several readings too fast to trust")
        case .RF:
            return LocalizedString("Radio signal interference detected.", comment: "Placeholder description for RF sensor measurement error")
        case .REF_R:
            return LocalizedString("Sensor reference resistance out of range.", comment: "Placeholder description for REF_R sensor measurement error")
        case .SIGNAL_SATURATED:
            return LocalizedString("Sensor signal is saturated and can't be converted to a glucose value.", comment: "Description for SIGNAL_SATURATED sensor measurement error: raw signal clipped at its maximum")
        case .SENSOR_SIGNAL_LOW:
            return LocalizedString("Sensor signal is too weak to measure reliably.", comment: "Description for SENSOR_SIGNAL_LOW sensor measurement error: weak/degraded electrochemical signal, e.g. failing sensor or poor insertion")
        case .THERMISTOR_OUT_OF_RANGE:
            return LocalizedString("Sensor's temperature sensor is reporting an implausible value.", comment: "Description for THERMISTOR_OUT_OF_RANGE sensor measurement error: raw thermistor reading outside its plausible electrical range - a hardware fault, not a temporary condition")
        case .TEMP_HIGH:
            return LocalizedString("Sensor is too hot to measure glucose. This should resolve on its own within a few minutes.", comment: "Description for TEMP_HIGH sensor measurement error, matching Abbott's own \"Sensor Too Hot\" wording")
        case .TEMP_LOW:
            return LocalizedString("Sensor is too cold to measure glucose. This should resolve on its own within a few minutes.", comment: "Description for TEMP_LOW sensor measurement error, matching Abbott's own \"Sensor Too Cold\" wording")
        case .INVALID_DATA:
            return LocalizedString("Sensor data failed validation and can't be processed.", comment: "Description for INVALID_DATA sensor measurement error: corrupt or inconsistent payload/frame")
        }
    }
}
