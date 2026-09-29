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
    @Environment(\.guidanceColors) private var guidanceColors

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
    @ObservedObject private var notifyShowDeviceDetails: GenericObservableObject
    @ObservedObject private var notifyShowCalibrations: GenericObservableObject

    @State private var presentableStatus: StatusMessage?

    @State private var showingDestructQuestion = false
    // @State private var showingExporter = false
    // @Environment(\.presentationMode) var presentationMode

    var pairingService: SensorPairingProtocol
    var bluetoothSearcher: BluetoothSearcher

    init(
        transmitterInfo: LibreTransmitter.TransmitterInfo,
        sensorInfo: LibreTransmitter.SensorInfo,
        glucoseMeasurement: LibreTransmitter.GlucoseInfo,
        notifyComplete: GenericObservableObject,
        notifyDelete: GenericObservableObject,
        notifyReset: GenericObservableObject,
        notifyReconnect: GenericObservableObject,
        notifyShowDeviceDetails: GenericObservableObject,
        notifyShowCalibrations: GenericObservableObject,
        pairingService: SensorPairingProtocol,
        bluetoothSearcher: BluetoothSearcher)
    {
        self.transmitterInfo = transmitterInfo
        self.sensorInfo = sensorInfo
        self.glucoseMeasurement = glucoseMeasurement
        self.notifyComplete = notifyComplete
        self.notifyDelete = notifyDelete
        self.notifyReset = notifyReset
        self.notifyReconnect = notifyReconnect
        self.notifyShowDeviceDetails = notifyShowDeviceDetails
        self.notifyShowCalibrations = notifyShowCalibrations
        self.pairingService = pairingService
        self.bluetoothSearcher = bluetoothSearcher
    }

    static let formatter = NumberFormatter()

    var body: some View {
            List {
                headerSection
                measurementSection

                sensorInfoSection

                disclosureButton(title: "Device details") {
                    notifyShowDeviceDetails.notify()
                }

                manageSection
                destructSection

            }.listStyle(InsetGroupedListStyle())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    doneButton
                }
            }
    }

    /// A List row that looks like a NavigationLink (label + disclosure chevron) but triggers
    /// a plain action instead, for rows whose destination is pushed manually in UIKit.
    func disclosureButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                SettingsItem(title: title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    var sensorInfoSection: some View {
        Section(header: Text(LocalizedString("Sensor Information", comment: "Text describing header for sensor information section"))) {
            SettingsItem(title: "Sensor Type", detail: $transmitterInfo.sensorType )
            SettingsItem(title: "Sensor Serial", detail: $sensorInfo.sensorSerial )
            SettingsItem(title: "Sensor Start", detail: sensorInfo.activatedAtString )
            SettingsItem(title: "Sensor End", detail: sensorInfo.expiresAtString )
        }
    }

    private var doneButton: some View {
        Button("Done", action: {
            notifyComplete.notify()
        })
    }
    
    var manageSection: some View {
        Section(header: Text(LocalizedString("Manage", comment: "Text describing header for manage section"))) {
            disclosureButton(title: Features.allowsEditingFactoryCalibrationData ? "Edit calibrations" : "View factory calibrations") {
                notifyShowCalibrations.notify()
            }

            NavigationLink(destination: AuthView(completeNotifier: notifyComplete, notifyReset: notifyReset, notifyReconnect: notifyReconnect, pairingService: pairingService, bluetoothSearcher: bluetoothSearcher)) {
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
    
    private var isConnected: Bool {
        [BluetoothmanagerState.Connected, .Notifying].map(\.rawValue).contains(transmitterInfo.connectionState)
    }

    var sensorStatusRow: some View {
        let status = LibreSensorStatusDisplay.compute(
            lifecycle: sensorInfo.sensorLifecycle,
            isDeviceSelected: sensorInfo.isPaired,
            isConnected: isConnected,
            measurementErrors: sensorInfo.activeMeasurementErrors
        )
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.iconName)
                .foregroundStyle(status.iconColor(guidanceColors))
            VStack(alignment: .leading, spacing: 2) {
                status.title.fontWeight(.heavy).foregroundStyle(.primary)
                status.message.foregroundStyle(.secondary)
            }
        }
    }

    // Bridge transmitter (MiaoMiao/Bubble/Blucon, etc) battery is hardware state,
    // independent of the sensor's own lifecycle. As such its kept as its own row rather than
    // folded into `LibreSensorStatusDisplay`'s severity, so it can surface
    // regardless of what the sensor status above is currently showing.
    private var isBridgeBatteryLow: Bool {
        guard let percent = transmitterInfo.batteryPercent else { return false }
        return percent <= 20
    }

    var bridgeBatteryRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "battery.25")
                .foregroundStyle(guidanceColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedString("Bridge battery low", comment: "Title for a warning that the bridge transmitter's battery is low"))
                    .fontWeight(.heavy)
                    .foregroundStyle(.primary)
                Text(LocalizedString("Consider charging your transmitter soon.", comment: "Message for a warning that the bridge transmitter's battery is low"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    var headerSection: some View {
        Section {
            VStack(alignment: .trailing) {

                Spacer()
                headerImage

                lifecycleProgress
                Spacer()

            }
            sensorStatusRow
            if isBridgeBatteryLow {
                bridgeBatteryRow
            }
        }
    }

}

/// Pushed manually as its own hosting controller (see
/// LibreTransmitterManagerV3.settingsViewController) rather than via NavigationLink, so its
/// navigationItem.title can be set directly in UIKit - see the comment on SettingsView.body.
struct DeviceInfoView: View {
    @ObservedObject var transmitterInfo: LibreTransmitter.TransmitterInfo

    var body: some View {
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
            }
        }
        .textSelection(.enabled)
    }
}
