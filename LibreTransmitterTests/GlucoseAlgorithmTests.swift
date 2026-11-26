//
//  GlucoseAlgorithmTests.swift
//  LibreTransmitterTests
//

import XCTest
@testable import LibreTransmitter

// Foundation also has a Measurement type
private typealias Measurement = LibreTransmitter.Measurement

class GlucoseAlgorithmTests: XCTestCase {

    // i2 = 509 selects t1 = 1.75 and t2 = 0.0706475, and i6 gives R = 67300 at rawTemperature 8000:
    // the values of the worked example in the comments of the previous implementation
    private func calibration(i2: Int = 509, i3: Double = 40, i4: Double = 4000, i6: Double = 8491.940298507463) -> SensorData.CalibrationInfo {
        SensorData.CalibrationInfo(i1: 0, i2: i2, i3: i3, i4: i4, i5: 0, i6: i6, isValidForFooterWithReverseCRCs: 0)
    }

    private func measurement(minutes: Double = 0, rawGlucose: Int = 900, rawTemperature: Int = 8000, rawTemperatureAdjustment: Int = 0) -> Measurement {
        Measurement(
            date: Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(minutes * 60),
            rawGlucose: rawGlucose,
            rawTemperature: rawTemperature,
            rawTemperatureAdjustment: rawTemperatureAdjustment)
    }

    // Values produced by the implementation before temperature smoothing, input validation and late rounding were added
    func testMatchesPreviousImplementationWithoutTemperatureSmoothing() {
        let expected: [(rawGlucose: Int, rawTemperature: Int, adjustment: Int, glucose: Double)] = [
            (900, 8000, 0, 167.07451667322786),
            (1200, 8000, 0, 233.99732578860434),
            (500, 8200, -40, 80.81725070622558),
            (900, 7800, 60, 161.11538708445798)
        ]

        for value in expected {
            let reading = measurement(rawGlucose: value.rawGlucose, rawTemperature: value.rawTemperature, rawTemperatureAdjustment: value.adjustment)
            XCTAssertEqual(reading.glucoseValueFromRaw(calibrationInfo: calibration())!, value.glucose, accuracy: 1e-9)
        }
    }

    func testWorkedExampleTemperature() {
        XCTAssertEqual(measurement().temperature(calibrationInfo: calibration())!, 33.4242, accuracy: 1e-3)
    }

    func testCalibratedGlucoseIsNotRoundedBeforeExtraSlopeAndOffset() {
        let calibration = calibration()
        calibration.extraSlope = 1.1
        calibration.extraOffset = -3

        XCTAssertEqual(measurement().calibratedGlucose(calibrationInfo: calibration)!, 167.07451667322786 * 1.1 - 3, accuracy: 1e-9)
    }

    func testInvalidCalibrationReturnsNil() {
        XCTAssertNil(measurement().glucoseValueFromRaw(calibrationInfo: calibration(i2: 0)))
        XCTAssertNil(measurement().glucoseValueFromRaw(calibrationInfo: calibration(i2: 1024)))
        XCTAssertNil(measurement().glucoseValueFromRaw(calibrationInfo: calibration(i3: 100, i4: 100)))
        XCTAssertNotNil(measurement().glucoseValueFromRaw(calibrationInfo: calibration(i2: 1)))
        XCTAssertNotNil(measurement().glucoseValueFromRaw(calibrationInfo: calibration(i2: 1023)))
    }

    func testThermistorOutsideModelReturnsNil() {
        // zero or negative divisor
        XCTAssertNil(measurement().temperature(calibrationInfo: calibration(i6: 0)))
        XCTAssertNil(measurement(rawTemperatureAdjustment: -9000).temperature(calibrationInfo: calibration()))
        // resistance below zero
        XCTAssertNil(measurement(rawTemperature: 100).temperature(calibrationInfo: calibration()))
        XCTAssertNil(measurement(rawTemperature: 100).calibratedGlucose(calibrationInfo: calibration()))
    }

    func testReportableGlucoseRange() {
        XCTAssertNil(GlucoseAlgorithm.reportableGlucose(nil))
        XCTAssertNil(GlucoseAlgorithm.reportableGlucose(-5))
        XCTAssertNil(GlucoseAlgorithm.reportableGlucose(0))
        XCTAssertNil(GlucoseAlgorithm.reportableGlucose(.nan))
        XCTAssertNil(GlucoseAlgorithm.reportableGlucose(.infinity))
        // Out-of-range readings clamp to the rated bounds (40..500) rather than being dropped
        XCTAssertEqual(GlucoseAlgorithm.reportableGlucose(12), 40)
        XCTAssertEqual(GlucoseAlgorithm.reportableGlucose(39.9), 40)
        XCTAssertEqual(GlucoseAlgorithm.reportableGlucose(120.4), 120.4)
        XCTAssertEqual(GlucoseAlgorithm.reportableGlucose(500), 500)
        XCTAssertEqual(GlucoseAlgorithm.reportableGlucose(500.1), 500)
        XCTAssertEqual(GlucoseAlgorithm.reportableGlucose(742), 500)
    }

