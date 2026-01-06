//
//  SensorStreamingClient.swift
//  560d2b1e-b42b-4959-a133-1c68ad916076
//
//  Created by Codex on 1/6/26.
//

import AVFoundation
import CoreLocation
import CoreMotion
import Foundation
import UIKit

/// Streams gyroscope + ambient light proxy data over a WebSocket at ~60Hz.
final class SensorStreamingClient: NSObject {
    static let shared = SensorStreamingClient()

    struct StreamOptions {
        var includeGyroscope = true
        var includeLocation = false
        var includeCameraLight = false
        var includePictureData = false
    }

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
    private var options = StreamOptions()
    private let optionsQueue = DispatchQueue(label: "com.goldenarmor.telemetry.options", attributes: .concurrent)
    private let dataQueue = DispatchQueue(label: "com.goldenarmor.telemetry.data", attributes: .concurrent)
    private let locationManager = CLLocationManager()
    private var latestLocation: CLLocation?
    private let cameraSession = AVCaptureSession()
    private let cameraQueue = DispatchQueue(label: "com.goldenarmor.telemetry.camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private var cameraSessionConfigured = false
    private var latestCameraLightLevel: Double?
    private var latestPictureBase64: String?
    private var lastPictureCaptureDate = Date.distantPast
    private let pictureCaptureInterval: TimeInterval = 1.0
    private var streamInterval: TimeInterval = 0.1

    private override init() {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
        self.webSocketURL = URL(string: "wss://incoming.telemetry.mozilla.org/submit/mdn-fred/events/1/9d309dcd-5d75-4797-808b-6f3d770604c7")!
        self.startupDateString = ISO8601DateFormatter().string(from: Date())
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func startStreaming() {
        guard timer == nil else { return }
        configureSensors(for: currentOptionsSnapshot())
        connectSocket()
        startTimer()
    }

    func stopStreaming() {
        timer?.cancel()
        timer = nil
        motionManager.stopGyroUpdates()
        locationManager.stopUpdatingLocation()
        stopCameraSession()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        endBackgroundTask()
    }

    func updateOptions(_ newOptions: StreamOptions) {
        optionsQueue.async(flags: .barrier) {
            self.options = newOptions
        }
        configureSensors(for: newOptions)
    }

    func updateStreamInterval(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        streamInterval = interval
        if isStreaming {
            restartTimer()
        }
    }

    private func currentOptionsSnapshot() -> StreamOptions {
        optionsQueue.sync { options }
    }

    private func configureSensors(for options: StreamOptions) {
        if options.includeGyroscope {
            startMotionUpdates()
        } else {
            motionManager.stopGyroUpdates()
        }

        DispatchQueue.main.async {
            self.configureLocationAccess(for: options)
            self.configureCameraAccess(for: options)
        }
    }

    private func configureLocationAccess(for options: StreamOptions) {
        if options.includeLocation {
            let status = currentLocationAuthorizationStatus()
            switch status {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.startUpdatingLocation()
            default:
                updateLatestLocation(nil)
            }
        } else {
            locationManager.stopUpdatingLocation()
            updateLatestLocation(nil)
        }
    }

    private func currentLocationAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return locationManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    private func configureCameraAccess(for options: StreamOptions) {
        if options.includeCameraLight || options.includePictureData {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                startCameraSessionIfNeeded()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        self.startCameraSessionIfNeeded()
                    } else {
                        self.clearCameraData()
                    }
                }
            default:
                clearCameraData()
            }
        } else {
            stopCameraSession()
            clearCameraData()
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isGyroAvailable else { return }
        motionManager.gyroUpdateInterval = 1.0 / 60.0
        motionManager.startGyroUpdates()
    }

    private func startCameraSessionIfNeeded() {
        cameraQueue.async {
            if !self.cameraSessionConfigured {
                self.configureCameraSession()
                self.cameraSessionConfigured = true
            }
            guard !self.cameraSession.isRunning else { return }
            self.cameraSession.startRunning()
        }
    }

