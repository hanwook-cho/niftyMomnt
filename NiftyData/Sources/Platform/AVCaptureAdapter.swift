// NiftyData/Sources/Platform/AVCaptureAdapter.swift
// Wraps AVFoundation. Implements CaptureEngineProtocol.
// This is the only file that imports AVFoundation for capture.
//
// Mode classes:
//   Photo class (.still, .live)  — AVCapturePhotoOutput, .photo preset
//   Video class (.clip, .atmosphere placeholder) — AVCaptureMovieFileOutput
//   Audio class (.echo) — AVAudioRecorder (.m4a)

import AVFoundation
import Combine
import CoreLocation
import Foundation
import NiftyCore
import os
import UIKit

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "AVCaptureAdapter")

public final class AVCaptureAdapter: CaptureEngineProtocol {
    private let config: AppConfig
    private let stateSubject = CurrentValueSubject<CaptureState, Never>(.idle)
    private let telemetrySubject = PassthroughSubject<CaptureTelemetry, Never>()

    /// Serial queue for all AVCaptureSession configuration work.
    /// AVFoundation requires that begin/commitConfiguration are called on a consistent
    /// queue; calling them ad-hoc from Swift concurrency threads causes multi-second
    /// stalls on class changes (e.g. video → photo output swap).
    private let sessionQueue = DispatchQueue(label: "com.hwcho99.niftymomnt.sessionQ",
                                             qos: .userInitiated)

    /// Shared session. The UI layer attaches an AVCaptureVideoPreviewLayer to this.
    public let session = AVCaptureSession()
    /// Retained so we can remove it cleanly without iterating session.inputs post-stopRunning.
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    /// Retained so we can remove it cleanly without iterating session.inputs post-stopRunning.
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var isSessionConfigured = false
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentMode: CaptureMode = .still
    /// Prevents concurrent switchMode calls from stacking redundant reconfigures.
    private var isSwitchingMode = false
    /// Retained until the photo delegate callback fires.
    private var activePhotoDelegate: PhotoDelegate?
    /// Retained until the movie file is fully written.
    private var activeMovieDelegate: MovieDelegate?
    /// Retained while Echo is recording audio-only media.
    private var activeEchoRecording: EchoRecordingSession?

    /// Provides GPS coordinate at capture time.
    private let locationProvider = LocationProvider()

    public init(config: AppConfig) {
        self.config = config
        // locationProvider.start() is called from startSession() — after the app window
        // is active — so the system location permission prompt fires correctly.
    }

    public var captureState: AnyPublisher<CaptureState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    public var telemetry: AnyPublisher<CaptureTelemetry, Never> {
        telemetrySubject.eraseToAnyPublisher()
    }

    // MARK: - Session lifecycle