    func testRangeHeldGlucoseUsesTheOfficialReadersLOAndHIValues() {
        XCTAssertNil(GlucoseAlgorithm.rangeHeldGlucose(nil))
        XCTAssertNil(GlucoseAlgorithm.rangeHeldGlucose(-5))
        XCTAssertNil(GlucoseAlgorithm.rangeHeldGlucose(0))
        XCTAssertNil(GlucoseAlgorithm.rangeHeldGlucose(.nan))
        XCTAssertEqual(GlucoseAlgorithm.rangeHeldGlucose(12), 39)
        XCTAssertEqual(GlucoseAlgorithm.rangeHeldGlucose(39.6), 39.6)
        XCTAssertEqual(GlucoseAlgorithm.rangeHeldGlucose(120.4), 120.4)
        XCTAssertEqual(GlucoseAlgorithm.rangeHeldGlucose(742), 501)
    }

    // MARK: LO/HI of trend readings, after glucose smoothing

    /// Trend readings one minute apart, newest first, calibrating to `glucose` (to within 0.05 mg/dL)
    private func trend(_ glucose: [Double]) -> [Measurement] {
        let calibration = calibration()
        let distance = { (raw: Int, target: Double) in
            abs((self.measurement(rawGlucose: raw).glucoseValueFromRaw(calibrationInfo: calibration) ?? .infinity) - target)
        }
        return glucose.enumerated().map { minutesAgo, target in
            let raw = (1...16383).min { distance($0, target) < distance($1, target) }!
            return measurement(minutes: -Double(minutesAgo), rawGlucose: raw)
        }
    }

    private func reportedTrend(_ glucose: [Double], smoothing mode: GlucoseSmoothingMode) -> [LibreGlucose] {
        let key = "com.loopkit.libreGlucoseSmoothingMode"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.glucoseSmoothingMode = mode
        return LibreGlucose.fromTrendMeasurements(trend(glucose), nativeCalibrationData: calibration())
    }

    /// The value sent to Loop and its LO/HI mark must agree: a mark only on 40 or 500, and 40 or 500
    /// marked whenever the value before clamping was out of range
    private func assertMarksAgree(_ readings: [LibreGlucose], file: StaticString = #filePath, line: UInt = #line) {
        for reading in readings {
            XCTAssertTrue((40...500).contains(reading.glucoseDouble), "\(reading)", file: file, line: line)
            switch reading.condition {
            case .belowRange?: XCTAssertEqual(reading.glucoseDouble, 40, file: file, line: line)
            case .aboveRange?: XCTAssertEqual(reading.glucoseDouble, 500, file: file, line: line)
            default: XCTAssertTrue((39.5..<500.5).contains(reading.glucoseDouble), "\(reading)", file: file, line: line)
            }
        }
    }

    func testFallIntoLOIsMarkedOnTheSmoothedValue() {
        let falling: [Double] = [38, 40.5, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64, 66, 68]

        // smoothed, the newest reading averages above 40, so it is neither LO nor clamped. 38 enters
        // the average as the official reader's LO value, 39
        let smoothed = reportedTrend(falling, smoothing: .glucose)
        assertMarksAgree(smoothed)
        XCTAssertNil(smoothed[0].condition)
        XCTAssertEqual(smoothed[0].glucoseDouble, (39 + 40.5 + 42 + 44 + 46) / 5, accuracy: 0.05)

        // unsmoothed, it is LO
        let unsmoothed = reportedTrend(falling, smoothing: .off)
        assertMarksAgree(unsmoothed)
        XCTAssertEqual(unsmoothed[0].condition, .belowRange)
        XCTAssertEqual(unsmoothed[0].glucoseDouble, 40)
    }

    func testSteadyOutOfRangeReadingsStayLOAndHIWhenSmoothed() {
        for mode in [GlucoseSmoothingMode.glucose, .off] {
            let low = reportedTrend(Array(repeating: 25, count: 16), smoothing: mode)
            assertMarksAgree(low)
            XCTAssertTrue(low.allSatisfy { $0.condition == .belowRange }, "\(mode)")

            let high = reportedTrend(Array(repeating: 650, count: 16), smoothing: mode)
            assertMarksAgree(high)
            XCTAssertTrue(high.allSatisfy { $0.condition == .aboveRange }, "\(mode)")
        }
    }

    func testRiseIntoHIIsMarkedOnTheSmoothedValue() {
        let rising: [Double] = [503, 499, 497, 495, 493, 491, 489, 487, 485, 483, 481, 479, 477, 475, 473, 471]

        let smoothed = reportedTrend(rising, smoothing: .glucose)
        assertMarksAgree(smoothed)
        XCTAssertNil(smoothed[0].condition)

        let unsmoothed = reportedTrend(rising, smoothing: .off)
        assertMarksAgree(unsmoothed)
        XCTAssertEqual(unsmoothed[0].condition, .aboveRange)
    }

