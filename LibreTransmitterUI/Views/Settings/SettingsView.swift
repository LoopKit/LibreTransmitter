//
//  SettingsOverview.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 12/06/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI

import LibreTransmitter
import HealthKit
import LoopKit
import LoopKitUI
import UniformTypeIdentifiers

public struct SettingsItem: View {

    @State var title: String = "" // we don't want this to change after it is set
    @Binding var detail: String

    init(title: String, detail: Binding<String>) {
        self.title = title
        self._detail = detail
    }

    // basically allows caller to set a static string without having to use .constant
    init(title: String, detail: String="") {
        self.title = title
        self._detail = Binding<String>(get: {
            detail
        }, set: { _ in
            // pass
        })
    }

    public var body: some View {
        HStack {
            Text(title)
            if !detail.isEmpty {
                Spacer()
                Text(detail).font(.subheadline)
            }
            
        }

    }
}

struct SettingsView: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.appName) private var appName

    var longDateFormatter: DateFormatter = ({
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .long
        df.doesRelativeDateFormatting = true
        return df
    })()

    @ObservedObject private var transmitterInfo: LibreTransmitter.TransmitterInfo
    @ObservedObject private var sensorInfo: LibreTransmitter.SensorInfo

    @ObservedObject private var glucoseMeasurement: LibreTransmitter.GlucoseInfo

    @ObservedObject private var notifyComplete: GenericObservableObject
    @ObservedObject private var notifyDelete: GenericObservableObject
    @ObservedObject private var notifyReset: GenericObservableObject
    @ObservedObject private var notifyReconnect: GenericObservableObject

    @State private var presentableStatus: StatusMessage?
    @ObservedObject var alarmStatus: LibreTransmitter.AlarmStatus

    @State private var showingDestructQuestion = false
    @State private var showingMinuteByMinuteWarning = false
    @State private var minuteByMinuteForwardingEnabled: Bool
    // @State private var showingExporter = false
    // @Environment(\.presentationMode) var presentationMode

    var pairingService: SensorPairingProtocol
    var bluetoothSearcher: BluetoothSearcher

    private let cgmManager: LibreTransmitterManagerV3

    init(
        cgmManager: LibreTransmitterManagerV3,
        transmitterInfo: LibreTransmitter.TransmitterInfo,
        sensorInfo: LibreTransmitter.SensorInfo,
        glucoseMeasurement: LibreTransmitter.GlucoseInfo,
        notifyComplete: GenericObservableObject,
        notifyDelete: GenericObservableObject,
        notifyReset: GenericObservableObject,
        notifyReconnect: GenericObservableObject,
        alarmStatus: LibreTransmitter.AlarmStatus,
        pairingService: SensorPairingProtocol,
        bluetoothSearcher: BluetoothSearcher)
    {
        self.cgmManager = cgmManager
        self._minuteByMinuteForwardingEnabled = State(initialValue: cgmManager.experimentalMinuteByMinuteForwarding)
        self.transmitterInfo = transmitterInfo
        self.sensorInfo = sensorInfo
        self.glucoseMeasurement = glucoseMeasurement
        self.notifyComplete = notifyComplete
        self.notifyDelete = notifyDelete
        self.notifyReset = notifyReset
        self.notifyReconnect = notifyReconnect
        self.alarmStatus = alarmStatus
        self.pairingService = pairingService
        self.bluetoothSearcher = bluetoothSearcher
    }

    private var glucoseUnit: HKUnit {
        displayGlucosePreference.unit
    }

    static let formatter = NumberFormatter()

    // no navigationview necessary when running inside a uihostingcontroller
    // uihostingcontroller seems to add a navigationview for us, causing problems if we
    // also add one herer
    var body: some View {
            List {
                headerSection
                snoozeSection
                measurementSection
                if let date = glucoseMeasurement.predictionDate, let prediction = glucoseMeasurement.prediction {
                    Section(header: Text(LocalizedString("Last Blood Sugar prediction", comment: "Text describing header for Blood Sugar prediction section"))) {
                        SettingsItem(title: "CurrentBG", detail: displayGlucosePreference.format(prediction))
                        SettingsItem(title: "Date", detail: longDateFormatter.string(from: date) )
                    }
                }
                
                NavigationLink(destination: deviceInfoSection) {
                    SettingsItem(title: "Device details")
                }
                
                NavigationLink(destination: CalibrationEditView()) {
                    Button(Features.allowsEditingFactoryCalibrationData ? "Edit calibrations" : "View factory calibrations") {
                        print("edit calibration clicked")
                    }
                }
                if cgmManager.isLibre2DirectConnection {
                    forwardingSection
                }
                advancedSection
                sensorChangeSection
                destructSection
                
            }.listStyle(InsetGroupedListStyle())
            // The sheet must be attached at the List level. Attached inside a
            // Section, the List rebuilds its rows on the state change and
            // dismisses the sheet immediately.
            .sheet(isPresented: $showingMinuteByMinuteWarning) {
                MinuteByMinuteWarningSheet(
                    onEnable: {
                        setMinuteByMinuteForwarding(true)
                        showingMinuteByMinuteWarning = false
                    },
                    onCancel: { showingMinuteByMinuteWarning = false }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    doneButton
                }
            }
    }

    var snoozeSection: some View {
        Section {
            NavigationLink(destination: SnoozeView(isAlarming: $alarmStatus.isAlarming, activeAlarms: $alarmStatus.glucoseScheduleAlarmResult)) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
                Text(LocalizedString("Pause Glucose alarms", comment: "Text for pausing glucose alarms")).frame(alignment: .center)
                    .foregroundColor(.blue)
                
            }
        }
    }

    var measurementSection : some View {
        var glucoseText: String = ""
        var glucoseDateText: String = ""
        if let glucose = glucoseMeasurement.glucose {
            glucoseText = displayGlucosePreference.format(glucose)
        }
        if let date = glucoseMeasurement.date {
            glucoseDateText = longDateFormatter.string(from: date)
        }

        return Section(header: Text(LocalizedString("Last measurement", comment: "Text describing header for last measurement section"))) {
            SettingsItem(title: "Glucose", detail: glucoseText)
            SettingsItem(title: "Date", detail: glucoseDateText )
            SettingsItem(title: "Sensor Footer checksum", detail: $glucoseMeasurement.checksum )
        }
    }

    var deviceInfoSection: some View {
        List {
            Section(header: Text(LocalizedString("Device Info", comment: "Text describing header for device info section"))) {
                if !transmitterInfo.battery.isEmpty {
                    SettingsItem(title: "Battery", detail: $transmitterInfo.battery )
                }
                
                // The firmware version is not always extractable for all devices
                // and the libre2 direct version does not support it at all
                if !transmitterInfo.hardware.isEmpty {
                    SettingsItem(title: "Hardware", detail: $transmitterInfo.hardware )
                }
                // The firmware version is not always extractable for all devices
                // and the libre2 direct version does not support it at all
                if !transmitterInfo.firmware.isEmpty {
                    SettingsItem(title: "Firmware", detail: $transmitterInfo.firmware )
                }
                
                SettingsItem(title: "Connection State", detail: $transmitterInfo.connectionState )
                SettingsItem(title: "Transmitter Type", detail: $transmitterInfo.transmitterType )
                
                // The mac address of a given device is normally not available on ios
                // Only the bluetooth identifier, which is a normalized derivative of the mac address is available
                // However, some transmitters, such as the bubble, provide their own mac address as part of its advertisement info
                // which we extract and put herer
                if !transmitterInfo.transmitterMacAddress.isEmpty {
                    SettingsItem(title: "Mac", detail: $transmitterInfo.transmitterMacAddress )
                }
                
                SettingsItem(title: "Sensor Type", detail: $transmitterInfo.sensorType )
                
                SettingsItem(title: "Sensor Start", detail: sensorInfo.activatedAtString )
                SettingsItem(title: "Sensor End", detail: sensorInfo.expiresAtString )
            }
        }
        .textSelection(.enabled)
    }

    private var doneButton: some View {
        Button("Done", action: {
            notifyComplete.notify()
        })
    }
    
    var sensorChangeSection: some View {
        
        Section {
            NavigationLink(destination: AuthView(completeNotifier: notifyComplete, notifyReset: notifyReset, notifyReconnect: notifyReconnect, pairingService: pairingService, bluetoothSearcher: bluetoothSearcher)) {
                /*Button("Change Sensor") {
                }.foregroundColor(.blue)*/
                SettingsItem(title: "Change Sensor").foregroundColor(.blue)
            }
        }
    }

    var destructSection: some View {
        Section {
            Button("Delete CGM") {
                showingDestructQuestion = true
            }.foregroundColor(.red)
            .alert(isPresented: $showingDestructQuestion) {
                Alert(
                    title: Text(LocalizedString("Are you sure you want to remove this cgm from loop?", comment: "Text describing question to remove the cgmmanager from loop")),
                    message: Text(LocalizedString("There is no undo. Deleting requires authentication!", comment: "Text warning user there is no undo for deleting cgmmanager")),
                    primaryButton: .destructive(Text(LocalizedString("Delete", comment: "Action text for deleting cgmmanager"))) {
                        
                        self.authenticate { success in
                            print("got authentication response: \(success)")
                            if success {
                                DispatchQueue.main.async {
                                    notifyDelete.notify()
                                }
                            }
                        }
                        
                    },
                    secondaryButton: .cancel()
                )
            }

        }
    }

    /// Toggle for the per-minute experimental forwarding mode. Default is
    /// off (readings throttled to ~5 min) because the loop algorithms were
    /// designed against 5-minute CGM input. Turning it on requires the user
    /// to read the warning sheet. Only shown for the libre2 direct bluetooth
    /// connection, the only mode that produces a reading every minute.
    var forwardingSection: some View {
        Section(header: Text(String(format: LocalizedString("Forwarding to %1$@", comment: "Text describing header for forwarding section (1: appName)"), appName))) {
            Toggle(LocalizedString("Send every reading (experimental)", comment: "Experimental minute-by-minute forwarding toggle"), isOn: Binding(
                get: { minuteByMinuteForwardingEnabled },
                set: { newValue in
                    if newValue {
                        showingMinuteByMinuteWarning = true
                    } else {
                        setMinuteByMinuteForwarding(false)
                    }
                }
            ))
            Text(minuteByMinuteForwardingEnabled
                 ? String(format: LocalizedString("Every reading from the sensor (~1/min) is sent to %1$@.", comment: "Forwarding footer: minute-by-minute on (1: appName)"), appName)
                 : String(format: LocalizedString("Only one reading every ~5 minutes is sent to %1$@, matching the cadence other CGMs use.", comment: "Forwarding footer: minute-by-minute off (1: appName)"), appName))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func setMinuteByMinuteForwarding(_ enabled: Bool) {
        cgmManager.setExperimentalMinuteByMinuteForwarding(enabled)
        minuteByMinuteForwardingEnabled = enabled
    }

    var advancedSection: some View {
        Section(header: Text(LocalizedString("Configuration", comment: "Text describing header for advanced settings section"))) {
            // these subviews don't really need to be notified once glucose unit changes
            // so we just pass glucoseunit directly on init
            NavigationLink(destination: AlarmSettingsView(glucoseUnit: self.glucoseUnit)) {
                SettingsItem(title: "Alarms")
            }
            
            if NotificationHelper.criticalAlarmsEnabled {
                NavigationLink(destination: CriticalAlarmsVolumeView()) {
                    SettingsItem(title: "Critical Alarms volume")
                }
            }
            
            NavigationLink(destination: GlucoseSettingsView()) {
                SettingsItem(title: "Glucose Settings")
            }
        
            NavigationLink(destination: NotificationSettingsView()) {
                SettingsItem(title: "Notifications")
            }

        }
    }
    
    private var daysRemaining: Int? {
        if let remaining = sensorInfo.expiresAt?.timeIntervalSinceNow, remaining > .days(1) {
            return Int(remaining.days)
        }
        return nil
    }
    
    private var hoursRemaining: Int? {
    
        if let remaining = sensorInfo.expiresAt?.timeIntervalSinceNow, remaining > .hours(1) {
            return Int(remaining.hours.truncatingRemainder(dividingBy: 24))
        }
        return nil
    }
    
    private var minutesRemaining: Int? {
        
        if let remaining = sensorInfo.expiresAt?.timeIntervalSinceNow, remaining < .hours(2) {
            return Int(remaining.minutes.truncatingRemainder(dividingBy: 60))
        }
        return nil
    }
    
    func timeComponent(value: Int, units: String) -> some View {
        Group {
            Text(String(value)).font(.system(size: 28)).fontWeight(.heavy)
                .foregroundColor(.primary)
                // .foregroundColor(viewModel.podOk ? .primary : .secondary)
            Text(units).foregroundColor(.secondary)
        }
    }
    
    var sensorIsExpired : Bool {
        if let expiresAt = sensorInfo.expiresAt {
            return expiresAt.timeIntervalSinceNow < 0
        }
        
        return false
    }
    
    var showProgress : Bool {
        
        if let expiresAt = sensorInfo.expiresAt {
            return expiresAt.timeIntervalSinceNow > 0
        }
        
        return false
    }
    
    var lifecycleProgress: some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                if showProgress {
                    Text(LocalizedString("Sensor expires in ", comment: "Text describing sensor expires in label in settingsview"))
                        .foregroundColor(.secondary)
                }/* else {
                    Text(LocalizedString("No Connection: ", comment: "Text describing no connection label in settingsview"))
                        .foregroundColor(.secondary)
                    + Text("\(transmitterInfo.connectionState)")
                        .foregroundColor(.secondary)
                }*/
                
                Spacer()
                if showProgress {
                    daysRemaining.map { (days) in
                        timeComponent(value: days, units: days == 1 ?
                                      LocalizedString("day", comment: "Unit for singular day in sensor liferemaining") :
                                        LocalizedString("days", comment: "Unit for plural days in sensor life remaining"))
                    }
                    hoursRemaining.map { (hours) in
                        timeComponent(value: hours, units: hours == 1 ?
                                      LocalizedString("hour", comment: "Unit for singular hour in sensor life remaining") :
                                        LocalizedString("hours", comment: "Unit for plural hours in sensor life remaining"))
                    }
                    minutesRemaining.map { (minutes) in
                        timeComponent(value: minutes, units: minutes == 1 ?
                                      LocalizedString("minute", comment: "Unit for singular minute in sensor life remaining") :
                                        LocalizedString("minutes", comment: "Unit for plural minutes in sensor life remaining"))
                    }
                }
            }
            if showProgress {
                
                SwiftUI.ProgressView(value: sensorInfo.calculateProgress())
                    .scaleEffect(x: 1, y: 4, anchor: .center)
                    .padding(.top, 2)
                // ProgressView(progress: ))
                Spacer()
            }
            // .accentColor(self.viewModel.lifeState.progressColor(guidanceColors: guidanceColors))
        }
    }
    
    var headerImage: some View {
        VStack(alignment: .center) {
            Image(uiImage: UIImage(named: "libresensor200", in: Bundle.current, compatibleWith: nil)!)
                .resizable()
                .aspectRatio(contentMode: ContentMode.fit)
                .frame(height: 100)
                .padding(.horizontal)
        }.frame(maxWidth: .infinity)
    }
    
    var sensorStatusText : String {
        let ret = sensorInfo.sensorState
        return ret.isEmpty ? " - " : ret
    }
    var sensorStatus: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedString("Sensor State", comment: "Text describing Sensor state label in settingsview"))
                .fontWeight(.heavy)
                .fixedSize()
            Text("\(sensorStatusText)")
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }
    
    var sensorSerialText : String {
        let ret = sensorInfo.sensorSerial
        print("got serial: \(ret)")
        return ret.isEmpty ? " - " : ret
    }
    
    var sensorSerial : some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedString("Sensor Serial", comment: "Text describing Sensor serial label in settingsview"))
                // .font(.system(size: 1))
                .fontWeight(.heavy)
                .fixedSize()
            Text("\(sensorSerialText)")
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }
    
    var headerSection: some View {
        Section {
            VStack(alignment: .trailing) {
                
                Spacer()
                headerImage
                
                lifecycleProgress
                Spacer()
                HStack(alignment: .top) {
                    sensorStatus
                    Spacer()
                    sensorSerial
                }
                
                /*Divider()
                Text("some faultAction")
                    .font(Font.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                 */
                
            }
            if sensorIsExpired {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sensor is expired")
                        .font(Font.subheadline.weight(.bold))
                    Text("Replace sensor immediately to continue receving glucose values")
                        .font(Font.footnote.weight(.semibold))
                }.padding(.vertical, 8)
            } else if !["Notifying", "Connected"].contains(transmitterInfo.connectionState) || !showProgress {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString("No Connection: ", comment: "Text describing no connection label in settingsview"))
                        .font(Font.subheadline.weight(.bold))
                     Text("\(transmitterInfo.connectionState)")
                        .font(Font.footnote.weight(.semibold))
                }.padding(.vertical, 8)
            }
        }
    }

}

