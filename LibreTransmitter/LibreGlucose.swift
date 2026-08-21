//
//  MiaomiaoClient.h
//  MiaomiaoClient
//

import Foundation
import LoopKit
import os.log
import LoopAlgorithm

private var logger = Logger(forType: "LibreGlucose")

public struct LibreGlucose: Codable, Hashable {
    public let unsmoothedGlucose: Double
    public var glucoseDouble: Double
    public var error = [MeasurementError.OK]
    public var glucose: UInt16 {
        UInt16(glucoseDouble.rounded())
    }

    public var timestamp: Date

    public init(unsmoothedGlucose: Double, glucoseDouble: Double, error: [MeasurementError] = [MeasurementError.OK], timestamp: Date) {
        self.unsmoothedGlucose = unsmoothedGlucose
        self.glucoseDouble = glucoseDouble
        self.timestamp = timestamp
    }

    public static func timeDifference(oldGlucose: LibreGlucose, newGlucose: LibreGlucose) -> TimeInterval {
        newGlucose.startDate.timeIntervalSince(oldGlucose.startDate)
    }

    public var syncId: String {
        "\(Int(self.startDate.timeIntervalSince1970))\(self.unsmoothedGlucose)"
    }

    public var isStateValid: Bool {
        // We know that the official libre algorithm doesn't produce values
        // below 39. However, both the raw sensor contents and the derived algorithm
        // supports values down to 0 without issues. A bit uncertain if nightscout and loop will work with values below 1, so we restrict this to 1
        glucose >= 1
    }

    public func GetGlucoseTrend(last: Self) -> GlucoseTrend {
        Self.GetGlucoseTrend(current: self, last: last)
    }
}

extension LibreGlucose: GlucoseValue {
    public var startDate: Date {
        timestamp
    }

    public var quantity: LoopQuantity {
        .init(unit: .milligramsPerDeciliter, doubleValue: glucoseDouble)
    }
}

extension LibreGlucose {
    private static let preferredTrendInterval: TimeInterval = 5 * 60
    private static let allowedTrendInterval: ClosedRange<TimeInterval> = (4 * 60)...(6 * 60)

    static func calculateSlope(current: Self, last: Self) -> Double {
        if current.timestamp == last.timestamp {
            return 0.0
        }

        let _curr = Double(current.timestamp.timeIntervalSince1970 * 1_000)
        let _last = Double(last.timestamp.timeIntervalSince1970 * 1_000)

        return (last.glucoseDouble - current.glucoseDouble) / (_last - _curr)
    }

    static func calculateSlopeByMinute(current: Self, last: Self) -> Double {
        return calculateSlope(current: current, last: last) * 60_000
    }

    static func calculateRecentTrend(in glucoses: [Self]) -> (trend: GlucoseTrend, rate: Double)? {
        let sortedGlucoses = glucoses.sorted { $0.startDate > $1.startDate }
        guard let newest = sortedGlucoses.first else {
            return nil
        }

        let reference = sortedGlucoses.dropFirst()
            .filter {
                allowedTrendInterval.contains(newest.startDate.timeIntervalSince($0.startDate))
            }
            .min {
                abs(newest.startDate.timeIntervalSince($0.startDate) - preferredTrendInterval) <
                    abs(newest.startDate.timeIntervalSince($1.startDate) - preferredTrendInterval)
            }

        guard let reference else {
            return nil
        }

        return (
            trend: newest.GetGlucoseTrend(last: reference),
            rate: calculateSlopeByMinute(current: newest, last: reference)
        )
    }

    static func GetGlucoseTrend(current: Self?, last: Self?) -> GlucoseTrend {

        guard let current, let last else {
            return  .flat
        }

        let  s = calculateSlopeByMinute(current: current, last: last)

        switch s {
        case _ where s <= (-3.5):
            return .downDownDown
        case _ where s <= (-2):
            return .downDown
        case _ where s <= (-1):
            return .down
        case _ where s <= (1):
            return .flat
        case _ where s <= (2):
            return .up
        case _ where s <= (3.5):
            return .upUp
        case _ where s <= (40):
            return .upUpUp

        default:

            return .flat
        }
    }
}

extension LibreGlucose {
    static func fromHistoryMeasurements(_ measurements: [Measurement], nativeCalibrationData: SensorData.CalibrationInfo) -> [LibreGlucose] {
        var arr = [LibreGlucose]()

        for historical in measurements {
            let calibrated = historical.calibratedGlucose(calibrationInfo: nativeCalibrationData)
            let glucose = LibreGlucose(
                // unsmoothedGlucose: historical.temperatureAlgorithmGlucose,
                // glucoseDouble: historical.temperatureAlgorithmGlucose,
                unsmoothedGlucose: calibrated,
                glucoseDouble: calibrated,
                error: historical.error,
                timestamp: historical.date)

            if glucose.glucoseDouble > 0 {
                arr.append(glucose)
            }
        }

        return arr
    }

    static func fromTrendMeasurements(_ measurements: [Measurement], nativeCalibrationData: SensorData.CalibrationInfo) -> [LibreGlucose] {
        var arr = [LibreGlucose]()

        var shouldSmoothGlucose = true
        for trend in measurements {
            // trend arrows on each libreglucose value is not needed
            // instead we calculate it once when latestbackfill is set, which in turn sets
            // the sensordisplayable property
            let glucose = LibreGlucose(
                // unsmoothedGlucose: trend.temperatureAlgorithmGlucose,
                unsmoothedGlucose: trend.calibratedGlucose(calibrationInfo: nativeCalibrationData),
                glucoseDouble: 0.0,
                error: trend.error,
                timestamp: trend.date)
            // if sensor is ripped off body while transmitter is attached, values below 1 might be created
            // libre manual: glucose readings are gathered in the system range of 40-500 mg/dL
            if glucose.unsmoothedGlucose > 0 && glucose.unsmoothedGlucose <= 500 {
                arr.append(glucose)
            }

            // Just for expliciticity, if one of the values are 0,
            // then the rest of the values should not be smoothed
            if glucose.unsmoothedGlucose <= 0 {
                shouldSmoothGlucose = false
            }
        }

        let smoothingEnabled = UserDefaults.standard.glucoseSmoothingEnabled
        if shouldSmoothGlucose && smoothingEnabled {
            logger.debug("Glucose smoothing applied to \(arr.count) trend readings")
            arr = CalculateSmothedData5Points(origtrends: arr)
        } else if shouldSmoothGlucose {
            let smoothedReadings = CalculateSmothedData5Points(origtrends: arr)
            let smoothingDifferences = zip(arr, smoothedReadings)
                .map { pair in
                    let (raw, smoothed) = pair
                    return "\(raw.timestamp)=\(smoothed.glucoseDouble - raw.unsmoothedGlucose) mg/dL"
                }
                .joined(separator: ", ")
            logger.debug("Glucose smoothing disabled; timestamp differences: \(smoothingDifferences)")
            for i in 0 ..< arr.count {
                arr[i].glucoseDouble = arr[i].unsmoothedGlucose
            }
        } else {
            logger.debug("Glucose smoothing skipped because the trend batch contains an invalid reading")
            for i in 0 ..< arr.count {
                arr[i].glucoseDouble = arr[i].unsmoothedGlucose
            }
        }

        return arr
    }
}