    func testSyncIdOfAHeldReadingIsUnchanged() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(LibreGlucose(unsmoothedGlucose: 39, glucoseDouble: 40, timestamp: date).syncId,
                       LibreGlucose(unsmoothedGlucose: 40, glucoseDouble: 40, timestamp: date).syncId)
        XCTAssertEqual(LibreGlucose(unsmoothedGlucose: 501, glucoseDouble: 500, timestamp: date).syncId,
                       LibreGlucose(unsmoothedGlucose: 500, glucoseDouble: 500, timestamp: date).syncId)
    }

    func testLowPassFilterStepResponse() {
        let start = Date(timeIntervalSince1970: 0)
        let values: [(date: Date, value: Double?)] = (0...5).map { minute in
            (start.addingTimeInterval(Double(minute) * 60), minute == 0 ? 0 : 1)
        }

        let filtered = GlucoseAlgorithm.lowPassFiltered(values, timeConstant: 5 * 60)

        XCTAssertEqual(filtered[0], 0)
        // after five one minute steps a first order filter has reached 1 - e^-1 of a unit step
        XCTAssertEqual(filtered[5]!, 1 - exp(-1), accuracy: 1e-12)
    }

    func testLowPassFilterSkipsMissingValues() {
        let start = Date(timeIntervalSince1970: 0)
        let filtered = GlucoseAlgorithm.lowPassFiltered([
            (start, 30),
            (start.addingTimeInterval(60), nil),
            (start.addingTimeInterval(120), 30)
        ], timeConstant: 300)

        XCTAssertEqual(filtered[0], 30)
        XCTAssertNil(filtered[1])
        XCTAssertEqual(filtered[2], 30)
    }

    func testTemperatureSmoothingDampsTemperatureSpike() {
        // newest first, as delivered by SensorData.trendMeasurements; the newest reading has a sudden temperature jump
        let readings = (0..<16).map { minute in
            measurement(minutes: -Double(minute), rawTemperature: minute == 0 ? 7600 : 8000)
        }

        let raw = GlucoseAlgorithm.calibratedGlucoses(for: readings, calibrationInfo: calibration(), smoothTemperature: false)
        let smoothed = GlucoseAlgorithm.calibratedGlucoses(for: readings, calibrationInfo: calibration(), smoothTemperature: true)
        let baseline = 167.07451667322786

        // unsmoothed values are unchanged by the batch function
        XCTAssertEqual(raw[1]!, baseline, accuracy: 1e-9)
        XCTAssertEqual(smoothed[1]!, baseline, accuracy: 1e-9)

        let rawJump = abs(raw[0]! - baseline)
        let smoothedJump = abs(smoothed[0]! - baseline)
        XCTAssertGreaterThan(rawJump, 5)
        // one minute into a five minute filter only about 18 % of the change comes through
        XCTAssertEqual(smoothedJump / rawJump, 1 - exp(-0.2), accuracy: 0.02)
    }

    // 16 one minute readings rising 2 raw units per minute, newest (raw 1500) first
    private func risingTrend(at date: Date = Date(timeIntervalSince1970: 1_792_000_000)) -> [Measurement] {
        (0..<16).map { minute in
            Measurement(date: date.addingTimeInterval(-60 * Double(minute)), rawGlucose: 1500 - 2 * minute,
                        rawTemperature: minute == 0 ? 8100 : 8000, rawTemperatureAdjustment: 0)
        }
    }

    func testPredictionExtrapolatesFromNewestReading() {
        let readings = risingTrend()
        let predicted = readings.predictBloodSugar(10)

        XCTAssertEqual(predicted?.rawGlucose, 1520)
        XCTAssertEqual(predicted?.date, readings[0].date.addingTimeInterval(600))
        // temperature comes from the newest reading
        XCTAssertEqual(predicted?.rawTemperature, 8100)
    }

    func testPredictionDoesNotDependOnInputOrder() {
        let readings = risingTrend()

        XCTAssertEqual(readings.reversed().predictBloodSugar(10)?.rawGlucose, 1520)
        XCTAssertEqual(readings.reversed().predictBloodSugar(10)?.rawTemperature, 8100)
    }

    func testPredictionIsExactWithAbsoluteTimestamps() {
        // regression on absolute Unix timestamps lost precision to cancellation:
        // at these timestamps it predicted 1519 or 1521
        for timestamp in [1_792_004_800.0, 1_792_006_660, 1_792_022_020] {
            let readings = risingTrend(at: Date(timeIntervalSince1970: timestamp))
            XCTAssertEqual(readings.predictBloodSugar(10)?.rawGlucose, 1520)
        }
    }

    func testPredictionSkipsInvalidReadings() {
        var readings = risingTrend()
        readings[5] = Measurement(date: readings[5].date, rawGlucose: 0, rawTemperature: 8000, rawTemperatureAdjustment: 0)

        XCTAssertEqual(readings.predictBloodSugar(10)?.rawGlucose, 1520)
    }

    func testPredictionRequiresEnoughReadings() {
        XCTAssertNil(Array(risingTrend().prefix(9)).predictBloodSugar(10))
        XCTAssertNotNil(Array(risingTrend().prefix(10)).predictBloodSugar(10))
        XCTAssertNil([Measurement]().predictBloodSugar(10))
    }

    func testPredictionWithIdenticalTimestampsReturnsNil() {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let readings = (0..<12).map { Measurement(date: date, rawGlucose: 1500 + $0, rawTemperature: 8000, rawTemperatureAdjustment: 0) }

        XCTAssertNil(readings.predictBloodSugar(10))
    }

    func testCalibratedGlucosesKeepInputOrderAndInvalidReadings() {
        let readings = [
            measurement(minutes: 0, rawGlucose: 1200),
            measurement(minutes: -1, rawTemperature: 100),
            measurement(minutes: -2, rawGlucose: 900)
        ]

        let glucoses = GlucoseAlgorithm.calibratedGlucoses(for: readings, calibrationInfo: calibration(), smoothTemperature: true)

        XCTAssertEqual(glucoses.count, 3)
        XCTAssertEqual(glucoses[0]!, 233.99732578860434, accuracy: 1e-9)
        XCTAssertNil(glucoses[1])
        XCTAssertEqual(glucoses[2]!, 167.07451667322786, accuracy: 1e-9)
    }

    func testTemperatureOutsideOperatingRangeReturnsNil() {
        // Normal on-body temperature (~33 C) and the upper edge (~44 C) are accepted
        XCTAssertNotNil(measurement(rawTemperature: 8000).temperature(calibrationInfo: calibration()))
        XCTAssertNotNil(measurement(rawTemperature: 5000).temperature(calibrationInfo: calibration()))
        // Too hot: rawTemperature 4000 -> ~49.5 C, above the 45 C operating maximum
        XCTAssertNil(measurement(rawTemperature: 4000).temperature(calibrationInfo: calibration()))
        XCTAssertNil(measurement(rawTemperature: 4000).calibratedGlucose(calibrationInfo: calibration()))
        // Too cold: rawTemperature 30000 -> ~6.6 C, below the 10 C operating minimum
        XCTAssertNil(measurement(rawTemperature: 30000).temperature(calibrationInfo: calibration()))
        XCTAssertNil(measurement(rawTemperature: 30000).calibratedGlucose(calibrationInfo: calibration()))
    }

    func testWarmupReadingsAreSuppressed() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let cal = calibration()
        // Within the 60 minute warmup period -> dropped
        let during = GlucoseAlgorithm.calibratedGlucoses(
            for: [measurement(minutes: 30)], calibrationInfo: cal, smoothTemperature: false, sensorStart: start)
        XCTAssertNil(during.first!)
        // After warmup -> a value is produced
        let after = GlucoseAlgorithm.calibratedGlucoses(
            for: [measurement(minutes: 90)], calibrationInfo: cal, smoothTemperature: false, sensorStart: start)
        XCTAssertNotNil(after.first!)
        // At exactly the warmup boundary (age == warmupInterval) the reading is allowed; just inside is not
        XCTAssertNotNil(GlucoseAlgorithm.calibratedGlucoses(
            for: [measurement(minutes: 60)], calibrationInfo: cal, smoothTemperature: false, sensorStart: start).first!)
        XCTAssertNil(GlucoseAlgorithm.calibratedGlucoses(
            for: [measurement(minutes: 59)], calibrationInfo: cal, smoothTemperature: false, sensorStart: start).first!)
        // Without a known sensor start time, readings are not gated
        let unknownStart = GlucoseAlgorithm.calibratedGlucoses(
            for: [measurement(minutes: 30)], calibrationInfo: cal, smoothTemperature: false, sensorStart: nil)
        XCTAssertNotNil(unknownStart.first!)
    }

    func testDisplayProjectionIsSymmetricAndStampedNow() {
        // risingTrend climbs 2 raw/min; the newest reading is raw 1500 at readings[0].date.
        let rising = risingTrend()
        let up = rising.predictDisplayGlucose()
        // rising -> projected 8 min ahead: 1500 + 2 * 8 = 1516
        XCTAssertEqual(up?.rawGlucose, 1516)
        // stamped at the newest reading (a current display value), not a future minute
        XCTAssertEqual(up?.date, rising[0].date)
        XCTAssertEqual(up?.rawTemperature, 8100)

        // Mirror it into a falling trend (newest still raw 1500, now declining 2 raw/min)
        let falling = rising.map {
            Measurement(date: $0.date, rawGlucose: 3000 - $0.rawGlucose,
                        rawTemperature: $0.rawTemperature, rawTemperatureAdjustment: 0)
        }
        let down = falling.predictDisplayGlucose()
        // falling -> projected just as far: 1500 - 2 * 8 = 1484
        XCTAssertEqual(down?.rawGlucose, 1484)
        XCTAssertEqual(down?.date, falling[0].date)
    }

    func testDisplayProjectionUsesSixteenMinutes() {
        // Flat 1500 for minutes 0-5, one lower reading exactly 16 minutes old, and far-off readings
        // 17-19 minutes old. The 16 minute reading is inside the window (inclusive edge) and tilts
        // the slope up: least squares over (0...5 @ 1500, 16 @ 1400) gives 6.66 raw/min, so
        // 1500 + 8 * 6.66 = 1553. A 15 minute window would give 1500; a 17 minute one 1103.
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let readings = ([0, 1, 2, 3, 4, 5, 16, 17, 18, 19] as [Double]).map { minute in
            Measurement(date: now.addingTimeInterval(-60 * minute),
                        rawGlucose: minute <= 5 ? 1500 : minute == 16 ? 1400 : 3000,
                        rawTemperature: 8000, rawTemperatureAdjustment: 0)
        }
        XCTAssertEqual(readings.predictDisplayGlucose()?.rawGlucose, 1553)
    }

    func testDisplayProjectionFromASingleLibre2BLEPacket() {
        // A Libre 2 BLE packet alone: trend readings 0, 2, 4, 6, 7, 12 and 15 minutes old, nothing
        // buffered yet. The 15 minute slot is inside the window, and the uneven spacing still gives
        // the exact slope of a straight line.
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        func packet(_ rate: Int) -> [Measurement] {
            [0, 2, 4, 6, 7, 12, 15].map { age in
                Measurement(date: now.addingTimeInterval(-60 * Double(age)), rawGlucose: 1500 - rate * age,
                            rawTemperature: 8000, rawTemperatureAdjustment: 0)
            }
        }
        XCTAssertEqual(packet(3).predictDisplayGlucose()?.rawGlucose, 1500 + 3 * 8)
        XCTAssertEqual(packet(-3).predictDisplayGlucose()?.rawGlucose, 1500 - 3 * 8)
        // A reading dated 20 s past 15 minutes (buffered from an earlier packet) still counts. With
        // only 0 and 2 minutes besides it, leaving it out would leave too few readings (nil).
        let drifted = [(0.0, 1500), (120.0, 1494), (920.0, 1454)].map { seconds, raw in
            Measurement(date: now.addingTimeInterval(-seconds), rawGlucose: raw,
                        rawTemperature: 8000, rawTemperatureAdjustment: 0)
        }
        XCTAssertEqual(drifted.predictDisplayGlucose()?.rawGlucose, 1500 + 3 * 8)
    }

    func testDisplayProjectionLimitsFalls() {
        typealias Projection = [Measurement].DisplayProjection
        XCTAssertEqual(Projection.maximumFallMgdl, 15)
        // a fall within the limit is kept: 120 at -1 mg/dL/min, 8 min ahead
        XCTAssertEqual(Projection.limitingFall(112, newest: 120), 112)
        // a fast fall stops 15 below the newest reading: 120 at -3 mg/dL/min would project to 96
        XCTAssertEqual(Projection.limitingFall(96, newest: 120), 105)
        // rises are not limited
        XCTAssertEqual(Projection.limitingFall(144, newest: 120), 144)
    }
}

