// Apps/niftyMomnt/UI/CaptureHub/CaptureHubView.swift
// Spec §4 v1.8 — Four-zone capture surface.
//
// v1.8 changes applied:
//   Zone A: 64pt, overlay ON live preview (iOS Camera stacking). Icon order:
//     LEFT ①  Flash  (amber-active pill — leftmost = iOS Camera muscle memory)
//     LEFT ②  Self-Timer  (neutral pill, amber when timer set)
//     CENTER  Film Strip Counter  (Roll Mode only)
//     RIGHT ① Flip Camera
//     RIGHT ② More / overflow
//   Zone A §4.1a: AF/AE Lock contextual banner — tap-hold 600ms on viewfinder.
//   Zone C v1.7: preset peek swatches (5 colour dots beside name, active=12pt, others=9pt).
//   §4.5 v1.7: Post-Capture Overlay — location chip, 4 tilted sticker chips, quick share pill.

import AVFoundation
import NiftyCore
import QuartzCore
import SwiftUI
import UIKit

// MARK: - CaptureHubView

struct CaptureHubView: View {
    let container: AppContainer
    let onNavigateToJournal: () -> Void
    let isCaptureActive: Bool
    @Environment(\.scenePhase) private var scenePhase
 
    // Safe area read from UIKit on appear — SwiftUI's GeometryProxy.safeAreaInsets
    // returns 0 in every nested ignoresSafeArea context in this app's view hierarchy.
    @State private var topSafeArea: CGFloat = 59     // Dynamic Island / notch fallback
    @State private var bottomSafeArea: CGFloat = 34  // Home indicator fallback

    // Mode & preset
    @State private var currentMode: CaptureMode = .still
    @State private var activePresetIndex: Int = 1   // AMALFI default
    @State private var isFrontCamera: Bool = false
    @State private var showPresetPicker: Bool = false
    @State private var showCaptureSettingsDeck: Bool = false
    @State private var ghostText: String = ""
    @State private var ghostOpacity: Double = 0

    // Shutter / recording
    @State private var isRecording: Bool = false
    @State private var clipProgress: Double = 0
    @State private var clipCountdown: Int = 30
    @State private var soundStampPulse: Bool = false
    @State private var presetBarCollapsed: Bool = false

    // Zone A — icon state
    @State private var flashOn: Bool = true
    @State private var livePhotoOn: Bool = false

    // §4.1a — AF/AE Lock
    @State private var afLockActive: Bool = false
    @State private var afLockPoint: CGPoint = .zero
    @State private var afBannerOpacity: Double = 0

    // §4.5 — Post-capture overlay
    @State private var showPostCapture: Bool = false
    @State private var postCaptureChipsVisible: Bool = false
    // postCaptureLocationLabel is read from container.lastCapturedPlaceName (set by use case)
    @State private var postCaptureShareVisible: Bool = false
    @State private var selectedVibeChipIndex: Int? = nil

    // Last captured thumbnail (shown left of shutter)
    @State private var lastCapturedImage: UIImage? = nil
    @State private var lastCapturedThumbnailUsesFit: Bool = false
    @State private var isPreviewRunning: Bool = false
    @State private var previewControlTask: Task<Void, Never>? = nil
    @State private var clipTimerTask: Task<Void, Never>? = nil
    @State private var boothCaptureState: BoothCaptureState = .idle
    @State private var boothCapturedShots: [(Asset, Data)] = []
    @State private var boothCapturedImages: [UIImage?] = Array(repeating: nil, count: 4)
    @State private var boothSelectedFrame: FeaturedFrame = .none
    @State private var boothSelectedBorderColor: L4CBorderColor = .white
    @State private var boothPhotoShape: L4CPhotoShape = .fourByThree
    @State private var showBoothReviewSheet: Bool = false
    @State private var boothFlashOpacity: Double = 0

    // Roll mode (v0.4: 36-shot soft limit, wired to GRDB via fetchTodayMomentCount)
    private let rollModeMax = 36
    @State private var rollShotsRemaining: Int = 36

    // One-time flip hint
    @AppStorage("nifty.flipHintShown") private var flipHintShown: Bool = false
    @State private var showFlipHint: Bool = false
    @AppStorage("capture.selfTimerDelay") private var captureSelfTimerDelay: Int = 0
    @AppStorage("capture.secondaryCameraEnabled") private var secondaryCameraEnabled: Bool = true
    @AppStorage("nifty.soundStampEnabled") private var soundStampEnabled: Bool = false
    @AppStorage("capture.liveVibePreviewEnabled") private var liveVibePreviewEnabled: Bool = true
    @AppStorage("capture.aspectRatio") private var captureAspectRatioRaw: String = "9:16"
    @AppStorage("capture.clipVideoFormat") private var clipVideoFormatRaw: String = "hd"
    @AppStorage("capture.clipDurationSeconds") private var clipDurationSeconds: Int = 10
    @AppStorage("capture.echoMaxDurationSeconds") private var echoMaxDurationSeconds: Int = 60
    @AppStorage("capture.atmosphereLoopSeconds") private var atmosphereLoopSeconds: Int = 5
    @AppStorage("capture.liveApplePhotosExportEnabled") private var liveApplePhotosExportEnabled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activePreset: VibePresetUI { VibePresetUI.defaults[activePresetIndex] }

    private let postCaptureVibeOptions: [(emoji: String, label: String)] = [
        ("✨", "golden hour"), ("🌊", "wandering"),
        ("🌃", "city night"),  ("☁️", "moody")
    ]

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // ── Full-bleed live preview — hoisted above if/else so the same
                //    AVCaptureVideoPreviewLayer instance persists through mode changes.
                //    Re-creating it on each photoBooth toggle causes a ~0.4s stall while
                //    AVFoundation reconnects the display path on the new layer.
                CameraPreviewView(session: container.captureSession)
                    .ignoresSafeArea()
                FocusLockGestureView { point, size in
                    Task { await handleFocusLockGesture(at: point, frameSize: size) }
                }
                .ignoresSafeArea()

                // ── §4.1a AF/AE Lock — pulsing amber dot at lock point ──
                if afLockActive {
                    afLockDot
                        .position(afLockPoint)
                }

                // ── §4.5 Post-capture overlay (covers Zone B only) ──
                if showPostCapture {
                    postCaptureOverlay(geo: geo)
                }

                if currentMode == .photoBooth {
                    boothOverlay(geo: geo)
                }

                // ── Mode anchor (Zone B, above preset bar) ──
                // Bottom edge sits 8pt above Zone C top edge.
                // Zone D = 88 + bottomSafeArea, Zone C = 46pt (or 4pt when collapsed).
                modeAnchorLayer
                    .padding(.bottom, presetBarCollapsed
                             ? 88 + bottomSafeArea + 4 + 8
                             : 88 + bottomSafeArea + 46 + 8)

                // ── Sound Stamp pulse arcs ──
                if soundStampPulse {
                    soundStampArcs
                        .padding(.bottom, 44)
                        .allowsHitTesting(false)
                }

                // ── Ghost label (center-frame, on mode switch) ──
                ghostLabelLayer

