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

    // MARK: Session
    //
    // Typed as AVCaptureSession (superclass) so AppContainer.captureSession: AVCaptureSession
    // never needs to change. Initialized as AVCaptureMultiCamSession when:
    //   • config.features.contains(.dualCamera)
    //   • AVCaptureMultiCamSession.isMultiCamSupported (iPhone 13 Pro+)
    // Decision is final at init time — the session cannot be swapped after creation.
    // The user toggle (nifty.dualCameraEnabled) controls whether the secondary output
    // is wired up in configureDualCameraSession(for:), not which session class is used.

    /// Shared session. The UI layer attaches an AVCaptureVideoPreviewLayer to this.
    /// Piqd v0.4 — became `var` so we can swap session class between plain
    /// `AVCaptureSession` (for Still/Sequence/Clip — full 0.5×/1×/2× optical on triple)
    /// and `AVCaptureMultiCamSession` (only when entering Dual format). Swap is driven
    /// by `swapSessionClass(toMultiCam:)`.
    public private(set) var session: AVCaptureSession

    /// True when `session` is currently an `AVCaptureMultiCamSession`. Tracks the swap
    /// state — was a `let`, now mutates on Dual entry/exit (Piqd v0.4).
    private var isDualCamSession: Bool

    /// Retained so we can remove it cleanly without iterating session.inputs post-stopRunning.
    private var videoDeviceInput: AVCaptureDeviceInput?

    /// Read-only accessor used by the v0.4 `+Zoom` extension to reach the active
    /// video device without iterating session inputs. Internal-only.
    internal var activeVideoDevice: AVCaptureDevice? { videoDeviceInput?.device }

    /// Piqd v0.4 — picks the best available virtual back camera so the zoom pill can
    /// drive optical lens switching at 0.5× / 1× / 2× via `virtualDeviceSwitchOverVideoZoomFactors`.
    /// Falls back to the single wide-angle on devices/simulators without virtual hardware.
    /// Used only on non-Dual capture paths; Dual multicam topology continues to use the
    /// physical wide-angle on each side.
    fileprivate nonisolated static func bestVideoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Piqd v0.4 — initial input is always the physical wide-angle. Zoom-pill taps
        // swap the input device per lens (UW / W / Tele). iOS 26 no longer exposes UW
        // through virtual-device zoom factors, so virtual devices buy us nothing here.
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// Piqd v0.4 — diagnostic helper logged after each (re)configuration so device-test
    /// telemetry shows which physical device the zoom pill is actually driving.
    internal func logActiveZoomCapabilities(context: String) {
        guard let d = videoDeviceInput?.device else {
            log.debug("[zoom] \(context): no video device")
            return
        }
        let typeString = d.deviceType.rawValue
        let minF = Double(d.minAvailableVideoZoomFactor)
        let maxF = Double(d.maxAvailableVideoZoomFactor)
        let switchOversString = String(describing: d.virtualDeviceSwitchOverVideoZoomFactors)
        let zoomFactor = Double(d.videoZoomFactor)
        log.info("[zoom] \(context) device=\(typeString) min=\(minF) max=\(maxF) zoom=\(zoomFactor) switchOvers=\(switchOversString)")

        // Active format detail.
        let af = d.activeFormat
        let dims = CMVideoFormatDescriptionGetDimensions(af.formatDescription)
        let afSecondaryNative = String(describing: af.secondaryNativeResolutionZoomFactors)
        log.info("[zoom] \(context) activeFormat dims=\(dims.width)x\(dims.height) maxZoom=\(Double(af.videoMaxZoomFactor)) secondaryNativeZooms=\(afSecondaryNative)")

        // Enumerate ALL formats — flag any whose `secondary` array stringifies to
        // anything other than empty or "[4.0]". String-based filter avoids NSNumber
        // bridging crashes seen on iOS 26.
        let allFormats = d.formats
        log.info("[zoom] \(context) totalFormats=\(allFormats.count)")
        var interesting = 0
        for (idx, format) in allFormats.enumerated() {
            let secondaryStr = String(describing: format.secondaryNativeResolutionZoomFactors)
            // Boring patterns: empty, "[]", "[4.0]", "[4]"
            if secondaryStr == "()" || secondaryStr == "[]" || secondaryStr == "[4.0]"
                || secondaryStr == "[4]" || secondaryStr.isEmpty || secondaryStr == "(\n)"
                || secondaryStr == "(\n    4\n)" {
                continue
            }
            let fd = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            log.info("[zoom] \(context) ★ fmt[\(idx)] dims=\(fd.width)x\(fd.height) max=\(Double(format.videoMaxZoomFactor)) secondary=\(secondaryStr)")
            interesting += 1
        }
        log.info("[zoom] \(context) interestingFormatCount=\(interesting)")

        // Discovery: enumerate every back-position device the system knows about, and
        // for each list its `min`/`max` and switchOvers. Helps locate which virtual
        // device, if any, exposes 0.5× on this iOS 26 / iPhone 17 Pro combo.
        let allTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: allTypes, mediaType: .video, position: .back
        )
        log.info("[zoom] \(context) === back-camera discovery (\(discovery.devices.count) devices)")
        for dev in discovery.devices {
            let min = Double(dev.minAvailableVideoZoomFactor)
            let max = Double(dev.maxAvailableVideoZoomFactor)
            let so = String(describing: dev.virtualDeviceSwitchOverVideoZoomFactors)
            log.info("[zoom] \(context) · \(dev.deviceType.rawValue) min=\(min) max=\(max) switchOvers=\(so)")
        }
    }
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?

    // MARK: - Primary preview frame tap (Piqd v0.4)
    //
    // Optional `AVCaptureVideoDataOutput` attached to the standard (non-Dual) session so
    // pre-shutter assists like `SubjectGuidanceDetector` can read live preview frames.
    // The output is `alwaysDiscardsLateVideoFrames = true` and the consumer is expected
    // to throttle its own work (face detection runs at ≤ 2 fps); we don't lower the
    // device's frame rate. Skipped on `AVCaptureMultiCamSession` (Dual format) — Dual
    // already wires a secondary VideoDataOutput, and subject-guidance is Snap-only.
    private var primaryVideoDataOutput: AVCaptureVideoDataOutput?
    private lazy var primaryFrameDelegate = SecondaryFrameDelegate { [weak self] buffer in
        guard let self else { return }
        self.lockedSinkLock.lock()
        let sink = self.primaryFrameSink
        self.lockedSinkLock.unlock()
        sink?(buffer)
    }
    private let primaryFrameQ = DispatchQueue(
        label: "com.hwcho99.niftymomnt.primaryFrameQ",
        qos: .userInitiated
    )
    private let lockedSinkLock = NSLock()
    private var primaryFrameSink: ((CMSampleBuffer) -> Void)?

    /// Install (or clear with `nil`) a closure that receives every primary preview frame
    /// from the standard (non-Dual) session. Caller is expected to throttle. Replacing
    /// the sink is atomic; no frames are dropped between swaps. Has no effect under Dual.
    public func setPrimaryFrameSink(_ sink: ((CMSampleBuffer) -> Void)?) {
        lockedSinkLock.lock()
        primaryFrameSink = sink
        lockedSinkLock.unlock()
    }
    /// Secondary AVCaptureMovieFileOutput used only in Dual-video format. Non-nil ⇒
    /// `startRecording(mode:)` runs both outputs; `stopRecording()` awaits both.
    /// The MOV URL is stored in `secondaryMovieURL` so Stage B's compositor can pick it up.
    private var secondaryMovieOutput: AVCaptureMovieFileOutput?
    private var activeSecondaryMovieDelegate: MovieDelegate?
    /// Temp URL of the companion secondary stream from the most recent Dual recording.
    /// Consumed by Stage B's DualCompositor; cleared on the next Dual start.
    public private(set) var secondaryMovieURL: URL?
    /// Secondary AVCapturePhotoOutput used only in Dual-still format. Non-nil ⇒
    /// `captureAsset()` fans out to both photo outputs and composites the result.
    private var secondaryPhotoOutput: AVCapturePhotoOutput?
    private var activeSecondaryPhotoDelegate: PhotoDelegate?
    /// Layout used to compose Dual Still and Dual Video outputs. Set by `configure(for:layout:)`.
    private var dualLayout: DualLayout = .pip
    /// Weak ref to the view's primary preview layer. Under dual-video topology the session's
    /// inputs are added with `addInputWithNoConnections`, which breaks the layer's auto-wired
    /// preview connection — so we need to re-add an explicit connection after reconfiguring
    /// and restore auto-connect when we leave Dual.
    private weak var primaryPreviewLayer: AVCaptureVideoPreviewLayer?

    public func attachPrimaryPreview(_ layer: AVCaptureVideoPreviewLayer) {
        primaryPreviewLayer = layer
    }
    /// Retained so we can remove it cleanly without iterating session.inputs post-stopRunning.
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var isSessionConfigured = false
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentMode: CaptureMode = .still
    /// Prevents concurrent switchMode calls from stacking redundant reconfigures.
    private var isSwitchingMode = false
    /// Retained until the photo delegate callback fires.
    private var activePhotoDelegate: PhotoDelegate?
    /// Per-call strong refs for concurrent Sequence frame captures. Keyed by UUID per call so
    /// overlapping requests (Task-per-tick from `SequenceCaptureController`) don't stomp each
    /// other the way a single shared slot would. Cleared after the awaiting call resumes.
    private var inFlightFrameDelegates: [UUID: PhotoDelegate] = [:]
    /// Retained until the movie file is fully written.
    private var activeMovieDelegate: MovieDelegate?
    /// Retained while Echo is recording audio-only media.
    private var activeEchoRecording: EchoRecordingSession?

    // MARK: Dual-camera secondary stream
    //
    // The secondary camera (front / ultra-wide) frames are captured into
    // `latestSecondaryFrame` via AVCaptureVideoDataOutput.
    // They are NEVER persisted to disk — only held in memory for Lab VLM payloads.

    private var secondaryVideoInput: AVCaptureDeviceInput?
    private var secondaryVideoOutput: AVCaptureVideoDataOutput?
    private let secondaryFrameLock = NSLock()
    private var _latestSecondaryFrame: CMSampleBuffer?

    /// Secondary frame delegate (retains self via weak ref).
    private lazy var secondaryDelegate = SecondaryFrameDelegate { [weak self] buffer in
        guard let self else { return }
        self.secondaryFrameLock.lock()
        self._latestSecondaryFrame = buffer
        self.secondaryFrameLock.unlock()
        // Per-frame log is handled inside SecondaryFrameDelegate (throttled to ~1/s).
    }

    /// Returns the most recent secondary camera frame as JPEG-compressed Data,
    /// or `nil` when dual-cam is not active or no frame has been received yet.
    public func latestSecondaryFrameData() -> Data? {
        secondaryFrameLock.lock()
        let buffer = _latestSecondaryFrame
        secondaryFrameLock.unlock()

        guard let buffer,
              let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            log.debug("AVCaptureAdapter.latestSecondaryFrameData — no frame available")
            return nil
        }
        let w = CVPixelBufferGetWidth(imageBuffer)
        let h = CVPixelBufferGetHeight(imageBuffer)
        let secDeviceName = secondaryVideoInput?.device.localizedName ?? "unknown"
        let secPosition = secondaryVideoInput?.device.position == .front ? "front" : "back"
        log.info("AVCaptureAdapter.latestSecondaryFrameData — device='\(secDeviceName)' position=\(secPosition) pixelBuffer=\(w)×\(h)")
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let jpegData = context.jpegRepresentation(of: ciImage,
                                                        colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                        options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7]) else {
            log.warning("AVCaptureAdapter.latestSecondaryFrameData — JPEG compression failed")
            return nil
        }
        log.info("AVCaptureAdapter.latestSecondaryFrameData — JPEG \(jpegData.count) bytes (prefix: \(jpegData.prefix(4).map { String(format: "%02x", $0) }.joined()))")
        return jpegData
    }

    /// Whether to allocate an AVCaptureMultiCamSession at init time.
    ///
    /// Decision factors (both must be true):
    ///   1. `.dualCamera` feature flag is present in `config.features`
    ///   2. The device hardware supports multi-cam (`AVCaptureMultiCamSession.isMultiCamSupported`)
    ///
    /// The user toggle ("nifty.dualCameraEnabled") is intentionally NOT checked here.
    /// Session type is a `let` — it cannot change after init. Checking a UserDefaults default
    /// (which is `false` until the user explicitly toggles the switch) would permanently lock
    /// the device into a standard session. Instead, the toggle is checked in
    /// `configureDualCameraSession(for:)` to control whether the secondary output is wired up,
    /// while the session type remains correct from the start.
    private static func shouldUseDualCam(config: AppConfig) -> Bool {
        guard config.features.contains(.dualCamera) else {
            log.info("dualCamCapability — DISABLED (feature flag .dualCamera not in config)")
            return false
        }
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            log.info("dualCamCapability — DISABLED (isMultiCamSupported=false — iPhone 13 Pro+ required)")
            return false
        }
        // Piqd v0.4 — capability check only. The session class is plain AVCaptureSession
        // by default; MultiCam is created lazily on Dual entry via `swapSessionClass`.
        log.info("dualCamCapability — ENABLED (feature flag ✓ + hardware multicam ✓); session class will swap on Dual entry")
        return true
    }

    /// Provides GPS coordinate at capture time.
    private let locationProvider = LocationProvider()

    public init(config: AppConfig) {
        self.config = config
        // Piqd v0.4 — always init with plain AVCaptureSession so non-Dual formats get
        // full optical 0.5×/1×/2× on triple-camera devices (MultiCam constraints drop
        // ultra-wide on triple in multicam topology). Session class swaps to MultiCam
        // lazily on Dual entry via `swapSessionClass(toMultiCam:)`.
        self.session = AVCaptureSession()
        self.isDualCamSession = false
        let dualCapable = Self.shouldUseDualCam(config: config)
        log.info("AVCaptureAdapter — initialized with AVCaptureSession (dualCapable=\(dualCapable); MultiCam class spawned only on Dual entry)")
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

        // §2 — Log session type clearly so checklist can be verified without a breakpoint.
        let sessionClass = isDualCamSession ? "AVCaptureMultiCamSession" : "AVCaptureSession"

        // Request camera access if not yet determined — first launch shows the system prompt.
        let initialStatus = AVCaptureDevice.authorizationStatus(for: .video)
        log.info("startSession — sessionType=\(sessionClass) mode=\(mode.rawValue) authStatus=\(initialStatus.rawValue)")
        if initialStatus == .notDetermined {
            log.info("startSession — authStatus=notDetermined; requesting camera access")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            log.info("startSession — camera access request result: \(granted ? "granted ✓" : "denied ✗")")
            if !granted {
                await MainActor.run { stateSubject.send(.error(.unauthorized)) }
                throw CaptureError.unauthorized
            }
        } else {
            guard initialStatus == .authorized else {
                log.error("startSession denied — camera not authorized (status \(initialStatus.rawValue))")
                await MainActor.run { stateSubject.send(.error(.unauthorized)) }
                throw CaptureError.unauthorized
            }
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

        // ── §2 Dual-camera status at capture time ─────────────────────────────
        // This block runs on every still/live capture so §2 of the verification
        // checklist can be confirmed directly from the console without a breakpoint.
        let sessionClass = isDualCamSession ? "AVCaptureMultiCamSession" : "AVCaptureSession"
        let secondaryWired = secondaryVideoOutput != nil
        log.info("captureAsset — sessionType=\(sessionClass) isDualCam=\(self.isDualCamSession) secondaryOutputWired=\(secondaryWired)")
        if isDualCamSession {
            let secondaryInput = secondaryVideoInput?.device.localizedName ?? "none (toggle off or unsupported)"
            log.info("captureAsset — secondary input=\(secondaryInput)")
            let hasFrame = secondaryFrameLock.withLock { _latestSecondaryFrame != nil }
            log.info("captureAsset — secondary frame buffer: \(hasFrame ? "HAS FRAME ✓" : "EMPTY — no frame yet (normal on first capture or toggle off)")")
        }
        // ─────────────────────────────────────────────────────────────────────

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

        // Dual Still: issue both capturePhoto calls before awaiting either continuation
        // so both ISPs start in parallel. Each Task { @MainActor in ... } runs sync
        // through its capturePhoto trigger, suspends on the continuation, then yields
        // the main actor for the next Task to issue its own capturePhoto.
        let isDualStill = (secondaryPhotoOutput != nil)
        let secOut = secondaryPhotoOutput

        let primaryTask: Task<Data, Error> = Task { @MainActor in
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
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
        }

        let secondaryTask: Task<Data, Error>? = secOut.map { secondaryOutput in
            Task { @MainActor in
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    let delegate = PhotoDelegate(continuation: cont, isLiveCapture: false)
                    activeSecondaryPhotoDelegate = delegate
                    let settings = AVCapturePhotoSettings()
                    settings.flashMode = .off
                    secondaryOutput.capturePhoto(with: settings, delegate: delegate)
                }
            }
        }

        let primaryData = try await primaryTask.value
        activePhotoDelegate = nil
        let secondaryData: Data? = try await secondaryTask?.value
        activeSecondaryPhotoDelegate = nil

        let jpegData: Data
        if isDualStill, let secondaryData {
            log.info("captureAsset — dual still: compositing primary=\(primaryData.count)B + secondary=\(secondaryData.count)B layout=\(self.dualLayout.rawValue)")
            let compositor = DualStillCompositor(layout: self.dualLayout)
            do {
                jpegData = try compositor.composite(primaryData: primaryData, secondaryData: secondaryData)
            } catch {
                log.error("captureAsset — dual still composite failed: \(error.localizedDescription); falling back to primary")
                jpegData = primaryData
            }
        } else {
            jpegData = primaryData
        }
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

        // §2 — Confirm secondary frame readiness at capture time.
        // CaptureMomentUseCase fetches this via latestSecondaryFrameData() to supplement vibe classification.
        if isDualCamSession {
            let secBytes = secondaryFrameLock.withLock { _latestSecondaryFrame.map { CMSampleBufferGetTotalSampleSize($0) } }
            if let bytes = secBytes {
                log.info("captureAsset — secondary frame ready (\(bytes) bytes raw) — available for vibe classification + Lab VLM")
            } else {
                log.warning("captureAsset — secondary frame still empty (secondary camera may not have started streaming yet)")
            }
        }

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

        // Dual-video: drive the secondary movie output in parallel. Both outputs share
        // `assetID` conceptually (the primary delegate's ID is used as the vault asset
        // ID; the secondary MOV is stashed in `secondaryMovieURL` for Stage B compositing).
        if let secOut = secondaryMovieOutput {
            let secURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dual-sec-\(assetID.uuidString)")
                .appendingPathExtension("mov")
            let secDelegate = MovieDelegate(assetID: assetID)
            activeSecondaryMovieDelegate = secDelegate
            secondaryMovieURL = secURL
            log.debug("startRecording — dual secondary tempURL=\(secURL.lastPathComponent)")
            secOut.startRecording(to: secURL, recordingDelegate: secDelegate)
        }

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
        if let secOut = secondaryMovieOutput, secOut.isRecording {
            log.debug("stopRecording — stopping secondary movie output")
            secOut.stopRecording()
        }
        // Wait for the primary file delegate to confirm the file is fully written.
        let (assetID, duration) = try await delegate.waitForCompletion()
        activeMovieDelegate = nil
        // Drain the secondary delegate so the companion MOV is flushed before Stage B
        // compositing; failures here are non-fatal for Stage A (we still return the primary).
        if let secDelegate = activeSecondaryMovieDelegate {
            do {
                _ = try await secDelegate.waitForCompletion()
                log.debug("stopRecording — secondary MOV flushed")
            } catch {
                log.warning("stopRecording — secondary MOV finalize failed: \(error.localizedDescription)")
                secondaryMovieURL = nil
            }
            activeSecondaryMovieDelegate = nil
        }
        let isDualCapture = secondaryMovieOutput != nil
        log.debug("stopRecording — done id=\(assetID.uuidString) duration=\(String(format: "%.1f", duration))s dual=\(isDualCapture)")

        let gps = locationProvider.currentCoordinate
        var finalDuration = duration

        // Dual-video: composite the two MOVs into a single PIP MP4 at the path the
        // CaptureMomentUseCase expects (`tmpdir/{assetID}.mov`). On success the primary
        // file is overwritten by the composite; on failure we keep the primary rear-only
        // so the clip is never lost.
        if isDualCapture, let secURL = secondaryMovieURL {
            let primaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(assetID.uuidString)
                .appendingPathExtension("mov")
            let compositeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dual-out-\(assetID.uuidString)")
                .appendingPathExtension("mov")
            let compositor = DualCompositor(layout: self.dualLayout)
            do {
                let outDuration = try await compositor.composite(primaryURL: primaryURL,
                                                                 secondaryURL: secURL,
                                                                 outputURL: compositeURL)
                try? FileManager.default.removeItem(at: primaryURL)
                try FileManager.default.moveItem(at: compositeURL, to: primaryURL)
                try? FileManager.default.removeItem(at: secURL)
                finalDuration = CMTimeGetSeconds(outDuration)
                log.info("stopRecording — dual composite ready at \(primaryURL.lastPathComponent) duration=\(String(format: "%.2f", finalDuration))s")
            } catch {
                log.error("stopRecording — dual composite failed: \(error.localizedDescription); keeping primary rear-only MOV")
                try? FileManager.default.removeItem(at: compositeURL)
            }
            secondaryMovieURL = nil
        }

        let type: AssetType = isDualCapture ? .dual : assetType(for: currentMode)
        stateSubject.send(.processing)
        return Asset(id: assetID, type: type, capturedAt: Date(), location: gps, duration: finalDuration)
    }

    // MARK: - Mode / Camera Switch

    public func reconfigureSession(to mode: CaptureMode, gestureTime: Double) async throws {
        // Leaving Dual (still or video): rebuild the session from scratch rather than
        // mutating the multi-cam topology. Full teardown is simpler and reliable given
        // the explicit connection wiring in the dual configs.
        if secondaryMovieOutput != nil || secondaryPhotoOutput != nil || secondaryVideoInput != nil {
            log.info("switchMode — leaving Dual; full teardown before reconfigure to \(mode.rawValue)")
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                sessionQueue.async { [self] in
                    session.beginConfiguration()
                    for out in session.outputs { session.removeOutput(out) }
                    for inp in session.inputs { session.removeInput(inp) }
                    for conn in session.connections { session.removeConnection(conn) }
                    photoOutput = nil
                    movieOutput = nil
                    secondaryVideoOutput = nil
                    secondaryMovieOutput = nil
                    secondaryPhotoOutput = nil
                    primaryVideoDataOutput = nil
                    videoDeviceInput = nil
                    secondaryVideoInput = nil
                    audioDeviceInput = nil
                    isSessionConfigured = false
                    session.commitConfiguration()
                    do {
                        try configureSession(for: mode)
                        isSessionConfigured = true
                        currentMode = mode
                        // Restore standard preview auto-connect now that the session is
                        // back on single-camera topology.
                        if let layer = primaryPreviewLayer {
                            DispatchQueue.main.sync {
                                layer.session = nil
                                layer.session = session
                            }
                        }
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            stateSubject.send(.ready(mode: mode))
            return
        }
        // Piqd v0.4 — `isSessionConfigured == false` means a fresh session (typically
        // post-`swapSessionClass`); we MUST run the reconfigure path even if `mode`
        // matches the previously-configured mode.
        if isSessionConfigured {
            guard mode != currentMode else { return }
        }
        log.debug("switchMode \(self.currentMode.rawValue) → \(mode.rawValue) (isSessionConfigured=\(self.isSessionConfigured))")

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
                    // AVCaptureMultiCamSession forbids sessionPreset — skip entirely.
                    // Format is controlled per-device via activeFormat, not a session-level preset.
                    if !isDualCamSession {
                        session.sessionPreset = wasVideoMode ? .photo : resolvedPreset(for: mode)
                    }
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
                    // Same class — preset-only update (skipped for AVCaptureMultiCamSession
                    // which forbids all sessionPreset assignments).
                    let tBegin = CACurrentMediaTime()
                    session.beginConfiguration()
                    if !isDualCamSession {
                        session.sessionPreset = resolvedPreset(for: mode)
                    }
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
                    let device = AVCaptureAdapter.bestVideoDevice(position: newPosition),
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
        // Dual-camera path: only for still/live photo modes on supported hardware.
        if isDualCamSession && !isVideoMode(mode) {
            log.debug("configureSession — dual-camera path for mode=\(mode.rawValue)")
            try configureDualCameraSession(for: mode)
            return
        }

        log.debug("configureSession — standard path for mode=\(mode.rawValue)")
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
            log.debug("configureSession — committed")
        }

        // AVCaptureMultiCamSession rejects all sessionPreset assignments.
        // For video modes on a dual-cam session the standard path is used (no dual-cam
        // video config path exists yet), so skip the preset silently.
        if !isDualCamSession {
            session.sessionPreset = resolvedPreset(for: mode)
        }

        // Video input (camera) — uses best available virtual device on back so the zoom
        // pill can drive optical lens switching (Piqd v0.4). Falls back to wide-angle.
        guard
            let device = AVCaptureAdapter.bestVideoDevice(position: currentPosition),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            log.error("configureSession — could not add primary video input")
            throw CaptureError.sessionFailed
        }
        session.addInput(input)
        videoDeviceInput = input
        log.debug("configureSession — primary input added: \(input.device.localizedName)")
        logActiveZoomCapabilities(context: "configureSession.\(mode.rawValue)")

        // Output — photo or movie
        if isVideoMode(mode) {
            try addAudioInput()
            let output = AVCaptureMovieFileOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                movieOutput = output
                log.debug("configureSession — AVCaptureMovieFileOutput added")
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
                log.debug("configureSession — AVCapturePhotoOutput added")
            }
        }

        // Piqd v0.4 — primary preview frame tap for pre-shutter assists (subject guidance,
        // backlight detection, etc.). Skipped on MultiCam (Dual) — see field doc.
        if !isDualCamSession {
            let videoOut = AVCaptureVideoDataOutput()
            videoOut.alwaysDiscardsLateVideoFrames = true
            videoOut.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if session.canAddOutput(videoOut) {
                session.addOutput(videoOut)
                videoOut.setSampleBufferDelegate(primaryFrameDelegate, queue: primaryFrameQ)
                primaryVideoDataOutput = videoOut
                log.debug("configureSession — primary AVCaptureVideoDataOutput added (frame-tap)")
            } else {
                log.warning("configureSession — canAddOutput(primary VideoDataOutput) false; skipping frame-tap")
            }
        }
    }

    /// Configures an `AVCaptureMultiCamSession` with:
    ///   • Primary back-wide camera → `AVCapturePhotoOutput`  (saved normally)
    ///   • Secondary front / ultra-wide camera → `AVCaptureVideoDataOutput` (frames only, never persisted)
    ///
    /// Called only when `isDualCamSession == true` and mode is a photo class (still / live).
    private func configureDualCameraSession(for mode: CaptureMode) throws {
        guard let multiSession = session as? AVCaptureMultiCamSession else {
            log.error("configureDualCameraSession — session is not AVCaptureMultiCamSession; falling through to standard")
            try configureSession(for: mode)   // safe fallback
            return
        }

        // Check user toggle here (not at init time).
        // @AppStorage default values never write to UserDefaults, so the key starts as false
        // until the user explicitly flips the switch. We default to true here so that the
        // secondary output is wired unless the user has explicitly turned it off.
        let rawToggle = UserDefaults.standard.object(forKey: "nifty.dualCameraEnabled")
        let toggleEnabled = rawToggle == nil ? true : UserDefaults.standard.bool(forKey: "nifty.dualCameraEnabled")
        log.info("configureDualCameraSession — user toggle nifty.dualCameraEnabled=\(toggleEnabled) (rawStored=\(rawToggle != nil ? "set" : "nil→defaultTrue"))")

        log.debug("configureDualCameraSession — beginning configuration for mode=\(mode.rawValue)")
        multiSession.beginConfiguration()
        defer {
            multiSession.commitConfiguration()
            log.debug("configureDualCameraSession — configuration committed")
        }

        // ── Primary: back virtual device → AVCapturePhotoOutput ──────────────
        // Piqd v0.4 — Dual format uses physical wide-angle on the back. Virtual devices
        // in the multicam topology have heavy format constraints; wide-angle is the most
        // compatible and the zoom pill is hidden in Dual anyway, so optical lens switching
        // isn't needed here. (Non-Dual formats run on a plain `AVCaptureSession` and pick
        // up the full virtual triple/dual-wide for 0.5×/1×/2× — see `swapSessionClass`.)
        let candidateTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera
        ]
        var resolvedDevice: AVCaptureDevice?
        var resolvedInput: AVCaptureDeviceInput?
        for type in candidateTypes {
            guard let d = AVCaptureDevice.default(type, for: .video, position: .back),
                  let i = try? AVCaptureDeviceInput(device: d),
                  multiSession.canAddInput(i) else { continue }
            resolvedDevice = d
            resolvedInput = i
            log.debug("configureDualCameraSession — primary candidate accepted: \(String(describing: type))")
            break
        }
        guard let primaryDevice = resolvedDevice, let primaryInput = resolvedInput else {
            log.error("configureDualCameraSession — could not create primary back input")
            throw CaptureError.sessionFailed
        }
        multiSession.addInput(primaryInput)
        videoDeviceInput = primaryInput
        log.debug("configureDualCameraSession — primary input: \(primaryDevice.localizedName)")
        logActiveZoomCapabilities(context: "configureDualCameraSession.\(mode.rawValue)")

        let photoOut = AVCapturePhotoOutput()
        guard multiSession.canAddOutput(photoOut) else {
            log.error("configureDualCameraSession — canAddOutput(AVCapturePhotoOutput) false")
            throw CaptureError.sessionFailed
        }
        multiSession.addOutput(photoOut)
        photoOutput = photoOut
        if photoOut.isLivePhotoCaptureSupported {
            photoOut.isLivePhotoCaptureEnabled = true
            log.debug("configureDualCameraSession — Live Photo enabled on primary output")
        }
        log.debug("configureDualCameraSession — primary AVCapturePhotoOutput added")

        // ── Secondary: front / ultra-wide → AVCaptureVideoDataOutput ─────────
        // Priority: front TrueDepth → ultra-wide back → front wide
        // Frames captured for Lab VLM payload only; never written to disk.
        // Gated on user toggle — but session is already AVCaptureMultiCamSession regardless.

        guard toggleEnabled else {
            log.info("configureDualCameraSession — secondary output SKIPPED (user toggled off); primary-only dual-cam session active")
            return
        }

        let secondaryDevice: AVCaptureDevice? = {
            if let d = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) { return d }
            if let d = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) { return d }
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }()

        guard
            let secDev = secondaryDevice,
            let secInput = try? AVCaptureDeviceInput(device: secDev),
            multiSession.canAddInput(secInput)
        else {
            // Non-fatal: primary still works without secondary.
            log.warning("configureDualCameraSession — could not add secondary input; continuing with primary-only")
            return
        }
        multiSession.addInput(secInput)
        secondaryVideoInput = secInput
        log.debug("configureDualCameraSession — secondary input: \(secDev.localizedName)")

        let videoOut = AVCaptureVideoDataOutput()
        // Reduce memory pressure: discard frames that arrive while processing is ongoing.
        videoOut.alwaysDiscardsLateVideoFrames = true
        // BGRA pixel format is friendliest for CIImage → JPEG conversion.
        videoOut.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard multiSession.canAddOutput(videoOut) else {
            log.warning("configureDualCameraSession — canAddOutput(secondary VideoDataOutput) false; skipping")
            return
        }
        // Dispatch secondary frame callbacks on a low-priority background queue so they
        // never compete with the sessionQueue or the main thread.
        let secondaryQ = DispatchQueue(label: "com.hwcho99.niftymomnt.secondaryCamQ", qos: .utility)
        videoOut.setSampleBufferDelegate(secondaryDelegate, queue: secondaryQ)
        multiSession.addOutput(videoOut)
        secondaryVideoOutput = videoOut
        log.info("configureDualCameraSession — secondary AVCaptureVideoDataOutput ADDED (frames → latestSecondaryFrame)")
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
        if let primaryVideoDataOutput {
            session.removeOutput(primaryVideoDataOutput)
            self.primaryVideoDataOutput = nil
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
        case .snap:       return .still   // Piqd v0.1 — Snap Still default; format selector lands in v0.3
        case .roll:       return .still   // Piqd Roll Mode — stills primary
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

// MARK: - SecondaryFrameDelegate

/// Captures `CMSampleBuffer` frames from the secondary camera stream and forwards them
/// to the provided closure. Declared `@unchecked Sendable` because CMSampleBuffer
/// itself is not `Sendable`; access is serialized through `secondaryFrameLock` in the adapter.
private final class SecondaryFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onFrame: (CMSampleBuffer) -> Void

    /// Incremented on `secondaryQ` (serial) so no lock needed.
    private var frameCount = 0
    private var dropCount  = 0

    init(onFrame: @escaping (CMSampleBuffer) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1
        onFrame(sampleBuffer)
        // Log once per ~30 frames (~1 s at 30 fps) so the console isn't flooded.
        // Use frameCount == 1 for the very first frame so it appears immediately.
        if frameCount == 1 || frameCount % 30 == 0 {
            log.debug("AVCaptureAdapter — secondary stream active: frame=\(self.frameCount) (\(CMSampleBufferGetTotalSampleSize(sampleBuffer)) bytes/frame)")
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        dropCount += 1
        // Only log drops every 30 to keep noise low.
        if dropCount % 30 == 1 {
            log.debug("SecondaryFrameDelegate — frame(s) dropped (alwaysDiscardsLateVideoFrames) total=\(self.dropCount)")
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

// MARK: - Piqd v0.3 — CaptureFormat configuration

/// Piqd v0.3 entry point for the Snap-Mode format selector. Maps the format to the
/// existing CaptureMode output-class plumbing + single-commit session reconfiguration.
/// Exposed as an extension to keep the v0.3 delta surgical.
///
/// Mapping (per plan row 11 / U11):
///   • `.still`    → photo output (`.still` CaptureMode)         — photoOutput retained.
///   • `.sequence` → photo output (`.still` CaptureMode)         — photoOutput retained;
///                    cadence is driven by `SequenceCaptureController` above, not by the
///                    adapter.
///   • `.clip`     → movie output (`.clip` CaptureMode)          — swaps photoOutput →
///                    AVCaptureMovieFileOutput + audio input.
///   • `.dual`     → requires `AVCaptureMultiCamSession` + two movie outputs; wiring of
///                    the two movie outputs lives in a dedicated `DualMovieRecorder`
///                    adapter (Wave 2b). Here we only validate hardware support + route
///                    the session to the dual-cam path.
public extension AVCaptureAdapter {

    enum FormatConfigureError: Error {
        /// `.dual` was requested but the active session is not an AVCaptureMultiCamSession
        /// (device lacks MultiCam support, or AppConfig.features omitted `.dualCamera`).
        case dualCamUnavailable
    }

    /// True iff `.dual` is a legal selection on this device + this adapter's config.
    /// UI should read this to disable/hide the Dual segment; `CaptureActivityStore`
    /// mirrors it for XCUITests (UI11). Piqd v0.4 — checks hardware capability + feature
    /// flag rather than current session class (which may be plain right now and swap to
    /// MultiCam lazily on Dual entry).
    var isDualFormatSupported: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
            && config.features.contains(.dualCamera)
    }

    /// Reconfigure the capture session for the given Snap-Mode format. Single-commit via
    /// the existing `reconfigureSession(to:gestureTime:)` path.
    /// `dualKind` and `dualLayout` are only consulted when `format == .dual`; ignored otherwise.
    func configure(for format: CaptureFormat,
                   dualKind: DualMediaKind = .video,
                   dualLayout: DualLayout = .pip,
                   gestureTime: Double = CACurrentMediaTime()) async throws {
        // Piqd v0.4 — swap session class to plain AVCaptureSession for non-Dual formats
        // (so triple-camera devices expose full 0.5×/1×/2× optical) and to MultiCam only
        // when entering Dual. Idempotent: returns false when already in the right class.
        let didSwap = await swapSessionClass(toMultiCam: format == .dual)

        // After a swap, the new session is empty — go through the FULL build path
        // instead of the surgical reconfigure path which assumes existing inputs.
        if didSwap && format != .dual {
            let targetMode: CaptureMode = (format == .clip) ? .clip : .still
            try await rebuildPlainSession(for: targetMode)
            return
        }

        switch format {
        case .still, .sequence:
            try await reconfigureSession(to: .still, gestureTime: gestureTime)

        case .clip:
            try await reconfigureSession(to: .clip, gestureTime: gestureTime)

        case .dual:
            guard isDualFormatSupported else {
                throw FormatConfigureError.dualCamUnavailable
            }
            self.dualLayout = dualLayout
            switch dualKind {
            case .video:
                try await configureDualVideoSession(gestureTime: gestureTime)
            case .still:
                try await configureDualStillSession(gestureTime: gestureTime)
            }
            // Piqd v0.4 — after a session-class swap, the freshly-created MultiCam
            // session needs an explicit startRunning. The dual configure methods only
            // do begin/commitConfiguration and historically relied on the pre-existing
            // session already being running.
            if didSwap {
                await ensureRunning(forMode: .clip)
            }
        }
    }

    /// Piqd v0.4 — swap the back primary video input to a different physical lens
    /// (`.builtInUltraWideCamera` / `.builtInWideAngleCamera` / `.builtInTelephotoCamera`).
    /// Used by the zoom pill to deliver 0.5×/1×/2× as actual lens swaps. iOS 26 no longer
    /// auto-exposes UW via virtual-device zoom factors — manual input swap is required.
    /// ~150ms per swap (begin/commit + format negotiation).
    func swapBackInput(to newDevice: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    session.beginConfiguration()
                    if let oldInput = videoDeviceInput {
                        session.removeInput(oldInput)
                    }
                    let newInput = try AVCaptureDeviceInput(device: newDevice)
                    guard session.canAddInput(newInput) else {
                        // Restore old input on failure.
                        if let oldInput = videoDeviceInput, session.canAddInput(oldInput) {
                            session.addInput(oldInput)
                        }
                        session.commitConfiguration()
                        cont.resume(throwing: CaptureError.sessionFailed)
                        return
                    }
                    session.addInput(newInput)
                    self.videoDeviceInput = newInput
                    self.currentPosition = newDevice.position
                    session.commitConfiguration()
                    log.info("swapBackInput — \(newDevice.localizedName) (\(newDevice.deviceType.rawValue))")
                    cont.resume()
                } catch {
                    log.error("swapBackInput — failed: \(error.localizedDescription)")
                    session.commitConfiguration()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Piqd v0.4 — start the current session if not already running. Used after a session
    /// swap to MultiCam since `configureDualVideoSession`/`configureDualStillSession` only
    /// reconfigure topology, not lifecycle.
    fileprivate func ensureRunning(forMode mode: CaptureMode) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                if !self.session.isRunning {
                    self.session.startRunning()
                    log.info("ensureRunning — startRunning called; running=\(self.session.isRunning)")
                }
                cont.resume()
            }
        }
        await MainActor.run { stateSubject.send(.ready(mode: mode)) }
    }

    /// Piqd v0.4 — replace the current session with one of the right class. Runs on the
    /// session queue. Tears down all input/output references on the old session and
    /// re-attaches the preview layer to the new one. Returns true if a swap actually
    /// happened (caller may need to fully rebuild rather than surgically reconfigure).
    /// Idempotent — returns false when the session is already in the requested class.
    @discardableResult
    func swapSessionClass(toMultiCam needsMultiCam: Bool) async -> Bool {
        guard needsMultiCam != isDualCamSession else { return false }
        let dualCapable = Self.shouldUseDualCam(config: config)
        if needsMultiCam && !dualCapable {
            log.warning("swapSessionClass — requested MultiCam but device/config doesn't support it; staying on plain session")
            return false
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sessionQueue.async { [self] in
                let wasRunning = session.isRunning
                if wasRunning {
                    log.info("swapSessionClass — stopping current session before swap (was running)")
                    session.stopRunning()
                }
                // Drop input/output refs — the old session is about to be discarded.
                session.beginConfiguration()
                for out in session.outputs { session.removeOutput(out) }
                for inp in session.inputs { session.removeInput(inp) }
                for conn in session.connections { session.removeConnection(conn) }
                session.commitConfiguration()
                videoDeviceInput = nil
                audioDeviceInput = nil
                photoOutput = nil
                movieOutput = nil
                secondaryVideoInput = nil
                secondaryVideoOutput = nil
                secondaryMovieOutput = nil
                secondaryPhotoOutput = nil
                primaryVideoDataOutput = nil
                isSessionConfigured = false

                let newSession: AVCaptureSession = needsMultiCam
                    ? AVCaptureMultiCamSession()
                    : AVCaptureSession()
                self.session = newSession
                self.isDualCamSession = needsMultiCam
                log.info("swapSessionClass — created new \(needsMultiCam ? "AVCaptureMultiCamSession" : "AVCaptureSession")")

                // Re-attach preview layer to the new session on main. Under MultiCam the
                // explicit preview connection is wired inside `configureDualVideoSession`;
                // under plain we use auto-connect via `layer.session = newSession`.
                if let layer = primaryPreviewLayer {
                    DispatchQueue.main.sync {
                        layer.session = nil
                        if needsMultiCam {
                            layer.setSessionWithNoConnection(newSession)
                        } else {
                            layer.session = newSession
                        }
                    }
                }
                cont.resume(returning: true)
            }
        }
    }

    /// Piqd v0.4 — full rebuild of a freshly-swapped plain `AVCaptureSession`. Mirrors the
    /// configure path used by `startSession` (configureSession + startRunning) without
    /// the auth/location work that already ran at app launch. Used after `swapSessionClass`
    /// returns true and the target format is non-Dual.
    fileprivate func rebuildPlainSession(for mode: CaptureMode) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    try configureSession(for: mode)
                    self.isSessionConfigured = true
                    self.currentMode = mode
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    log.info("rebuildPlainSession — session running for mode=\(mode.rawValue) inputs=\(self.session.inputs.count) outputs=\(self.session.outputs.count)")
                    cont.resume()
                } catch {
                    log.error("rebuildPlainSession — failed: \(error.localizedDescription)")
                    cont.resume(throwing: error)
                }
            }
        }
        await MainActor.run { stateSubject.send(.ready(mode: mode)) }
    }

    /// Updates the layout used by the next Dual capture without reconfiguring the session.
    /// Safe to call any time; takes effect on the next `captureAsset()` / `stopRecording()`.
    func setDualLayout(_ layout: DualLayout) {
        self.dualLayout = layout
    }

    /// Reconfigures the shared AVCaptureMultiCamSession with two AVCaptureMovieFileOutputs
    /// (primary back-wide + secondary front/ultrawide) plus an audio connection on the primary
    /// output. Explicit input/output connection wiring is required for multi-cam — auto-connect
    /// would ambiguously route both camera streams to the same output.
    private func configureDualVideoSession(gestureTime: Double) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                guard let multi = session as? AVCaptureMultiCamSession else {
                    cont.resume(throwing: CaptureError.sessionFailed)
                    return
                }
                let tBegin = CACurrentMediaTime()
                multi.beginConfiguration()

                // Tear down everything — safest path from any prior photo/clip config.
                for out in multi.outputs { multi.removeOutput(out) }
                for inp in multi.inputs { multi.removeInput(inp) }
                for conn in multi.connections { multi.removeConnection(conn) }
                photoOutput = nil
                movieOutput = nil
                secondaryVideoOutput = nil
                secondaryMovieOutput = nil
                videoDeviceInput = nil
                secondaryVideoInput = nil
                audioDeviceInput = nil

                do {
                    // Primary back-wide input
                    guard let primDev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        throw CaptureError.sessionFailed
                    }
                    let primIn = try AVCaptureDeviceInput(device: primDev)
                    guard multi.canAddInput(primIn) else { throw CaptureError.sessionFailed }
                    multi.addInputWithNoConnections(primIn)
                    videoDeviceInput = primIn

                    // Secondary input — front TrueDepth preferred, then front wide, then ultrawide back.
                    let secDev: AVCaptureDevice? = {
                        if let d = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) { return d }
                        if let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) { return d }
                        return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                    }()
                    guard let secondary = secDev else { throw CaptureError.sessionFailed }
                    let secIn = try AVCaptureDeviceInput(device: secondary)
                    guard multi.canAddInput(secIn) else { throw CaptureError.sessionFailed }
                    multi.addInputWithNoConnections(secIn)
                    secondaryVideoInput = secIn

                    // Audio (primary only).
                    if let mic = AVCaptureDevice.default(for: .audio) {
                        let audIn = try AVCaptureDeviceInput(device: mic)
                        if multi.canAddInput(audIn) {
                            multi.addInputWithNoConnections(audIn)
                            audioDeviceInput = audIn
                        }
                    }

                    // Primary movie output
                    let primOut = AVCaptureMovieFileOutput()
                    guard multi.canAddOutput(primOut) else { throw CaptureError.sessionFailed }
                    multi.addOutputWithNoConnections(primOut)
                    movieOutput = primOut

                    guard let primPort = primIn.ports(for: .video,
                                                      sourceDeviceType: primDev.deviceType,
                                                      sourceDevicePosition: primDev.position).first else {
                        throw CaptureError.sessionFailed
                    }
                    let primVidConn = AVCaptureConnection(inputPorts: [primPort], output: primOut)
                    guard multi.canAddConnection(primVidConn) else { throw CaptureError.sessionFailed }
                    multi.addConnection(primVidConn)

                    // Preview connection from the primary port → registered preview layer.
                    // Required because addInputWithNoConnections doesn't auto-wire preview.
                    if let layer = primaryPreviewLayer {
                        // Detach any auto-connection the layer may still hold from prior
                        // standard-topology sessions, then re-attach in no-connection mode.
                        DispatchQueue.main.sync {
                            layer.session = nil
                            layer.setSessionWithNoConnection(multi)
                        }
                        let previewConn = AVCaptureConnection(inputPort: primPort, videoPreviewLayer: layer)
                        if multi.canAddConnection(previewConn) {
                            multi.addConnection(previewConn)
                            if #available(iOS 17.0, *),
                               previewConn.isVideoRotationAngleSupported(90) {
                                previewConn.videoRotationAngle = 90
                            }
                            log.info("configureDualVideoSession — preview connection added")
                        } else {
                            log.warning("configureDualVideoSession — canAddConnection(preview) false")
                        }
                    }

                    if let audIn = audioDeviceInput,
                       let audPort = audIn.ports.first(where: { $0.mediaType == .audio }) {
                        let audConn = AVCaptureConnection(inputPorts: [audPort], output: primOut)
                        if multi.canAddConnection(audConn) {
                            multi.addConnection(audConn)
                        }
                    }

                    // Secondary movie output (video only)
                    let secOut = AVCaptureMovieFileOutput()
                    guard multi.canAddOutput(secOut) else { throw CaptureError.sessionFailed }
                    multi.addOutputWithNoConnections(secOut)
                    secondaryMovieOutput = secOut

                    guard let secPort = secIn.ports(for: .video,
                                                    sourceDeviceType: secondary.deviceType,
                                                    sourceDevicePosition: secondary.position).first else {
                        throw CaptureError.sessionFailed
                    }
                    let secVidConn = AVCaptureConnection(inputPorts: [secPort], output: secOut)
                    guard multi.canAddConnection(secVidConn) else { throw CaptureError.sessionFailed }
                    multi.addConnection(secVidConn)

                    // Rotation — portrait for both.
                    if #available(iOS 17.0, *) {
                        if primVidConn.isVideoRotationAngleSupported(90) { primVidConn.videoRotationAngle = 90 }
                        if secVidConn.isVideoRotationAngleSupported(90) { secVidConn.videoRotationAngle = 90 }
                    }

                    currentMode = .clip
                    isSessionConfigured = true
                } catch {
                    multi.commitConfiguration()
                    cont.resume(throwing: error)
                    return
                }

                multi.commitConfiguration()
                let now = CACurrentMediaTime()
                log.info("configureDualVideoSession — committed in \(String(format: "%.3f", now - tBegin))s; total from gesture \(String(format: "%.3f", now - gestureTime))s")
                cont.resume()
            }
        }
        stateSubject.send(.ready(mode: .clip))
    }

    /// Reconfigures the shared AVCaptureMultiCamSession with two AVCapturePhotoOutputs
    /// (primary back-wide + secondary front/ultrawide) for Dual Still capture. No audio,
    /// no movie outputs. Mirrors the wiring in configureDualVideoSession otherwise.
    private func configureDualStillSession(gestureTime: Double) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                guard let multi = session as? AVCaptureMultiCamSession else {
                    cont.resume(throwing: CaptureError.sessionFailed)
                    return
                }
                let tBegin = CACurrentMediaTime()
                multi.beginConfiguration()

                for out in multi.outputs { multi.removeOutput(out) }
                for inp in multi.inputs { multi.removeInput(inp) }
                for conn in multi.connections { multi.removeConnection(conn) }
                photoOutput = nil
                movieOutput = nil
                secondaryVideoOutput = nil
                secondaryMovieOutput = nil
                secondaryPhotoOutput = nil
                videoDeviceInput = nil
                secondaryVideoInput = nil
                audioDeviceInput = nil

                do {
                    guard let primDev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        throw CaptureError.sessionFailed
                    }
                    let primIn = try AVCaptureDeviceInput(device: primDev)
                    guard multi.canAddInput(primIn) else { throw CaptureError.sessionFailed }
                    multi.addInputWithNoConnections(primIn)
                    videoDeviceInput = primIn

                    let secDev: AVCaptureDevice? = {
                        if let d = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) { return d }
                        if let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) { return d }
                        return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                    }()
                    guard let secondary = secDev else { throw CaptureError.sessionFailed }
                    let secIn = try AVCaptureDeviceInput(device: secondary)
                    guard multi.canAddInput(secIn) else { throw CaptureError.sessionFailed }
                    multi.addInputWithNoConnections(secIn)
                    secondaryVideoInput = secIn

                    // Primary photo output
                    let primOut = AVCapturePhotoOutput()
                    guard multi.canAddOutput(primOut) else { throw CaptureError.sessionFailed }
                    multi.addOutputWithNoConnections(primOut)
                    photoOutput = primOut

                    guard let primPort = primIn.ports(for: .video,
                                                      sourceDeviceType: primDev.deviceType,
                                                      sourceDevicePosition: primDev.position).first else {
                        throw CaptureError.sessionFailed
                    }
                    let primConn = AVCaptureConnection(inputPorts: [primPort], output: primOut)
                    guard multi.canAddConnection(primConn) else { throw CaptureError.sessionFailed }
                    multi.addConnection(primConn)

                    // Preview connection (no-connection topology breaks auto-wire).
                    if let layer = primaryPreviewLayer {
                        DispatchQueue.main.sync {
                            layer.session = nil
                            layer.setSessionWithNoConnection(multi)
                        }
                        let previewConn = AVCaptureConnection(inputPort: primPort, videoPreviewLayer: layer)
                        if multi.canAddConnection(previewConn) {
                            multi.addConnection(previewConn)
                            if #available(iOS 17.0, *),
                               previewConn.isVideoRotationAngleSupported(90) {
                                previewConn.videoRotationAngle = 90
                            }
                            log.info("configureDualStillSession — preview connection added")
                        } else {
                            log.warning("configureDualStillSession — canAddConnection(preview) false")
                        }
                    }

                    // Secondary photo output
                    let secOut = AVCapturePhotoOutput()
                    guard multi.canAddOutput(secOut) else { throw CaptureError.sessionFailed }
                    multi.addOutputWithNoConnections(secOut)
                    secondaryPhotoOutput = secOut

                    guard let secPort = secIn.ports(for: .video,
                                                    sourceDeviceType: secondary.deviceType,
                                                    sourceDevicePosition: secondary.position).first else {
                        throw CaptureError.sessionFailed
                    }
                    let secConn = AVCaptureConnection(inputPorts: [secPort], output: secOut)
                    guard multi.canAddConnection(secConn) else { throw CaptureError.sessionFailed }
                    multi.addConnection(secConn)

                    if #available(iOS 17.0, *) {
                        if primConn.isVideoRotationAngleSupported(90) { primConn.videoRotationAngle = 90 }
                        if secConn.isVideoRotationAngleSupported(90) { secConn.videoRotationAngle = 90 }
                    }

                    currentMode = .still
                    isSessionConfigured = true
                } catch {
                    multi.commitConfiguration()
                    cont.resume(throwing: error)
                    return
                }

                multi.commitConfiguration()
                let now = CACurrentMediaTime()
                log.info("configureDualStillSession — committed in \(String(format: "%.3f", now - tBegin))s; total from gesture \(String(format: "%.3f", now - gestureTime))s")
                cont.resume()
            }
        }
        stateSubject.send(.ready(mode: .still))
    }

    /// Internal helper mirroring the private `isDualCamSession` flag through a computed
    /// property so this extension (which lives outside the class scope) can read it.
    private var isSessionMultiCam: Bool {
        session is AVCaptureMultiCamSession
    }
}

