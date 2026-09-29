//
//  LibreTransmitterManager.swift
//  Created by LoopKit Authors on 25/02/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI
import UIKit
import UserNotifications
import Combine

import CoreBluetooth
import HealthKit
import os.log

open class LibreTransmitterManagerV3: CGMManager, LibreTransmitterDelegate {
    
    

    
   
    

    public typealias GlucoseReadout = (trends: [LibreGlucose], historical: [LibreGlucose])
    public lazy var logger = Logger(forType: Self.self)

    public let isOnboarded = true   // No distinction between created and onboarded

    private var alertsUnitPreference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)

    public var hasValidSensorSession: Bool {
        lastConnected != nil
    }

    public var cgmManagerStatus: CGMManagerStatus {
        CGMManagerStatus(hasValidSensorSession: hasValidSensorSession, lastCommunicationDate: latestReadingTimestamp, device: nil)
    }

    /// Tracks which `LibreAlertCondition`s were issued as of the last `evaluateAlerts()` call,
    /// so it can diff against the currently-firing set and retract anything that's resolved.
    var firingAlertConditions: Set<LibreAlertCondition> = []

    /// Timestamp of the most recent successful glucose reading, from either data path.
    /// Used to detect signal loss (absence of readings) and to populate `CGMManagerStatus.lastCommunicationDate`.
    var latestReadingTimestamp: Date?

    /// The most recently observed hard sensor fault, normalized across both data paths.
    /// Cleared once the sensor recovers to a normal reporting state.
    var lastFault: LibreSensorLifecycle.FaultKind?

    /// The most recently reported `SensorState` byte from a classic (FRAM-reading) transmitter.
    /// Direct-BLE Libre2 has no equivalent signal and leaves this `nil`.
    var lastKnownSensorState: SensorState?

    public var sensorLifecycle: LibreSensorLifecycle {
        LibreSensorLifecycle.compute(
            sensorPaired: isDeviceSelected,
            activatedAt: sensorInfoObservable.activatedAt,
            expiresAt: sensorInfoObservable.expiresAt,
            latestReadingAt: latestReadingTimestamp,
            sensorMaxMinutesWearTime: sensorInfoObservable.sensorMaxMinutesWearTime,
            sensorState: lastKnownSensorState,
            lastFault: lastFault
        )
    }

    public var glucoseDisplay: GlucoseDisplayable?

    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier) {

    }

    public func getSoundBaseURL() -> URL? {
        nil
    }

    public func getSounds() -> [Alert.Sound] {
        []
    }

    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
        self.cgmManagerDelegate?.deviceManager(self, logEventForDeviceIdentifier: UserDefaults.standard.currentSensor, type: type, message: message, completion: nil)
    }

    public func libreManagerDidRestoreState(found peripherals: [CBPeripheral], connected to: CBPeripheral?) {
        let devicename = to?.name  ?? "no device"
        let id = to?.identifier.uuidString ?? "null"
        
        logger.debug("Bluetooth State restored (Loop restarted?). Found \(peripherals.count) peripherals, and connected to \(devicename) with identifier \(id)")
    }

    public var batteryLevel: Double? {
        let batt = self.proxy?.metadata?.battery
        logger.debug("LibreTransmitterManager was asked to return battery: \(batt.debugDescription)")
        // convert from 8% -> 0.8
        if let battery = proxy?.metadata?.battery {
            return Double(battery) / 100
        }

        return nil
    }

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            return delegate.delegate
        }
        set {
            delegate.delegate = newValue
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            return delegate.queue
        }
        set {
            delegate.queue = newValue
        }
    }

    public let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()

    public var managedDataInterval: TimeInterval?

    private func getPersistedSensorDataForDebug() -> String {
        guard let data = UserDefaults.standard.queuedSensorData else {
            return "nil"
        }

        let c = self.calibrationData?.description ?? "no calibrationdata"
        return data.array.map {
            "SensorData(uuid: \"0123\".data(using: .ascii)!, bytes: \($0.bytes))!"
        }
        .joined(separator: ",\n")
        + ",\n Calibrationdata: \(c)"
    }
    
    public func verifySensorChange(for sensor: Data, activatedAt: Date) {
        
        let sensorId = sensor.hexEncodedString()
        let currentSensor = UserDefaults.standard.currentSensor
        
        logger.debug("\(#function) for potential new sensor identified by uid: \(sensorId), currentsensor: \(String(describing: currentSensor))")
        
        guard currentSensor == nil || currentSensor != sensorId else {
            logger.debug("\(#function) no sensorchange detected")
            return
        }
        
        logDeviceCommunication("New sensor \(sensorId) discovered, activated at \(activatedAt)", type: .connection)
        
        logger.debug("\(#function) sensorchange detected")
            
        let event = PersistedCgmEvent(
                        date: activatedAt,
                        type: .sensorStart,
                        deviceIdentifier: sensorId,
                        expectedLifetime: .hours(24 * 14 + 12),
                        warmupPeriod: .hours(1)
                        )
        
        self.delegateQueue.async {
            self.cgmManagerDelegate?.cgmManager(self, hasNew: [event])
        }
        
        
        UserDefaults.standard.currentSensor = sensorId
        
        
        
    }

    public var debugDescription: String {

        return [
            "## LibreTransmitterManager",
            "Testdata: foo",
            "lastConnected: \(String(describing: lastConnected))",
            "Connection state: \(String(describing: self.proxy?.connectionStateString))",
            "Sensor state: \(String(describing: proxy?.sensorData?.state.description))",
            "transmitterbattery: \(String(describing: proxy?.metadata?.batteryString))",
            "SensorData: \(getPersistedSensorDataForDebug())",
            "providesBLEHeartbeat: \(providesBLEHeartbeat)",
            "Metainfo::\n\(AppMetaData.allProperties)",
            ""
        ].joined(separator: "\n")
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        logger.debug("fetchNewDataIfNeeded called but we don't continue")

        // Real data delivery happens via the delegate callbacks (libreTransmitterDidUpdate /
        // libreSensorDidUpdate), not through this polling entry point. However, this is the only
        // place we can detect "silence" (no callback at all), which is what signal-loss means -
        // so use it as a periodic safety net for evaluating lifecycle alerts.
        evaluateAlerts()

        completion(.noData)
    }

    public var lastConnected: Date?

    public var latestBackfill: LibreGlucose? {
        willSet(newValue) {
            guard let newValue else {
                return
            }

            var trend: GlucoseTrend?
            let oldValue = latestBackfill

            defer {
                // evaluateAlerts() is deliberately not called here: it depends on
                // sensorInfoObservable's activatedAt/expiresAt, which are only
                // guaranteed fresh once setObservables() has run for this same
                // update - callers trigger evaluateAlerts() themselves right after
                // that call, using data from this same read.
                latestReadingTimestamp = newValue.startDate
            }

            logger.debug("latestBackfill set, newvalue is \(newValue.glucose)")

            if let oldValue {
                // the idea here is to use the diff between the old and the new glucose to calculate slope and direction, rather than using trend from the glucose value.
                // this is because the old and new glucose values represent earlier readouts, while the trend buffer contains somewhat more jumpy (noisy) values.
                let timediff = LibreGlucose.timeDifference(oldGlucose: oldValue, newGlucose: newValue)
                logger.debug("timediff is \(timediff)")
                let oldIsRecentEnough = timediff <= TimeInterval.minutes(15)

                trend = oldIsRecentEnough ? newValue.GetGlucoseTrend(last: oldValue) : nil

                self.glucoseDisplay = ConcreteGlucoseDisplayable(isStateValid: newValue.isStateValid, trendType: trend, isLocal: true)
            } else {
                // could consider setting this to ConcreteSensorDisplayable with trendtype GlucoseTrend.flat, but that would be kinda lying
                self.glucoseDisplay = nil
            }
        }

    }

    static public let pluginIdentifier: String = "LibreTransmitterManagerV3"

    public required convenience init?(rawState: CGMManager.RawStateValue) {

        self.init()
        logger.debug("LibreTransmitterManager  has run init from rawstate")

        let persisted = LibreCGMManagerState(rawValue: rawState)
        sensorInfoObservable.activatedAt = persisted.activatedAt
        sensorInfoObservable.expiresAt = persisted.expiresAt
        sensorInfoObservable.sensorMaxMinutesWearTime = persisted.sensorMaxMinutesWearTime
        sensorInfoObservable.sensorSerial = persisted.sensorSerial ?? ""
        transmitterInfoObservable.sensorType = persisted.sensorType ?? ""
        latestReadingTimestamp = persisted.latestReadingTimestamp
        lastConnected = persisted.lastConnected
        lastPersistedState = persisted
    }

    /// A stored snapshot of the last state actually handed to
    /// `cgmManagerDelegate?.cgmManagerDidUpdateState(self)`, so `evaluateAlerts()`
    /// only notifies the delegate (triggering an app-level persistence save)
    /// when something persistence-relevant actually changed.
    var lastPersistedState: LibreCGMManagerState?

    var currentPersistableState: LibreCGMManagerState {
        LibreCGMManagerState(
            activatedAt: sensorInfoObservable.activatedAt,
            sensorMaxMinutesWearTime: sensorInfoObservable.sensorMaxMinutesWearTime,
            sensorSerial: sensorInfoObservable.sensorSerial.isEmpty ? nil : sensorInfoObservable.sensorSerial,
            sensorType: transmitterInfoObservable.sensorType.isEmpty ? nil : transmitterInfoObservable.sensorType,
            latestReadingTimestamp: latestReadingTimestamp,
            lastConnected: lastConnected
        )
    }

    public var rawState: CGMManager.RawStateValue {
        currentPersistableState.rawValue
    }

    open var localizedTitle: String {
        transmitterInfoObservable.sensorType.isEmpty ? LocalizedString("FreeStyle Libre", comment: "Generic fallback title for the CGM settings screen before a sensor type is known") : transmitterInfoObservable.sensorType
    }

    public let appURL: URL? = nil // URL(string: "spikeapp://")

    public let providesBLEHeartbeat = true
    public var shouldSyncToRemoteService: Bool {
        UserDefaults.standard.mmSyncToNs
    }

    public required init() {
        lastConnected = nil

        logger.debug("LibreTransmitterManager will be created now")

        sensorInfoObservable.isPaired = isDeviceSelected

        if isDeviceSelected {
            establishProxy()
        }
    }

    var isDeviceSelected: Bool {
        return UserDefaults.standard.preSelectedDevice != nil || UserDefaults.standard.preSelectedUid != nil || SelectionState.shared.selectedUID != nil
    }
    
    public func resetManager() {
        proxy?.activePlugin?.reset()
        disconnect()
        transmitterInfoObservable = TransmitterInfo()
        sensorInfoObservable = SensorInfo()
        sensorInfoObservable.isPaired = isDeviceSelected
        glucoseInfoObservable = GlucoseInfo()
        latestReadingTimestamp = nil
        lastFault = nil
        lastKnownSensorState = nil
        firingAlertConditions = []

        // Make sure the now-cleared state actually gets persisted, so a stale
        // activatedAt/expiresAt from the previous sensor doesn't get restored
        // on the next app launch.
        lastPersistedState = nil
        let delegate = cgmManagerDelegate
        delegateQueue.async {
            delegate?.cgmManagerDidUpdateState(self)
        }
    }

    public func disconnect() {
        logger.debug("LibreTransmitterManager disconnect called")

        proxy?.disconnectManually()
        proxy?.delegate = nil
        proxy = nil
        lastConnected = nil
        lastDirectUpdate = nil
    }
    
    open func establishProxy() {
        logger.debug("LibreTransmitterManager establishProxy called")

        proxy = LibreTransmitterProxyManager()
        proxy?.delegate = self
    }

    deinit {
        logger.debug("LibreTransmitterManager deinit called")
        // cleanup any references to events to this class
        disconnect()
    }

    public var proxy: LibreTransmitterProxyManager?

    /*
     These properties are mostly useful for swiftui
     */
    public var transmitterInfoObservable = TransmitterInfo()
    public var sensorInfoObservable = SensorInfo()
    public var glucoseInfoObservable = GlucoseInfo()

    var dateFormatter: DateFormatter = ({
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .full
        df.locale = Locale.current
        return df
    })()

    // when was the libre2 direct ble update last received?
    var lastDirectUpdate: Date?

    internal var countTimesWithoutData: Int = 0

    open var pairingService: SensorPairingProtocol {
        return SensorPairingService()
    }

    open var bluetoothSearcher: BluetoothSearcher {
        return BluetoothSearchManager()
    }
}

