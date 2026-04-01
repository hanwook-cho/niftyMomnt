// Apps/niftyMomnt/UI/CaptureHub/CaptureHubView.swift
// Spec §4 v1.8 — Four-zone capture surface.
//
// v1.8 changes applied:
//   Zone A: 64pt, overlay ON live preview (iOS Camera stacking). Icon order:
//     LEFT ①  Flash  (amber-active pill — leftmost = iOS Camera muscle memory)
//     LEFT ②  Self-Timer  (neutral pill, amber when timer set)
//     CENTER  Film Strip Counter  (Roll Mode only)
//     RIGHT ① Live Photo toggle
//     RIGHT ② More / overflow
//   Zone A §4.1a: AF/AE Lock contextual banner — tap-hold 600ms on viewfinder.
//   Zone C v1.7: preset peek swatches (5 colour dots beside name, active=12pt, others=9pt).
//   §4.5 v1.7: Post-Capture Overlay — location chip, 4 tilted sticker chips, quick share pill.

import AVFoundation
import NiftyCore
import SwiftUI
import UIKit

// MARK: - CaptureHubView

struct CaptureHubView: View {
    let container: AppContainer
    let onNavigateToJournal: () -> Void
 
    // Safe area read from UIKit on appear — SwiftUI's GeometryProxy.safeAreaInsets
    // returns 0 in every nested ignoresSafeArea context in this app's view hierarchy.
    @State private var topSafeArea: CGFloat = 59     // Dynamic Island / notch fallback
    @State private var bottomSafeArea: CGFloat = 34  // Home indicator fallback

    // Mode & preset
    @State private var currentMode: CaptureMode = .still
    @State private var activePresetIndex: Int = 1   // AMALFI default
    @State private var isFrontCamera: Bool = false
    @State private var showPresetPicker: Bool = false
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
    @State private var timerSetting: Int = 0          // 0 / 3 / 10 seconds
    @State private var livePhotoOn: Bool = false

    // §4.1a — AF/AE Lock
    @State private var afLockActive: Bool = false
    @State private var afLockPoint: CGPoint = .zero
    @State private var afBannerOpacity: Double = 0

    // §4.5 — Post-capture overlay
    @State private var showPostCapture: Bool = false
    @State private var postCaptureChipsVisible: Bool = false
    @State private var postCaptureShareVisible: Bool = false
    @State private var selectedVibeChipIndex: Int? = nil

    // Roll mode
    @State private var rollShotsRemaining: Int = 17

    // One-time flip hint
    @AppStorage("nifty.flipHintShown") private var flipHintShown: Bool = false
    @State private var showFlipHint: Bool = false

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