// MARK: - The official reader's sensor-age offset (optional, off by default)

final class OfficialAgeOffsetTests: XCTestCase {
    /// Measured: (reading age in minutes, open-source mg/dL, what the official reader returned), from
    /// cold scans of flat frames of a real sensor. The offset must reproduce each to the whole mg/dL.
    private let measured: [(age: Double, glucose: Double, official: Double)] = [
        (61, 199.99, 208), (119, 199.99, 213), (329, 199.99, 218), (419, 199.99, 218), (719, 199.99, 212),
        (1439, 199.99, 203), (2279, 199.99, 200), (4319, 199.99, 200),            // early term, gone by ~38 h
        (16559, 199.99, 202), (20159, 199.99, 205), (22319, 199.99, 207),          // late term from day 10
        (239, 150.01, 167),                                                        // no low term at or above 90
        (89, 40.0, 65), (239, 40.0, 70), (359, 59.96, 85), (539, 80.07, 98),       // low term inside 63-556 min
        (549, 40.0, 65), (559, 40.0, 55), (719, 40.0, 52)                          // ...and outside it
    ]

    func testOffsetReproducesTheOfficialReader() {
        for point in measured {
            let adjusted = point.glucose + GlucoseAlgorithm.OfficialAgeOffset.offset(ageMinutes: point.age, glucose: point.glucose)
            XCTAssertEqual(adjusted.rounded(), point.official, "\(point)")
        }
    }

