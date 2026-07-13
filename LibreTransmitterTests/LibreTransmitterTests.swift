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

    private func glucose(minutes: TimeInterval, unsmoothed: Double? = nil, smoothed: Double) -> LibreGlucose {
        LibreGlucose(
            unsmoothedGlucose: unsmoothed ?? smoothed,
            glucoseDouble: smoothed,
            timestamp: Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(minutes * 60)
        )
    }

}