// MARK: - Convenience functions
extension LibreTransmitterManagerV3 {

    public func setObservables(sensorData: SensorDataProtocol?, bleData: Libre2.LibreBLEResponse?, metaData: LibreTransmitterMetadata?) {
        logger.debug("setObservables called")
        DispatchQueue.main.async {

            if let metaData=metaData {
                self.logger.debug("will set transmitterInfoObservable")
                self.transmitterInfoObservable.battery = metaData.batteryString
                self.transmitterInfoObservable.batteryPercent = metaData.battery
                self.transmitterInfoObservable.hardware = metaData.hardware ?? ""
                self.transmitterInfoObservable.firmware = metaData.firmware ?? ""
                self.transmitterInfoObservable.sensorType = metaData.sensorType()?.description ?? "Unknown"
                self.transmitterInfoObservable.transmitterMacAddress = metaData.macAddress ?? ""

            }
            let now = Date.now

            self.transmitterInfoObservable.connectionState = self.proxy?.connectionStateString ?? "n/a"
            self.transmitterInfoObservable.transmitterType = self.proxy?.shortTransmitterName ?? "Unknown"

            if let sensorData {
                self.logger.debug("will set sensorInfoObservable")
                self.sensorInfoObservable.sensorAge = sensorData.humanReadableSensorAge
                self.sensorInfoObservable.sensorAgeLeft = sensorData.humanReadableTimeLeft
                self.sensorInfoObservable.sensorMinutesLeft = sensorData.minutesLeft
                self.sensorInfoObservable.activatedAt = now - TimeInterval(minutes: Double(sensorData.minutesSinceStart))
                self.sensorInfoObservable.expiresAt = now + TimeInterval(minutes: Double(sensorData.minutesLeft))
                
                self.sensorInfoObservable.sensorMinutesSinceStart = sensorData.minutesSinceStart
                self.sensorInfoObservable.sensorMaxMinutesWearTime = sensorData.maxMinutesWearTime

                self.sensorInfoObservable.sensorState = sensorData.state.description
                self.sensorInfoObservable.sensorSerial = sensorData.serialNumber

                self.glucoseInfoObservable.checksum = String(sensorData.footerCrc.byteSwapped)

                if let sensorEndTime = sensorData.sensorEndTime {
                    self.sensorInfoObservable.sensorEndTime = self.dateFormatter.string(from: sensorEndTime )

                } else {
                    self.sensorInfoObservable.sensorEndTime = "Unknown or ended"

                }

            } else if let bleData, let sensor = UserDefaults.standard.preSelectedSensor {
                let aday = 86_400.0 // in seconds
                var humanReadableSensorAge: String {
                    let days = TimeInterval(bleData.age * 60) / aday
                    return String(format: "%.2f", days) + " day(s)"
                }

                var maxMinutesWearTime: Int {
                    sensor.maxAge
                }
                
                var minutesSinceStart: Int {
                    bleData.age
                }

                var minutesLeft: Int {
                    maxMinutesWearTime - bleData.age
                }

                var humanReadableTimeLeft: String {
                    let days = TimeInterval(minutesLeft * 60) / aday
                    return String(format: "%.2f", days) + " day(s)"
                }

                // once the sensor has ended we don't know the exact date anymore
                var sensorEndTime: Date? {
                    if minutesLeft <= 0 {
                        return nil
                    }

                    // we can assume that the libre2 direct bluetooth packet is received immediately
                    // after the sensor has been done a new measurement, so using Date() should be fine here
                    return Date().addingTimeInterval(TimeInterval(minutes: Double(minutesLeft)))
                }
                
                self.sensorInfoObservable.sensorMinutesLeft = minutesLeft
                self.sensorInfoObservable.sensorMinutesSinceStart = minutesLeft
                
                self.sensorInfoObservable.activatedAt = now - TimeInterval(minutes: Double(minutesSinceStart))
                
                if minutesLeft > 0 {
                    self.sensorInfoObservable.expiresAt = now + TimeInterval(minutes: Double(minutesLeft))
                }
                
                self.sensorInfoObservable.sensorMaxMinutesWearTime = maxMinutesWearTime

                self.sensorInfoObservable.sensorAge = humanReadableSensorAge
                self.sensorInfoObservable.sensorAgeLeft = humanReadableTimeLeft
                self.sensorInfoObservable.sensorState = "Operational"
                self.sensorInfoObservable.sensorState = "Operational"
                let family = SensorFamily.libre2
                self.sensorInfoObservable.sensorSerial = SensorSerialNumber(withUID: sensor.uuid, sensorFamily: family)?.serialNumber ?? "-"

                if let mapping = UserDefaults.standard.calibrationMapping,
                   let calibration = self.calibrationData,
                   mapping.uuid == sensor.uuid && calibration.isValidForFooterWithReverseCRCs ==  mapping.reverseFooterCRC {
                    self.glucoseInfoObservable.checksum = "\(mapping.reverseFooterCRC)"
                }

                if let sensorEndTime {
                    self.sensorInfoObservable.sensorEndTime = self.dateFormatter.string(from: sensorEndTime )

                } else {
                    self.sensorInfoObservable.sensorEndTime = "Unknown or ended"

                }

            }

            if let d = self.latestBackfill {
                self.logger.debug("will set glucoseInfoObservable")
                self.glucoseInfoObservable.glucose = d.quantity
                self.glucoseInfoObservable.date = d.timestamp
                self.sensorInfoObservable.activeMeasurementErrors = d.error.filter { $0 != .OK }
            }
        }
    }