                // ── Flip hint (one-time) ──
                if showFlipHint {
                    Text("double-tap to flip")
                        .font(.niftyCaption)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, NiftySpacing.md)
                        .padding(.vertical, NiftySpacing.xs)
                        .background(.ultraThinMaterial.opacity(0.6))
                        .clipShape(Capsule())
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .frame(maxHeight: .infinity, alignment: .center)
                }

                // ── §4.1a AF/AE Lock banner (below Zone A bottom edge) ──
                if afLockActive {
                    afLockBanner(geo: geo)
                }

                if isRecording && (currentMode == .clip || currentMode == .echo || currentMode == .atmosphere) {
                    recordingStatusOverlay
                }

                aspectRatioGuide(geo: geo)

                // ── Zone C + Zone D stacked at bottom ──
                VStack(spacing: 0) {
                    presetBar
                    shutterRow
                }

                // ── Zone A — overlay ON live preview (v1.8: iOS Camera stacking) ──
                topBar(geo: geo)
                    .frame(maxHeight: .infinity, alignment: .top)

                // ── Preset picker overlay ──
                if showPresetPicker {
                    presetPickerOverlay
                }

                if showCaptureSettingsDeck {
                    captureSettingsDeckOverlay
                }
            }
            .gesture(viewfinderGestures(geo: geo))
            .onTapGesture(count: 2) { flipCamera() }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: currentMode == .photoBooth)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { readWindowSafeArea() }
        .onAppear { performPreviewControl(active: true) }
        .task { await refreshRollCounter() }
        .onDisappear { performPreviewControl(active: false) }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: isCaptureActive) { _, isActive in
            performPreviewControl(active: isActive)
        }
        .onChange(of: soundStampEnabled) { _, enabled in
            container.applySoundStampToggle(enabled: enabled, currentMode: currentMode)
        }
        .sheet(isPresented: $showBoothReviewSheet, onDismiss: handleBoothReviewDismiss) {
            StripPreviewSheet(
                container: container,
                shots: boothCapturedShots,
                initialFrame: boothSelectedFrame,
                initialBorder: boothSelectedBorderColor,
                photoShape: boothPhotoShape,
                onSaved: { _ in
                    showBoothReviewSheet = false
                    resetBoothSession()
                },
                onRetake: {
                    showBoothReviewSheet = false
                    resetBoothSession()
                }
            )
        }
    }

    /// Reads the real device safe area from UIKit's key window.
    /// Called on appear because SwiftUI GeometryProxy.safeAreaInsets is unreliable
    /// inside nested ignoresSafeArea() view hierarchies (always returns 0).
    private func readWindowSafeArea() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else { return }
        topSafeArea = window.safeAreaInsets.top
        bottomSafeArea = window.safeAreaInsets.bottom
    }

    /// v0.4: Fetches today's moment count from GRDB and updates the Roll Mode counter.
    private func refreshRollCounter() async {
        let count = (try? await container.graphManager.fetchTodayMomentCount()) ?? 0
        rollShotsRemaining = max(0, rollModeMax - count)
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            performPreviewControl(active: true)
        case .inactive, .background:
            performPreviewControl(active: false)
        @unknown default:
            performPreviewControl(active: false)
        }
    }

    private func performPreviewControl(active: Bool) {
        previewControlTask?.cancel()
        previewControlTask = Task {
            if active {
                await startCameraPreview()
            } else {
                await stopCameraPreview()
            }
        }
    }

    /// Requests camera permission (first launch only) then starts the live preview session.
    private func startCameraPreview() async {
        if isPreviewRunning { return }
        guard isCaptureActive else { return }
        guard scenePhase == .active else { return }
        // Permission check is handled by UseCase -> Adapter
        do {
            try await container.captureUseCase.startPreview(mode: currentMode, config: container.config)
            await MainActor.run { isPreviewRunning = true }
        } catch {
            #if DEBUG
            print("[CaptureHub] startPreview failed: \(error)")
            #endif
        }
    }

    private func stopCameraPreview() async {
        if !isPreviewRunning { return }
        await container.captureUseCase.stopPreview()
        await MainActor.run { isPreviewRunning = false }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) async {
        switch newPhase {
        case .active:
            await startCameraPreview()
        case .inactive, .background:
            await stopCameraPreview()
        @unknown default:
            await stopCameraPreview()
        }
    }

    // MARK: - Zone A: Top Bar (v1.8 — 64pt, overlay on preview)

    private func topBar(geo: GeometryProxy) -> some View {
        ZStack {
            // iOS 26 Liquid Glass formula: dark base + blur/saturate/brightness
            // SwiftUI approximation: ultraThinMaterial with dark overlay
            Rectangle()
                .fill(Color(red: 8/255, green: 8/255, blue: 8/255).opacity(0.0))//HWCHO
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.white.opacity(0.10))
                        .frame(height: 0.5)
                }

            HStack(spacing: 0) {
                // LEFT GROUP: Flash ① + Timer ②
                HStack(spacing: NiftySpacing.sm) {
                    flashPill
                    timerPill
                }
                .padding(.leading, 14)

                Spacer()

                // CENTER: Film Strip Counter (Roll Mode) + SoundStamp mic indicator
                HStack(spacing: NiftySpacing.sm) {
                    if container.config.features.contains(.rollMode) {
                        filmStripCounter
                    }
                    if container.config.features.contains(.soundStamp) && container.isSoundStampActive {
                        soundStampIndicator
                    }
                }

                Spacer()

                // RIGHT GROUP: Live Photo ① + More ②
                HStack(spacing: NiftySpacing.sm) {
                    flipCameraPill
                    morePill
                }
                .padding(.trailing, 14)
            }
            .padding(.top, topSafeArea + 12)
            .frame(height: 64 + topSafeArea)
        }
        .frame(height: 64 + topSafeArea)
    }

    // MARK: Icon Pills (40×40pt circular, iOS 26 Liquid Glass)

    private var flashPill: some View {
        Button { flashOn.toggle() } label: {
            ZStack {
                Circle()
                    .fill(flashOn
                          ? Color(hex: "#E8A020").opacity(0.18)
                          : Color.white.opacity(0.09))
                    .overlay(
                        Circle().strokeBorder(
                            flashOn
                                ? Color(hex: "#E8A020").opacity(0.40)
                                : Color.white.opacity(0.12),
                            lineWidth: 0.5
                        )
                    )
                // Filled lightning bolt (not emoji per spec)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        flashOn
                            ? Color(hex: "#E8A020").opacity(0.92)
                            : Color.white.opacity(0.50)
                    )
            }
            .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Flash \(flashOn ? "on" : "off")")
    }

    private var timerPill: some View {
        let isSet = captureSelfTimerDelay > 0
        return Button {
            let options = [0, 3, 10]
            let currentIndex = options.firstIndex(of: captureSelfTimerDelay) ?? 0
            let next = options[(currentIndex + 1) % options.count]
            captureSelfTimerDelay = next
        } label: {
            ZStack {
                Circle()
                    .fill(isSet
                          ? Color(hex: "#E8A020").opacity(0.18)
                          : Color.white.opacity(0.09))
                    .overlay(
                        Circle().strokeBorder(
                            isSet
                                ? Color(hex: "#E8A020").opacity(0.40)
                                : Color.white.opacity(0.12),
                            lineWidth: 0.5
                        )
                    )
                if isSet {
                    Text("\(captureSelfTimerDelay)s")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: "#E8A020").opacity(0.92))
                } else {
                    // SVG-spec: clock face with hands, crown bar
                    Image(systemName: "timer")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Self-timer: \(captureSelfTimerDelay == 0 ? "Off" : "\(captureSelfTimerDelay)s")")
    }

    private var flipCameraPill: some View {
        return Button {
            flipCamera()
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.09))
                    .overlay(
                        Circle().strokeBorder(
                            Color.white.opacity(0.12),
                            lineWidth: 0.5
                        )
                    )
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))
            }
            .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Flip camera")
    }

    private var morePill: some View {
        Button {
            withAnimation(.niftySpring) { showCaptureSettingsDeck.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.09))
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                HStack(spacing: 3.5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(.white.opacity(0.78))
                            .frame(width: 3, height: 3)
                    }
                }
            }
            .frame(width: 40, height: 40)
        }
        .accessibilityLabel("More options")
    }

    // MARK: Sound Stamp Indicator (Zone A centre, pre-roll active)

    private var soundStampIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#E8A020"))
            Text("LIVE")
                .font(.system(size: 9, weight: .bold))
                .kerning(0.06 * 9)
                .foregroundStyle(Color(hex: "#E8A020").opacity(0.80))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: "#E8A020").opacity(0.12))
        .overlay(
            Capsule().strokeBorder(Color(hex: "#E8A020").opacity(0.30), lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }

    // MARK: Film Strip Counter (Zone A centre, Roll Mode only)

    private var filmStripCounter: some View {
        HStack(spacing: NiftySpacing.sm) {
            HStack(spacing: 2) {
                ForEach(0..<9, id: \.self) { i in
                    let used = i < Int(Double(rollModeMax - rollShotsRemaining) / Double(rollModeMax) * 9.0)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(used ? Color(hex: "#E8A020") : Color.white.opacity(0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5)
                                .strokeBorder(
                                    used ? Color(hex: "#BA7517").opacity(0.5) : Color.white.opacity(0.10),
                                    lineWidth: 0.5
                                )
                        )
                        .frame(width: 7, height: 10)
                }
            }
            Text("\(rollShotsRemaining) left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(rollShotsRemaining == 0
                                 ? Color(hex: "#E8A020")
                                 : .white.opacity(0.92))
        }
    }

    // MARK: - §4.1a AF/AE Lock

    private var afLockDot: some View {
        Circle()
            .fill(Color(hex: "#E8A020"))
            .frame(width: 8, height: 8)
            .opacity(0.8)
            .animation(
                reduceMotion ? nil :
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: afLockActive
            )
    }

    private func afLockBanner(geo: GeometryProxy) -> some View {
        let topBarBottom = 64 + topSafeArea
        return VStack(spacing: 2) {
            Text("Focus Locked")
                .font(.system(size: 11, weight: .bold))
                .kerning(0.04 * 11)
                .foregroundStyle(Color(hex: "#E8A020"))
            Text("Exposure held")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
        }
            .padding(.horizontal, NiftySpacing.lg)
            .padding(.vertical, NiftySpacing.xs + 2)
            .background(Color(hex: "#E8A020").opacity(0.18))
            .overlay(
                Capsule()
                    .strokeBorder(Color(hex: "#E8A020").opacity(0.40), lineWidth: 0.5)
            )
            .clipShape(Capsule())
            .opacity(afBannerOpacity)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, CGFloat(topBarBottom) + 20)
    }

    // Zone B viewfinder is now CameraPreviewView (AVCaptureVideoPreviewLayer).
    // The gradient placeholder was removed when live camera was wired up.

    // MARK: - Mode Anchor (Zone B overlay)

    private var modeAnchorLayer: some View {
        VStack(spacing: 6) {
            Text(currentMode.displayName)
                .font(.system(size: 12, weight: .semibold))
                .kerning(5)
                .foregroundStyle(.white.opacity(0.40))
            HStack(spacing: 8) {
                ForEach(-1...1, id: \.self) { offset in
                    let isActive = offset == 0
                    Circle()
                        .fill(.white.opacity(isActive ? 0.65 : 0.22))
                        .frame(width: isActive ? 7 : 5, height: isActive ? 7 : 5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - §4.5 Post-Capture Overlay

    private func postCaptureOverlay(geo: GeometryProxy) -> some View {
        ZStack {
            // Frozen capture tint
            Color.black.opacity(0.15)

            // Location vibe chip — top of Zone B, centred
            VStack {
                if postCaptureChipsVisible {
                    locationVibeChip
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .padding(.top, 64 + topSafeArea + 20)
                }
                Spacer()
            }

            // Vibe sticker chips — 2×2 grid centred in Zone B
            if postCaptureChipsVisible {
                vibeChipsGrid
            }

            // Quick Share pill — bottom of Zone B
            VStack {
                Spacer()
                if postCaptureShareVisible {
                    quickSharePill
                        .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.9)))
                        .padding(.bottom, 110 + 78) // above Zone C/D + 78pt spec offset
                }
            }

            // Dismiss on tap (if no chip tapped)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismissPostCapture() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var locationVibeChip: some View {
        Text(container.lastCapturedPlaceName.isEmpty ? "📍 —" : "📍 \(container.lastCapturedPlaceName)")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, NiftySpacing.lg)
            .padding(.vertical, NiftySpacing.sm)
            .background(.black.opacity(0.52))
            .background(.thinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    private var vibeChipsGrid: some View {
        VStack(spacing: NiftySpacing.sm) {
            Text("add a vibe")
                .font(.system(size: 10, weight: .heavy))
                .kerning(0.10 * 10)
                .foregroundStyle(.white.opacity(0.38))
                .opacity(selectedVibeChipIndex == nil ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: selectedVibeChipIndex)

            VStack(spacing: NiftySpacing.sm) {
                HStack(spacing: NiftySpacing.sm) {
                    stickerChip(index: 0, tilt: -2.5, delay: 0)
                    stickerChip(index: 1, tilt: 1.8, delay: 0.058)
                }
                HStack(spacing: NiftySpacing.sm) {
                    stickerChip(index: 2, tilt: -1.2, delay: 0.116)
                    stickerChip(index: 3, tilt: 2.2, delay: 0.174)
                }
            }
        }
    }

    private func stickerChip(index: Int, tilt: Double, delay: Double) -> some View {
        let option = postCaptureVibeOptions[index]
        let isSelected = selectedVibeChipIndex == index
        let isAmber = index == 0

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                selectedVibeChipIndex = index
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismissPostCapture() }
        } label: {
            Text("\(option.emoji) \(option.label)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isAmber ? Color(hex: "#E8A020") : .white.opacity(0.88))
                .padding(.vertical, NiftySpacing.sm)
                .padding(.horizontal, 15)
                .background(
                    isAmber
                        ? Color(hex: "#E8A020").opacity(0.22)
                        : Color.white.opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: index == 0 ? 28 : (index == 1 ? 18 : (index == 2 ? 22 : 26))))
                .overlay(
                    RoundedRectangle(cornerRadius: index == 0 ? 28 : (index == 1 ? 18 : (index == 2 ? 22 : 26)))
                        .strokeBorder(
                            isAmber ? Color(hex: "#E8A020").opacity(0.48) : .white.opacity(0.17),
                            lineWidth: isSelected ? 2 : 1.5
                        )
                )
        }
        .rotationEffect(.degrees(tilt))
        .scaleEffect(postCaptureChipsVisible ? 1 : 0.28)
        .opacity(postCaptureChipsVisible ? 1 : 0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.3) :
                .spring(response: 0.42, dampingFraction: 0.65).delay(delay),
            value: postCaptureChipsVisible
        )
    }

    private var quickSharePill: some View {
        HStack(spacing: NiftySpacing.md) {
            // Friend avatar stack placeholders
            HStack(spacing: -6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.niftyBrand.opacity(0.5))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                }
            }
            Text("send to close friends")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, NiftySpacing.xl)
        .padding(.vertical, NiftySpacing.md)
        .background(Color.niftyBrand.opacity(0.24))
        .background(.thinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.niftyBrand.opacity(0.48), lineWidth: 1))
    }

    // MARK: - Zone C: Preset Bar

    private var presetBar: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(activePreset.accentColor.opacity(0.82))
                .background(.ultraThinMaterial)
                .animation(reduceMotion ? nil : .niftyPresetSwitch, value: activePresetIndex)

            if !presetBarCollapsed {
                HStack(spacing: 0) {
                    Text(activePreset.name)
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.black.opacity(0.78))
                        .padding(.leading, NiftySpacing.lg)

                    Spacer()

                    Text("tap · hold")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.38))
                        .padding(.trailing, NiftySpacing.lg)
                }
                .frame(height: 46)
            }
        }
        .frame(height: presetBarCollapsed ? 4 : 46)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: presetBarCollapsed)
        .onLongPressGesture(minimumDuration: 0.4) {
            withAnimation(.niftySpring) { showPresetPicker = true }
        }
        .onTapGesture {
            if presetBarCollapsed {
                withAnimation(.easeOut(duration: 0.2)) { presetBarCollapsed = false }
            } else {
                cyclePreset(by: 1)
            }
        }
    }

    // MARK: - Zone D: Shutter Row

    private var shutterRow: some View {
        // ZStack(alignment: .top): background fills the full zone including home indicator
        // area; the content row stays in the upper 88pt so the shutter button is never
        // pushed down into the home indicator swipe zone.
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.30))
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
                }

            HStack(spacing: 0) {
                lastCaptureThumbnail
                    .padding(.leading, NiftySpacing.lg)
                Spacer()
                shutterButton
                Spacer()
                Color.clear
                    .frame(width: 68, height: 52)
                    .padding(.trailing, NiftySpacing.lg)
            }
            .frame(height: 88)
        }
        // Dynamic total height: 88pt content + device home indicator / bottom safe area
        .frame(height: 88 + bottomSafeArea)
    }

    private var lastCaptureThumbnail: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(Color(hex: "#1C1208"))
            .overlay {
                if let image = lastCapturedImage {
                    Group {
                        if lastCapturedThumbnailUsesFit {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                        } else {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.13), lineWidth: 1))
            .frame(width: 58, height: 42)
            .animation(.easeIn(duration: 0.2), value: lastCapturedImage != nil)
    }

    private var shutterButton: some View {
        ZStack {
            // Outer ring track (84pt — larger for easier tap target)
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 3)
                .frame(width: 84, height: 84)

            // Clip progress ring (amber arc fills clockwise)
            if currentMode == .clip && isRecording {
                Circle()
                    .trim(from: 0, to: clipProgress)
                    .stroke(
                        clipProgress > 0.83 ? Color.niftyAmber : activePreset.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 84, height: 84)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.1), value: clipProgress)
            }

            // Shutter body — dimensional radial gradient (70pt)
            Circle()
                .fill(RadialGradient(
                    colors: [.white, Color(hex: "#E8E8E8"), Color(hex: "#CCCCCC")],
                    center: UnitPoint(x: 0.4, y: 0.35),
                    startRadius: 0, endRadius: 34
                ))
                .frame(width: 70, height: 70)

            // Mode inner ring (58pt)
            Circle()
                .stroke(activePreset.accentColor.opacity(0.48), lineWidth: 1.5)
                .frame(width: 58, height: 58)

            shutterInterior
        }
        .onTapGesture { handleShutterTap() }
    }

    @ViewBuilder
    private var shutterInterior: some View {
        switch currentMode {
        case .still:
            if container.config.features.contains(.soundStamp) && soundStampEnabled {
                VStack(spacing: 1) {
                    Text("≋").font(.system(size: 10)).foregroundStyle(activePreset.accentColor.opacity(0.7))
                    Text("STAMP").font(.system(size: 6)).foregroundStyle(.white.opacity(0.5))
                }
            }
        case .clip:
            if isRecording {
                Text("\(clipCountdown)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(clipProgress > 0.83 ? Color.niftyAmber : activePreset.accentColor)
            }
        case .echo:
            if isRecording {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundStyle(activePreset.accentColor.opacity(0.8))
            }
        case .photoBooth:
            if boothSequenceIsRunning {
                Text("\(boothActiveSlotIndex + 1)/4")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(activePreset.accentColor.opacity(0.92))
            } else {
                Text("START")
                    .font(.system(size: 10, weight: .black))
                    .kerning(0.8)
                    .foregroundStyle(.black.opacity(0.74))
            }
        default:
            EmptyView()
        }
    }

    private var recordingStatusOverlay: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: "#FF5D5D"))
                    .frame(width: 8, height: 8)
                Text("REC")
                    .font(.system(size: 11, weight: .black))
                    .kerning(0.7)
                    .foregroundStyle(.white.opacity(0.94))
                Text(recordingModeLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(activePreset.accentColor.opacity(0.92))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.42))
            .background(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
            )
            .clipShape(Capsule())

            Text(recordingHintText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.28))
                .background(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                )
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, topSafeArea + 78)
        .allowsHitTesting(false)
    }

    private var recordingModeLabel: String {
        switch currentMode {
        case .clip:
            return selectedClipVideoFormat.shortTitle
        case .echo:
            return "ECHO"
        case .atmosphere:
            return "ATMOS"
        case .still, .live, .photoBooth:
            return currentMode.displayName.uppercased()
        }
    }

    private var recordingHintText: String {
        switch currentMode {
        case .clip:
            return "\(clipCountdown)s left · tap shutter to stop"
        case .echo:
            return "Tap shutter again to stop"
        case .atmosphere:
            return "Tap shutter again to stop"
        case .still, .live, .photoBooth:
            return ""
        }
    }

    @ViewBuilder
    private func boothOverlay(geo: GeometryProxy) -> some View {
        let previewFrame = previewGuideFrame(in: geo.size)
        let guideSize = boothGuideSize(in: previewFrame)
        let guideRect = CGRect(
            x: previewFrame.midX - (guideSize.width / 2),
            y: previewFrame.midY - (guideSize.height / 2),
            width: guideSize.width,
            height: guideSize.height
        )

        ZStack {
            boothGuideMask(previewFrame: previewFrame, guideRect: guideRect)

            if boothFlashOpacity > 0 {
                Color.white
                    .opacity(boothFlashOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 12) {
                if let status = boothStatusLabel {
                    Text(status)
                        .font(.system(size: 11, weight: .black))
                        .kerning(0.8)
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.32))
                        .background(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .clipShape(Capsule())
                }

                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < boothCapturedShots.count ? .white : .white.opacity(index == boothActiveSlotIndex ? 0.78 : 0.20))
                            .frame(width: index == boothActiveSlotIndex ? 18 : 14, height: index == boothActiveSlotIndex ? 18 : 14)
                            .overlay(
                                Circle()
                                    .strokeBorder(index == boothActiveSlotIndex ? activePreset.accentColor.opacity(0.92) : .clear, lineWidth: 2)
                            )
                    }
                }
            }
            .position(x: previewFrame.midX, y: guideRect.minY - 42)

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.6)
                    )

                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.96), lineWidth: 2)

                if let image = boothCurrentGuideImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: guideSize.width, height: guideSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                } else if let countdown = boothCountdownValue(for: boothActiveSlotIndex) {
                    Text("\(countdown)")
                        .font(.system(size: 52, weight: .black))
                        .foregroundStyle(.white.opacity(0.96))
                } else {
                    VStack(spacing: 10) {
                        Text(boothPhotoShape.displayTitle)
                            .font(.system(size: 12, weight: .black))
                            .kerning(0.8)
                            .foregroundStyle(.white.opacity(0.86))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.28))
                            .background(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                            )
                            .clipShape(Capsule())

                        Text("frame inside this guide")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.44))
                    }
                }
            }
            .frame(width: guideSize.width, height: guideSize.height)
            .position(x: guideRect.midX, y: guideRect.midY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var boothCurrentGuideImage: UIImage? {
        let activeIndex = boothActiveSlotIndex
        if case .freeze(let slotIndex) = boothCaptureState, slotIndex == activeIndex {
            return boothCapturedImages[slotIndex]
        }
        return nil
    }

    private func boothThumbnail(index: Int) -> some View {
        let image = boothCapturedImages[index]
        return RoundedRectangle(cornerRadius: 10)
            .fill(Color.black.opacity(0.22))
            .frame(width: 42, height: 42)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(index == boothActiveSlotIndex ? activePreset.accentColor.opacity(0.92) : .white.opacity(0.12), lineWidth: 1)
            )
    }

    private func boothGuideMask(previewFrame: CGRect, guideRect: CGRect) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.52))
                .frame(width: previewFrame.width, height: max(guideRect.minY - previewFrame.minY, 0))
                .position(x: previewFrame.midX, y: previewFrame.minY + max(guideRect.minY - previewFrame.minY, 0) / 2)

            Rectangle()
                .fill(Color.black.opacity(0.52))
                .frame(width: previewFrame.width, height: max(previewFrame.maxY - guideRect.maxY, 0))
                .position(x: previewFrame.midX, y: guideRect.maxY + max(previewFrame.maxY - guideRect.maxY, 0) / 2)

            Rectangle()
                .fill(Color.black.opacity(0.52))
                .frame(width: max(guideRect.minX - previewFrame.minX, 0), height: guideRect.height)
                .position(x: previewFrame.minX + max(guideRect.minX - previewFrame.minX, 0) / 2, y: guideRect.midY)

            Rectangle()
                .fill(Color.black.opacity(0.52))
                .frame(width: max(previewFrame.maxX - guideRect.maxX, 0), height: guideRect.height)
                .position(x: guideRect.maxX + max(previewFrame.maxX - guideRect.maxX, 0) / 2, y: guideRect.midY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func boothGuideSize(in previewFrame: CGRect) -> CGSize {
        let horizontalInset: CGFloat = 26
        let verticalInset: CGFloat = 84
        let maxWidth = max(previewFrame.width - (horizontalInset * 2), 1)
        let maxHeight = max(previewFrame.height - (verticalInset * 2), 1)
        let aspect = boothPhotoShape.widthToHeightAspect

        let widthFromHeight = maxHeight * aspect
        let finalWidth = min(maxWidth, widthFromHeight)
        let finalHeight = finalWidth / aspect
        return CGSize(width: finalWidth, height: finalHeight)
    }

    private func boothGuideCropRect(for imageSize: CGSize) -> CGRect {
        let targetAspect = boothPhotoShape.widthToHeightAspect
        let imageAspect = imageSize.width / max(imageSize.height, 1)

        if imageAspect > targetAspect {
            let cropWidth = imageSize.height * targetAspect
            return CGRect(
                x: (imageSize.width - cropWidth) / 2,
                y: 0,
                width: cropWidth,
                height: imageSize.height
            )
        }

        let cropHeight = imageSize.width / targetAspect
        return CGRect(
            x: 0,
            y: (imageSize.height - cropHeight) / 2,
            width: imageSize.width,
            height: cropHeight
        )
    }

    private func normalizedBoothPreviewImage(_ image: UIImage) -> UIImage {
        let normalized = image.normalizedOrientationImage()
        guard let cgImage = normalized.cgImage else { return normalized }
        let cropRect = boothGuideCropRect(for: CGSize(width: cgImage.width, height: cgImage.height))
        guard let cropped = cgImage.cropping(to: cropRect.integral) else { return normalized }
        return UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up)
    }

    private func boothOrientedImage(from data: Data) -> UIImage? {
        UIImage(data: data)?.normalizedOrientationImage()
    }

    // MARK: - Sound Stamp Pulse Arcs

    private var soundStampArcs: some View {
        ZStack {
            ForEach([0, 1, 2], id: \.self) { i in
                Circle()
                    .stroke(
                        activePreset.accentColor.opacity([0.55, 0.30, 0.12][i]),
                        lineWidth: CGFloat(1.5 - Double(i) * 0.5)
                    )
                    .frame(width: CGFloat(48 + i * 14), height: CGFloat(48 + i * 14))
                    .scaleEffect(soundStampPulse ? 1.0 : 0.6)
                    .opacity(soundStampPulse ? 1.0 : 0.0)
                    .animation(
                        reduceMotion ? .easeOut(duration: 1.0)
                        : .easeOut(duration: 1.5).delay(Double(i) * 0.15),
                        value: soundStampPulse
                    )
            }
        }
        .frame(width: 80, height: 80)
    }

    // MARK: - Ghost Label

    private var ghostLabelLayer: some View {
        Text(ghostText)
            .font(.niftyGhost)
            .kerning(0.25 * 28)
            .foregroundStyle(.white.opacity(ghostOpacity * 0.10))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }

    // MARK: - Preset Picker Overlay

    private var presetPickerOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.niftySpring) { showPresetPicker = false } }

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, NiftySpacing.md)
                    .padding(.bottom, NiftySpacing.xl)

                Text("CHOOSE PRESET")
                    .font(.niftyLabel)
                    .kerning(1.5)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, NiftySpacing.lg)

                ForEach(VibePresetUI.defaults) { preset in
                    Button { selectPreset(preset) } label: {
                        HStack(spacing: NiftySpacing.lg) {
                            Circle()
                                .fill(preset.accentColor)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle().stroke(
                                        preset.id == activePresetIndex ? .white : .clear,
                                        lineWidth: 2
                                    )
                                )
                            Text(preset.name)
                                .font(.niftyTitle)
                                .foregroundStyle(
                                    preset.id == activePresetIndex ? .white : .white.opacity(0.55)
                                )
                            Spacer()
                            if preset.id == activePresetIndex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white)
                                    .font(.niftyLabel)
                            }
                        }
                        .padding(.horizontal, NiftySpacing.xxl)
                        .padding(.vertical, NiftySpacing.md)
                    }
                }
                Spacer().frame(height: 60)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: NiftyRadius.overlay))
            .padding(.horizontal, NiftySpacing.sm)
            .padding(.bottom, NiftySpacing.lg)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var captureSettingsDeckOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.niftySpring) { showCaptureSettingsDeck = false }
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: NiftySpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Capture Controls")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(deckSubtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Spacer()

                    Text(deckModeTitle.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .kerning(0.8)
                        .foregroundStyle(activePreset.accentColor.opacity(0.96))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(activePreset.accentColor.opacity(0.16))
                        .overlay(
                            Capsule()
                                .strokeBorder(activePreset.accentColor.opacity(0.30), lineWidth: 0.8)
                        )
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 16)

                VStack(spacing: 12) {
                    ForEach(deckSections) { section in
                        captureSettingsSection(section)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(width: min(geoDeckWidth, 380))
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color(red: 18/255, green: 14/255, blue: 12/255).opacity(0.90))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 26)
                            .fill(
                                LinearGradient(
                                    colors: [activePreset.accentColor.opacity(0.22), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(1)
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .shadow(color: .black.opacity(0.36), radius: 24, y: 10)
            .padding(.top, topSafeArea + 62)
            .padding(.trailing, 14)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var geoDeckWidth: CGFloat {
        UIScreen.main.bounds.width - 28
    }

    private func captureSettingsSection(_ section: CaptureSettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(section.tint)
                    .frame(width: 22, height: 22)
                    .background(section.tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text(section.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                if let caption = section.caption {
                    Text(caption)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.34))
                }
                if section.isReadOnly {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.22))
                }
            }

            switch section.control {
            case .toggle(let binding):
                Toggle(isOn: binding) {
                    EmptyView()
                }
                .labelsHidden()
                .tint(section.tint)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(section.isReadOnly)

            case .chips(let options, let binding):
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        Button {
                            binding.wrappedValue = option.value
                        } label: {
                            Text(option.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(binding.wrappedValue == option.value ? .black.opacity(0.86) : .white.opacity(0.72))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    binding.wrappedValue == option.value
                                        ? section.tint
                                        : Color.white.opacity(0.06)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            binding.wrappedValue == option.value
                                                ? section.tint.opacity(0.34)
                                                : .white.opacity(0.10),
                                            lineWidth: 0.6
                                        )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(section.isReadOnly)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var deckModeTitle: String {
        switch currentMode {
        case .still: return "Still"
        case .live: return "Live"
        case .clip: return "Clip"
        case .echo: return "Echo"
        case .atmosphere: return "Atmosphere"
        case .photoBooth: return "Booth"
        }
    }

    private var deckSubtitle: String {
        switch currentMode {
        case .still:
            return "Shape how your next still lands."
        case .live:
            return "Tune motion and export defaults."
        case .clip:
            return "Set the clip ceiling before you roll."
        case .echo:
            return "Keep voice capture tight and intentional."
        case .atmosphere:
            return "Control the loop length of the moment."
        case .photoBooth:
            return "Pick the strip vibe before the four-shot run."
        }
    }

    private var deckSections: [CaptureSettingsSection] {
        switch currentMode {
        case .still:
            var sections: [CaptureSettingsSection] = [
                .chips(
                    title: "Aspect Ratio",
                    icon: "rectangle.expand.vertical",
                    tint: activePreset.accentColor,
                    caption: selectedAspectRatio.displayTitle,
                    options: aspectRatioOptions,
                    selection: Binding(
                        get: { selectedAspectRatio.optionValue },
                        set: { if let ratio = CaptureAspectRatio(optionValue: $0) { captureAspectRatioRaw = ratio.rawValue } }
                    )
                ),
                .chips(
                    title: "Timer",
                    icon: "timer",
                    tint: Color(hex: "#E8A020"),
                    caption: captureSelfTimerDelay == 0 ? "Off" : "\(captureSelfTimerDelay)s",
                    options: timerOptions,
                    selection: Binding(get: { captureSelfTimerDelay }, set: { captureSelfTimerDelay = $0 })
                ),
                .toggle(
                    title: "Context Cam",
                    icon: "rectangle.on.rectangle",
                    tint: Color(hex: "#8EB4D4"),
                    caption: secondaryCameraEnabled ? "On" : "Off",
                    value: Binding(get: { secondaryCameraEnabled }, set: { secondaryCameraEnabled = $0 })
                ),
                .toggle(
                    title: "Vibe Preview",
                    icon: "sparkles",
                    tint: activePreset.accentColor,
                    caption: liveVibePreviewEnabled ? "Live" : "Post only",
                    value: Binding(get: { liveVibePreviewEnabled }, set: { liveVibePreviewEnabled = $0 })
                )
            ]
            if container.config.features.contains(.soundStamp) {
                sections.insert(
                    .toggle(
                        title: "Sound Stamp",
                        icon: "waveform",
                        tint: Color(hex: "#FF8A5B"),
                        caption: soundStampEnabled ? "On" : "Off",
                        value: Binding(get: { soundStampEnabled }, set: { soundStampEnabled = $0 })
                    ),
                    at: 2
                )
            }
            return sections
        case .live:
            return [
                .chips(
                    title: "Aspect Ratio",
                    icon: "rectangle.expand.vertical",
                    tint: activePreset.accentColor,
                    caption: "Apple Live format",
                    options: aspectRatioOptions,
                    selection: Binding(
                        get: { CaptureAspectRatio.nineBySixteen.optionValue },
                        set: { _ in }
                    ),
                    isReadOnly: true
                ),
                .chips(
                    title: "Timer",
                    icon: "timer",
                    tint: Color(hex: "#E8A020"),
                    caption: captureSelfTimerDelay == 0 ? "Off" : "\(captureSelfTimerDelay)s",
                    options: timerOptions,
                    selection: Binding(get: { captureSelfTimerDelay }, set: { captureSelfTimerDelay = $0 })
                ),
                .toggle(
                    title: "Context Cam",
                    icon: "rectangle.on.rectangle",
                    tint: Color(hex: "#8EB4D4"),
                    caption: secondaryCameraEnabled ? "On" : "Off",
                    value: Binding(get: { secondaryCameraEnabled }, set: { secondaryCameraEnabled = $0 })
                ),
                .toggle(
                    title: "Vibe Preview",
                    icon: "sparkles",
                    tint: activePreset.accentColor,
                    caption: liveVibePreviewEnabled ? "Live" : "Post only",
                    value: Binding(get: { liveVibePreviewEnabled }, set: { liveVibePreviewEnabled = $0 })
                ),
                .toggle(
                    title: "Apple Photos",
                    icon: "photo.on.rectangle",
                    tint: Color(hex: "#6FD2B8"),
                    caption: liveApplePhotosExportEnabled ? "Live export" : "Still fallback",
                    value: Binding(get: { liveApplePhotosExportEnabled }, set: { liveApplePhotosExportEnabled = $0 })
                )
            ]
        case .clip:
            return [
                .chips(
                    title: "Video Format",
                    icon: "viewfinder.rectangular",
                    tint: activePreset.accentColor,
                    caption: selectedClipVideoFormat.displayTitle,
                    options: clipVideoFormatOptions,
                    selection: Binding(
                        get: { selectedClipVideoFormat.optionValue },
                        set: { if let format = ClipVideoFormat(optionValue: $0) { clipVideoFormatRaw = format.rawValue } }
                    )
                ),
                .chips(
                    title: "Clip Length",
                    icon: "stopwatch",
                    tint: activePreset.accentColor,
                    caption: "\(clipDurationSeconds)s ceiling",
                    options: [
                        .init(title: "5s", value: 5),
                        .init(title: "10s", value: 10),
                        .init(title: "15s", value: 15),
                        .init(title: "30s", value: 30)
                    ],
                    selection: Binding(get: { clipDurationSeconds }, set: { clipDurationSeconds = $0 })
                )
            ]
        case .echo:
            return [
                .chips(
                    title: "Echo Limit",
                    icon: "mic",
                    tint: Color(hex: "#FF8A5B"),
                    caption: "\(echoMaxDurationSeconds)s max",
                    options: [
                        .init(title: "30s", value: 30),
                        .init(title: "60s", value: 60),
                        .init(title: "90s", value: 90),
                        .init(title: "120s", value: 120)
                    ],
                    selection: Binding(get: { echoMaxDurationSeconds }, set: { echoMaxDurationSeconds = $0 })
                )
            ]
        case .atmosphere:
            return [
                .chips(
                    title: "Loop Length",
                    icon: "speaker.wave.2",
                    tint: Color(hex: "#C4B5FD"),
                    caption: "\(atmosphereLoopSeconds)s loop",
                    options: [
                        .init(title: "3s", value: 3),
                        .init(title: "5s", value: 5),
                        .init(title: "10s", value: 10),
                        .init(title: "15s", value: 15)
                    ],
                    selection: Binding(get: { atmosphereLoopSeconds }, set: { atmosphereLoopSeconds = $0 })
                )
            ]
        case .photoBooth:
            return [
                .chips(
                    title: "Photo Shape",
                    icon: "aspectratio",
                    tint: activePreset.accentColor,
                    caption: boothPhotoShape.displayTitle,
                    options: boothPhotoShapeOptions,
                    selection: Binding(
                        get: { boothPhotoShape.optionValue },
                        set: {
                            if let shape = L4CPhotoShape(optionValue: $0) {
                                boothPhotoShape = shape
                            }
                        }
                    )
                ),
                .chips(
                    title: "Template",
                    icon: "square.stack.3d.up",
                    tint: activePreset.accentColor,
                    caption: boothSelectedFrame.displayName,
                    options: boothFrameOptions,
                    selection: Binding(
                        get: { boothSelectedFrame.optionValue },
                        set: {
                            if let frame = FeaturedFrame(optionValue: $0) {
                                boothSelectedFrame = frame
                            }
                        }
                    )
                ),
                .chips(
                    title: "Border Colour",
                    icon: "swatchpalette",
                    tint: Color(hex: "#FFD6E0"),
                    caption: boothSelectedBorderColor.displayTitle,
                    options: boothBorderColorOptions,
                    selection: Binding(
                        get: { boothSelectedBorderColor.optionValue },
                        set: {
                            if let border = L4CBorderColor(optionValue: $0) {
                                boothSelectedBorderColor = border
                            }
                        }
                    )
                )
            ]
        }
    }

    private var timerOptions: [CaptureSettingsOption] {
        [
            .init(title: "Off", value: 0),
            .init(title: "3s", value: 3),
            .init(title: "10s", value: 10)
        ]
    }

    private var selectedAspectRatio: CaptureAspectRatio {
        CaptureAspectRatio(rawValue: captureAspectRatioRaw) ?? .nineBySixteen
    }

    private var effectiveAspectRatio: CaptureAspectRatio {
        currentMode == .live ? .nineBySixteen : selectedAspectRatio
    }

    private var aspectRatioOptions: [CaptureSettingsOption] {
        CaptureAspectRatio.allCases.map { .init(title: $0.displayTitle, value: $0.optionValue) }
    }

    private var selectedClipVideoFormat: ClipVideoFormat {
        ClipVideoFormat(rawValue: clipVideoFormatRaw) ?? .hd
    }

    private var clipVideoFormatOptions: [CaptureSettingsOption] {
        ClipVideoFormat.allCases.map { .init(title: $0.shortTitle, value: $0.optionValue) }
    }

    private var boothFrameOptions: [CaptureSettingsOption] {
        FeaturedFrame.allCases.enumerated().map { index, frame in
            .init(title: frame.displayName, value: index)
        }
    }

    private var boothPhotoShapeOptions: [CaptureSettingsOption] {
        [
            .init(title: "4:3", value: 0),
            .init(title: "3:4", value: 1)
        ]
    }

    private var boothBorderColorOptions: [CaptureSettingsOption] {
        [
            .init(title: "White", value: 0),
            .init(title: "Black", value: 1),
            .init(title: "Pink", value: 2),
            .init(title: "Blue", value: 3)
        ]
    }

    @ViewBuilder
    private func aspectRatioGuide(geo: GeometryProxy) -> some View {
        if currentMode == .still || currentMode == .live {
            let previewFrame = previewGuideFrame(in: geo.size)
            let guideSize = effectiveAspectRatio.guideSize(in: previewFrame.size)
            ZStack {
                Color.black.opacity(0.001)
                    .overlay {
                        aspectRatioLetterboxOverlay(
                            previewFrame: previewFrame,
                            guideSize: guideSize
                        )
                    }

                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .frame(width: 58, height: 24)
                    .overlay(
                        Text(effectiveAspectRatio.displayTitle)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.78))
                    )
                    .position(x: previewFrame.midX, y: previewFrame.minY + 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    private func previewGuideFrame(in containerSize: CGSize) -> CGRect {
        let topInset = topSafeArea + 64
        let bottomInset = 88 + bottomSafeArea + (presetBarCollapsed ? 4 : 46)
        let availableHeight = max(containerSize.height - topInset - bottomInset, 1)
        return CGRect(x: 0, y: topInset, width: containerSize.width, height: availableHeight)
    }

    private func aspectRatioLetterboxOverlay(previewFrame: CGRect, guideSize: CGSize) -> some View {
        let guideRect = CGRect(
            x: previewFrame.midX - (guideSize.width / 2),
            y: previewFrame.midY - (guideSize.height / 2),
            width: guideSize.width,
            height: guideSize.height
        )
        let maskColor = Color(red: 18/255, green: 13/255, blue: 10/255).opacity(0.24)

        return ZStack {
            if effectiveAspectRatio != .nineBySixteen {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 10/255, green: 8/255, blue: 6/255).opacity(0.30),
                                maskColor
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: previewFrame.width, height: max(guideRect.minY - previewFrame.minY, 0))
                    .position(x: previewFrame.midX, y: previewFrame.minY + max(guideRect.minY - previewFrame.minY, 0) / 2)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                maskColor,
                                Color(red: 10/255, green: 8/255, blue: 6/255).opacity(0.34)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: previewFrame.width, height: max(previewFrame.maxY - guideRect.maxY, 0))
                    .position(x: previewFrame.midX, y: guideRect.maxY + max(previewFrame.maxY - guideRect.maxY, 0) / 2)
            }
        }
    }

    // MARK: - Gesture Handling

    private func viewfinderGestures(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if currentMode == .photoBooth && boothSequenceIsRunning {
                    return
                }
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                if !isHorizontal && value.translation.height < -60 {
                    onNavigateToJournal()
                    return
                }
                guard isHorizontal else { return }
                let inLowerThird = value.startLocation.y > geo.size.height * 0.55
                guard inLowerThird else { return }
                cycleMode(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    private func flipCamera() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            isFrontCamera.toggle()
        }
        Task { try? await container.captureUseCase.switchCamera() }
        if !flipHintShown {
            flipHintShown = true
            withAnimation { showFlipHint = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { showFlipHint = false }
            }
        }
    }

    private func cycleMode(by delta: Int) {
        let modes = availableModes()
        guard let idx = modes.firstIndex(of: currentMode) else { return }
        let newMode = modes[(idx + delta + modes.count) % modes.count]
        if currentMode == .photoBooth && boothSequenceIsRunning {
            return
        }
        if currentMode == .photoBooth && newMode != .photoBooth {
            resetBoothSession()
        }
        withAnimation(.niftyPresetSwitch) { currentMode = newMode }
        showGhostLabel(newMode.ghostText)
        if afLockActive { dismissAfLock() }
        if newMode == .clip || newMode == .echo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if isRecording { withAnimation { presetBarCollapsed = true } }
            }
        } else {
            withAnimation { presetBarCollapsed = false }
        }
        // Reconfigure AVCaptureSession outputs for the new mode.
        // Skip for photoBooth — session prep is deferred to START tap (during countdown).
        let gestureTime = CACurrentMediaTime()
        if newMode == .photoBooth {
            // Measure UI-only transition cost (no hardware work)
            Task { @MainActor in
                let lag = CACurrentMediaTime() - gestureTime
                print("[CaptureHub] cycleMode → photoBooth UI transition lag: \(String(format: "%.3f", lag))s")
            }
        } else {
            Task { try? await container.captureUseCase.switchMode(to: newMode, config: container.config, gestureTime: gestureTime) }
        }
    }

    private func cyclePreset(by delta: Int) {
        let count = VibePresetUI.defaults.count
        withAnimation(.niftyPresetSwitch) {
            activePresetIndex = (activePresetIndex + delta + count) % count
        }
    }

    private func selectPreset(_ preset: VibePresetUI) {
        withAnimation(.niftyPresetSwitch) {
            activePresetIndex = preset.id
            showPresetPicker = false
        }
    }

    private func showGhostLabel(_ text: String) {
        ghostText = text
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.08)) { ghostOpacity = 1 }
        withAnimation(reduceMotion ? nil : .niftyGhostFade.delay(0.08)) { ghostOpacity = 0 }
    }

    // MARK: §4.1a AF/AE Lock

    private func activateAfLock(at point: CGPoint) {
        afLockPoint = point
        afLockActive = true
        withAnimation(.easeOut(duration: 0.24)) { afBannerOpacity = 1 }
    }

    private func dismissAfLock() {
        withAnimation(.easeOut(duration: 0.15)) { afBannerOpacity = 0 }
        afLockActive = false
        Task { await container.captureUseCase.unlockFocusAndExposure() }
    }

    private func handleFocusLockGesture(at point: CGPoint, frameSize: CGSize) async {
        guard currentMode != .photoBooth else { return }
        do {
            try await container.captureUseCase.focusAndLock(at: point, frameSize: frameSize)
            await MainActor.run { activateAfLock(at: point) }
        } catch {
            #if DEBUG
            print("[CaptureHub] focusAndLock failed: \(error)")
            #endif
        }
    }

    // MARK: - Shutter Actions

    private func handleShutterTap() {
        switch currentMode {
        case .still:
            triggerStillCapture()
        case .live:
            // Live Photo: same pipeline as still but tagged .live
            triggerStillCapture()
        case .echo:
            // Echo: tap toggles recording (audio-focused, no hold needed)
            if isRecording {
                print("[CaptureHub] Echo: Tapping shutter to STOP recording")
                stopVideoCapture()
            } else {
                print("[CaptureHub] Echo: Tapping shutter to START recording")
                startVideoCapture(mode: .echo)
            }
        case .atmosphere:
            // Atmosphere: tap toggles continuous recording
            if isRecording {
                stopVideoCapture()
            } else {
                startVideoCapture(mode: .atmosphere)
            }
        case .clip:
            if isRecording {
                stopVideoCapture()
                clipProgress = 0
                clipCountdown = clipDurationSeconds
                withAnimation { presetBarCollapsed = false }
            } else {
                startVideoCapture(mode: .clip)
            }
        case .photoBooth:
            startBoothCapture()
        }
    }

    private func triggerStillCapture() {
        if container.config.features.contains(.soundStamp) {
            withAnimation { soundStampPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { soundStampPulse = false }
            }
        }
        Task {
            do {
                let asset = try await container.captureUseCase.captureAsset(preset: activePreset.name)
                rollShotsRemaining = max(0, rollShotsRemaining - 1)
                // Load thumbnail from vault to display left of shutter
                if let (_, data) = try? await container.vaultManager.loadPrimary(asset.id) {
                    lastCapturedImage = UIImage(data: data)
                    lastCapturedThumbnailUsesFit = false
                }
            } catch {
                // Capture failed — overlay already showing, just log
                #if DEBUG
                print("[CaptureHub] captureAsset failed: \(error)")
                #endif
            }
        }
        // §4.5: Show post-capture overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showPostCapture = true
            withAnimation(.easeOut(duration: 0.28).delay(0.2)) { postCaptureChipsVisible = true }
            withAnimation(.spring(response: 0.44, dampingFraction: 0.72).delay(0.42)) {
                postCaptureShareVisible = true
            }
            // Auto-dismiss after 3s if not interacted
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { dismissPostCapture() }
        }
    }

    private func dismissPostCapture() {
        withAnimation(.easeOut(duration: 0.2)) {
            postCaptureChipsVisible = false
            postCaptureShareVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showPostCapture = false
            selectedVibeChipIndex = nil
        }
    }

    private func startVideoCapture(mode: CaptureMode) {
        if mode == .clip {
            clipTimerTask?.cancel()
            clipProgress = 0
            clipCountdown = clipDurationSeconds
            startClipCountdown()
        }
        print("[CaptureHub] startVideoCapture(mode: \(mode.rawValue)) — triggering Task...")
        withAnimation(.niftySpring) { isRecording = true }
        Task {
            do {
                try await container.captureUseCase.startVideoRecording(mode: mode, config: container.config)
                print("[CaptureHub] startVideoCapture — Task success for \(mode.rawValue)")
            } catch {
                clipTimerTask?.cancel()
                withAnimation { isRecording = false }
                #if DEBUG
                print("[CaptureHub] startVideoRecording failed: \(error)")
                #endif
            }
        }
    }

    private func stopVideoCapture() {
        print("[CaptureHub] stopVideoCapture attempt — isRecording: \(isRecording), currentMode: \(currentMode.rawValue) (Task starting)")
        guard isRecording else {
            print("[CaptureHub] stopVideoCapture — SKIPPED: isRecording was already false")
            return
        }
        clipTimerTask?.cancel()
        clipTimerTask = nil
        withAnimation(.niftySpring) { isRecording = false }
        Task {
            do {
                print("[CaptureHub] stopVideoCapture — calling useCase.stopVideoRecording...")
                let asset = try await container.captureUseCase.stopVideoRecording(config: container.config, preset: activePreset.name)
                rollShotsRemaining = max(0, rollShotsRemaining - 1)
                print("[CaptureHub] stopVideoCapture — success! assetID: \(asset.id.uuidString) type: \(asset.type.rawValue) duration: \(asset.duration ?? 0)")
                if asset.type == .echo {
                    await MainActor.run {
                        lastCapturedImage = UIImage(
                            systemName: "waveform.circle.fill",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 42, weight: .regular)
                        )?
                        .withTintColor(UIColor(Color.niftyAmberVivid), renderingMode: .alwaysOriginal)
                        lastCapturedThumbnailUsesFit = true
                    }
                } else if let thumb = await loadVideoThumbnail(assetID: asset.id) {
                    await MainActor.run {
                        lastCapturedImage = thumb
                        lastCapturedThumbnailUsesFit = true
                    }
                }
            } catch {
                #if DEBUG
                print("[CaptureHub] stopVideoRecording failed: \(error)")
                #endif
            }
        }
    }

    private func startClipCountdown() {
        let ceiling = max(clipDurationSeconds, 1)
        clipTimerTask = Task {
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let progress = min(max(elapsed / Double(ceiling), 0), 1)
                let remaining = max(Int(ceil(Double(ceiling) - elapsed)), 0)

                await MainActor.run {
                    clipProgress = progress
                    clipCountdown = remaining
                }

                if elapsed >= Double(ceiling) {
                    await MainActor.run {
                        if isRecording {
                            stopVideoCapture()
                            withAnimation { presetBarCollapsed = false }
                        }
                    }
                    break
                }

                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func loadVideoThumbnail(assetID: UUID) async -> UIImage? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let url = dir
            .appendingPathComponent("assets")
            .appendingPathComponent("\(assetID.uuidString).mov")

        guard FileManager.default.fileExists(atPath: url.path) else {
            #if DEBUG
            print("[CaptureHub] loadVideoThumbnail missing MOV at \(url.lastPathComponent)")
            #endif
            return nil
        }

        let avAsset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        } catch {
            #if DEBUG
            print("[CaptureHub] loadVideoThumbnail failed for \(assetID): \(error)")
            #endif
            return nil
        }
    }

    private func availableModes() -> [CaptureMode] {
        CaptureMode.allCases.filter { mode in
            switch mode {
            case .still:      return container.config.assetTypes.contains(.still)
            case .live:       return container.config.assetTypes.contains(.live)
            case .clip:       return container.config.assetTypes.contains(.clip)
            case .echo:       return container.config.assetTypes.contains(.echo)
            case .atmosphere: return container.config.assetTypes.contains(.atmosphere)
            case .photoBooth: return container.config.features.contains(.l4c)
            }
        }
    }

    private var boothSequenceIsRunning: Bool {
        boothCaptureState != .idle && boothCaptureState != .completed
    }

    private var boothActiveSlotIndex: Int {
        switch boothCaptureState {
        case .idle:
            return boothCapturedImages.firstIndex(where: { $0 == nil }) ?? 0
        case .countingDown(let slotIndex, _),
             .flashing(let slotIndex),
             .freeze(let slotIndex):
            return slotIndex
        case .advancing(let nextSlotIndex):
            return min(nextSlotIndex, 3)
        case .completed:
            return 3
        }
    }

    private var boothStatusLabel: String? {
        switch boothCaptureState {
        case .idle:
            return "4 CUTS · \(boothSelectedFrame.displayName)"
        case .countingDown(let slotIndex, _):
            return "SHOT \(slotIndex + 1) OF 4"
        case .flashing(let slotIndex):
            return "SNAP \(slotIndex + 1) OF 4"
        case .freeze(let slotIndex):
            return "LOCKED \(slotIndex + 1) OF 4"
        case .advancing(let nextSlotIndex):
            return nextSlotIndex < 4 ? "UP NEXT \(nextSlotIndex + 1) OF 4" : "BUILDING STRIP"
        case .completed:
            return "REVIEW YOUR STRIP"
        }
    }

    private func boothCountdownValue(for index: Int) -> Int? {
        if case .countingDown(let slotIndex, let count) = boothCaptureState, slotIndex == index {
            return count
        }
        return nil
    }

    private func startBoothCapture() {
        guard currentMode == .photoBooth else { return }
        guard !boothSequenceIsRunning else { return }
        resetBoothSession(keepSelections: true)
        withAnimation(.niftySpring) {
            showCaptureSettingsDeck = false
            presetBarCollapsed = true
        }
        Task { await runBoothCaptureSequence() }
    }

    private func runBoothCaptureSequence() async {
        do {
            try await container.captureUseCase.switchMode(to: .still, config: container.config)

            for slotIndex in 0..<4 {
                for count in stride(from: 3, through: 1, by: -1) {
                    await MainActor.run {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            boothCaptureState = .countingDown(slotIndex: slotIndex, count: count)
                        }
                    }
                    try await Task.sleep(for: .seconds(1))
                }

                await MainActor.run {
                    boothCaptureState = .flashing(slotIndex: slotIndex)
                    withAnimation(.easeOut(duration: 0.12)) { boothFlashOpacity = 0.92 }
                }
                try await Task.sleep(for: .milliseconds(120))
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.18)) { boothFlashOpacity = 0 }
                }

                let shot = try await container.lifeFourCutsUseCase.captureOneShot()
                let normalizedShot = normalizeBoothShot(shot)
                let image = UIImage(data: normalizedShot.1)

                await MainActor.run {
                    boothCapturedShots.append(normalizedShot)
                    boothCapturedImages[slotIndex] = image
                    boothCaptureState = .freeze(slotIndex: slotIndex)
                    lastCapturedImage = image
                    lastCapturedThumbnailUsesFit = false
                }
                try await Task.sleep(for: .milliseconds(420))

                await MainActor.run {
                    let next = min(slotIndex + 1, 4)
                    boothCaptureState = next < 4 ? .advancing(nextSlotIndex: next) : .completed
                }
                try await Task.sleep(for: .milliseconds(slotIndex == 3 ? 140 : 260))
            }

            await MainActor.run {
                showBoothReviewSheet = true
            }
        } catch {
            #if DEBUG
            print("[CaptureHub] booth capture failed: \(error)")
            #endif
            await MainActor.run {
                resetBoothSession(keepSelections: true)
            }
        }
    }

    private func handleBoothReviewDismiss() {
        if currentMode == .photoBooth {
            withAnimation(.easeOut(duration: 0.2)) {
                presetBarCollapsed = false
            }
        }
    }

    private func resetBoothSession(keepSelections: Bool = true) {
        boothCaptureState = .idle
        boothCapturedShots = []
        boothCapturedImages = Array(repeating: nil, count: 4)
        showBoothReviewSheet = false
        boothFlashOpacity = 0
        if !keepSelections {
            boothSelectedFrame = .none
            boothSelectedBorderColor = .white
        }
        withAnimation(.easeOut(duration: 0.2)) {
            presetBarCollapsed = false
        }
    }

    private func normalizeBoothShot(_ shot: (Asset, Data)) -> (Asset, Data) {
        guard let oriented = boothOrientedImage(from: shot.1) else { return shot }
        let normalized = normalizedBoothPreviewImage(oriented)
        guard let data = normalized.jpegData(compressionQuality: 0.92) else {
            return shot
        }
        return (shot.0, data)
    }
}