    func testOffsetShapeAndEdges() {
        typealias Offset = GlucoseAlgorithm.OfficialAgeOffset
        XCTAssertEqual(Offset.offset(ageMinutes: 59, glucose: 120), 0)                // warmup
        XCTAssertEqual(Offset.offset(ageMinutes: 60, glucose: 120), 7.6, accuracy: 0.1) // early term starts at 60
        XCTAssertEqual(Offset.offset(ageMinutes: 326, glucose: 120), 18.2, accuracy: 0.1) // peak at ~5.4 h
        XCTAssertEqual(Offset.offset(ageMinutes: 5 * 1440, glucose: 120), 0, accuracy: 0.01) // mid-wear: nothing
        XCTAssertEqual(Offset.offset(ageMinutes: 14 * 1440, glucose: 120), 16.0 / 3, accuracy: 0.01)
        // additive: the same at every level at or above 90
        XCTAssertEqual(Offset.offset(ageMinutes: 300, glucose: 100), Offset.offset(ageMinutes: 300, glucose: 300))
        // the low term only between 63 and 556 minutes
        XCTAssertEqual(Offset.offset(ageMinutes: 62, glucose: 40), Offset.offset(ageMinutes: 62, glucose: 200))
        XCTAssertGreaterThan(Offset.offset(ageMinutes: 63, glucose: 40), Offset.offset(ageMinutes: 63, glucose: 200) + 10)
        XCTAssertEqual(Offset.offset(ageMinutes: 557, glucose: 40), Offset.offset(ageMinutes: 557, glucose: 200))
    }