    func getStartDateForFilter() -> Date? {
        // We prefer to use local cached glucose value for the date to filter
        // todo: fix this for ble packets
        var startDate = self.latestBackfill?.startDate

        //
        // but that might not be available when loop is restarted for example
        //
        if startDate == nil {
            startDate = self.delegate.call { $0?.startDateToFilterNewData(for: self) }
        }

        // add one second to startdate to make this an exclusive (non overlapping) match
        return startDate?.addingTimeInterval(1)
    }

    func glucosesToSamplesFilter(_ array: [LibreGlucose], startDate: Date?, calculateTrends: Bool = true) -> [NewGlucoseSample] {
        let glucoses = array.filter { $0.isStateValid }
        
        let newest = glucoses.first
        let oldest = glucoses.last
        
        var trend: GlucoseTrend?
        
        if calculateTrends, let newest, let oldest, oldest != newest {
            trend = newest.GetGlucoseTrend(last: oldest)
            logger.debug("creating trendarrow from glucoses: newest: \(String(describing:newest)) oldest: \(String(describing: oldest)) ")
        } else {
            logger.debug("Not creating trendarrow for remote uploada")
            trend = .none
        }
        logger.debug("tried creating trendarrow using \(glucoses.count) elements for trend calc")
        
        return glucoses
            .filterDateRange(startDate, nil)
            .compactMap {
                return NewGlucoseSample(
                    date: $0.startDate,
                    quantity: $0.quantity,
                    condition: nil,
                    trend: trend,
                    trendRate: nil,
                    isDisplayOnly: false,
                    wasUserEntered: false,
                    syncIdentifier: $0.syncId,
                    device: self.proxy?.device)
            }
    }

    public var calibrationData: SensorData.CalibrationInfo? {
        KeychainManager.standard.getLibreNativeCalibrationData()
    }
    
    public func getSmallImage() -> UIImage {
        proxy?.activePluginType?.smallImage ?? UIImage(named: "libresensor", in: Bundle.current, compatibleWith: nil)!
    }
}


extension LibreTransmitterManagerV3: DisplayGlucoseUnitObserver {
    public func unitDidChange(to displayGlucoseUnit: HKUnit) {
        self.alertsUnitPreference.unitDidChange(to: displayGlucoseUnit)
    }
}
