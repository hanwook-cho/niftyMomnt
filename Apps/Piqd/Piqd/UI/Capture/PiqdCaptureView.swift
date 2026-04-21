// Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift
// Piqd v0.3 capture screen. Layers on top of v0.2:
//   • Snap format selector (Still/Sequence/Clip/Dual) — swipe-up or long-press-from-Still
//     on the shutter; tap-outside or 3s idle to collapse; auto-collapses on pick.
//   • ShutterButtonView — morphs per (format, state); drives Clip/Dual progress arc.
//   • FilmCounterView stays Roll-only. New sequenceFrameCounter shows "N/M" during Seq firing.
//   • Mode pill dimmed + non-hit while capturing (FR-MODE-09).
//   • SafeRenderBorderView overlays during Sequence/Clip/Dual capture window.
//   • Roll Mode is Still-only in v0.3 (FR-ROLL-01): swipe-up + long-press do nothing; format
//     selector never appears in Roll.
// Real AVCapture controller wiring (Sequence/Clip/Dual) lands behind TODO hooks — the
// UI_TEST_MODE stubs produce correctly-tagged vault rows so XCUITest UI6/UI9/UI12/UI17 pass.

import AVFoundation
import NiftyCore
import NiftyData
import SwiftUI
import os

private let modeSwitchLog = Logger(subsystem: "com.hwcho99.niftymomnt", category: "PiqdModeSwitch")

struct PiqdCaptureView: View {
    let container: PiqdAppContainer

    @State private var isCapturing = false
    @State private var flashAssetID: String?
    @State private var errorText: String?
    @State private var cameraAuthorized = true
    @State private var showModeSheet = false
    @State private var showDevSettings = false
    @State private var showRollFull = false
    @State private var rollUsed: Int = 0
    @State private var rollLimit: Int = 24
    @State private var modeSwitchStartedAt: CFAbsoluteTime?
    @State private var modeSwitchTarget: CaptureMode?

    // Piqd v0.3 — format selector + shutter state.
    @State private var showFormatSelector = false
    @State private var selectorIdleCollapseTask: Task<Void, Never>?
    @State private var shutterState: ShutterState = .idle
    @State private var sequenceFrameIndex: Int = 0
    @State private var clipProgress: Double = 0
    @State private var clipStartedAt: CFAbsoluteTime?
    @State private var pressStartedAt: CFAbsoluteTime?
    @State private var stillLongPressTask: Task<Void, Never>?
    @State private var showSequenceInterruptedToast = false

    private var modeStore: ModeStore { container.modeStore }
    private var dev: DevSettingsStore { container.devSettings }
    private var activity: CaptureActivityStore { container.captureActivity }
    private var aspect: AspectRatio { AspectRatio.defaultFor(modeStore.mode) }

    /// Effective Snap format. Roll is always Still in v0.3.
    private var activeFormat: CaptureFormat { modeStore.effectiveFormat(for: modeStore.mode) }

