//
//  SensorStreamingClient.swift
//  560d2b1e-b42b-4959-a133-1c68ad916076
//
//  Created by Codex on 1/6/26.
//

import Foundation
import CoreMotion
import UIKit

/// Streams gyroscope + ambient light proxy data over a WebSocket at ~60Hz.
final class SensorStreamingClient {
    static let shared = SensorStreamingClient()

    /// Target WebSocket endpoint. Updating it triggers a reconnect when streaming.
    var webSocketURL: URL {
        didSet {
            guard oldValue != webSocketURL, isStreaming else { return }
            reconnectSocket()
        }
    }

    /// Whether the app should try to keep streaming after moving to the background.
    var allowsBackgroundStreaming: Bool = false {
        didSet {
            if allowsBackgroundStreaming {
                extendBackgroundTimeIfNeeded()
            } else {
                endBackgroundTask()
            }
        }
    }

    private let motionManager = CMMotionManager()
    private let session: URLSession
    private var socketTask: URLSessionWebSocketTask?
    private var timer: DispatchSourceTimer?
    private var isStreaming: Bool { timer != nil }
    private let workQueue = DispatchQueue(label: "com.goldenarmor.telemetry.streamer", qos: .userInitiated)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let telemetryIdentifier = "560d2b1e-b42b-4959-a133-1c68ad916076"
    private let sessionID = UUID().uuidString
    private let clientID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let startupDateString: String
    private var sequenceNumber: Int = 0

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
        self.webSocketURL = URL(string: "wss://560d2b1e-b42b-4959-a133-1c68ad916076/telemetry/IPHONE-DATA")!
        self.startupDateString = ISO8601DateFormatter().string(from: Date())
    }

    func startStreaming() {
        guard timer == nil else { return }
        startMotionUpdates()
        connectSocket()
        startTimer()
    }

    func stopStreaming() {
        timer?.cancel()
        timer = nil
        motionManager.stopGyroUpdates()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        endBackgroundTask()
    }

    private func startMotionUpdates() {
        guard motionManager.isGyroAvailable else { return }
        motionManager.gyroUpdateInterval = 1.0 / 60.0
        motionManager.startGyroUpdates()
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in
            self?.sendSample()
        }
        timer.resume()
        self.timer = timer
    }

    private func sendSample() {
        guard let gyroData = motionManager.gyroData else { return }

        let now = Date()
        let brightness = DispatchQueue.main.sync { UIScreen.main.brightness }
        let eventTimestamp = Int64(now.timeIntervalSince1970 * 1000)
        sequenceNumber += 1

        let payload = TelemetryPayload(
            metrics: .init(uuid: .init(gleanPageID: telemetryIdentifier)),
            events: [
                .init(
                    category: "TELEMETRY",
                    name: "IPHONE-DATA",
                    timestamp: eventTimestamp,
                    extra: .init(
                        id: telemetryIdentifier,
                        uuid: telemetryIdentifier,
                        gyroscope: .init(x: gyroData.rotationRate.x,
                                         y: gyroData.rotationRate.y,
                                         z: gyroData.rotationRate.z),
                        lightLevel: Double(brightness),
                        endpoint: webSocketURL.absoluteString,
                        device_model: UIDevice.current.model,
                        system_name: UIDevice.current.systemName,
                        system_version: UIDevice.current.systemVersion,
                        app_build: Bundle.main.appBuildVersion,
                        app_version: Bundle.main.appDisplayVersion
                    )
                )
            ],
            ping_info: .init(
                seq: sequenceNumber,
                start_time: isoDateFormatter.string(from: now),
                end_time: isoDateFormatter.string(from: now),
                reason: "ios_sensor_stream"
            ),
            client_info: .init(
                telemetry_sdk_build: "swift-\(UIDevice.current.systemVersion)",
                session_id: sessionID,
                client_id: clientID,
                session_count: sequenceNumber,
                first_run_date: startupDateString,
                os: UIDevice.current.systemName,
                os_version: UIDevice.current.systemVersion,
                architecture: Architecture.current.rawValue,
                locale: Locale.current.identifier,
                app_build: Bundle.main.appBuildVersion,
                app_display_version: Bundle.main.appDisplayVersion,
                app_channel: "prod"
            )
        )

        guard let jsonString = payload.jsonString else { return }
        socketTask?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                NSLog("SensorStreamingClient send error: \(error.localizedDescription)")
                self?.reconnectSocket(after: 2)
            }
        }
    }

    private func connectSocket() {
        socketTask?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: webSocketURL)
        socketTask = task
        task.resume()
        listenForMessages()
    }

    private func listenForMessages() {
        socketTask?.receive { [weak self] result in
            switch result {
            case .failure:
                self?.reconnectSocket(after: 2)
            case .success:
                self?.listenForMessages()
            }
        }
    }

    private func reconnectSocket(after delay: TimeInterval = 0) {
        guard isStreaming else { return }
        workQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connectSocket()
        }
    }

    private func extendBackgroundTimeIfNeeded() {
        guard allowsBackgroundStreaming else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.backgroundTask == .invalid else { return }
            self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "TelemetryStream") {
                self.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.backgroundTask != .invalid else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
    }

    func notifySceneDidEnterBackground() {
        extendBackgroundTimeIfNeeded()
    }

    func notifySceneWillEnterForeground() {
        endBackgroundTask()
    }
}

private enum Architecture: String {
    case arm64
    case x86_64
    case unknown

    static var current: Architecture {
    #if arch(arm64)
        return .arm64
    #elseif arch(x86_64)
        return .x86_64
    #else
        return .unknown
    #endif
    }
}

private struct TelemetryPayload: Codable {
    struct Metrics: Codable {
        struct UUIDSection: Codable {
            let gleanPageID: String

            enum CodingKeys: String, CodingKey {
                case gleanPageID = "glean.page_id"
            }
        }

        let uuid: UUIDSection
    }

    struct Event: Codable {
        struct Extra: Codable {
            let id: String
            let uuid: String
            let gyroscope: Gyro
            let lightLevel: Double
            let endpoint: String
            let device_model: String
            let system_name: String
            let system_version: String
            let app_build: String
            let app_version: String
        }

        let category: String
        let name: String
        let timestamp: Int64
        let extra: Extra
    }

    struct PingInfo: Codable {
        let seq: Int
        let start_time: String
        let end_time: String
        let reason: String
    }

    struct ClientInfo: Codable {
        let telemetry_sdk_build: String
        let session_id: String
        let client_id: String
        let session_count: Int
        let first_run_date: String
        let os: String
        let os_version: String
        let architecture: String
        let locale: String
        let app_build: String
        let app_display_version: String
        let app_channel: String
    }

    struct Gyro: Codable {
        let x: Double
        let y: Double
        let z: Double
    }

    let metrics: Metrics
    let events: [Event]
    let ping_info: PingInfo
    let client_info: ClientInfo
}

private extension TelemetryPayload {
    var jsonString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private extension Bundle {
    var appDisplayVersion: String {
        if let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return "Unknown"
    }

    var appBuildVersion: String {
        if let build = object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String {
            return build
        }
        return "Unknown"
    }
}