    /// Applied before the 40-500 clamp: early in wear the official reader turns 30 into about 60,
    /// not LO, so the adjusted value must not be clamped and marked LO first.
    func testOffsetComesBeforeTheReportableRangeClamp() {
        let adjusted = 30 + GlucoseAlgorithm.OfficialAgeOffset.offset(ageMinutes: 120, glucose: 30)
        XCTAssertEqual(adjusted, 59.6, accuracy: 0.5)
        XCTAssertNil(LibreGlucose.rangeCondition(for: adjusted))
    }

    /// The official reader doesn't raise readings that round below 22 mg/dL, so neither does the
    /// offset: one at or below 0 is still dropped, and near-zero data (a sensor pulled off) isn't
    /// lifted into range
    func testNoOffsetBelowTheOfficialReadersLowestGlucose() {
        typealias Offset = GlucoseAlgorithm.OfficialAgeOffset
        for age in [90.0, 240, 480, 720] {
            XCTAssertEqual(Offset.offset(ageMinutes: age, glucose: 21.4), 0, "\(age)")
            XCTAssertEqual(Offset.offset(ageMinutes: age, glucose: 0), 0, "\(age)")
            XCTAssertEqual(Offset.offset(ageMinutes: age, glucose: -20), 0, "\(age)")
            XCTAssertGreaterThan(Offset.offset(ageMinutes: age, glucose: 21.6), 10, "\(age)")
        }
    }

    func testToggleIsOffByDefault() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: Features.officialAgeOffsetKey)
        defer { defaults.set(saved, forKey: Features.officialAgeOffsetKey) }
        defaults.removeObject(forKey: Features.officialAgeOffsetKey)
        XCTAssertFalse(Features.officialAgeOffsetEnabled)
    }
}

// MARK: - Regression vectors from the official reader's algorithm

/// Frames built from `Libre2.Example2` (decrypted; the public test data in PreLibre2.swift) with every
/// trend and history record set to one reading, so there is no rate and no trend projection. Each
/// vector sets the raw glucose, raw temperature and sensor age (ring indices kept consistent, CRCs
/// recomputed) and records what the official reader's algorithm (LibreLink 2.3.0's
/// libDataProcessing, run unmodified on an emulator, one cold scan per vector, each scanned twice and
/// agreeing) returned. `abbott == nil` means it returned no reading. Generated 2026-11-26.
enum OfficialReaderVectors {
    enum Kind { case temperature, level, range, warmup, wearlimit, low }

    static let maxMinutesWearTime = 20_759

    static let base: [UInt8] = hexBytes([
        "815a101c030000000000000000000000000000000000000027630213430500b89600430500b89600430500",
        "b89600430500b89600430500b89600430500b89600430500b89600430500b89600430500b89600430500b8",
        "9600430500b89600430500b89600430500b89600430500b89600430500b89600430500b89600430500b896",
        "00430500b89600430500b89600430500b89600430500b89600430500b89600430500b89600430500b89600",
        "430500b89600430500b89600430500b89600430500b89600430500b89600430500b89600430500b8960043",
        "0500b89600430500b89600430500b89600430500b89600430500b89600430500b89600430500b896004305",
        "00b89600430500b89600430500b89600430500b89600430500b89600430500b89600430500b89600430500",
        "b89600430500b89600430500b89600620c010071c63001ca091751140396805a00cda618a31a0000b2c860"
    ].joined())