    public func startSession(mode: CaptureMode, config: AppConfig) async throws {
        await MainActor.run { locationProvider.start() }

        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        log.debug("startSession mode=\(mode.rawValue) authStatus=\(String(describing: authStatus.rawValue))")
        guard authStatus == .authorized else {
            log.error("startSession denied — camera not authorized (status \(authStatus.rawValue))")
            await MainActor.run { stateSubject.send(.error(.unauthorized)) }
            throw CaptureError.unauthorized
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                if !isSessionConfigured {
                    log.debug("configuring AVCaptureSession for mode=\(mode.rawValue)")
                    do {
                        try configureSession(for: mode)
                        self.isSessionConfigured = true
                        self.currentMode = mode
                    } catch {
                        cont.resume(throwing: error)
                        return
                    }
                    log.debug("AVCaptureSession configured — inputs: \(self.session.inputs.count) outputs: \(self.session.outputs.count)")
                }
                if !session.isRunning {
                    session.startRunning()
                }
                if session.isRunning {
                    log.debug("AVCaptureSession running")
                    cont.resume()
                } else {
                    log.error("AVCaptureSession failed to start — waiting 300ms then rebuilding")
                    Thread.sleep(forTimeInterval: 0.3)
                    do {
                        resetSessionStateOnQueue()
                        try configureSession(for: mode)
                        self.isSessionConfigured = true
                        self.currentMode = mode
                        session.startRunning()
                        if session.isRunning {
                            log.debug("AVCaptureSession running after rebuild")
                            cont.resume()
                        } else {
                            log.error("AVCaptureSession failed to start after rebuild")
                            cont.resume(throwing: CaptureError.sessionFailed)
                        }
                    } catch {
                        log.error("AVCaptureSession rebuild failed: \(error)")
                        cont.resume(throwing: error)
                    }
                }
            }
        }
        await MainActor.run { stateSubject.send(.ready(mode: mode)) }
    }

    public func stopSession() async {
        await MainActor.run { locationProvider.stop() }
        activeEchoRecording?.cancelAndDelete()
        activeEchoRecording = nil
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                resetSessionStateOnQueue()
                self.isSessionConfigured = false
                self.currentMode = .still
                cont.resume()
            }
        }
        await MainActor.run { stateSubject.send(.idle) }
    }

    // MARK: - Still / Live Photo Capture

    public func captureAsset() async throws -> Asset {
        guard let photoOutput else {
            log.error("captureAsset — photoOutput is nil (not a photo-mode session?)")
            throw CaptureError.sessionFailed
        }
        let isLive = currentMode == .live
        log.debug("captureAsset — triggering AVCapturePhotoOutput mode=\(self.currentMode.rawValue)")
        stateSubject.send(.capturing(mode: currentMode))

        // Create assetID before capture so we can name the Live Photo MOV temp file.
        let assetID = UUID()

        // For Live mode: supply a temp URL for the companion MOV.
        // AVFoundation writes the MOV here automatically when livePhotoMovieFileURL is set.
        let liveMovTempURL: URL? = (isLive && photoOutput.isLivePhotoCaptureEnabled)
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent(assetID.uuidString)
                .appendingPathExtension("mov")
            : nil

        let jpegData = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let delegate = PhotoDelegate(continuation: cont, isLiveCapture: liveMovTempURL != nil)
            activePhotoDelegate = delegate
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            if let movURL = liveMovTempURL {
                settings.livePhotoMovieFileURL = movURL
                log.debug("captureAsset — Live Photo MOV temp: \(movURL.lastPathComponent)")
            }
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
        activePhotoDelegate = nil
        log.debug("captureAsset — delegate returned \(jpegData.count) bytes")

        let gps = locationProvider.currentCoordinate
        if let gps {
            log.debug("captureAsset — GPS: lat=\(gps.latitude, format: .fixed(precision: 5)) lon=\(gps.longitude, format: .fixed(precision: 5))")
        } else {
            log.warning("captureAsset — no GPS fix. Geocoding will be skipped.")
        }

        let tempJpegURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(assetID.uuidString)
            .appendingPathExtension("jpg")
        try jpegData.write(to: tempJpegURL)
        log.debug("captureAsset — JPEG written to temp: \(tempJpegURL.lastPathComponent)")

        if let movURL = liveMovTempURL {
            let movExists = FileManager.default.fileExists(atPath: movURL.path)
            log.debug("captureAsset — live MOV at temp: \(movExists ? "present" : "MISSING")")
        }

        let assetType: AssetType = isLive ? .live : .still
        stateSubject.send(.processing)
        return Asset(id: assetID, type: assetType, capturedAt: Date(), location: gps)
    }

    // MARK: - Clip / Echo / Atmosphere Recording

    public func startRecording(mode: CaptureMode) async throws {
        if mode == .echo || mode == .atmosphere {
            guard activeEchoRecording == nil else {
                log.warning("startRecording — echo already recording, ignoring")
                return
            }
            let assetID = UUID()
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(assetID.uuidString)
                .appendingPathExtension("m4a")
            let session = try EchoRecordingSession(assetID: assetID, fileURL: tempURL)
            try session.start()
            activeEchoRecording = session
            currentMode = mode
            stateSubject.send(.capturing(mode: mode))
            log.debug("startRecording — echo tempURL=\(tempURL.lastPathComponent)")
            return
        }

        guard let movieOutput else {
            log.error("startRecording — movieOutput is nil (not a video-mode session?)")
            throw CaptureError.sessionFailed
        }
        guard !movieOutput.isRecording else {
            log.warning("startRecording — already recording, ignoring")
            return
        }
        let assetID = UUID()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(assetID.uuidString)
            .appendingPathExtension("mov")
        let delegate = MovieDelegate(assetID: assetID)
        activeMovieDelegate = delegate

        if let connection = movieOutput.connection(with: .video) {
            let deviceOrientation = UIDevice.current.orientation
            if #available(iOS 17.0, *) {
                if let rotationAngle = currentVideoRotationAngle(for: deviceOrientation),
                   connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                    log.debug("startRecording — rotationAngle=\(rotationAngle)")
                } else if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                    log.debug("startRecording — rotationAngle fallback=90")
                }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = currentVideoOrientation(for: deviceOrientation) ?? .portrait
                log.debug("startRecording — videoOrientation fallback applied")
            }
        }

        log.debug("startRecording — mode=\(mode.rawValue) tempURL=\(tempURL.lastPathComponent)")
        movieOutput.startRecording(to: tempURL, recordingDelegate: delegate)
        currentMode = mode
        stateSubject.send(.capturing(mode: mode))
    }

    public func stopRecording() async throws -> Asset {
        if (currentMode == .echo || currentMode == .atmosphere), let session = activeEchoRecording {
            let (assetID, duration) = try session.stop()
            activeEchoRecording = nil
            let gps = locationProvider.currentCoordinate
            
            if currentMode == .atmosphere {
                log.debug("stopRecording — atmosphere capturing final high-res frame")
                // Trigger a photo capture for the Atmosphere hero image
                let photoOutput = self.photoOutput
                let jpegData = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    let delegate = PhotoDelegate(continuation: cont, isLiveCapture: false)
                    self.activePhotoDelegate = delegate
                    let settings = AVCapturePhotoSettings()
                    photoOutput?.capturePhoto(with: settings, delegate: delegate)
                }
                self.activePhotoDelegate = nil
                let tempJpegURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(assetID.uuidString)
                    .appendingPathExtension("jpg")
                try jpegData.write(to: tempJpegURL)
            }

            stateSubject.send(.processing)
            let mLabel = self.currentMode.rawValue
            let dLabel = String(format: "%.1f", duration)
            log.debug("stopRecording — \(mLabel) done id=\(assetID.uuidString) duration=\(dLabel)s")
            return Asset(id: assetID, type: assetType(for: self.currentMode), capturedAt: Date(), location: gps, duration: duration)
        }

        guard let movieOutput, let delegate = activeMovieDelegate else {
            log.error("stopRecording — no active recording")
            throw CaptureError.sessionFailed
        }
        log.debug("stopRecording — stopping movie output")
        movieOutput.stopRecording()
        // Wait for the file delegate to confirm the file is fully written.
        let (assetID, duration) = try await delegate.waitForCompletion()
        activeMovieDelegate = nil
        log.debug("stopRecording — done id=\(assetID.uuidString) duration=\(String(format: "%.1f", duration))s")

        let gps = locationProvider.currentCoordinate
        let type = assetType(for: currentMode)
        stateSubject.send(.processing)
        return Asset(id: assetID, type: type, capturedAt: Date(), location: gps, duration: duration)
    }

    // MARK: - Mode / Camera Switch

    public func switchMode(to mode: CaptureMode, gestureTime: Double) async throws {
        guard mode != currentMode else { return }
        log.debug("switchMode \(self.currentMode.rawValue) → \(mode.rawValue)")

        let wasVideoMode = isVideoMode(currentMode)
        let willBeVideoMode = isVideoMode(mode)

        // All session configuration must run on sessionQueue to avoid multi-second
        // stalls that occur when begin/commitConfiguration are called from an ad-hoc thread.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                // Skip if another switch is already in progress; the caller already updated
                // its own currentMode state so the session will converge on the next swipe.
                guard !isSwitchingMode else {
                    log.debug("switchMode — skipping, switch already in progress")
                    cont.resume()
                    return
                }
                isSwitchingMode = true
                defer { isSwitchingMode = false }

                // t0 = gesture receipt time; measure full latency from user input
                let queueLag = CACurrentMediaTime() - gestureTime
                log.debug("switchMode — sessionQueue lag from gesture: \(String(format: "%.3f", queueLag))s")

                if wasVideoMode != willBeVideoMode {
                    log.debug("switchMode — output class change: \(wasVideoMode ? "video" : "photo") → \(willBeVideoMode ? "video" : "photo")")
                    session.beginConfiguration()
                    let tBegin = CACurrentMediaTime()

                        // Surgical cleanup: remove only outputs. 
                        // Do NOT remove videoDeviceInput here as it breaks the preview layer connection (Fig error -17281).
                        if let photoOut = self.photoOutput {
                            session.removeOutput(photoOut)
                            self.photoOutput = nil
                        }
                        if let movieOut = self.movieOutput {
                            session.removeOutput(movieOut)
                            self.movieOutput = nil
                        }

                        if wasVideoMode, let audio = self.audioDeviceInput {
                        session.removeInput(audio)
                            self.audioDeviceInput = nil
                        log.debug("switchMode — audio input removed")
                    }
                    session.sessionPreset = wasVideoMode ? .photo : resolvedPreset(for: mode)
                    if willBeVideoMode {
                        try? addAudioInput()
                        let output = AVCaptureMovieFileOutput()
                        if session.canAddOutput(output) {
                            session.addOutput(output)
                            movieOutput = output
                        }
                        photoOutput = nil
                    } else {
                        let output = AVCapturePhotoOutput()
                        if session.canAddOutput(output) {
                            session.addOutput(output)
                            photoOutput = output
                            if output.isLivePhotoCaptureSupported {
                                output.isLivePhotoCaptureEnabled = true
                                log.debug("switchMode — Live Photo capture enabled on new output")
                            }
                        }
                        movieOutput = nil
                    }
                    session.commitConfiguration()
                    self.currentMode = mode
                    let now = CACurrentMediaTime()
                    log.debug("switchMode — commitConfiguration: \(String(format: "%.3f", now - tBegin))s  total from gesture: \(String(format: "%.3f", now - gestureTime))s")
                } else {
                    // Same class — preset-only update, always fast
                    let tBegin = CACurrentMediaTime()
                    session.beginConfiguration()
                    session.sessionPreset = resolvedPreset(for: mode)
                    session.commitConfiguration()
                    self.currentMode = mode
                    let now = CACurrentMediaTime()
                    log.debug("switchMode — same-class preset update: \(String(format: "%.3f", now - tBegin))s  total from gesture: \(String(format: "%.3f", now - gestureTime))s")
                }
                cont.resume()
            }
        }
        currentMode = mode
        stateSubject.send(.ready(mode: mode))
        log.debug("switchMode done — now \(mode.rawValue)")
    }

    public func switchCamera() async throws {
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        log.debug("switchCamera → \(newPosition == .front ? "front" : "back")")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                session.beginConfiguration()
                if let videoInput = videoDeviceInput {
                    session.removeInput(videoInput)
                    videoDeviceInput = nil
                }

                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                    let input = try? AVCaptureDeviceInput(device: device),
                    session.canAddInput(input)
                else {
                    log.error("switchCamera — could not find device for position \(String(describing: newPosition))")
                    session.commitConfiguration()
                    cont.resume(throwing: CaptureError.modeSwitchFailed)
                    return
                }
                session.addInput(input)
                videoDeviceInput = input
                session.commitConfiguration()
                currentPosition = newPosition
                log.debug("switchCamera done — now \(newPosition == .front ? "front" : "back")")
                cont.resume()
            }
        }
    }

    public func focusAndLock(at point: CGPoint, frameSize: CGSize) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                guard let device = videoDeviceInput?.device else {
                    cont.resume(throwing: CaptureError.sessionFailed)
                    return
                }

                let normalizedPoint = CGPoint(
                    x: min(max(point.y / max(frameSize.height, 1), 0), 1),
                    y: 1 - min(max(point.x / max(frameSize.width, 1), 0), 1)
                )

                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }

                    if device.isFocusPointOfInterestSupported {
                        device.focusPointOfInterest = normalizedPoint
                    }
                    if device.isExposurePointOfInterestSupported {
                        device.exposurePointOfInterest = normalizedPoint
                    }
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                    device.isSubjectAreaChangeMonitoringEnabled = false
                    log.debug("focusAndLock — x=\(normalizedPoint.x, format: .fixed(precision: 3)) y=\(normalizedPoint.y, format: .fixed(precision: 3))")
                    cont.resume()
                } catch {
                    log.error("focusAndLock — failed: \(error)")
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func unlockFocusAndExposure() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                guard let device = videoDeviceInput?.device else {
                    cont.resume()
                    return
                }

                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }

                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    device.isSubjectAreaChangeMonitoringEnabled = true
                    log.debug("unlockFocusAndExposure")
                } catch {
                    log.error("unlockFocusAndExposure — failed: \(error)")
                }
                cont.resume()
            }
        }
    }

    public func applyPreset(_ preset: VibePreset) async {
        // TODO v0.4: apply LUT / color space settings via AVCaptureDevice
    }

    public func availableModes() -> [CaptureMode] {
        CaptureMode.allCases
    }

    // MARK: - Private helpers

    private func configureSession(for mode: CaptureMode) throws {
        log.debug("configureSession — starting for mode=\(mode.rawValue)")
        session.beginConfiguration()
        defer { 
            session.commitConfiguration()
            log.debug("configureSession — committed")
        }

        //resetSessionStateOnQueue()

        session.sessionPreset = resolvedPreset(for: mode)

        // Video input (camera)
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            throw CaptureError.sessionFailed
        }
        session.addInput(input)
        videoDeviceInput = input

        // Output — photo or movie
        if isVideoMode(mode) {
            try addAudioInput()
            let output = AVCaptureMovieFileOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                movieOutput = output
            }
        } else {
            let output = AVCapturePhotoOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                photoOutput = output
                if output.isLivePhotoCaptureSupported {
                    output.isLivePhotoCaptureEnabled = true
                    log.debug("configureSession — Live Photo capture enabled")
                }
            }
        }
    }

    private func resetSessionStateOnQueue() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let videoInput = videoDeviceInput {
            session.removeInput(videoInput)
            videoDeviceInput = nil
        }
        if let audioInput = audioDeviceInput {
            session.removeInput(audioInput)
            audioDeviceInput = nil
        }
        if let photoOutput {
            session.removeOutput(photoOutput)
            self.photoOutput = nil
        }
        if let movieOutput {
            session.removeOutput(movieOutput)
            self.movieOutput = nil
        }
        isSessionConfigured = false
    }

    /// Adds the default audio (microphone) input if not already present.
    private func addAudioInput() throws {
        // Use stored reference instead of iterating session.inputs — session.inputs
        // may contain invalidated device inputs after stopRunning(), and calling
        // .device.hasMediaType() on them causes an ObjC exception / EXC_BREAKPOINT.
        guard audioDeviceInput == nil else { return }
        guard let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(input) else {
            log.warning("addAudioInput — could not add microphone input")
            return
        }
        session.addInput(input)
        audioDeviceInput = input
        log.debug("addAudioInput — microphone added")
    }

    private func isVideoMode(_ mode: CaptureMode) -> Bool {
        // Echo uses AVAudioRecorder independently of AVCaptureSession.
        // Keeping it in photo-output class avoids the AVAudioSession conflict that arises
        // when AVCaptureSession adds audio input and EchoRecordingSession tries to reconfigure
        // the same shared audio session.
        mode == .clip
    }

    private func resolvedPreset(for mode: CaptureMode) -> AVCaptureSession.Preset {
        let preset = isVideoMode(mode) ? videoPreset(for: mode) : .photo
        if session.canSetSessionPreset(preset) { return preset }

        if isVideoMode(mode) {
            for fallback in [AVCaptureSession.Preset.hd1920x1080, .high, .vga640x480] {
                if session.canSetSessionPreset(fallback) { return fallback }
            }
        }
        return .photo
    }

    private func videoPreset(for mode: CaptureMode) -> AVCaptureSession.Preset {
        switch mode {
        case .clip:
            switch UserDefaults.standard.string(forKey: "capture.clipVideoFormat") {
            case "vga": return .vga640x480
            case "4k": return .hd4K3840x2160
            case "hd": return .hd1920x1080
            default: return .hd1920x1080
            }
        case .atmosphere:
            return .high
        default: return .photo
        }
    }

    private func assetType(for mode: CaptureMode) -> AssetType {
        switch mode {
        case .still:      return .still
        case .live:       return .live
        case .clip:       return .clip
        case .echo:       return .echo
        case .atmosphere: return .atmosphere
        case .photoBooth: return .still   // individual booth shots are stills
        }
    }

    private func currentVideoRotationAngle(for orientation: UIDeviceOrientation) -> CGFloat? {
        switch orientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        default: return nil
        }
    }

    private func currentVideoOrientation(for orientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
    }
}