    private func configureCameraSession() {
        cameraSession.beginConfiguration()
        cameraSession.sessionPreset = .low
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              cameraSession.canAddInput(input)
        else {
            cameraSession.commitConfiguration()
            return
        }
        cameraSession.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if cameraSession.canAddOutput(videoOutput) {
            cameraSession.addOutput(videoOutput)
        }
        videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)
        cameraSession.commitConfiguration()
    }

    private func stopCameraSession() {
        cameraQueue.async {
            guard self.cameraSession.isRunning else { return }
            self.cameraSession.stopRunning()
        }
    }

    private func clearCameraData() {
        dataQueue.async(flags: .barrier) {
            self.latestCameraLightLevel = nil
            self.latestPictureBase64 = nil
        }
    }

    private func updateLatestLocation(_ location: CLLocation?) {
        dataQueue.async(flags: .barrier) {
            self.latestLocation = location
        }
    }

    private func snapshotLocationInfo() -> TelemetryPayload.LocationInfo? {
        dataQueue.sync {
            guard let location = latestLocation else { return nil }
            return TelemetryPayload.LocationInfo(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy
            )
        }
    }

    private func snapshotCameraLightLevel() -> Double? {
        dataQueue.sync {
            latestCameraLightLevel
        }
    }

    private func snapshotPictureData() -> String? {
        dataQueue.sync {
            latestPictureBase64
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now(), repeating: streamInterval)
        timer.setEventHandler { [weak self] in
            self?.sendSample()
        }
        timer.resume()
        self.timer = timer
    }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        startTimer()
    }

private func sendSample() {
        let options = currentOptionsSnapshot()
        let now = Date()
        let eventTimestamp = Int64(now.timeIntervalSince1970 * 1000)
        sequenceNumber += 1

        var gyroscopePayload: TelemetryPayload.Gyro?
        if options.includeGyroscope, let gyroData = motionManager.gyroData {
            gyroscopePayload = .init(
                x: gyroData.rotationRate.x,
                y: gyroData.rotationRate.y,
                z: gyroData.rotationRate.z
            )
        }

        let screenBrightness = DispatchQueue.main.sync { Double(UIScreen.main.brightness) }
        let cameraLight = options.includeCameraLight ? snapshotCameraLightLevel() : nil
        let pictureData = options.includePictureData ? snapshotPictureData() : nil
        let locationInfo = options.includeLocation ? snapshotLocationInfo() : nil

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
                        gyroscope: gyroscopePayload,
                        lightLevel: screenBrightness,
                        cameraLightLevel: cameraLight,
                        pictureData: pictureData,
                        location: locationInfo,
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
                NSLog("Websocket Success: \(result)")
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
            let gyroscope: Gyro?
            let lightLevel: Double?
            let cameraLightLevel: Double?
            let pictureData: String?
            let location: LocationInfo?
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

    struct LocationInfo: Codable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
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

// MARK: - CLLocationManagerDelegate

extension SensorStreamingClient: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateLatestLocation(location)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        configureLocationAccess(for: currentOptionsSnapshot())
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        configureLocationAccess(for: currentOptionsSnapshot())
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("Location error: \(error.localizedDescription)")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension SensorStreamingClient: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let options = currentOptionsSnapshot()
        guard options.includeCameraLight || options.includePictureData,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        if options.includeCameraLight, let brightness = averageBrightness(from: ciImage) {
            dataQueue.async(flags: .barrier) {
                self.latestCameraLightLevel = brightness
            }
        }

        if options.includePictureData {
            let now = Date()
            guard now.timeIntervalSince(lastPictureCaptureDate) >= pictureCaptureInterval else { return }
            if let jpegString = jpegString(from: ciImage) {
                lastPictureCaptureDate = now
                dataQueue.async(flags: .barrier) {
                    self.latestPictureBase64 = jpegString
                }
            }
        }
    }

    private func averageBrightness(from image: CIImage) -> Double? {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let r = Double(bitmap[0])
        let g = Double(bitmap[1])
        let b = Double(bitmap[2])
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    }

    private func jpegString(from image: CIImage) -> String? {
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return nil }
        let baseImage = UIImage(cgImage: cgImage)
        guard let resized = baseImage.downsized(to: CGSize(width: 200, height: 150)),
              let data = resized.jpegData(compressionQuality: 0.2) else { return nil }
        return data.base64EncodedString()
    }
}

private extension UIImage {
    func downsized(to targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
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

