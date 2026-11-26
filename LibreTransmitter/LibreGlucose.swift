//
//  MiaomiaoClient.h
//  MiaomiaoClient
//

import Foundation
import LoopKit
import os.log

private var logger = Logger(forType: "LibreGlucose")

public struct LibreGlucose: Codable, Hashable {
    public let unsmoothedGlucose: Double
    public var glucoseDouble: Double
    public var error = [MeasurementError.OK]
    public var glucose: UInt16 {
        UInt16(glucoseDouble.rounded())
    }

    public var timestamp: Date

    /// Set when the reading was outside the sensor's 40-500 mg/dL range: the glucose value is clamped
    /// to the boundary and this tells Loop/Nightscout the true value is below/above range (shown as
    /// LO/HI). This is the LoopKit mechanism for out-of-range readings - not isDisplayOnly, which
    /// would make Loop ignore the value and is unsafe for a genuine low.
    public var condition: GlucoseCondition?

    public init(unsmoothedGlucose: Double, glucoseDouble: Double, error: [MeasurementError] = [MeasurementError.OK], timestamp: Date, condition: GlucoseCondition? = nil) {
        self.unsmoothedGlucose = unsmoothedGlucose
        self.glucoseDouble = glucoseDouble
        self.timestamp = timestamp
        self.condition = condition
    }

    /// Classifies a calibrated reading against the sensor's reportable range for the sample condition.
    /// LO/HI mark for a calibrated value. Decided on the value rounded to whole mg/dL, as the official
    /// reader does: 39.5 shows as 40 and 500.4 as 500 (in range); 39.4 is LO and 500.5 is HI.
    static func rangeCondition(for calibrated: Double?) -> GlucoseCondition? {
        guard let calibrated else { return nil }
        let shown = calibrated.rounded()
        if shown < GlucoseAlgorithm.minimumGlucose { return .belowRange }
        if shown > GlucoseAlgorithm.maximumGlucose { return .aboveRange }
        return nil
    }

    public static func timeDifference(oldGlucose: LibreGlucose, newGlucose: LibreGlucose) -> TimeInterval {
        newGlucose.startDate.timeIntervalSince(oldGlucose.startDate)
    }

    public var syncId: String {
        // Rounded so the identifier stays the same as when glucose was rounded before calibration, and
        // within 40-500 so a trend reading held at 39 / 501 gets the same identifier as before
        "\(Int(self.startDate.timeIntervalSince1970))\(min(max(self.unsmoothedGlucose, GlucoseAlgorithm.minimumGlucose), GlucoseAlgorithm.maximumGlucose).rounded())"
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
    static func fromHistoryMeasurements(_ measurements: [Measurement], nativeCalibrationData: SensorData.CalibrationInfo, sensorStart: Date? = nil) -> [LibreGlucose] {
        let calibrated = GlucoseAlgorithm.calibratedGlucoses(
            for: measurements,
            calibrationInfo: nativeCalibrationData,
            smoothTemperature: UserDefaults.standard.temperatureSmoothingEnabled,
            sensorStart: sensorStart,
            officialAgeOffset: Features.officialAgeOffsetEnabled)

        return zip(measurements, calibrated).compactMap { historical, calibrated in
            guard let glucose = GlucoseAlgorithm.reportableGlucose(calibrated) else {
                return nil
            }
            return LibreGlucose(
                unsmoothedGlucose: glucose,
                glucoseDouble: glucose,
                error: historical.error,
                timestamp: historical.date,
                condition: Self.rangeCondition(for: calibrated))
        }
    }

    static func fromTrendMeasurements(_ measurements: [Measurement], nativeCalibrationData: SensorData.CalibrationInfo, sensorStart: Date? = nil) -> [LibreGlucose] {
        var arr = [LibreGlucose]()

        var shouldSmoothGlucose = true
        let calibrated = GlucoseAlgorithm.calibratedGlucoses(
            for: measurements,
            calibrationInfo: nativeCalibrationData,
            smoothTemperature: UserDefaults.standard.temperatureSmoothingEnabled,
            sensorStart: sensorStart,
            officialAgeOffset: Features.officialAgeOffsetEnabled)

        for (trend, calibrated) in zip(measurements, calibrated) {
            // trend arrows on each libreglucose value is not needed
            // instead we calculate it once when latestbackfill is set, which in turn sets
            // the sensordisplayable property

            // if sensor is ripped off body while transmitter is attached, values below 1 might be created
            // libre manual: glucose readings are gathered in the system range of 40-500 mg/dL.
            // Held at 39 / 501 here and clamped to 40-500 after smoothing, with LO/HI marked then
            if let glucose = GlucoseAlgorithm.rangeHeldGlucose(calibrated) {
                arr.append(LibreGlucose(
                    unsmoothedGlucose: glucose,
                    glucoseDouble: 0.0,
                    error: trend.error,
                    timestamp: trend.date))
            }

            // Just for expliciticity, if one of the values are invalid or 0,
            // then the rest of the values should not be smoothed
            if (calibrated ?? 0) <= 0 {
                shouldSmoothGlucose = false
            }
        }

        let smoothingEnabled = UserDefaults.standard.glucoseSmoothingEnabled
        if shouldSmoothGlucose && smoothingEnabled {
            logger.debug("Glucose smoothing applied to \(arr.count) trend readings")
            arr = CalculateSmoothedData(origtrends: arr)
        } else if shouldSmoothGlucose {
            let smoothedReadings = CalculateSmoothedData(origtrends: arr)
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

        // LO/HI is decided on the value that is reported, after smoothing, so the value and its mark
        // always agree; the official reader likewise decides on the value it shows
        for i in 0 ..< arr.count {
            arr[i].condition = Self.rangeCondition(for: arr[i].glucoseDouble)
            arr[i].glucoseDouble = GlucoseAlgorithm.reportableGlucose(arr[i].glucoseDouble) ?? arr[i].glucoseDouble
        }

        return arr
    }
}