// MARK: - LocationProvider

/// Lightweight CLLocationManager wrapper that keeps the last known coordinate.
private final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private(set) var currentCoordinate: GPSCoordinate?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    func start() {
        let status = manager.authorizationStatus
        log.debug("LocationProvider.start — authorizationStatus=\(status.rawValue)")
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            log.warning("LocationProvider — location not authorized (status \(status.rawValue))")
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        log.debug("LocationProvider.stop")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        log.debug("LocationProvider — authorization changed: \(status.rawValue)")
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentCoordinate = GPSCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        log.debug("LocationProvider — lat=\(loc.coordinate.latitude, format: .fixed(precision: 5)) lon=\(loc.coordinate.longitude, format: .fixed(precision: 5)) acc=\(loc.horizontalAccuracy)m")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("LocationProvider — didFailWithError: \(error)")
    }
}

// MARK: - Photo capture delegate

/// Bridges AVCapturePhotoCaptureDelegate into a Swift continuation.
///
/// For Still captures: resumes the continuation in `didFinishProcessingPhoto`.
/// For Live Photo captures: stores the JPEG in `didFinishProcessingPhoto`, then resumes
/// in `didFinishCapture` (the final callback) so both the JPEG and the companion MOV
/// are fully written before the use-case pipeline continues.
private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data, Error>?
    /// True when a `livePhotoMovieFileURL` was set on the capture settings.
    private let isLiveCapture: Bool
    /// Stored between `didFinishProcessingPhoto` and `didFinishCapture` for Live captures.
    private var storedJpegData: Data?

    init(continuation: CheckedContinuation<Data, Error>, isLiveCapture: Bool = false) {
        self.continuation = continuation
        self.isLiveCapture = isLiveCapture
    }

    // Called when the still frame is ready.
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            log.error("PhotoDelegate — still frame error: \(error)")
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            log.error("PhotoDelegate — fileDataRepresentation() returned nil")
            continuation?.resume(throwing: CaptureError.captureFailed)
            continuation = nil
            return
        }
        log.debug("PhotoDelegate — still frame OK (\(data.count) bytes)")
        if isLiveCapture {
            // For Live Photo: hold JPEG until the companion MOV is also written.
            storedJpegData = data
        } else {
            continuation?.resume(returning: data)
            continuation = nil
        }
    }

    // Called when the Live Photo MOV companion file is fully written to disk.
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
        duration: CMTime,
        photoDisplayTime: CMTime,
        resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            log.error("PhotoDelegate — live MOV write error: \(error)")
            // Non-fatal: continue with JPEG-only; didFinishCapture will resume.
        } else {
            log.debug("PhotoDelegate — live MOV written: \(outputFileURL.lastPathComponent)")
        }
    }

    // Final callback — all processing complete. Resume for Live captures here.
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        guard isLiveCapture else { return }  // Still captures already resumed above.
        if let error {
            log.error("PhotoDelegate — didFinishCapture error: \(error)")
            continuation?.resume(throwing: error)
        } else if let data = storedJpegData {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: CaptureError.captureFailed)
        }
        continuation = nil
    }
}

