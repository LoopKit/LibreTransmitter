//
//  LibreTransmitterTests.swift
//  LibreTransmitterTests
//
//  Created by Nathan Racklyeft on 5/8/16.
//  Copyright © 2016 Mark Wilson. All rights reserved.
//

import XCTest
@testable import LibreTransmitter

class LibreTransmitterTests: XCTestCase {

    // Readings are reported up to and including the wear limit minute, then cut off, as the
    // official reader does; an unknown limit (0) cuts off nothing.
    private func reading(_ minutesAgo: Double, now: Date) -> LibreGlucose {
        LibreGlucose(unsmoothedGlucose: 120, glucoseDouble: 120, timestamp: now.addingTimeInterval(-60 * minutesAgo))
    }

    // Libre 2 BLE backfill: nothing while readings arrive on time; after a gap, readings from the
    // packet at least 4.5 minutes apart and from both ends of the gap, newest first.
    func testBLEBackfillOnlyAfterAGap() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        // a packet's trend (0, 2, 4, 6, 7, 12, 15 min) and history (e.g. 9, 24, 39 min) readings
        let candidates = [0, 2, 4, 6, 7, 12, 15].map { reading(Double($0), now: now) } + [9, 24, 39].map { reading(Double($0), now: now) }
        typealias M = LibreTransmitterManagerV3
        // on time: last reported 5 minutes ago -> nothing
        XCTAssertTrue(M.bleBackfill(candidates, lastReported: now.addingTimeInterval(-5 * 60), newest: now).isEmpty)
        // no last reported reading -> nothing
        XCTAssertTrue(M.bleBackfill(candidates, lastReported: nil, newest: now).isEmpty)
        // a 30 minute gap: 6, 12 and 24 minutes old (0-4 are too close to the newest, 7 and 9 to 6,
        // 15 to 12; 39 is before the gap)
        let gap30 = M.bleBackfill(candidates, lastReported: now.addingTimeInterval(-30 * 60), newest: now)
        XCTAssertEqual(gap30.map { now.timeIntervalSince($0.startDate) / 60 }, [6, 12, 24])
        // a 50 minute gap reaches the oldest history reading too
        let gap50 = M.bleBackfill(candidates, lastReported: now.addingTimeInterval(-50 * 60), newest: now)
        XCTAssertEqual(gap50.map { now.timeIntervalSince($0.startDate) / 60 }, [6, 12, 24, 39])
        // spacing holds between all picked readings and both ends
        for pair in zip(gap50, gap50.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.startDate.timeIntervalSince(pair.1.startDate), M.bleBackfillSpacing)
        }
    }

    func testBLEHistoryDatingAmbiguity() {
        typealias M = LibreTransmitterManagerV3
        XCTAssertFalse(M.historyIsUnambiguous(age: 302))
        XCTAssertFalse(M.historyIsUnambiguous(age: 16_937))
        for age in [300, 301, 303, 310, 316, 16_940] { XCTAssertTrue(M.historyIsUnambiguous(age: age), "\(age)") }
    }

    func testWearLimitCutoff() {
        XCTAssertFalse(LibreTransmitterManagerV3.isPastWearLimit(age: 20_758, maxAge: 20_759))
        XCTAssertFalse(LibreTransmitterManagerV3.isPastWearLimit(age: 20_759, maxAge: 20_759))
        XCTAssertTrue(LibreTransmitterManagerV3.isPastWearLimit(age: 20_760, maxAge: 20_759))
        XCTAssertFalse(LibreTransmitterManagerV3.isPastWearLimit(age: 30_000, maxAge: 0))
    }

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testDirectUpdateIntervals() {
        XCTAssertEqual(Features.minimumDirectUpdateInterval(oneMinuteReadingsEnabled: true), 48)
        XCTAssertEqual(Features.minimumDirectUpdateInterval(oneMinuteReadingsEnabled: false), 270)
    }

    func testGlucoseSmoothingDefaultsToThePreviousGlucoseAverage() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        XCTAssertEqual(defaults.glucoseSmoothingMode, .glucose)
        XCTAssertTrue(defaults.glucoseSmoothingEnabled)
        XCTAssertFalse(defaults.temperatureSmoothingEnabled)
    }

    func testGlucoseSmoothingModes() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        defaults.glucoseSmoothingMode = .temperature
        XCTAssertFalse(defaults.glucoseSmoothingEnabled)
        XCTAssertTrue(defaults.temperatureSmoothingEnabled)

        defaults.glucoseSmoothingMode = .glucose
        XCTAssertTrue(defaults.glucoseSmoothingEnabled)
        XCTAssertFalse(defaults.temperatureSmoothingEnabled)

        defaults.glucoseSmoothingMode = .off
        XCTAssertFalse(defaults.glucoseSmoothingEnabled)
        XCTAssertFalse(defaults.temperatureSmoothingEnabled)
    }

    func testGlucoseSmoothingTurnedOffBeforeTheModeIsOff() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        defaults.set(false, forKey: "com.loopkit.libreGlucoseSmoothingEnabled")
        XCTAssertEqual(defaults.glucoseSmoothingMode, .off)

        defaults.set(true, forKey: "com.loopkit.libreGlucoseSmoothingEnabled")
        XCTAssertEqual(defaults.glucoseSmoothingMode, .glucose)
    }

    func testTrendUsesSmoothedGlucoseValues() {
        let current = glucose(minutes: 0, unsmoothed: 200, smoothed: 110)
        let previous = glucose(minutes: -5, unsmoothed: 100, smoothed: 100)

        XCTAssertEqual(LibreGlucose.calculateSlopeByMinute(current: current, last: previous), 2)
        XCTAssertEqual(current.GetGlucoseTrend(last: previous), .up)
    }

    func testVeryFastRiseProducesTripleUpTrend() {
        let current = glucose(minutes: 0, smoothed: 120)
        let previous = glucose(minutes: -5, smoothed: 100)

        XCTAssertEqual(current.GetGlucoseTrend(last: previous), .upUpUp)
    }

    func testRecentTrendUsesFiveMinuteComparisonInsteadOfOneMinuteNoise() {
        let glucoses = [
            glucose(minutes: 0, smoothed: 100),
            glucose(minutes: -1, smoothed: 110),
            glucose(minutes: -5, smoothed: 100),
            glucose(minutes: -15, smoothed: 70)
        ]

        let result = LibreGlucose.calculateRecentTrend(in: glucoses)

        XCTAssertEqual(result?.rate, 0)
        XCTAssertEqual(result?.trend, .flat)
    }

    func testRecentTrendAllowsNearestPointWithinCadenceTolerance() {
        let glucoses = [
            glucose(minutes: 0, smoothed: 112),
            glucose(minutes: -4.5, smoothed: 103),
            glucose(minutes: -6, smoothed: 70)
        ]

        let result = LibreGlucose.calculateRecentTrend(in: glucoses)

        XCTAssertEqual(result?.rate, 2)
        XCTAssertEqual(result?.trend, .up)
    }

    func testRecentTrendRequiresAtLeastFourMinuteComparison() {
        let glucoses = [
            glucose(minutes: 0, smoothed: 105),
            glucose(minutes: -1, smoothed: 100)
        ]

        XCTAssertNil(LibreGlucose.calculateRecentTrend(in: glucoses))
    }

    func testBLERecordsAreStampedWithTheirAge() {
        // A decrypted packet: ten 4-byte records with a nonzero raw value, then the age.
        var packet = [UInt8](repeating: 0, count: 44)
        for i in 0 ..< 10 {
            packet[i * 4] = 100
        }
        packet[40] = 100

        let response = Libre2.parseBLEData(Data(packet))

        // Trend records are 0, 2, 4, 6, 7, 12 and 15 minutes old; history records 15 minutes apart.
        for measurements in [response.trend, response.history] {
            let newest = measurements.max { $0.idValue < $1.idValue }!
            for m in measurements {
                let minutes = newest.date.timeIntervalSince(m.date) / 60
                XCTAssertEqual(minutes, Double(newest.idValue - m.idValue), accuracy: 0.01)
            }
        }
        XCTAssertEqual(response.trend.map(\.idValue), [85, 88, 93, 94, 96, 98, 100])
    }

    func testSmoothingOfOneMinuteReadingsIsUnchanged() {
        let glucoses = (0 ..< 16).map { glucose(minutes: -Double($0), smoothed: 100 + Double($0 * $0 % 7)) }

        let smoothed = CalculateSmoothedData(origtrends: glucoses).map(\.glucoseDouble)

        XCTAssertEqual(smoothed, CalculateSmothedData5Points(origtrends: glucoses).map(\.glucoseDouble))
    }

    func testSmoothingOfLibre2BLEReadingsCoversFiveMinutes() {
        // Glucose rising 1 mg/dL a minute, at the ages a Libre 2 BLE packet holds.
        let glucoses = [0, 2, 4, 6, 7, 12, 15].map { glucose(minutes: -Double($0), smoothed: 150 - Double($0)) }

        let smoothed = CalculateSmoothedData(origtrends: glucoses).map(\.glucoseDouble)

        // The newest is the mean of the readings 0, 2 and 4 minutes old, not of 0…7.
        XCTAssertEqual(smoothed[0], 148, accuracy: 0.001)
        XCTAssertEqual(smoothed[3], (144 + 143) / 2, accuracy: 0.001)
        XCTAssertEqual(smoothed[6], 135, accuracy: 0.001)
    }

    private func glucose(minutes: TimeInterval, unsmoothed: Double? = nil, smoothed: Double) -> LibreGlucose {
        LibreGlucose(
            unsmoothedGlucose: unsmoothed ?? smoothed,
            glucoseDouble: smoothed,
            timestamp: Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(minutes * 60)
        )
    }

}