private struct CaptureSettingsOption: Identifiable {
    let title: String
    let value: Int
    var id: Int { value }
}

private enum CaptureSettingsControl {
    case toggle(Binding<Bool>)
    case chips([CaptureSettingsOption], Binding<Int>)
}

private struct CaptureSettingsSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tint: Color
    let caption: String?
    let control: CaptureSettingsControl
    let isReadOnly: Bool

    static func toggle(
        title: String,
        icon: String,
        tint: Color,
        caption: String? = nil,
        value: Binding<Bool>,
        isReadOnly: Bool = false
    ) -> CaptureSettingsSection {
        .init(
            title: title,
            icon: icon,
            tint: tint,
            caption: caption,
            control: .toggle(value),
            isReadOnly: isReadOnly
        )
    }

    static func chips(
        title: String,
        icon: String,
        tint: Color,
        caption: String? = nil,
        options: [CaptureSettingsOption],
        selection: Binding<Int>,
        isReadOnly: Bool = false
    ) -> CaptureSettingsSection {
        .init(
            title: title,
            icon: icon,
            tint: tint,
            caption: caption,
            control: .chips(options, selection),
            isReadOnly: isReadOnly
        )
    }
}

private enum CaptureAspectRatio: String, CaseIterable {
    case nineBySixteen = "9:16"
    case fourByFive = "4:5"
    case oneByOne = "1:1"

