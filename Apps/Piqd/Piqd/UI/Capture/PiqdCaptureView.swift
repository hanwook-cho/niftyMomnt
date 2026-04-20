// Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift
// Piqd v0.2 capture screen. Adds the mode system (Snap ↔ Roll) on top of v0.1's
// shutter + flash + camera-denied hint:
//   • ModePill — long-hold to open the confirmation sheet; 5-tap reveals dev settings.
//   • ModeSwitchSheet — confirms switch, calls reconfigureSession via the use case.
//   • Per-mode aspect ratio (Snap 9:16, Roll 4:3) applied as letterbox + post-capture crop.
//   • GrainOverlayView — drawn over the preview only when in Roll mode.
//   • FilmCounterView — Roll-only HUD reading from RollCounterRepository.
//   • RollFullOverlay — locks the shutter when the daily Roll limit is reached.

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
    /// Set by `switchMode` so the `.task(id: modeStore.mode)` observer can measure the
    /// total wall-clock from user confirmation through reconfigureSession completion.
    @State private var modeSwitchStartedAt: CFAbsoluteTime?
    @State private var modeSwitchTarget: CaptureMode?

    private var modeStore: ModeStore { container.modeStore }
    private var dev: DevSettingsStore { container.devSettings }
    private var aspect: AspectRatio { AspectRatio.defaultFor(modeStore.mode) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewWithLetterbox

            if !cameraAuthorized {
                cameraDeniedHint
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
                shutterButton
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

            // UI_TEST_MODE-only hidden trigger: XCUITest's synthetic press(forDuration:)
            // does not reliably route through SwiftUI gesture recognizers on iOS 26,
            // so we expose a full-width invisible Button that directly triggers the
            // long-hold action when tapped by the test runner.
            if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
                VStack {
                    Button("longhold") { showModeSheet = true }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .opacity(0.001)
                        .accessibilityIdentifier("piqd-mode-pill-longhold-test")
                    Spacer()
                }
                .padding(.top, 140)
                .allowsHitTesting(true)
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
            // Mode change should reflect on session config too.
            await applyModeToSession(animated: true)
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
                    // UI4 polls this value to detect mode-switch completion.
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
                onTap: { modeStore.registerPillTap() },
                onLongHoldTriggered: { showModeSheet = true }
            )
            Spacer()
            if modeStore.mode == .roll {
                FilmCounterView(used: rollUsed, limit: rollLimit)
            }
        }
    }

    private var shutterButton: some View {
        let disabled = isCapturing || (modeStore.mode == .roll && rollUsed >= rollLimit)
        return Button {
            Task { await handleShutter() }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(disabled ? .white.opacity(0.4) : .white)
                    .frame(width: 64, height: 64)
                    .scaleEffect(isCapturing ? 0.85 : 1.0)
            }
        }
        .disabled(disabled)
        .accessibilityIdentifier("piqd.shutter")
    }

    // MARK: - Layout

    /// Inscribed rect for the preview at `ratio` (width/height). Letterboxes top/bottom
    /// for tall (9:16) and side-bars for wider (4:3) on a 9:16-ish phone canvas.
    private func letterboxRect(in size: CGSize, ratio: CGFloat) -> CGRect {
        let canvasRatio = size.width / size.height
        if ratio >= canvasRatio {
            // Wider than canvas → constrain by width.
            let h = size.width / ratio
            let y = (size.height - h) / 2
            return CGRect(x: 0, y: y, width: size.width, height: h)
        } else {
            // Taller than canvas → constrain by height.
            let w = size.height * ratio
            let x = (size.width - w) / 2
            return CGRect(x: x, y: 0, width: w, height: size.height)
        }
    }

    // MARK: - Actions

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

    /// Piqd v0.2 — Snap and Roll both record .still under the hood for v0.2 (no video output
    /// changes), so the only thing that "changes" is the aspect ratio + UI chrome. We still
    /// call reconfigureSession for parity with the use case API; it's a no-op when source/dest
    /// are both photo-class modes.
    private func applyModeToSession(animated: Bool) async {
        do {
            try await container.captureUseCase.reconfigureSession(to: .still, config: container.config)
        } catch {
            errorText = "reconfigure failed: \(error.localizedDescription)"
        }
        // Close the timing span opened in switchMode. Logged unconditionally so we can
        // gather a p95 distribution from console logs across runs.
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

    private func handleShutter() async {
        isCapturing = true
        defer { isCapturing = false }
        errorText = nil

        // Roll mode — gate on daily limit. UI_TEST_MODE follows the same gate so tests
        // exercising RollFull overlay see realistic behavior.
        if modeStore.mode == .roll {
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
        }

        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
            flashAssetID = UUID().uuidString
            await persistTestStub()
            return
        }

        do {
            let asset = try await container.captureUseCase.captureAsset(
                preset: nil,
                aspectRatio: aspect,
                encoder: container.imageEncoder,
                locked: modeStore.mode == .roll
            )
            withAnimation(.easeOut(duration: 0.15)) {
                flashAssetID = asset.id.uuidString
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeIn(duration: 0.15)) {
                flashAssetID = nil
            }
        } catch {
            errorText = "capture failed: \(error.localizedDescription)"
        }
    }

    private func persistTestStub() async {
        let asset = Asset(type: .still, capturedAt: Date())
        let data = PiqdCaptureView.onePixelJPEG
        try? await container.vaultManager.save(
            asset, data: data,
            fileExtension: "jpg",
            locked: modeStore.mode == .roll
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