    /// Dual is available iff hardware reports multicam support AND the dev kill-switch
    /// isn't set. Gated at selector render time.
    private var isDualAvailable: Bool {
        !dev.forceDualCamUnavailable && AVCaptureMultiCamSession.isMultiCamSupported
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewWithLetterbox

            if !cameraAuthorized {
                cameraDeniedHint
            }

            // Safe-render border overlays while a video/sequence capture is in flight.
            if activity.isCapturing && modeStore.mode == .snap {
                SafeRenderBorderView()
                    .ignoresSafeArea()
            }

            if flashAssetID != nil {
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityElement()
                    .accessibilityIdentifier("piqd.captureIndicator")
            }

            VStack {
                topHUD
                    .padding(.horizontal, 16)
                    .padding(.top, 52)
                Spacer()

                if showFormatSelector && modeStore.mode == .snap {
                    FormatSelectorView(
                        current: activeFormat,
                        isDualAvailable: isDualAvailable,
                        onPick: { picked in pickFormat(picked) }
                    )
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                shutterControl
                    .padding(.bottom, 48)
            }

            if let errorText {
                VStack {
                    Spacer()
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.red.opacity(0.8), in: .rect(cornerRadius: 8))
                        .padding(.bottom, 140)
                }
            }

            if showSequenceInterruptedToast {
                VStack {
                    Spacer()
                    Text("Sequence didn't finish")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(.bottom, 110)
                        .accessibilityIdentifier("piqd.toast.sequenceInterrupted")
                }
                .transition(.opacity)
            }

            // Tap-outside collapse catcher — sits above the preview, below selector/shutter,
            // so taps on the selector/shutter continue to route normally.
            if showFormatSelector {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { collapseFormatSelector(reason: "tapOutside") }
                    .allowsHitTesting(true)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            // UI_TEST_MODE-only hidden trigger: XCUITest's synthetic press(forDuration:)
            // does not reliably route through SwiftUI gesture recognizers on iOS 26,
            // so we expose a full-width invisible Button that directly triggers the
            // long-hold action when tapped by the test runner.
            if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
                VStack {
                    Button("longhold") { if !activity.isCapturing { showModeSheet = true } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .opacity(0.001)
                        .accessibilityIdentifier("piqd-mode-pill-longhold-test")
                    Spacer()
                }
                .padding(.top, 140)
                .allowsHitTesting(!activity.isCapturing)
            }

            if showRollFull || (modeStore.mode == .roll && rollLimit > 0 && rollUsed >= rollLimit) {
                RollFullOverlay(
                    limit: rollLimit,
                    onDismiss: { showRollFull = false },
                    onSwitchToSnap: {
                        showRollFull = false
                        Task { await switchMode(to: .snap) }
                    }
                )
            }
        }
        .background(.black)
        .task { await startPreview() }
        .task(id: modeStore.mode) {
            await refreshRollCounter()
            await applyModeToSession(animated: true)
            // Leaving Snap → collapse selector silently (Roll has no selector).
            if modeStore.mode != .snap { showFormatSelector = false }
        }
        .onChange(of: modeStore.devMenuRequested) { _, newValue in
            if newValue {
                showDevSettings = true
                modeStore.devMenuRequested = false
            }
        }
        .sheet(isPresented: $showModeSheet) {
            ModeSwitchSheet(
                current: modeStore.mode,
                onSelect: { selected in
                    showModeSheet = false
                    Task { await switchMode(to: selected) }
                },
                onCancel: { showModeSheet = false }
            )
        }
        .sheet(isPresented: $showDevSettings) {
            PiqdDevSettingsView(store: dev, onClose: { showDevSettings = false })
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var previewWithLetterbox: some View {
        GeometryReader { geo in
            let cropped = letterboxRect(in: geo.size, ratio: aspect.ratio)
            ZStack {
                CameraPreviewView(session: container.captureSession)
                    .frame(width: cropped.width, height: cropped.height)
                    .position(x: cropped.midX, y: cropped.midY)
                    .accessibilityElement()
                    .accessibilityIdentifier("piqd.capture")
                    .accessibilityValue(modeStore.mode.rawValue)

                if modeStore.mode == .roll && dev.grainOverlayEnabled {
                    GrainOverlayView()
                        .frame(width: cropped.width, height: cropped.height)
                        .position(x: cropped.midX, y: cropped.midY)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var cameraDeniedHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
            Text("Camera access needed in Settings")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("piqd.cameraDeniedHint")
    }

    @ViewBuilder
    private var topHUD: some View {
        HStack(alignment: .center) {
            ModePill(
                mode: modeStore.mode,
                holdDuration: dev.longHoldDurationSeconds,
                hapticEnabled: dev.hapticEnabled,
                isLocked: activity.isCapturing,
                onTap: { modeStore.registerPillTap() },
                onLongHoldTriggered: { if !activity.isCapturing { showModeSheet = true } }
            )
            Spacer()
            if modeStore.mode == .roll {
                FilmCounterView(used: rollUsed, limit: rollLimit)
            }
        }
    }

    /// Shutter + gesture surface. Wraps ShutterButtonView in a DragGesture for swipe-up
    /// (Snap-only) and a long-press for Still→selector (Snap-only) / Clip & Dual press-hold.
    @ViewBuilder
    private var shutterControl: some View {
        let disabled = isShutterDisabled
        ShutterButtonView(
            format: activeFormat,
            state: disabled ? .disabled : shutterState,
            progress: clipProgress,
            sequenceCounterText: sequenceCounterText
        )
        .contentShape(Circle())
        .accessibilityIdentifier("piqd.shutter")
        .accessibilityAddTraits(.isButton)
        .allowsHitTesting(!disabled)
        .gesture(shutterGesture)
    }

    private var isShutterDisabled: Bool {
        if activity.isCapturing { return false } // allow release during recording
        if modeStore.mode == .roll && rollLimit > 0 && rollUsed >= rollLimit { return true }
        return false
    }

    private var sequenceCounterText: String? {
        guard activity.isCapturing, activity.reason == .sequence else { return nil }
        return "\(sequenceFrameIndex)/\(dev.sequenceFrameCount)"
    }

    private var shutterGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in onShutterTouchChanged(value) }
            .onEnded   { value in onShutterTouchEnded(value)   }
    }

    // MARK: - Gesture handling

    private func onShutterTouchChanged(_ value: DragGesture.Value) {
        guard pressStartedAt == nil else { return }
        pressStartedAt = CFAbsoluteTimeGetCurrent()

        // Press-and-hold recording for Clip/Dual starts on touch-down (after the 50ms
        // latency budget covered by ClipRecorderController tests).
        if modeStore.mode == .snap && (activeFormat == .clip || activeFormat == .dual) {
            Task { await beginVideoRecording(format: activeFormat) }
            return
        }

        // Still + long-press (Snap only) — schedule the selector-open deadline.
        if modeStore.mode == .snap && activeFormat == .still {
            stillLongPressTask?.cancel()
            let duration = dev.longHoldDurationSeconds
            stillLongPressTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if Task.isCancelled { return }
                // Still held — open selector.
                if pressStartedAt != nil { presentFormatSelector() }
            }
        }
    }

    private func onShutterTouchEnded(_ value: DragGesture.Value) {
        let startedAt = pressStartedAt
        pressStartedAt = nil
        stillLongPressTask?.cancel()
        stillLongPressTask = nil

        let elapsed = startedAt.map { CFAbsoluteTimeGetCurrent() - $0 } ?? 0
        let dy = value.translation.height

        // Swipe-up ≥40pt (Snap-only) → present selector. UI19 asserts Roll does nothing.
        if modeStore.mode == .snap && dy <= -40 {
            presentFormatSelector()
            return
        }

        // Clip / Dual release → end recording (unless auto-stopped by ceiling).
        if modeStore.mode == .snap && (activeFormat == .clip || activeFormat == .dual)
            && activity.isCapturing {
            Task { await endVideoRecording(autoStopped: false) }
            return
        }

        // If the still long-press already opened the selector, the press shouldn't fall
        // through as a tap.
        if showFormatSelector { return }

        // Otherwise tap-fire the capture.
        _ = elapsed
        Task { await handleShutter() }
    }

    // MARK: - Format selector lifecycle

    private func presentFormatSelector() {
        guard modeStore.mode == .snap, !activity.isCapturing, !showFormatSelector else { return }
        withAnimation(.easeOut(duration: 0.22)) { showFormatSelector = true }
        armSelectorIdleCollapse()
    }

    private func collapseFormatSelector(reason: String) {
        guard showFormatSelector else { return }
        selectorIdleCollapseTask?.cancel()
        selectorIdleCollapseTask = nil
        withAnimation(.easeIn(duration: 0.15)) { showFormatSelector = false }
    }

    private func armSelectorIdleCollapse() {
        selectorIdleCollapseTask?.cancel()
        selectorIdleCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            collapseFormatSelector(reason: "idle")
        }
    }

    private func pickFormat(_ format: CaptureFormat) {
        guard modeStore.mode == .snap else { return }
        modeStore.setSnapFormat(format)
        collapseFormatSelector(reason: "picked")
    }

    // MARK: - Layout

    private func letterboxRect(in size: CGSize, ratio: CGFloat) -> CGRect {
        let canvasRatio = size.width / size.height
        if ratio >= canvasRatio {
            let h = size.width / ratio
            let y = (size.height - h) / 2
            return CGRect(x: 0, y: y, width: size.width, height: h)
        } else {
            let w = size.height * ratio
            let x = (size.width - w) / 2
            return CGRect(x: x, y: 0, width: w, height: size.height)
        }
    }

    // MARK: - Preview + mode switching

    private func startPreview() async {
        if ProcessInfo.processInfo.environment["PIQD_FORCE_CAMERA_DENIED"] == "1" {
            cameraAuthorized = false
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            cameraAuthorized = false
            return
        }
        do {
            try await container.captureUseCase.startPreview(mode: .still, config: container.config)
            cameraAuthorized = true
        } catch {
            errorText = "preview failed: \(error.localizedDescription)"
        }
    }

    private func applyModeToSession(animated: Bool) async {
        do {
            try await container.captureUseCase.reconfigureSession(to: .still, config: container.config)
        } catch {
            errorText = "reconfigure failed: \(error.localizedDescription)"
        }
        if let started = modeSwitchStartedAt, modeSwitchTarget == modeStore.mode {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1000.0
            let budgetNote = elapsedMs <= 150 ? "OK" : "OVER"
            modeSwitchLog.log("mode switch → \(modeStore.mode.rawValue, privacy: .public) took \(elapsedMs, format: .fixed(precision: 1))ms [\(budgetNote, privacy: .public)]")
            modeSwitchStartedAt = nil
            modeSwitchTarget = nil
        }
    }

    private func switchMode(to newMode: CaptureMode) async {
        guard newMode != modeStore.mode else { return }
        modeSwitchStartedAt = CFAbsoluteTimeGetCurrent()
        modeSwitchTarget = newMode
        withAnimation(.easeInOut(duration: 0.15)) {
            modeStore.set(newMode)
        }
        await refreshRollCounter()
    }

    private func refreshRollCounter() async {
        let count = (try? await container.rollCounter.currentCount()) ?? 0
        let limit = await container.rollCounter.currentLimit()
        rollUsed = count
        rollLimit = limit
    }

    // MARK: - Capture dispatch

    /// Tap-fire: Still (Snap or Roll) or Sequence (Snap only).
    private func handleShutter() async {
        guard !activity.isCapturing else { return }

        // Non-Still Snap formats are routed from press-hold gestures; here we only handle
        // taps (.still + .sequence).
        if modeStore.mode == .snap {
            switch activeFormat {
            case .still:
                await captureStill()
            case .sequence:
                await captureSequence()
            case .clip, .dual:
                // Should never be reached — gestures drive these.
                break
            }
            return
        }

        // Roll — always Still, gated by the daily counter.
        if modeStore.mode == .roll {
            await captureRollStill()
        }
    }

    private func captureStill() async {
        isCapturing = true
        shutterState = .pressing
        defer {
            isCapturing = false
            shutterState = .idle
        }
        errorText = nil

        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
            flashAssetID = UUID().uuidString
            await persistTestStub(type: .still)
            try? await Task.sleep(nanoseconds: 150_000_000)
            flashAssetID = nil
            return
        }

        do {
            let asset = try await container.captureUseCase.captureAsset(
                preset: nil,
                aspectRatio: aspect,
                encoder: container.imageEncoder,
                locked: false
            )
            withAnimation(.easeOut(duration: 0.15)) { flashAssetID = asset.id.uuidString }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeIn(duration: 0.15)) { flashAssetID = nil }
        } catch {
            errorText = "capture failed: \(error.localizedDescription)"
        }
    }

    private func captureRollStill() async {
        do {
            _ = try await container.rollCounter.increment()
        } catch RollCounterError.limitReached {
            showRollFull = true
            await refreshRollCounter()
            return
        } catch {
            errorText = "counter failed: \(error.localizedDescription)"
            return
        }
        await refreshRollCounter()

        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
            flashAssetID = UUID().uuidString
            await persistTestStub(type: .still, locked: true)
            try? await Task.sleep(nanoseconds: 150_000_000)
            flashAssetID = nil
            return
        }

        do {
            let asset = try await container.captureUseCase.captureAsset(
                preset: nil,
                aspectRatio: aspect,
                encoder: container.imageEncoder,
                locked: true
            )
            withAnimation(.easeOut(duration: 0.15)) { flashAssetID = asset.id.uuidString }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeIn(duration: 0.15)) { flashAssetID = nil }
        } catch {
            errorText = "capture failed: \(error.localizedDescription)"
        }
    }

    /// Sequence tap: fires `dev.sequenceFrameCount` synthetic frames at `dev.sequenceIntervalMs`,
    /// driving the frame counter and safe-render border. In UI_TEST_MODE writes a single
    /// SEQ vault row on completion; on `forceSequenceAssemblyFailure` writes nothing.
    private func captureSequence() async {
        guard !activity.isCapturing else { return }
        activity.beginCapture(reason: .sequence)
        shutterState = .firing
        sequenceFrameIndex = 0
        defer {
            shutterState = .idle
            if activity.isCapturing { activity.endCapture() }
        }

        let frames = dev.sequenceFrameCount
        let interval = Double(dev.sequenceIntervalMs) / 1000.0
        for i in 1...frames {
            sequenceFrameIndex = i
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { return }
        }

        // Assembly — honoured dev flag drops the vault row (UI13).
        guard !dev.forceSequenceAssemblyFailure else { return }

        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
            await persistTestStub(type: .sequence, duration: Double(frames) * interval)
            return
        }

        // TODO(v0.3 real path): drive SequenceCaptureController → StoryEngine.assembleSequence;
        // write vault row with sequenceAssembledURL populated.
    }

    /// Press-hold start for Clip/Dual. Opens a CaptureActivity, arms the ceiling auto-stop.
    private func beginVideoRecording(format: CaptureFormat) async {
        guard !activity.isCapturing else { return }
        activity.beginCapture(reason: format == .clip ? .clip : .dual)
        shutterState = .recording
        clipStartedAt = CFAbsoluteTimeGetCurrent()
        clipProgress = 0

        let ceiling: Double = (format == .clip) ? Double(dev.clipMaxDurationSeconds) : 15.0

        // Progress tick — 30Hz is enough for the UI arc.
        Task { @MainActor in
            while activity.isCapturing {
                if let started = clipStartedAt {
                    let elapsed = CFAbsoluteTimeGetCurrent() - started
                    clipProgress = min(1.0, elapsed / ceiling)
                    if elapsed >= ceiling {
                        await endVideoRecording(autoStopped: true)
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }

        // TODO(v0.3 real path): dispatch to ClipRecorderController / DualRecorderController.
    }

    private func endVideoRecording(autoStopped: Bool) async {
        guard activity.isCapturing else { return }
        let started = clipStartedAt ?? CFAbsoluteTimeGetCurrent()
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        let reason = activity.reason
        activity.endCapture()
        shutterState = .idle
        clipStartedAt = nil
        clipProgress = 0

        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
            let type: AssetType = (reason == .dual) ? .dual : .clip
            await persistTestStub(type: type, duration: elapsed)
            return
        }

        _ = autoStopped
        // TODO(v0.3 real path): finalize the recorded MP4 (Clip) or composite (Dual) and
        // persist the vault row with `duration` set.
    }

    // MARK: - Test stubs

    private func persistTestStub(type: AssetType, locked: Bool = false, duration: Double? = nil) async {
        let asset = Asset(
            type: type,
            capturedAt: Date(),
            duration: duration,
            isPrivate: locked
        )
        let data = PiqdCaptureView.onePixelJPEG
        try? await container.vaultManager.save(
            asset, data: data,
            fileExtension: "jpg",
            locked: locked
        )
        let moment = Moment(
            id: UUID(),
            label: "UI Test",
            assets: [asset],
            centroid: GPSCoordinate(latitude: 0, longitude: 0),
            startTime: asset.capturedAt,
            endTime: asset.capturedAt,
            dominantVibes: [],
            moodPoint: nil,
            isStarred: false,
            heroAssetID: asset.id
        )
        try? await container.graphManager.saveMoment(moment)
    }

    private static let onePixelJPEG: Data = Data([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
        0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
        0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
        0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
        0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
        0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
        0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
        0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
        0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
        0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
        0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
        0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
        0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
        0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
        0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
        0x00, 0x00, 0x3F, 0x00, 0xFB, 0xD0, 0xFF, 0xD9
    ])
}