struct MinuteByMinuteWarningSheet: View {
    let onEnable: () -> Void
    let onCancel: () -> Void
    @Environment(\.appName) private var appName

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(LocalizedString("Experimental setting", comment: "Minute-by-minute warning header"), systemImage: "exclamationmark.triangle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.orange)

                    Text(String(format: LocalizedString("%1$@'s algorithm was designed and tuned against CGMs that emit a new reading every 5 minutes. With this setting on, %1$@ receives a new reading from the sensor every minute instead.", comment: "Minute-by-minute warning paragraph 1 (1: appName)"), appName))
                    Text(String(format: LocalizedString("This can change how %1$@ reacts to glucose movement compared to default behavior:", comment: "Minute-by-minute warning paragraph 2 (1: appName)"), appName))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: LocalizedString("• Dosing decisions may shift sooner or further than what %1$@'s review and tuning guidance assumes.", comment: "Minute-by-minute warning bullet 1 (1: appName)"), appName))
                        Text(LocalizedString("• Trend math, retrospective correction, and momentum effects were validated at the 5-minute cadence.", comment: "Minute-by-minute warning bullet 2"))
                        Text(LocalizedString("• Readings are sent unsmoothed, so single-reading noise is passed on as-is.", comment: "Minute-by-minute warning bullet 3"))
                        Text(LocalizedString("• You're accepting responsibility for monitoring outcomes more closely while this is on.", comment: "Minute-by-minute warning bullet 4"))
                    }
                    .font(.callout)
                    Text(LocalizedString("Leave this off unless you understand the implications. You can turn it off again at any time.", comment: "Minute-by-minute warning footer"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationBarTitle(Text(LocalizedString("Send every reading", comment: "Minute-by-minute warning screen title")), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedString("Cancel", comment: "Cancel button"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedString("Enable", comment: "Enable button"), action: onEnable)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

extension Bundle {
    /// The host app's display name (Loop, iAPS, Trio, a rebrand, …).
    /// `Bundle.main` is the running app, not this plugin, so this resolves to
    /// whatever app embedded LibreTransmitter.
    var bundleDisplayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Loop"
    }
}

struct SettingsOverview_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView()
    }
}
