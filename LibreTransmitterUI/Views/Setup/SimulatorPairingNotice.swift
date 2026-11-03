//
//  SimulatorPairingNotice.swift
//  LibreTransmitterUI
//
//  Shown on Libre 2 setup in the iOS Simulator only.
//

#if targetEnvironment(simulator)
import Combine
import SwiftUI
import LibreTransmitter

/// The iOS Simulator has no NFC and no Bluetooth, so Libre 2 pairing there
/// talks to libre2sim, a simulated sensor that runs on the Mac. This says so,
/// lists what it takes, checks each step it can, and shows why a pairing
/// failed (the setup screen otherwise only stops spinning).
struct SimulatorPairingNotice: View {
    let pairingService: SensorPairingProtocol

    @State private var sensor: String?  // what libre2sim says about its sensor; nil until checked
    @State private var reachable: Bool?
    @State private var pairingError: String?

    // ImpossiBLE's CoreBluetooth stand-in, present only when its library is injected.
    private let bluetoothLoaded = NSClassFromString("CBSPeripheral") != nil
    private let url = SimulatedSensorPairingService.baseURL

    private var errors: AnyPublisher<Error, Never> {
        (pairingService as? SimulatedSensorPairingService)?.errorPublisher ?? Empty().eraseToAnyPublisher()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verbatim: "Simulator: this pairs with libre2sim, not a real sensor").font(.headline)
            } icon: {
                Image(systemName: "desktopcomputer")
            }
            Text(verbatim: "The Simulator has no NFC or Bluetooth. Pair Sensor talks to libre2sim, a simulated Libre 2 running on this Mac. Its readings are made up: for development only, never for treatment decisions.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            step(1, done: reachable,
                 "Start libre2sim on this Mac (github.com/dabear/libre2sim): run ./start.sh in its folder.",
                 detail: reachable == false ? "Not running at \(url.absoluteString)." : sensor)
            step(2, done: bluetoothLoaded,
                 "Run this app with the ImpossiBLE library: copy the three environment variables start.sh prints into the scheme (Run, Arguments, Environment Variables), then run again.",
                 detail: bluetoothLoaded ? nil : "The library is not loaded, so the app cannot connect after pairing.")
            step(3, done: nil,
                 "Tap Pair Sensor. libre2sim's control panel (\(url.absoluteString)) can activate the sensor or end its warmup.",
                 detail: nil)

            if let pairingError {
                Text(verbatim: "Pairing failed: \(pairingError)")
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
        .task {
            // Recheck while the screen is up, so starting libre2sim shows here.
            while !Task.isCancelled {
                await check()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .onReceive(errors.receive(on: DispatchQueue.main)) { error in
            pairingError = error.localizedDescription
        }
    }

    private func step(_ n: Int, done: Bool?, _ text: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                switch done {
                case true?: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                case false?: Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
                case nil: Image(systemName: "\(n).circle")
                }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(verbatim: detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Asks libre2sim's /status what state its sensor is in.
    private func check() async {
        struct Status: Decodable {
            let serial: String
            let framState: Int
            let lifeCount: Int
            let warmupMinutes: Int
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url.appendingPathComponent("status"))
            let s = try JSONDecoder().decode(Status.self, from: data)
            let state: String
            switch s.framState {
            case 1: state = "still in its applicator: activate it in the control panel"
            case 2: state = "warming up, \(max(s.warmupMinutes - s.lifeCount, 0)) min left (or end the warmup in the control panel)"
            case 3: state = "ready to pair"
            default: state = "ended: start a new sensor in the control panel"
            }
            reachable = true
            sensor = "Found sensor \(s.serial): \(state)."
        } catch {
            reachable = false
            sensor = nil
        }
    }
}
#endif