    var optionValue: Int {
        switch self {
        case .nineBySixteen: return 0
        case .fourByFive: return 1
        case .oneByOne: return 2
        }
    }

    init?(optionValue: Int) {
        switch optionValue {
        case 0: self = .nineBySixteen
        case 1: self = .fourByFive
        case 2: self = .oneByOne
        default: return nil
        }
    }

    var displayTitle: String { rawValue }

    func guideSize(in container: CGSize) -> CGSize {
        let horizontalInset: CGFloat = 22
        let verticalInset: CGFloat = 164
        let maxWidth = max(container.width - (horizontalInset * 2), 1)
        let maxHeight = max(container.height - verticalInset, 1)

        let aspect: CGFloat
        switch self {
        case .nineBySixteen: aspect = 9.0 / 16.0
        case .fourByFive: aspect = 4.0 / 5.0
        case .oneByOne: aspect = 1.0
        }

        let widthFromHeight = maxHeight * aspect
        let finalWidth = min(maxWidth, widthFromHeight)
        let finalHeight = finalWidth / aspect
        return CGSize(width: finalWidth, height: finalHeight)
    }
}

private enum ClipVideoFormat: String, CaseIterable {
    case vga
    case hd
    case fourK = "4k"

    var optionValue: Int {
        switch self {
        case .vga: return 0
        case .hd: return 1
        case .fourK: return 2
        }
    }

