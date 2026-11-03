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

    func testGlucoseSmoothingDefaultsToEnabled() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        XCTAssertTrue(defaults.glucoseSmoothingEnabled)
    }

    func testGlucoseSmoothingCanBeDisabled() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        defaults.glucoseSmoothingEnabled = false

        XCTAssertFalse(defaults.glucoseSmoothingEnabled)
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