// MARK: - Movie recording delegate

/// Bridges AVCaptureFileOutputRecordingDelegate into a Swift continuation.
/// Thread-safe: handles the race where didFinishRecordingTo fires before waitForCompletion.
private final class MovieDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let assetID: UUID
    private var startTime: Date = Date()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(UUID, TimeInterval), Error>?
    private var pendingResult: Result<(UUID, TimeInterval), Error>?

    init(assetID: UUID) {
        self.assetID = assetID
        super.init()
    }

    /// Suspends until recording is fully written to disk.
    func waitForCompletion() async throws -> (UUID, TimeInterval) {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            defer { lock.unlock() }
            if let result = pendingResult {
                pendingResult = nil
                switch result {
                case .success(let val): cont.resume(returning: val)
                case .failure(let err): cont.resume(throwing: err)
                }
            } else {
                continuation = cont
            }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        startTime = Date()
        log.debug("MovieDelegate — recording started → \(fileURL.lastPathComponent)")
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let duration = Date().timeIntervalSince(startTime)
        let result: Result<(UUID, TimeInterval), Error>
        if let error {
            log.error("MovieDelegate — recording failed: \(error)")
            result = .failure(error)
        } else {
            log.debug("MovieDelegate — recording done \(outputFileURL.lastPathComponent) duration=\(String(format: "%.1f", duration))s")
            result = .success((assetID, duration))
        }
        lock.lock()
        defer { lock.unlock() }
        if let cont = continuation {
            continuation = nil
            switch result {
            case .success(let val): cont.resume(returning: val)
            case .failure(let err): cont.resume(throwing: err)
            }
        } else {
            pendingResult = result
        }
    }
}

// MARK: - Echo audio recording

private final class EchoRecordingSession: @unchecked Sendable {
    let assetID: UUID
    let fileURL: URL

    private let recorder: AVAudioRecorder
    private let startTime = Date()

    init(assetID: UUID, fileURL: URL) throws {
        self.assetID = assetID
        self.fileURL = fileURL

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try audioSession.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
    }

    func start() throws {
        guard recorder.record() else {
            throw CaptureError.captureFailed
        }
        log.debug("EchoRecordingSession — recording started → \(self.fileURL.lastPathComponent)")
    }

    func stop() throws -> (UUID, TimeInterval) {
        recorder.stop()
        let duration = Date().timeIntervalSince(startTime)
        log.debug("EchoRecordingSession — stop called. id=\(self.assetID.uuidString) duration=\(duration)s path=\(self.fileURL.lastPathComponent)")
        return (assetID, duration)
    }

    func cancelAndDelete() {
        recorder.stop()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
