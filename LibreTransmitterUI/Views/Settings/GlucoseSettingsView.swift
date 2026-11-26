//
//  GlucoseSettingsView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 26/05/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine
import LibreTransmitter

struct GlucoseSettingsView: View {

    @State private var presentableStatus: StatusMessage?

    @AppStorage("com.loopkit.libreSyncToNs") var mmSyncToNS: Bool = true
    @AppStorage("com.loopkit.libreBackfillFromHistory") var mmBackfillFromHistory: Bool = true
    @State private var smoothingMode = UserDefaults.standard.glucoseSmoothingMode
    @AppStorage("com.loopkit.libreshouldPersistSensorData") var shouldPersistSensorData: Bool = false

    @State private var authSuccess = false
    @State private var showingMinuteByMinuteWarning = false
    @AppStorage(Features.allowOneMinuteReadingsKey) private var minuteByMinuteForwardingEnabled = false
    @State private var showingAgeOffsetWarning = false
    @AppStorage(Features.officialAgeOffsetKey) private var officialAgeOffsetEnabled = false
    
    // Set this to true to require system authentication
    // for accessing the glucose section
    @State private var requiresAuthentication = Features.glucoseSettingsRequireAuthentication
    
    var body: some View {
        List {

            Section(header: Text(LocalizedString("Backfill options", comment: "Text describing header for backfill options in glucosesettingsview"))) {
                Toggle("Backfill from history", isOn: $mmBackfillFromHistory)
            }
            Section(header: Text(LocalizedString("Remote data storage", comment: "Text describing header for remote data storage"))) {
                Toggle("Upload to remote data service", isOn: $mmSyncToNS)

            }
            Section {
                Picker("Smoothing", selection: $smoothingMode) {
                    Text("Off").tag(GlucoseSmoothingMode.off)
                    Text("Temperature").tag(GlucoseSmoothingMode.temperature)
                    Text("Glucose (previous)").tag(GlucoseSmoothingMode.glucose)
                }
                .onChange(of: smoothingMode) { _, mode in
                    UserDefaults.standard.glucoseSmoothingMode = mode
                }
            } header: {
                Text("Glucose processing")
            } footer: {
                Text("Temperature filters the sensor temperature over about five minutes before temperature compensation; readings are not averaged. Glucose (previous) averages newly received trend readings over about five minutes, as before, which calms jitter but makes readings lag a changing glucose by about two minutes. Only one is applied at a time.")
            }
            Section {
                Toggle("Match the official reader's sensor-age adjustment (experimental)", isOn: Binding(
                    get: { officialAgeOffsetEnabled },
                    set: { enabled in
                        if enabled {
                            showingAgeOffsetWarning = true
                        } else {
                            officialAgeOffsetEnabled = false
                        }
                    }
                ))
            } header: {
                Text("Sensor age")
            } footer: {
                Text("When on, readings are raised the way the official reader raises them early and late in a sensor's wear: up to about 18 mg/dL in the first day (more for low readings) and a few mg/dL in the last days. Off: readings are not adjusted for sensor age.")
            }
            Section {
                Toggle("Send every Libre 2 / Libre 2 Plus reading (experimental)", isOn: Binding(
                    get: { minuteByMinuteForwardingEnabled },
                    set: { enabled in
                        if enabled {
                            showingMinuteByMinuteWarning = true
                        } else {
                            minuteByMinuteForwardingEnabled = false
                        }
                    }
                ))
            } header: {
                Text("Libre 2 / Libre 2 Plus forwarding")
            } footer: {
                if minuteByMinuteForwardingEnabled {
                    Text("For direct Libre 2 and Libre 2 Plus connections only. LibreTransmitter forwards the newest available reading about once per minute.")
                } else {
                    Text("For direct Libre 2 and Libre 2 Plus connections only. LibreTransmitter forwards the newest available reading about once every five minutes.")
                }
            }
            Section(header: Text(LocalizedString("Debug options", comment: "Text describing header for debug options in glucosesettingsview")), footer: Text(LocalizedString("Adds a lot of data to the Issue Report ", comment: "Text informing user of potentially large reports"))) {
                Toggle("Persist sensordata", isOn: $shouldPersistSensorData)
                    .onChange(of: shouldPersistSensorData) { _, newValue in
                        if !newValue {
                            UserDefaults.standard.queuedSensorData = nil
                        }
                    }
            }
            
        }
        .onAppear {
            if requiresAuthentication && !authSuccess {
                self.authenticate { success in
                    print("got authentication response: \(success)")
                    authSuccess = success
                }
            }
        }
        .disabled(requiresAuthentication ? !authSuccess : false)
        .listStyle(InsetGroupedListStyle())
        .alert(item: $presentableStatus) { status in
            Alert(title: Text(status.title), message: Text(status.message), dismissButton: .default(Text("Got it!")))
        }
        .sheet(isPresented: $showingAgeOffsetWarning) {
            OfficialAgeOffsetWarning {
                officialAgeOffsetEnabled = true
                showingAgeOffsetWarning = false
            } onCancel: {
                showingAgeOffsetWarning = false
            }
        }
        .sheet(isPresented: $showingMinuteByMinuteWarning) {
            MinuteByMinuteForwardingWarning {
                minuteByMinuteForwardingEnabled = true
                showingMinuteByMinuteWarning = false
            } onCancel: {
                showingMinuteByMinuteWarning = false
            }
        }
        .navigationBarTitle("Glucose Settings")
        
    }

}

private struct OfficialAgeOffsetWarning: View {
    let onEnable: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Experimental sensor-age adjustment", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text("The official reader adds an amount to each reading that depends on how long the sensor has been worn. This setting adds the same amount, as measured from the official algorithm, so readings match it more closely.")

                    Text("It raises readings: by up to about 18 mg/dL (1 mmol/L) during the first day, peaking around 5 to 6 hours after the sensor starts, and by a few mg/dL in the last days of wear. In the first 9 hours, low readings are raised more, for example a reading of 40 mg/dL (2.2 mmol/L) by about 30 mg/dL (1.7 mmol/L).")

                    Text("Raised low readings can delay low alerts and make Loop dose as if glucose were higher. There is no evidence that the adjusted values are more accurate than unadjusted ones; they only match the official reader more closely.")

                    Text("Use this only if you understand the effect and check fingerstick glucose when a reading doesn't match how you feel, especially on a new sensor.")

                    Button("Turn on the sensor-age adjustment", role: .destructive, action: onEnable)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Sensor-age adjustment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct MinuteByMinuteForwardingWarning: View {
    let onEnable: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Experimental Libre 2 / Libre 2 Plus setting", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text("This setting applies only when LibreTransmitter is connected directly to a Libre 2 or Libre 2 Plus sensor.")

                    Text("Loop's glucose processing and dosing behavior were designed around readings arriving about every five minutes.")

                    Text("With this enabled, LibreTransmitter sends the newest Libre 2 or Libre 2 Plus reading about once per minute. Loop can store and evaluate each reading, while its full dosing loop remains cadence-limited. The denser history may still affect glucose momentum, retrospective correction, alert timing, and other calculations.")

                    Text("Use this only if you understand the experimental behavior and monitor Loop closely after enabling it.")

                    Button("Enable for Libre 2 / Libre 2 Plus", role: .destructive, action: onEnable)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Every-minute readings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

struct GlucoseSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GlucoseSettingsView()
    }
}
