//
//  GlucoseAlgorithmTests.swift
//  LibreTransmitterTests
//

import XCTest
@testable import LibreTransmitter

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
        XCTAssertNil(GlucoseAlgorithm.reportableGlucose(500.1))
        XCTAssertEqual(GlucoseAlgorithm.reportableGlucose(12), 40)
        XCTAssertEqual(GlucoseAlgorithm.reportableGlucose(120.4), 120.4)
        XCTAssertEqual(GlucoseAlgorithm.reportableGlucose(500), 500)
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

    func testDefaultAgeCorrectionIsNeutral() {
        for days in [-1.0, 0, 0.5, 1, 7, 14, 20] {
            XCTAssertEqual(GlucoseAlgorithm.ageFactor(days * 86400), 1)
        }
        XCTAssertEqual(GlucoseAlgorithm.ageFactor(nil), 1)

        let readings = (0..<16).map { measurement(minutes: -Double($0)) }
        let withAge = GlucoseAlgorithm.calibratedGlucoses(
            for: readings, calibrationInfo: calibration(), smoothTemperature: false,
            sensorStart: readings[0].date.addingTimeInterval(-3600))
        XCTAssertEqual(withAge[0]!, 167.07451667322786, accuracy: 1e-9)
    }

    func testAgeFactorShape() {
        let correction = GlucoseAlgorithm.AgeCorrection(earlyDeficit: 0.1, earlyTimeConstant: 6 * 3600, drift: 0.05, maxAge: 14 * 86400)

        XCTAssertEqual(GlucoseAlgorithm.ageFactor(0, correction: correction), 0.9, accuracy: 1e-12)
        let earlyPart: Double = 0.1 * exp(-1)
        let driftPart: Double = 0.05 * 6 / (14 * 24)
        XCTAssertEqual(GlucoseAlgorithm.ageFactor(6 * 3600, correction: correction), 1 - earlyPart + driftPart, accuracy: 1e-12)
        XCTAssertEqual(GlucoseAlgorithm.ageFactor(14 * 86400, correction: correction), 1.05, accuracy: 1e-6)
        // drift stops at maxAge
        XCTAssertEqual(GlucoseAlgorithm.ageFactor(20 * 86400, correction: correction), 1.05, accuracy: 1e-6)
        // unknown or negative age is not corrected
        XCTAssertEqual(GlucoseAlgorithm.ageFactor(-60, correction: correction), 1)
        // a misconfigured correction can't zero or flip the sensitivity
        XCTAssertEqual(GlucoseAlgorithm.ageFactor(0, correction: .init(earlyDeficit: 2)), 0.5)
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
}