                // ── Full-bleed live preview (Zone B base) ──
                CameraPreviewView(session: container.captureSession)
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
            }
            .gesture(viewfinderGestures(geo: geo))
            .onTapGesture(count: 2) { flipCamera() }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { readWindowSafeArea() }
        .task { await startCameraPreview() }
        .onDisappear { Task { await container.captureUseCase.stopPreview() } }
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

    /// Requests camera permission (first launch only) then starts the live preview session.
    private func startCameraPreview() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .video) else { return }
        } else {
            guard status == .authorized else { return }
        }
        try? await container.captureUseCase.startPreview(mode: currentMode, config: container.config)
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

                // CENTER: Film Strip Counter (Roll Mode only)
                if container.config.features.contains(.rollMode) {
                    filmStripCounter
                }

                Spacer()

                // RIGHT GROUP: Live Photo ① + More ②
                HStack(spacing: NiftySpacing.sm) {
                    livePhotoPill
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
        let isSet = timerSetting > 0
        return Button {
            let options = [0, 3, 10]
            let next = options[(options.firstIndex(of: timerSetting)! + 1) % options.count]
            timerSetting = next
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
                    Text("\(timerSetting)s")
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
        .accessibilityLabel("Self-timer: \(timerSetting == 0 ? "Off" : "\(timerSetting)s")")
    }

    private var livePhotoPill: some View {
        let isActive = currentMode == .live
        return Button {
            // Toggle Live Photo — in real integration wires to AVCapturePhotoSettings
        } label: {
            ZStack {
                Circle()
                    .fill(isActive
                          ? Color.white.opacity(0.20)
                          : Color.white.opacity(0.09))
                    .overlay(
                        Circle().strokeBorder(
                            Color.white.opacity(isActive ? 0.24 : 0.12),
                            lineWidth: 0.5
                        )
                    )
                // SVG spec: centre dot + concentric ring + 4 cardinal dots
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.82), lineWidth: 1.2)
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(.white.opacity(0.82))
                        .frame(width: 4, height: 4)
                    ForEach([(0.0, -7.0), (0.0, 7.0), (-7.0, 0.0), (7.0, 0.0)], id: \.0) { (dx, dy) in
                        Circle()
                            .fill(.white.opacity(0.45))
                            .frame(width: 2, height: 2)
                            .offset(x: dx, y: dy)
                    }
                }
            }
            .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Live Photo \(isActive ? "on" : "off")")
    }

    private var morePill: some View {
        Button {
            // TODO: show overflow tray (aspect ratio, grid overlay, histogram)
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

    // MARK: Film Strip Counter (Zone A centre, Roll Mode only)

    private var filmStripCounter: some View {
        HStack(spacing: NiftySpacing.sm) {
            HStack(spacing: 2) {
                ForEach(0..<9, id: \.self) { i in
                    let used = i < (17 - rollShotsRemaining)
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
        return Text("AE/AF LOCK")
            .font(.system(size: 11, weight: .bold))
            .kerning(0.08 * 11)
            .foregroundStyle(Color(hex: "#E8A020"))
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
        Text("📍 Hongdae · Seoul · golden hour")
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

    // MARK: - Zone C: Preset Bar with Peek Swatches (v1.7)

    private var presetBar: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color(red: 0, green: 0, blue: 0).opacity(0.26))
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    activePreset.accentColor
                        .opacity(0.88)
                        .frame(height: 2)
                }

            if presetBarCollapsed {
                Color.clear.frame(height: 4)
            } else {
                HStack(spacing: 0) {
                    // Accent dot + preset name (17pt/900 per spec wireframe)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(activePreset.accentColor)
                            .frame(width: 9, height: 9)
                        Text(activePreset.name)
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .padding(.leading, NiftySpacing.lg)

                    // Peek swatches — 5 dots representing all presets (v1.7)
                    peekSwatches
                        .padding(.leading, NiftySpacing.md)

                    Spacer()

                    Text("hold")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.46))
                        .padding(.trailing, NiftySpacing.lg)
                }
                .frame(height: 46)
            }
        }
        .frame(height: presetBarCollapsed ? 4 : 46)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: presetBarCollapsed)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        cyclePreset(by: value.translation.width < 0 ? 1 : -1)
                    }
                }
        )
        .onLongPressGesture(minimumDuration: 0.4) {
            withAnimation(.niftySpring) { showPresetPicker = true }
        }
        .onTapGesture {
            if presetBarCollapsed {
                withAnimation(.easeOut(duration: 0.2)) { presetBarCollapsed = false }
            }
        }
    }

    private var peekSwatches: some View {
        HStack(spacing: 12) {
            ForEach(VibePresetUI.defaults) { preset in
                let isActive = preset.id == activePresetIndex
                Circle()
                    .fill(preset.accentColor)
                    .frame(width: isActive ? 12 : 9, height: isActive ? 12 : 9)
                    .opacity(isActive ? 1.0 : 0.50)
                    .overlay(
                        Circle().strokeBorder(
                            .white.opacity(isActive ? 0.38 : 0.14),
                            lineWidth: 0.5
                        )
                    )
                    .animation(.niftyPresetSwitch, value: activePresetIndex)
                    .onTapGesture { selectPreset(preset) }
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
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.13), lineWidth: 1))
            .overlay(alignment: .bottom) {
                Text("▶ LIVE")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(hex: "#E8A020"))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .frame(width: 58, height: 42)
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
        .onLongPressGesture(
            minimumDuration: 0.1,
            pressing: { pressing in
                if currentMode == .clip { handleClipPress(pressing: pressing) }
            },
            perform: {}
        )
    }

    @ViewBuilder
    private var shutterInterior: some View {
        switch currentMode {
        case .still:
            if container.config.features.contains(.soundStamp) {
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
        default:
            EmptyView()
        }
    }

    // MARK: - Sound Stamp Pulse Arcs

    private var soundStampArcs: some View {
        ZStack {
            ForEach([0, 1, 2], id: \.self) { i in
                Circle()
                    .stroke(activePreset.accentColor.opacity([0.55, 0.30, 0.12][i]),
                            lineWidth: CGFloat(1.5 - Double(i) * 0.5))
                    .frame(width: CGFloat(48 + i * 14), height: CGFloat(48 + i * 14))
                    .scaleEffect(soundStampPulse ? 1.0 : 0.6)
                    .opacity(soundStampPulse ? 1.0 : 0.0)
                    .animation(
                        reduceMotion ? .easeOut(duration: 1.0) :
                            .easeOut(duration: 1.5).delay(Double(i) * 0.15),
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

    // MARK: - Gesture Handling

    private func viewfinderGestures(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
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
        withAnimation(.niftyPresetSwitch) { currentMode = newMode }
        showGhostLabel(newMode.ghostText)
        // Dismiss AF lock on mode change
        if afLockActive { dismissAfLock() }
        if newMode == .clip || newMode == .echo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if isRecording { withAnimation { presetBarCollapsed = true } }
            }
        } else {
            withAnimation { presetBarCollapsed = false }
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
    }

    // MARK: - Shutter Actions

    private func handleShutterTap() {
        switch currentMode {
        case .still:
            triggerStillCapture()
        case .live:
            break // tap handled; in real integration calls AVCapturePhotoOutput
        case .echo:
            withAnimation(.niftySpring) {
                isRecording.toggle()
                if !isRecording { presetBarCollapsed = false }
            }
        case .atmosphere:
            break
        case .clip:
            break // hold gesture handles clip
        }
    }

    private func triggerStillCapture() {
        if container.config.features.contains(.soundStamp) {
            withAnimation { soundStampPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { soundStampPulse = false }
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

    private func handleClipPress(pressing: Bool) {
        withAnimation(.niftySpring) { isRecording = pressing }
        if !pressing {
            clipProgress = 0
            clipCountdown = 30
            withAnimation { presetBarCollapsed = false }
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
            }
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
        }
    }
    var ghostText: String {
        switch self {
        case .still:      return "S T I L L"
        case .live:       return "L I V E"
        case .clip:       return "C L I P"
        case .echo:       return "E C H O"
        case .atmosphere: return "A T M O S"
        }
    }
}