// MARK: - SequenceFrameCapturer (Piqd v0.3)
//
// Drives per-frame capture for Sequence mode. The controller awaits each call before firing
// the next, so the single shared `photoOutput` + `activePhotoDelegate` are never contended.
// `zoom` latched at tap-time is passed through; applied to the active video device if the
// request differs from the current `videoZoomFactor`.

extension AVCaptureAdapter: SequenceFrameCapturer {
    public func captureFrame(zoom: Double, index: Int) async throws -> URL {
        guard let photoOutput else {
            log.error("captureFrame[\(index)] — photoOutput is nil")
            throw CaptureError.sessionFailed
        }

        if zoom > 0, let device = videoDeviceInput?.device {
            let clamped = max(device.minAvailableVideoZoomFactor,
                              min(CGFloat(zoom), device.maxAvailableVideoZoomFactor))
            if abs(device.videoZoomFactor - clamped) > 0.001 {
                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = clamped
                    device.unlockForConfiguration()
                } catch {
                    log.warning("captureFrame[\(index)] — zoom lock failed: \(error.localizedDescription)")
                }
            }
        }

        // Retain the delegate in a per-call slot so overlapping Sequence ticks can't stomp
        // each other. AVCapturePhotoOutput does NOT retain the delegate (verified: removing
        // the shared-slot retention leaked continuations on device), so we hold it ourselves
        // until the awaiting call resumes, then drop it.
        let frameID = UUID()
        let data: Data = try await withCheckedThrowingContinuation { cont in
            let delegate = PhotoDelegate(continuation: cont, isLiveCapture: false)
            inFlightFrameDelegates[frameID] = delegate
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
        inFlightFrameDelegates.removeValue(forKey: frameID)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seq-\(frameID.uuidString)-\(index)")
            .appendingPathExtension("jpg")
        try data.write(to: tempURL)
        log.debug("captureFrame[\(index)] → \(tempURL.lastPathComponent) (\(data.count)B)")
        return tempURL
    }
}
