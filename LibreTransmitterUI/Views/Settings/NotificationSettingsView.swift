//
//  NotificationSettingsView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 27/05/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LibreTransmitter
import LoopKitUI

struct NotificationSettingsView: View {
    private enum Key: String {
        case mmAlertLowBatteryWarning = "com.loopkit.libreLowBatteryWarning"
        case mmAlertInvalidSensorDetected = "com.loopkit.libreInvalidSensorDetected"
        case mmAlertNewSensorDetected = "com.loopkit.libreNewSensorDetected"
        case mmAlertNoSensorDetected = "com.loopkit.libreNoSensorDetected"
        case mmAlertSensorSoonExpire = "com.loopkit.libreAlertSensorSoonExpire"
    }

    @AppStorage(Key.mmAlertLowBatteryWarning.rawValue) var mmAlertLowBatteryWarning: Bool = true
    @AppStorage(Key.mmAlertInvalidSensorDetected.rawValue) var mmAlertInvalidSensorDetected: Bool = true
    @AppStorage(Key.mmAlertNewSensorDetected.rawValue) var mmAlertNewSensorDetected: Bool = true
    @AppStorage(Key.mmAlertNoSensorDetected.rawValue) var mmAlertNoSensorDetected: Bool = true
    @AppStorage(Key.mmAlertSensorSoonExpire.rawValue) var mmAlertSensorSoonExpire: Bool = true

    var additionalNotificationsSection: some View {
        Section(header: Text(LocalizedString("Additional notification types", comment: "Text describing heading for additional notification types for third party transmitters"))) {
            Toggle("Low battery", isOn: $mmAlertLowBatteryWarning)
            Toggle("Invalid sensor", isOn: $mmAlertInvalidSensorDetected)
            Toggle("Sensor change", isOn: $mmAlertNewSensorDetected)
            Toggle("Sensor not found", isOn: $mmAlertNoSensorDetected)
            Toggle("Sensor expires soon", isOn: $mmAlertSensorSoonExpire)

        }
    }

    var body: some View {
        List {
            additionalNotificationsSection
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle("Notification")
    }
}

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView()
    }
}
