//
//  Libre2TrendTests.swift
//  LibreTransmitterTests
//

import XCTest
@testable import LibreTransmitter

// Foundation also has a Measurement type
private typealias Measurement = LibreTransmitter.Measurement

class Libre2TrendTests: XCTestCase {

    private let receivedAt = Date(timeIntervalSince1970: 1_792_000_000)

    /// A decrypted Libre 2 BLE packet: 7 trend and 3 history readings of 4 bytes each, then the sensor age.
    /// Raw glucose is the reading's slot index plus 1000, so readings can be told apart
    private func blePacket(age: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 44)
        for slot in 0..<10 {
            let rawGlucose = UInt32(1000 + slot)
            let rawTemperature = UInt32(8000 >> 2) // stored in multiples of four
            let block = rawGlucose | rawTemperature << 0xe
            for byte in 0..<4 {
                bytes[slot * 4 + byte] = UInt8(truncatingIfNeeded: block >> (8 * byte))
            }
        }
        bytes[40] = UInt8(age & 0xff)
        bytes[41] = UInt8(age >> 8)
        return Data(bytes)
    }

    private func minutesBefore(_ date: Date, _ measurement: Measurement) -> Double {
        date.timeIntervalSince(measurement.date) / 60
    }

    func testTrendReadingsAreDatedByTheirSensorMinute() {
        let parsed = Libre2.parseBLEData(blePacket(age: 1000), date: receivedAt)

        // sorted oldest first; slots 6...0 are 15, 12, 7, 6, 4, 2 and 0 minutes old
        XCTAssertEqual(parsed.trend.map(\.idValue), [985, 988, 993, 994, 996, 998, 1000])
        XCTAssertEqual(parsed.trend.map { minutesBefore(receivedAt, $0) }, [15, 12, 7, 6, 4, 2, 0])
        XCTAssertEqual(parsed.trend.map(\.rawGlucose), [1006, 1005, 1004, 1003, 1002, 1001, 1000])
    }

    func testHistoryReadingsAreDatedOnTheFifteenMinuteGrid() {
        let parsed = Libre2.parseBLEData(blePacket(age: 1000), date: receivedAt)

        XCTAssertEqual(parsed.history.map(\.idValue), [960, 975, 990])
        XCTAssertEqual(parsed.history.map { minutesBefore(receivedAt, $0) }, [40, 25, 10])
    }

    /// Simulates one packet a minute up to `lastAge`, buffering and merging like Libre2DirectTransmitter
    private func receivePackets(through lastAge: Int, count: Int) -> [Measurement] {
        var buffer = LimitedQueue<Measurement>(limit: 30)
        var merged: [Measurement] = []

        for age in (lastAge - count + 1)...lastAge {
            let date = receivedAt.addingTimeInterval(Double(age - lastAge) * 60)
            let trends = Libre2.parseBLEData(blePacket(age: age), date: date).trend
            let buffered = buffer.array
            for trend in Libre2.trendsToBuffer(trends, buffered: buffered) {
                buffer.enqueue(trend)
            }
            merged = Libre2.mergeTrends(trends, buffered: buffered)
        }
        return merged
    }

    func testFirstPacketOnlyHasItsOwnSlots() {
        let merged = receivePackets(through: 1000, count: 1)

        XCTAssertEqual(merged.map(\.idValue), [985, 988, 993, 994, 996, 998, 1000])
    }

    func testBufferedPacketsFillEveryMinuteOfTheWindow() {
        let merged = receivePackets(through: 1000, count: 25)

        // every minute within 20 minutes of the newest reading, each exactly once
        XCTAssertEqual(merged.map(\.idValue), Array(981...1000))
        XCTAssertEqual(merged.map { minutesBefore(receivedAt, $0) }, (0..<20).reversed().map(Double.init))
    }

    func testOnlyNewerReadingsAreBuffered() {
        let first = Libre2.parseBLEData(blePacket(age: 1000), date: receivedAt).trend
        let next = Libre2.parseBLEData(blePacket(age: 1001), date: receivedAt.addingTimeInterval(60)).trend

        XCTAssertEqual(Libre2.trendsToBuffer(first, buffered: []).count, 7)
        XCTAssertEqual(Libre2.trendsToBuffer(next, buffered: first).map(\.idValue), [1001])
    }

    func testMergeKeepsPacketReadingsOverBufferedOnes() {
        let packet = Libre2.parseBLEData(blePacket(age: 1000), date: receivedAt).trend
        // a buffered reading for a minute that is also in the packet, with a slightly different date
        let stale = Measurement(date: receivedAt.addingTimeInterval(-121), rawGlucose: 1, rawTemperature: 8000,
                                rawTemperatureAdjustment: 0, idValue: 998)

        let merged = Libre2.mergeTrends(packet, buffered: [stale])

        XCTAssertEqual(merged.filter { $0.idValue == 998 }.map(\.rawGlucose), [1001])
        XCTAssertEqual(merged.count, packet.count)
    }
}
