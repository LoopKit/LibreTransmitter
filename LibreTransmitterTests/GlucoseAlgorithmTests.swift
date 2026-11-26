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
