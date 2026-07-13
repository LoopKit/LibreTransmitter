//
//  NotificationHelper.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 30/05/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import UserNotifications
import os.log

private var logger = Logger(forType: "NotificationHelper")
// MARK: - Notification Utilities
public enum NotificationHelper {

    private enum Identifiers: String {
        case noSensorDetected = "com.loopkit.libremiaomiao.nosensordetected-notification"
        case sensorChange = "com.loopkit.libremiaomiao.sensorchange-notification"
        case invalidSensor = "com.loopkit.libremiaomiao.invalidsensor-notification"
        case lowBattery = "com.loopkit.libremiaomiao.lowbattery-notification"
        case sensorExpire = "com.loopkit.libremiaomiao.SensorExpire-notification"
        case noBridgeSelected = "com.loopkit.libremiaomiao.noBridgeSelected-notification"
        case invalidChecksum = "com.loopkit.libremiaomiao.invalidChecksum-notification"
        case calibrationOngoing = "com.loopkit.libremiaomiao.calibration-notification"
        case libre2directFinishedSetup = "com.loopkit.libremiaomiao.libre2direct-notification"
    }
    
    private static func ensureCanSendNotification(_ completion: @escaping () -> Void ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                logger.debug("\(#function) failed, authorization denied")
                return
            }
            logger.debug("\(#function) sending notification was allowed")

            completion()
        }
    }

    private static func addRequest(identifier: Identifiers, content: UNMutableNotificationContent, deleteOld: Bool = false) {
        let center = UNUserNotificationCenter.current()
        content.interruptionLevel = .timeSensitive
        
        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: nil)

        if deleteOld {
            // Required since ios12+ have started to cache/group notifications
            center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }

        center.add(request) { error in
            if let error {
                logger.debug("\(#function) unable to addNotificationRequest: \(error.localizedDescription)")
                return
            }

            logger.debug("\(#function) sending \(identifier.rawValue) notification")
        }
    }
    
}

// MARK: Sensor related notification sendouts
public extension NotificationHelper {
    static func sendLibre2DirectFinishedSetupNotifcation() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Libre 2 Direct Setup Complete"
            content.body = "Establishing initial connection can take up to 4 minutes. Keep your phone unlocked and Loop in the foreground while connecting"

            addRequest(identifier: .libre2directFinishedSetup, content: content)
        }
    }
    
    static func sendSensorNotDetectedNotificationIfNeeded(noSensor: Bool) {
        guard UserDefaults.standard.mmAlertNoSensorDetected && noSensor else {
            logger.debug("\(#function) Not sending noSensorDetected notification")
            return
        }

        sendSensorNotDetectedNotification()
    }

    private static func sendSensorNotDetectedNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "No Sensor Detected"
            content.body = "This might be an intermittent problem, but please check that your transmitter is tightly secured over your sensor"

            addRequest(identifier: .noSensorDetected, content: content)
        }
    }

    static func sendSensorChangeNotificationIfNeeded() {
        guard UserDefaults.standard.mmAlertNewSensorDetected else {
            logger.debug("\(#function) not sending sendSensorChange notification ")
            return
        }
        sendSensorChangeNotification()
    }

    static func sendSensorChangeNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "New Sensor Detected"
            content.body = "Please wait up to 30 minutes before glucose readings are available!"

            addRequest(identifier: .sensorChange, content: content)
            // content.sound = UNNotificationSound.

        }
    }

    static func sendInvalidSensorNotificationIfNeeded(sensorData: SensorData) {
        let isValid = sensorData.isLikelyLibre1FRAM && (sensorData.state == .starting || sensorData.state == .ready)

        guard UserDefaults.standard.mmAlertInvalidSensorDetected && !isValid else {
            logger.debug("\(#function) not sending invalidSensorDetected notification")
            return
        }

        sendInvalidSensorNotification(sensorData: sensorData)
    }

    enum CalibrationMessage: String {
        case invalidCalibrationData = "Could not calibrate sensor, invalid calibrationdata"
        case success = "Success!"
    }

    static func sendCalibrationNotification(_ calibrationMessage: CalibrationMessage) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.title = "Extracting calibrationdata from sensor"
            content.body = calibrationMessage.rawValue

            addRequest(identifier: .calibrationOngoing,
                       content: content,
                       deleteOld: true)
        }
    }

    static func sendInvalidSensorNotification(sensorData: SensorData) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Invalid Sensor Detected"

            if !sensorData.isLikelyLibre1FRAM {
                content.body = "Detected sensor seems not to be a libre 1 sensor!"
            } else if !(sensorData.state == .starting || sensorData.state == .ready) {
                content.body = "Detected sensor is invalid: \(sensorData.state.description)"
            }

            content.sound = .default

            addRequest(identifier: .invalidSensor, content: content)
        }
    }

    private static var lastSensorExpireAlert: Date?

    static func sendSensorExpireAlertIfNeeded(minutesLeft: Double) {
        guard UserDefaults.standard.mmAlertWillSoonExpire else {
            logger.debug("\(#function) mmAlertWillSoonExpire toggle was not enabled, not sending expiresoon alarm")
            return
        }

        guard TimeInterval(minutes: minutesLeft) < TimeInterval(hours: 24) else {
            logger.debug("\(#function) Sensor time left was more than 24 hours, not sending notification: \(minutesLeft.twoDecimals) minutes")
            return
        }

        let now = Date()
        // only once per 6 hours
        let min45 = 60.0 * 60 * 6

        if let earlier = lastSensorExpireAlert {
            if earlier.addingTimeInterval(min45) < now {
                sendSensorExpireAlert(minutesLeft: minutesLeft)
                lastSensorExpireAlert = now
            } else {
                logger.debug("\(#function) Sensor is soon expiring, but lastSensorExpireAlert was sent less than 6 hours ago, so aborting")
            }
        } else {
            sendSensorExpireAlert(minutesLeft: minutesLeft)
            lastSensorExpireAlert = now
        }
    }

    static func sendSensorExpireAlertIfNeeded(sensorData: SensorData) {
        sendSensorExpireAlertIfNeeded(minutesLeft: Double(sensorData.minutesLeft))
    }

    private static func sendSensorExpireAlert(minutesLeft: Double) {
        ensureCanSendNotification {

            let hours = minutesLeft == 0 ? 0 : round(minutesLeft/60)

            let dynamicText =  hours <= 1 ?  "minutes: \(minutesLeft.twoDecimals)" : "hours: \(hours.twoDecimals)"

            let content = UNMutableNotificationContent()
            content.title = "Sensor Ending Soon"
            content.body = "Current Sensor is Ending soon! Sensor Life left in \(dynamicText)"

            addRequest(identifier: .sensorExpire, content: content, deleteOld: true)
        }
    }
}