    static let rows: [(kind: Kind, raw: Int, rawTemperature: Int, age: Int, abbott: Int?)] = [
        (kind: .temperature, raw: 1194, rawTemperature: 8236, age: 7200, abbott: 120),  // open-source 119.998
        (kind: .temperature, raw: 1419, rawTemperature: 6832, age: 7200, abbott: 120),  // open-source 120.005
        (kind: .temperature, raw: 1652, rawTemperature: 5820, age: 7200, abbott: 120),  // open-source 120.016
        (kind: .temperature, raw: 1923, rawTemperature: 4976, age: 7200, abbott: 120),  // open-source 119.988
        (kind: .level, raw: 920, rawTemperature: 5820, age: 7200, abbott: 60),  // open-source 60.013
        (kind: .level, raw: 2628, rawTemperature: 5820, age: 7200, abbott: 200),  // open-source 200.021
        (kind: .level, raw: 4458, rawTemperature: 5820, age: 7200, abbott: 350),  // open-source 350.029
        (kind: .range, raw: 651, rawTemperature: 5820, age: 7200, abbott: 39),  // open-source 37.962
        (kind: .range, raw: 670, rawTemperature: 5820, age: 7200, abbott: 40),  // open-source 39.52
        (kind: .range, raw: 676, rawTemperature: 5820, age: 7200, abbott: 40),  // open-source 40.012
        (kind: .range, raw: 682, rawTemperature: 5820, age: 7200, abbott: 41),  // open-source 40.503
        (kind: .range, raw: 6281, rawTemperature: 5820, age: 7200, abbott: 499),  // open-source 499.464
        (kind: .range, raw: 6288, rawTemperature: 5820, age: 7200, abbott: 500),  // open-source 500.038
        (kind: .range, raw: 6294, rawTemperature: 5820, age: 7200, abbott: 501),  // open-source 500.53
        (kind: .range, raw: 6300, rawTemperature: 5820, age: 7200, abbott: 501),  // open-source 501.022
        (kind: .range, raw: 6532, rawTemperature: 5820, age: 7200, abbott: 501),  // open-source 520.039
        (kind: .warmup, raw: 1652, rawTemperature: 5820, age: 56, abbott: nil),  // open-source 120.016
        (kind: .warmup, raw: 1652, rawTemperature: 5820, age: 57, abbott: 120),  // open-source 120.016
        (kind: .warmup, raw: 1652, rawTemperature: 5820, age: 58, abbott: 120),  // open-source 120.016
        (kind: .warmup, raw: 1652, rawTemperature: 5820, age: 59, abbott: 120),  // open-source 120.016
        (kind: .warmup, raw: 1652, rawTemperature: 5820, age: 60, abbott: 128),  // open-source 120.016
        (kind: .wearlimit, raw: 1652, rawTemperature: 5820, age: 20758, abbott: 126),  // open-source 120.016
        (kind: .wearlimit, raw: 1652, rawTemperature: 5820, age: 20759, abbott: 126),  // open-source 120.016
        (kind: .wearlimit, raw: 1652, rawTemperature: 5820, age: 20760, abbott: nil),  // open-source None
        // generated 2026-11-26 the same way
        (kind: .low, raw: 371, rawTemperature: 5820, age: 240, abbott: nil),  // open-source 15.010
        (kind: .low, raw: 444, rawTemperature: 5820, age: 240, abbott: nil),  // open-source 20.994
        (kind: .low, raw: 449, rawTemperature: 5820, age: 240, abbott: nil),  // open-source 21.404
        (kind: .low, raw: 451, rawTemperature: 5820, age: 240, abbott: 56),  // open-source 21.568
        (kind: .low, raw: 456, rawTemperature: 5820, age: 240, abbott: 57),  // open-source 21.978
        (kind: .low, raw: 554, rawTemperature: 5820, age: 240, abbott: 63),  // open-source 30.011
        (kind: .low, raw: 444, rawTemperature: 5820, age: 720, abbott: nil),  // open-source 20.994
        (kind: .low, raw: 444, rawTemperature: 5820, age: 840, abbott: 39),  // open-source 20.994
        (kind: .low, raw: 310, rawTemperature: 5820, age: 4320, abbott: 39),  // open-source 10.010
        (kind: .low, raw: 200, rawTemperature: 5820, age: 4320, abbott: 39),  // open-source 0.993
    ]

    /// `base` with every record set to `raw` / `rawTemperature` and the sensor at `age` minutes
    static func frame(raw: Int, rawTemperature: Int, age: Int) -> [UInt8] {
        var f = base
        let records = (0..<16).map { 28 + 6 * $0 } + (0..<32).map { 124 + 6 * $0 }
        for offset in records {
            setBits(&f, offset * 8, 14, raw)
            setBits(&f, offset * 8 + 0x1a, 12, rawTemperature >> 2)
        }
        f[316] = UInt8(age & 0xff)
        f[317] = UInt8(age >> 8)
        f[26] = UInt8(age % 16)
        f[27] = UInt8((age - 3) / 15 % 32)
        for (start, end) in [(0, 24), (24, 320), (320, 344)] {
            let crc = Crc.crc16(Array(f[(start + 2)..<end]), seed: 0xffff)
            f[start] = UInt8(crc >> 8)
            f[start + 1] = UInt8(crc & 0xff)
        }
        return f
    }

    private static func setBits(_ bytes: inout [UInt8], _ bitOffset: Int, _ count: Int, _ value: Int) {
        for i in 0..<count {
            let byte = (bitOffset + i) / 8, bit = (bitOffset + i) % 8
            bytes[byte] = (bytes[byte] & ~UInt8(1 << bit)) | UInt8(((value >> i) & 1) << bit)
        }
    }

    private static func hexBytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map {
            let start = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }
}

final class OfficialReaderVectorTests: XCTestCase {
    private func sensorData(_ row: (kind: OfficialReaderVectors.Kind, raw: Int, rawTemperature: Int, age: Int, abbott: Int?)) -> SensorData {
        let sensorData = SensorData(bytes: OfficialReaderVectors.frame(raw: row.raw, rawTemperature: row.rawTemperature, age: row.age))!
        XCTAssertTrue(sensorData.hasValidCRCs)
        XCTAssertEqual(sensorData.minutesSinceStart, row.age)
        return sensorData
    }

