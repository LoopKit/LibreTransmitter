//
//  SimulatedSensorPairingService.swift
//  LibreTransmitter
//

#if targetEnvironment(simulator)
import Foundation
import Combine

/// The iOS Simulator has no NFC, so Libre 2 pairing there talks to libre2sim,
/// whose HTTP API stands in for the sensor's NFC tag. It is asked the same
/// questions SensorPairingService asks over CoreNFC, in the same order, and the
/// answers go through the same checks. Set LIBRE2SIM_URL to reach it somewhere
/// other than port 8081.
public final class SimulatedSensorPairingService: SensorPairingProtocol {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let readingsSubject = PassthroughSubject<SensorPairingInfo, Never>()
    private let errorSubject = PassthroughSubject<Error, Never>()

    private let unlockCode: UInt32 = 42 // same as SensorPairingService

    public var onCancel: (() -> Void)?

    public var publisher: AnyPublisher<SensorPairingInfo, Never> {
        readingsSubject.eraseToAnyPublisher()
    }

    public var errorPublisher: AnyPublisher<Error, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    public static var baseURL: URL {
        URL(string: ProcessInfo.processInfo.environment["LIBRE2SIM_URL"] ?? "http://127.0.0.1:8081")!
    }

    public func pairSensor() throws {
        Task {
            do {
                let info = try await scan()
                DispatchQueue.main.async { self.readingsSubject.send(info) }
            } catch {
                print("libre2sim pairing failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorSubject.send(error)
                    self.onCancel?()
                }
            }
        }
    }

    /// SensorPairingService's scan, with libre2sim as the tag.
    private func scan() async throws -> SensorPairingInfo {
        let sensorUID = Data(try await nfc(["op": "identifier"]).reversed())
        _ = try await nfc(["op": "systemInfo"])
        let patchInfo = try await nfc(["op": "custom", "code": 0xA1, "parameters": ""])

        let blocks = 43
        let requestBlocks = 3
        var fram = Data()
        for first in stride(from: 0, to: blocks, by: requestBlocks) {
            fram += try await readBlocks(first: first, count: min(requestBlocks, blocks - first))
        }

        // patchInfo should have length 6, but indexing it below would crash if it did not
        guard patchInfo.count >= 6 else { throw PairingError.noPatchInfo }

        // the real service builds the command, so the two cannot drift apart
        let cmd = SensorPairingService.enableStreamingCommand(unlockCode: unlockCode, patchInfo: patchInfo, sensorUID: sensorUID)
        let response = try await nfc(["op": "custom", "code": Int(cmd.code), "parameters": cmd.parameters.hexEncodedString()])

        var streamingEnabled = false
        var macAddress: String?
        if response.count == 6 {
            streamingEnabled = true
            macAddress = Data(response.reversed()).hexEncodedString().uppercased()
        }

        guard sensorUID.count == 8 && patchInfo.count == 6 && fram.count == 344 else {
            throw PairingError.noSensorData
        }
        let sensorType = SensorType(patchInfo: patchInfo)
        guard sensorType == .libre2 else {
            throw PairingError.wrongSensorType
        }

        let decryptedBytes: [UInt8]
        do {
            decryptedBytes = try Libre2.decryptFRAM(type: sensorType, id: [UInt8](sensorUID), info: patchInfo, data: [UInt8](fram))
        } catch {
            throw PairingError.decryptionError
        }

        return SensorPairingInfo(uuid: sensorUID, patchInfo: patchInfo, fram: Data(decryptedBytes), streamingEnabled: streamingEnabled, macAddress: macAddress)
    }

    private func readBlocks(first: Int, count: Int) async throws -> Data {
        struct Reply: Decodable { let blocks: [String] }
        let reply = try JSONDecoder().decode(Reply.self, from: try await post(["op": "readBlocks", "first": first, "count": count]))
        var data = Data()
        for block in reply.blocks {
            guard let bytes = Data(simulatorHex: block) else { throw Failure(message: "libre2sim sent a malformed block") }
            data += bytes
        }
        return data
    }

    /// An ISO 15693 command, answered as CoreNFC would return it.
    private func nfc(_ request: [String: Any]) async throws -> Data {
        struct Reply: Decodable { let response: String }
        let reply = try JSONDecoder().decode(Reply.self, from: try await post(request))
        guard let data = Data(simulatorHex: reply.response) else {
            throw Failure(message: "libre2sim sent a malformed NFC response")
        }
        return data
    }

    private func post(_ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("nfc"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "libre2sim is not running at \(Self.baseURL.absoluteString): \(error.localizedDescription)")
        }

        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            struct Reply: Decodable { let error: String? }
            let message = (try? JSONDecoder().decode(Reply.self, from: data))?.error ?? "HTTP \(status)"
            throw Failure(message: "libre2sim: \(message)")
        }
        return data
    }
}

private extension Data {
    init?(simulatorHex hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
#endif