// MARK: - Notification sendout
public extension NotificationHelper {
   

    static func sendNoTransmitterSelectedNotification() {
        ensureCanSendNotification {
            logger.debug("\(#function) sending NoTransmitterSelectedNotification")

            let content = UNMutableNotificationContent()
            content.title = "No Libre Transmitter Selected"
            content.body = "Delete CGMManager and start anew. Your libreoopweb credentials will be preserved"

            addRequest(identifier: .noBridgeSelected, content: content)
        }
    }

    static func sendInvalidChecksumIfDeveloper(_ sensorData: SensorData) {
        guard UserDefaults.standard.dangerModeActivated else {
            return
        }

        if sensorData.hasValidCRCs {
            return
        }

        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Invalid libre checksum"
            content.body = "Libre sensor was incorrectly read, CRCs were not valid"

            addRequest(identifier: .invalidChecksum, content: content)
        }
    }

    private static var lastBatteryWarning: Date?

    static func sendLowBatteryNotificationIfNeeded(device: LibreTransmitterMetadata) {
        guard UserDefaults.standard.mmAlertLowBatteryWarning else {
            logger.debug("\(#function) mmAlertLowBatteryWarning toggle was not enabled, not sending low notification")
            return
        }

        if let battery = device.battery, battery > 20 {
            logger.debug("\(#function) device battery is \(battery), not sending low notification")
            return

        }

        let now = Date()
        // only once per mins minute
        let mins = 60.0 * 120
        if let earlierplus = lastBatteryWarning?.addingTimeInterval(mins) {
            if earlierplus < now {
                sendLowBatteryNotification(batteryPercentage: device.batteryString,
                                           deviceName: device.name)
                lastBatteryWarning = now
            } else {
                logger.debug("\(#function) Device battery is running low, but lastBatteryWarning Notification was sent less than 45 minutes ago, aborting. earlierplus: \(earlierplus), now: \(now)")
            }
        } else {
            sendLowBatteryNotification(batteryPercentage: device.batteryString,
                                       deviceName: device.name)
            lastBatteryWarning = now
        }
    }

    private static func sendLowBatteryNotification(batteryPercentage: String, deviceName: String) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Low Battery"
            content.body = "Battery is running low (\(batteryPercentage)), consider charging your \(deviceName) device as soon as possible"
            content.sound = .default

            addRequest(identifier: .lowBattery, content: content)
        }
    }

}
