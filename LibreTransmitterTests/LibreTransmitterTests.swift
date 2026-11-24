//
//  LibreTransmitterTests.swift
//  LibreTransmitterTests
//
//  Created by Nathan Racklyeft on 5/8/16.
//  Copyright © 2016 Mark Wilson. All rights reserved.
//

import XCTest

class LibreTransmitterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testLibre2EUWithFirstByte84IsLibre2() {
        // Reported by a user with an EU sensor whose serial starts with 303
        XCTAssertEqual(SensorType(patchInfo: Data([0x84, 0x0E, 0x30, 0x01, 0xA0, 0x2A])), .libre2)
    }

    func testWrongSensorTypeShowsThePatchInfo() {
        // A first byte that isn't a known Libre 2 one, as a new sensor batch can report.
        let patchInfo = Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])
        XCTAssertEqual(SensorType(patchInfo: patchInfo), .unknown)

        let error = PairingError.wrongSensorType(patchInfo: patchInfo)
        XCTAssertEqual(error.localizedDescription, "Wrong sensor type detected (patch info: 123456789ABC)")
    }

}
