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
    @AppStorage("com.loopkit.libreGlucoseSmoothingEnabled") private var glucoseSmoothingEnabled = true
    @AppStorage("com.loopkit.libreshouldPersistSensorData") var shouldPersistSensorData: Bool = false

    @State private var authSuccess = false
    @State private var showingMinuteByMinuteWarning = false
    @AppStorage(Features.allowOneMinuteReadingsKey) private var minuteByMinuteForwardingEnabled = false
    
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
                Toggle("Smooth glucose readings", isOn: $glucoseSmoothingEnabled)
            } header: {
                Text("Glucose processing")
            } footer: {
                Text("Applies a five-point moving average to newly received trend readings.")
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
                    .onChange(of: shouldPersistSensorData) {newValue in
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