    init?(optionValue: Int) {
        switch optionValue {
        case 0: self = .vga
        case 1: self = .hd
        case 2: self = .fourK
        default: return nil
        }
    }

    var shortTitle: String {
        switch self {
        case .vga: return "VGA"
        case .hd: return "HD"
        case .fourK: return "4K"
        }
    }

    var displayTitle: String {
        switch self {
        case .vga: return "VGA 4:3"
        case .hd: return "HD 16:9"
        case .fourK: return "4K 16:9"
        }
    }
}

private enum BoothCaptureState: Equatable {
    case idle
    case countingDown(slotIndex: Int, count: Int)
    case flashing(slotIndex: Int)
    case freeze(slotIndex: Int)
    case advancing(nextSlotIndex: Int)
    case completed
}

private extension FeaturedFrame {
    var optionValue: Int {
        FeaturedFrame.allCases.firstIndex(where: { $0.id == id }) ?? 0
    }

    init?(optionValue: Int) {
        guard FeaturedFrame.allCases.indices.contains(optionValue) else { return nil }
        self = FeaturedFrame.allCases[optionValue]
    }
}

private extension L4CBorderColor {
    var boothPreviewColor: Color {
        switch self {
        case .white:
            return Color.white.opacity(0.90)
        case .black:
            return Color(red: 22/255, green: 22/255, blue: 24/255).opacity(0.94)
        case .pastelPink:
            return Color(red: 1.0, green: 0.87, blue: 0.91).opacity(0.94)
        case .skyBlue:
            return Color(red: 0.78, green: 0.90, blue: 1.0).opacity(0.94)
        }
    }