    /// Temperature compensation (26-37 °C), glucose levels and the LO/HI edges match the official
    /// reader exactly. Its 39 is LO and 501 is HI; both decide on the value rounded to whole mg/dL.
    func testTemperatureLevelsAndRangeMatchOfficialReader() {
        for row in OfficialReaderVectors.rows where [.temperature, .level, .range].contains(row.kind) {
            let sensorData = sensorData(row)
            let calibrated = GlucoseAlgorithm.calibratedGlucoses(
                for: sensorData.trendMeasurements(), calibrationInfo: sensorData.calibrationData, smoothTemperature: false)[0]
            guard let calibrated, let reported = GlucoseAlgorithm.reportableGlucose(calibrated) else {
                XCTFail("no value for \(row)")
                continue
            }
            let condition = LibreGlucose.rangeCondition(for: calibrated)
            switch row.abbott {
            case 39:
                XCTAssertEqual(condition, .belowRange, "\(row)")
                XCTAssertEqual(reported, GlucoseAlgorithm.minimumGlucose, "\(row)")
            case 501:
                XCTAssertEqual(condition, .aboveRange, "\(row)")
                XCTAssertEqual(reported, GlucoseAlgorithm.maximumGlucose, "\(row)")
            default:
                XCTAssertNil(condition, "\(row)")
                XCTAssertEqual(reported.rounded(), Double(row.abbott ?? -1), "\(row)")
            }
        }
    }

    /// The official reader stops reporting once the sensor is past the FRAM footer's wear limit, and
    /// reports at the limit minute itself: the same cut-off as `isPastWearLimit`.
    func testWearLimitMatchesOfficialReader() {
        for row in OfficialReaderVectors.rows where row.kind == .wearlimit {
            let sensorData = sensorData(row)
            XCTAssertEqual(sensorData.maxMinutesWearTime, OfficialReaderVectors.maxMinutesWearTime)
            XCTAssertEqual(LibreTransmitterManagerV3.isPastWearLimit(age: sensorData.minutesSinceStart, maxAge: sensorData.maxMinutesWearTime),
                           row.abbott == nil, "\(row)")
        }
    }

    /// Warmup differs from the official reader on purpose, recorded here so a change is deliberate:
    /// it reports uncorrected values from minute 57 and adds its sensor-age offset from minute 60
    /// (+8 here: 128); LibreTransmitter reports nothing before 60 and has no age offset.
    func testWarmupEdgeAgainstOfficialReader() {
        for row in OfficialReaderVectors.rows where row.kind == .warmup {
            let sensorData = sensorData(row)
            let trend = sensorData.trendMeasurements()
            let start = trend[0].date.addingTimeInterval(-60 * Double(row.age))
            let calibrated = GlucoseAlgorithm.calibratedGlucoses(
                for: trend, calibrationInfo: sensorData.calibrationData, smoothTemperature: false, sensorStart: start)[0]
            if row.age < 60 {
                XCTAssertNil(calibrated, "\(row)")
            } else {
                XCTAssertEqual(calibrated?.rounded(), 120, "\(row)")
                XCTAssertEqual(row.abbott, 128)
            }
        }
    }
    /// With the sensor-age offset on, the frames whose official output depends on age (minute 60 of
    /// warmup, and the late ramp at the wear limit) come out as the official reader's.
    func testAgeOffsetMatchesOfficialReaderWhenOn() {
        for row in OfficialReaderVectors.rows where (row.kind == .warmup && row.age >= 60) || (row.kind == .wearlimit && row.abbott != nil) {
            let sensorData = sensorData(row)
            let trend = sensorData.trendMeasurements()
            let start = trend[0].date.addingTimeInterval(-60 * Double(row.age))
            let calibrated = GlucoseAlgorithm.calibratedGlucoses(
                for: trend, calibrationInfo: sensorData.calibrationData, smoothTemperature: false,
                sensorStart: start, officialAgeOffset: true)[0]
            XCTAssertEqual(calibrated?.rounded(), row.abbott.map(Double.init), "\(row)")
        }
    }

    /// Low readings with the sensor-age offset on. The official reader raises readings from 22 mg/dL
    /// (rounded) and LibreTransmitter raises the same ones by the same amount. Below that the reader
    /// returns no reading in the first 12 hours and LO later; LibreTransmitter reports LO throughout,
    /// on purpose (see `OfficialAgeOffset`).
    func testLowEdgeWithAgeOffsetAgainstOfficialReader() {
        for row in OfficialReaderVectors.rows where row.kind == .low {
            let sensorData = sensorData(row)
            let trend = sensorData.trendMeasurements()
            let start = trend[0].date.addingTimeInterval(-60 * Double(row.age))
            let calibrated = GlucoseAlgorithm.calibratedGlucoses(
                for: trend, calibrationInfo: sensorData.calibrationData, smoothTemperature: false,
                sensorStart: start, officialAgeOffset: true)[0]
            guard let calibrated, let reported = GlucoseAlgorithm.reportableGlucose(calibrated) else {
                XCTFail("no value for \(row)")
                continue
            }
            switch row.abbott {
            case nil, 39?:
                XCTAssertEqual(LibreGlucose.rangeCondition(for: calibrated), .belowRange, "\(row)")
                XCTAssertEqual(reported, GlucoseAlgorithm.minimumGlucose, "\(row)")
            case let abbott?:
                XCTAssertNil(LibreGlucose.rangeCondition(for: calibrated), "\(row)")
                XCTAssertEqual(reported.rounded(), Double(abbott), "\(row)")
            }
        }
    }
}
