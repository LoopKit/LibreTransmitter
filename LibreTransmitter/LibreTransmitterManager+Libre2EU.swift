//
//  LibreTransmitterManager+Libre2EU.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors on 25/04/2022.
//  Copyright © 2022 Mark Wilson. All rights reserved.
//

import Foundation
import LoopKit

extension LibreTransmitterManagerV3 {

    /// Whether a sensor `age` minutes old is past its wear limit (`maxAge`, the FRAM footer's
    /// maxMinutesWearTime). Readings are reported up to and including the limit minute; 0 means the
    /// limit is unknown, and then nothing is cut off.
    static func isPastWearLimit(age: Int, maxAge: Int) -> Bool {
        maxAge > 0 && age > maxAge
    }

    /// Whether a BLE packet's history readings can be dated with confidence. The packet's history
    /// slots are placed on the 15-minute grid as ((age - 2) / 15) * 15 and the two before it; reading
    /// the same records from FRAM puts the newest one 3 minutes after its grid minute instead. The two
    /// agree except when age is 2 minutes past a grid minute, where they differ by a whole slot, so a
    /// packet's history readings are not used then (its trend readings still are).
    static func historyIsUnambiguous(age: Int) -> Bool {
        age % 15 != 2
    }

    /// Spacing (seconds) kept between backfilled readings, and between them and the readings around
    /// the gap: about Loop's five-minute cadence, with the same tolerance as BLE delivery.
    static let bleBackfillSpacing: TimeInterval = 4.5 * 60

    /// Readings to backfill over a gap in Libre 2 BLE delivery: from `candidates` (a packet's history
    /// readings, 2-46 minutes old on the 15-minute grid, and its older trend readings), those dated after
    /// `lastReported` and before `newest`, at least `bleBackfillSpacing` from each other and from both
    /// ends, newest first. Empty unless more than one delivery was missed (`newest` more than
    /// 7 minutes after `lastReported`) or when there is no last reported reading.
    static func bleBackfill(_ candidates: [LibreGlucose], lastReported: Date?, newest: Date) -> [LibreGlucose] {
        guard let lastReported, newest.timeIntervalSince(lastReported) > 7 * 60 else {
            return []
        }
        var picked = [LibreGlucose]()
        var previous = newest
        for reading in candidates.sorted(by: { $0.startDate > $1.startDate }) {
            guard previous.timeIntervalSince(reading.startDate) >= bleBackfillSpacing,
                  reading.startDate.timeIntervalSince(lastReported) >= bleBackfillSpacing else {
                continue
            }
            picked.append(reading)
            previous = reading.startDate
        }
        return picked
    }

    public func libreSensorDidUpdate(with error: LibreError) {

        self.logDeviceCommunication("Sensor error \(error)", type: .error)
        delegate.notify { delegate in
            await delegate?.cgmManager(self, hasNew: .error(error))
        }

    }
    

   
    
