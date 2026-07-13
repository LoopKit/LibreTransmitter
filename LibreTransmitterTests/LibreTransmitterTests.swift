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

}