    var optionValue: Int {
        switch self {
        case .white: return 0
        case .black: return 1
        case .pastelPink: return 2
        case .skyBlue: return 3
        }
    }

    init?(optionValue: Int) {
        switch optionValue {
        case 0: self = .white
        case 1: self = .black
        case 2: self = .pastelPink
        case 3: self = .skyBlue
        default: return nil
        }
    }

    var displayTitle: String {
        switch self {
        case .white: return "White"
        case .black: return "Black"
        case .pastelPink: return "Pink"
        case .skyBlue: return "Blue"
        }
    }
}

private extension L4CPhotoShape {
    var optionValue: Int {
        switch self {
        case .fourByThree: return 0
        case .threeByFour: return 1
        }
    }

    init?(optionValue: Int) {
        switch optionValue {
        case 0: self = .fourByThree
        case 1: self = .threeByFour
        default: return nil
        }
    }

    var displayTitle: String { rawValue }

    var widthToHeightAspect: CGFloat {
        switch self {
        case .fourByThree:
            return 4.0 / 3.0
        case .threeByFour:
            return 3.0 / 4.0
        }
    }
}

private extension UIImage {
    func normalizedOrientationImage() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - CaptureMode display helpers

private extension CaptureMode {
    var displayName: String {
        switch self {
        case .still:      return "STILL"
        case .live:       return "LIVE"
        case .clip:       return "CLIP"
        case .echo:       return "ECHO"
        case .atmosphere: return "ATMOS"
        case .photoBooth: return "BOOTH"
        }
    }
    var ghostText: String {
        switch self {
        case .still:      return "S T I L L"
        case .live:       return "L I V E"
        case .clip:       return "C L I P"
        case .echo:       return "E C H O"
        case .atmosphere: return "A T M O S"
        case .photoBooth: return "B O O T H"
        }
    }
}