    public func libreSensorDidUpdate(with bleData: Libre2.LibreBLEResponse, and Device: LibreTransmitterMetadata) {
        self.logger.debug("got sensordata: \(String(describing: bleData))")
        let typeDesc = Device.sensorType().debugDescription

        let now = Date()
        // Leave a small tolerance around the sensor's nominal 1- or 5-minute cadence.
        let minimumUpdateInterval = Features.currentMinimumDirectUpdateInterval
        if let nextAllowedUpdate = lastDirectUpdate?.addingTimeInterval(minimumUpdateInterval), nextAllowedUpdate >= now {
            logger.debug("last BLE update was less than \(minimumUpdateInterval) seconds ago, aborting Loop update")
            //self.logDeviceCommunication("Sensor didUpdate (not used) \(bleData)", type: .receive)
            return
        }

        logger.debug("Directly connected to libresensor of type \(typeDesc). Details:  \(Device.description)")
        
        self.logDeviceCommunication("Sensor \(typeDesc) didUpdate \(bleData)", type: .receive)
        

        guard let mapping = UserDefaults.standard.calibrationMapping,
              let calibrationData,
              let sensor = UserDefaults.standard.preSelectedSensor else {
            logger.error("calibrationdata, sensor uid or mapping missing, could not continue")
            
            
            
            delegate.notify { delegate in
                await delegate?.cgmManager(self, hasNew: .error(LibreError.noCalibrationData))
            }
            return
        }



        guard mapping.reverseFooterCRC == calibrationData.isValidForFooterWithReverseCRCs &&
                mapping.uuid == sensor.uuid else {
            logger.error("Calibrationdata was not correct for these bluetooth packets. This is a fatal error, we cannot calibrate without re-pairing")
            delegate.notify { delegate in
                await delegate?.cgmManager(self, hasNew: .error(LibreError.noCalibrationData))
            }
            return
        }

        if sensor.maxAge > 0 {
            let minutesLeft = Double(sensor.maxAge - bleData.age)
            NotificationHelper.sendSensorExpireAlertIfNeeded(minutesLeft: minutesLeft)

        }

        // Past its wear limit the sensor's readings are no longer reported, as the official reader
        // stops then too. The FRAM/transmitter path stops on the sensor's own state byte instead.
        guard !Self.isPastWearLimit(age: bleData.age, maxAge: sensor.maxAge) else {
            logger.debug("sensor age \(bleData.age) is past its wear limit \(sensor.maxAge), not reporting readings")
            delegate.notify { delegate in
                await delegate?.cgmManager(self, hasNew: .error(LibreError.expiredSensor))
            }
            return
        }


        verifySensorChange(for: sensor.uuid, activatedAt: Date() - TimeInterval(minutes: Double(bleData.age)))
           
        

        let sortedTrends = bleData.trend.sorted { $0.date > $1.date}

        let glucose = LibreGlucose.fromTrendMeasurements(sortedTrends, nativeCalibrationData: calibrationData, sensorStart: Date() - TimeInterval(minutes: Double(bleData.age)))

        let filterStart = getStartDateForFilter()
        var newGlucose : [NewGlucoseSample] = glucosesToSamplesFilter(glucose, startDate: filterStart)
        // For libre2 bluetooth we do need all trend elements to calculate trendarrow,
        // but we can't report all those trends back to loop
        if let newest = newGlucose.last {
            newGlucose = [newest]
        }

        // After a gap in delivery (out of range, the app suspended), backfill it from the packet's
        // history readings (15-minute grid, up to 46 minutes back) and older trend readings, marked
        // as backfill, when "Backfill from history" is on. Nothing changes while readings arrive on time.
        if UserDefaults.standard.mmBackfillFromHistory, let newest = newGlucose.first {
            let history = Self.historyIsUnambiguous(age: bleData.age)
                ? LibreGlucose.fromHistoryMeasurements(bleData.history, nativeCalibrationData: calibrationData,
                                                       sensorStart: Date() - TimeInterval(minutes: Double(bleData.age)))
                : []
            let backfill = Self.bleBackfill(history + glucose, lastReported: filterStart, newest: newest.date)
            if !backfill.isEmpty {
                logger.debug("backfilling \(backfill.count) readings over a BLE gap")
                newGlucose = glucosesToSamplesFilter(backfill, startDate: filterStart, calculateTrends: false, isBackfill: true) + newGlucose
            }
        }

        if newGlucose.isEmpty {
            self.countTimesWithoutData &+= 1
        } else {
            self.latestBackfill = glucose.max { $0.startDate < $1.startDate }
            // The newest reading carries the trend; backfilled readings before it don't
            if let latestBackfill, let newestSample = newGlucose.max(by: { $0.date < $1.date }) {
                self.glucoseDisplay = ConcreteGlucoseDisplayable(
                    isStateValid: latestBackfill.isStateValid,
                    trendType: newestSample.trend,
                    isLocal: true,
                    trendRate: newestSample.trendRate
                )
            }
            self.latestPrediction =  self.createBloodSugarPrediction(bleData.trend, calibration: calibrationData,
                                                                sensorStart: Date() - TimeInterval(minutes: Double(bleData.age)))
            self.logger.debug("latestbackfill set to \(self.latestBackfill.debugDescription)")
            self.countTimesWithoutData = 0
        }

        self.setObservables(sensorData: nil, bleData: bleData, metaData: Device)

        self.logger.debug("handleGoodReading returned with \(newGlucose.count) entries")
        var result: CGMReadingResult
        // If several readings from a valid and running sensor come out empty,
        // we have (with a large degree of confidence) a sensor that has been
        // ripped off the body
        if self.countTimesWithoutData > 1 {
            result = .error(LibreError.noValidSensorData)
        } else {
            result = newGlucose.isEmpty ? .noData : .newData(newGlucose)
        }
        delegate.notify { delegate in
            await delegate?.cgmManager(self, hasNew: result)
        }

        lastDirectUpdate = Date()

    }
}
