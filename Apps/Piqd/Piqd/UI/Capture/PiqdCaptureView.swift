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
    /// Piqd v0.5 — drafts tray sheet presentation (FR-SNAP-DRAFT-03).
    @State private var showDraftsTray = false
    // Piqd v0.6 — gear-icon action menu + Settings navigation.
    @State private var showSettingsMenu = false
    @State private var showSettings = false
    // Mirror of `container.firstRollWarningGate.isPresented`. Held as @State
    // because cross-@Observable property observation through `container` was
    // unreliable for sheet binding under XCUITest.
    @State private var showFirstRollWarning = false
    @State private var selectorIdleCollapseTask: Task<Void, Never>?
    @State private var shutterState: ShutterState = .idle
    @State private var sequenceFrameIndex: Int = 0
    @State private var clipProgress: Double = 0
    @State private var clipStartedAt: CFAbsoluteTime?
    @State private var pressStartedAt: CFAbsoluteTime?
    @State private var stillLongPressTask: Task<Void, Never>?
    @State private var clipDwellTask: Task<Void, Never>?
    @State private var showSequenceInterruptedToast = false

    /// Dual sub-mode toggle. Persisted across launches in UserDefaults("piqd").
    /// Only consulted when activeFormat == .dual.
    @State private var dualMediaKind: DualMediaKind = {
        let raw = UserDefaults(suiteName: "piqd")?.string(forKey: "piqd.dualMediaKind") ?? DualMediaKind.video.rawValue
        return DualMediaKind(rawValue: raw) ?? .video
    }()

    // Piqd v0.4 — Layer 1 chrome state.
    @State private var layerStore: LayerStore = {
        let env = ProcessInfo.processInfo.environment
        // Test override — `PIQD_TEST_LAYER1_IDLE_SECONDS=<float>` lets a UI test pick
        // a long interval for tests that exercise post-reveal chrome (where auto-retreat
        // mid-test is noise) and a short interval for the auto-retreat test itself.
        if let raw = env["PIQD_TEST_LAYER1_IDLE_SECONDS"], let parsed = TimeInterval(raw) {
            return LayerStore(idleInterval: parsed)
        }
        let interval = env["UI_TEST_MODE"] == "1"
            ? PiqdTokens.Layer.idleRetreatSecondsUITest
            : PiqdTokens.Layer.idleRetreatSeconds
        return LayerStore(idleInterval: interval)
    }()
    @State private var currentZoom: ZoomLevel = .wide
    @State private var availableZoomLevels: [ZoomLevel] = [.wide]
    @State private var pinchBaseFactor: Double = 1.0
    @State private var lastPinchFactor: Double = 1.0
    @State private var isFlipping: Bool = false
    @State private var flipRotation: Double = 0

    private var modeStore: ModeStore { container.modeStore }
    private var dev: DevSettingsStore { container.devSettings }
    private var activity: CaptureActivityStore { container.captureActivity }
    /// Active aspect ratio for both preview crop and capture-time crop. v0.4 — driven
    /// by the Layer 1 ratio pill in Snap Still; Sequence/Clip/Dual force 9:16; Roll = 4:3.
    private var aspect: AspectRatio {
        modeStore.effectiveAspectRatio(for: modeStore.mode, format: activeFormat)
    }

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

            // Piqd v0.4 — Layer 1 chrome. Sits above preview, below format
            // selector + shutter so those controls remain interactive when revealed.
            // Piqd v0.6 — also mounted in Roll mode so flip + gear are reachable.
            // Slot internals self-gate: zoom/ratio/draftsBadge are Snap-only;
            // flip + gear appear in both modes; in Roll the top-right stack
            // is offset to sit below the always-visible FilmCounter.
            Layer1ChromeView(
                    isRevealed: layerStore.state == .revealed,
                    topRight: {
                        // Snap-only stack: flip + gear inside Layer 1 chrome.
                        // FlipButton hidden in Dual (FR-SNAP-FLIP-04). Roll
                        // renders these elsewhere as always-visible siblings
                        // (see `rollAlwaysVisibleChrome`).
                        if modeStore.mode == .snap {
                            VStack(spacing: 12) {
                                if activeFormat != .dual {
                                    FlipButtonView(onTap: handleFlip)
                                        .opacity(activity.isCapturing ? 0.4 : 1.0)
                                        .allowsHitTesting(!activity.isCapturing)
                                }
                                GearIconView(onTap: { showSettingsMenu = true })
                                    .opacity(activity.isCapturing ? 0.4 : 1.0)
                                    .allowsHitTesting(!activity.isCapturing)
                            }
                        }
                    },
                    zoom: {
                        // Available in both modes (UIUX §4.2 — Roll Layer 1 includes
                        // zoom pill at same Y as Snap). Hidden in Snap-Dual where the
                        // sub-toggle replaces the pill. Roll's `activeFormat` is
                        // always `.still`, so the Dual check is vacuously true there.
                        if activeFormat != .dual {
                            ZoomPillView(
                                levels: availableZoomLevels,
                                current: currentZoom,
                                onSelect: { selectZoomLevel($0) }
                            )
                            .opacity(isZoomLocked ? 0.4 : 1.0)
                            .allowsHitTesting(!isZoomLocked)
                        }
                    },
                    ratio: {
                        // Snap-only. Hidden in Dual; locked at 9:16 in Sequence/Clip per FR-SNAP-RATIO-04.
                        if modeStore.mode == .snap && activeFormat != .dual {
                            AspectRatioPillView(
                                current: modeStore.effectiveAspectRatio(for: modeStore.mode, format: activeFormat),
                                isLocked: activeFormat != .still,
                                onTap: {
                                    modeStore.cycleSnapAspectRatio()
                                    layerStore.interact()
                                }
                            )
                        }
                    },
                    draftsBadge: {
                        // Piqd v0.5 — Snap Mode only; the badge view itself returns
                        // EmptyView when state == .hidden, so an empty drafts list
                        // also renders nothing.
                        if modeStore.mode == .snap {
                            UnsentBadgeView(
                                state: container.draftsBindings.badgeState,
                                onTap: {
                                    showDraftsTray = true
                                    layerStore.interact()
                                }
                            )
                        }
                    }
            )
            // No `.ignoresSafeArea()` — keeps the chrome inside the safe area so its
            // bottom-padding math shares a baseline with `shutterControl` below.

            // Tap-outside collapse catcher — sits above the preview but below the selector
            // + shutter so taps on those controls route normally. Any other tap collapses.
            if showFormatSelector {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { collapseFormatSelector(reason: "tapOutside") }
                    .allowsHitTesting(true)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            VStack {
                topHUD
                    .padding(.horizontal, 16)
                    .padding(.top, PiqdTokens.Layout.statusBarOffset)
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

                if modeStore.mode == .snap && activeFormat == .dual && !activity.isCapturing {
                    dualMediaKindToggle
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                // Piqd v0.4 — Subject guidance pill. Snap-only, hidden during recording
                // and when the format selector is open (which would obscure it visually).
                if dev.subjectGuidanceEnabled
                    && modeStore.mode == .snap
                    && !activity.isCapturing
                    && !showFormatSelector {
                    SubjectGuidancePillView(detector: container.subjectGuidance)
                        .padding(.bottom, 12)
                }

                shutterControl
                    .padding(.bottom, 48)
            }

            // In UI_TEST_MODE we suppress the error banner — AVCapture on simulator will
            // always fail `reconfigureSession`, and the banner would otherwise cover the
            // format selector (FR-SNAP-* tests rely on tapping selector segments).
            if let errorText, ProcessInfo.processInfo.environment["UI_TEST_MODE"] != "1" {
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
                    // Piqd v0.4 — XCUITest gesture-synthesis doesn't reach SwiftUI's
                    // simultaneousGesture on the viewfinder catcher, so the chrome can't
                    // be revealed by tapping the catcher in tests. This hidden button
                    // calls `layerStore.tap()` directly. Mirrors the long-hold pattern.
                    Button("layer1.tap") {
                        if modeStore.mode == .snap && !activity.isCapturing {
                            layerStore.tap()
                        }
                    }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .opacity(0.001)
                        .accessibilityIdentifier("piqd-layer1-tap-test")
                    // Piqd v0.5 — seeds a deterministic Snap-mode drafts row without
                    // exercising the camera pipeline. Tap repeatedly for multiple rows.
                    Button("drafts.fake-capture") {
                        Task {
                            let asset = Asset(
                                type: .still,
                                capturedAt: Date(),
                                duration: nil,
                                isPrivate: false
                            )
                            await container.draftsBindings.enroll(asset: asset)
                        }
                    }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .opacity(0.001)
                        .accessibilityIdentifier("piqd-drafts-fake-capture")
                    // Diagnostic hook: bypass handleShutter and call the gate
                    // directly. Lets the warning test isolate sheet-presentation
                    // issues from shutter-routing issues.
                    // Piqd v0.6 — XCUITest hook bypassing both Layer 1 reveal
                    // and the menu sheet. Goes straight to PiqdSettingsView.
                    // The action-menu intermediary is exercised via manual
                    // checklist (sheet presentation is racy in XCUITest).
                    Spacer()
                }
                .padding(.top, 140)
                .allowsHitTesting(!activity.isCapturing)
            }

            // UI_TEST_MODE capture-lock mirror. Existence of `piqd.captureLock` indicates
            // that the app is in a locked state (any format recording/firing).
            if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" && activity.isCapturing {
                VStack {
                    Text("lock")
                        .font(.system(size: 1))
                        .foregroundStyle(.white.opacity(0.01))
                        .accessibilityIdentifier("piqd.captureLock")
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // UI_TEST_MODE shutter state mirror. A Text element keyed by
            // (activeFormat.state) — existence polling on identifier avoids iOS 26
            // accessibilityValue caching. We use `.id(...)` to force SwiftUI to
            // rebuild the element whenever the tuple changes.
            if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
                let mirrorState: ShutterState = isShutterDisabled ? .disabled : shutterState
                let mirrorKey = "\(activeFormat.rawValue).\(mirrorState.rawValue)"
                VStack {
                    Text(mirrorKey)
                        .font(.system(size: 1))
                        .foregroundStyle(.white.opacity(0.01))
                        .accessibilityIdentifier("piqd.shutter.state.\(mirrorKey)")
                        .id(mirrorKey)
                    Spacer()
                }
                .allowsHitTesting(false)
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
        .task(id: container.onboardingCoordinator.isComplete) {
            // Defer camera bring-up until onboarding completes. Otherwise the
            // permission prompt fires during O0 (blocking the Continue tap)
            // and PiqdCaptureView's preview competes with O1/O2's own
            // preview layers attached to the same session.
            guard container.onboardingCoordinator.isComplete else { return }
            await startPreview()
            refreshAvailableZoomLevels()
            container.captureAdapter.setBacklightCorrection(enabled: dev.backlightCorrectionEnabled)
            if ProcessInfo.processInfo.environment["PIQD_DEV_OPEN_SETTINGS_ON_LAUNCH"] == "1" {
                showSettings = true
            }
        }
        .task {
            // Piqd v0.4 — start the invisible-level sensor for the lifetime of the capture
            // view. `MotionMonitor` is idempotent on start/stop.
            container.motionMonitor.start()
            container.vibeClassifier.start()
            // Route primary preview frames into the subject-guidance detector. The
            // detector throttles internally to ≤2fps and early-returns when stopped,
            // so it's safe to leave the sink installed permanently.
            container.captureAdapter.setPrimaryFrameSink { buffer in
                // Portrait-locked viewfinder: back camera buffer is rotated 90° CW from
                // the user's view (`.right`); front is mirrored (`.leftMirrored`).
                let position = container.captureAdapter.currentCameraPosition()
                let orientation: CGImagePropertyOrientation = position == .front ? .leftMirrored : .right
                container.subjectGuidance.process(buffer, orientation: orientation)
            }
        }
        .onDisappear {
            container.motionMonitor.stop()
            container.vibeClassifier.stop()
            container.captureAdapter.setPrimaryFrameSink(nil)
        }
        .onChange(of: activity.isCapturing) { _, isCapturing in
            // 30Hz idle / 5Hz during recording (UIUX §2.10).
            container.motionMonitor.setRecording(isCapturing)
            // Subject guidance is paused outright during any recording window
            // (Sequence/Clip/Dual). UIUX §2.11 — no pill mid-capture.
            if isCapturing {
                container.subjectGuidance.stop()
                // Vibe classifier also pauses mid-capture per UIUX §2.12 — the glyph
                // shouldn't pulse over the safe-render border.
                container.vibeClassifier.stop()
            } else {
                if modeStore.mode == .snap {
                    container.subjectGuidance.start()
                }
                container.vibeClassifier.start()
            }
        }
        .task(id: modeStore.mode) {
            // Subject guidance is Snap-only.
            if modeStore.mode == .snap && !activity.isCapturing {
                container.subjectGuidance.start()
            } else {
                container.subjectGuidance.stop()
            }
        }
        .task(id: modeStore.mode) {
            await refreshRollCounter()
            await applyModeToSession(animated: true)
            // Leaving Snap → collapse selector silently (Roll has no selector).
            if modeStore.mode != .snap { showFormatSelector = false }
        }
        .onChange(of: dev.dualLayout) { _, newLayout in
            container.captureAdapter.setDualLayout(newLayout)
        }
        .onChange(of: dev.backlightCorrectionEnabled) { _, enabled in
            container.captureAdapter.setBacklightCorrection(enabled: enabled)
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
        // Piqd v0.5 — drafts tray bottom sheet (PRD §5.5).
        .sheet(isPresented: $showDraftsTray, onDismiss: {
            // Restart Layer 1 idle clock so chrome auto-retreats after the sheet closes.
            layerStore.interact()
        }) {
            DraftsTraySheetView(
                bindings: container.draftsBindings,
                exporter: container.photoLibraryExporter,
                shareHandoff: container.shareHandoff,
                resolveURL: { id, type in
                    await container.vaultRepository.snapAssetURL(id: id, type: type)
                }
            )
        }
        // Piqd v0.6 — first-Roll storage warning (FR-STORAGE-08).
        // Non-interactive-dismiss; the only exit is the "Got it" button.
        .sheet(isPresented: $showFirstRollWarning, onDismiss: {
            // Acknowledge if dismissed via "Got it" — the sheet view sets
            // `gate.acknowledge()` which flips our local state via the
            // `.onChange` below.
        }) {
            FirstRollStorageWarningSheet(
                gate: container.firstRollWarningGate,
                onAcknowledge: { showFirstRollWarning = false }
            )
        }
        // Piqd v0.6 — gear-icon action menu. UIUX §8: "Settings" + "Inbox"
        // (Inbox disabled until v0.7). Custom sheet (vs. confirmationDialog)
        // because confirmationDialog presentation was racy under XCUITest on
        // iOS 26.
        .sheet(isPresented: $showSettingsMenu) {
            VStack(spacing: 0) {
                Button {
                    showSettingsMenu = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        showSettings = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "gearshape").frame(width: 24)
                        Text("Settings")
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("piqd.layer1.gear.menu.settings")

                Divider()

                HStack {
                    Image(systemName: "tray").frame(width: 24)
                    Text("Inbox (coming soon)")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("piqd.layer1.gear.menu.inbox")

                Spacer()
            }
            .presentationDetents([.height(160)])
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                PiqdSettingsView(container: container)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }
                                .accessibilityIdentifier("piqd.settings.done")
                        }
                    }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var previewWithLetterbox: some View {
        GeometryReader { geo in
            let cropped = letterboxRect(in: geo.size, ratio: aspect.ratio)
            ZStack {
                CameraPreviewView(
                    session: container.captureSession,
                    onPreviewLayerReady: { layer in
                        container.captureAdapter.attachPrimaryPreview(layer)
                    }
                )
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

                // Piqd v0.4 — invisible level. Centered in the cropped viewfinder, mode-
                // agnostic per UIUX §2.10. The line itself is `accessibilityHidden` and
                // `allowsHitTesting(false)`, so it never blocks taps or pinches.
                if dev.levelIndicatorEnabled {
                    LevelIndicatorView(monitor: container.motionMonitor)
                        .frame(width: cropped.width, height: cropped.height)
                        .position(x: cropped.midX, y: cropped.midY)
                }

                // Piqd v0.4 — Vibe-hint glyph. Snap-only Layer 0 element (always visible
                // when classifier emits `.social` and not recording). UIUX §2.12 — bottom-
                // left of the viewfinder, 16pt.
                if dev.vibeHintEnabled
                    && modeStore.mode == .snap
                    && !activity.isCapturing {
                    VibeHintView(classifier: container.vibeClassifier)
                        .position(
                            x: cropped.minX + PiqdTokens.Spacing.md + 8,
                            y: cropped.maxY - PiqdTokens.Spacing.md - 8
                        )
                }

                // Piqd v0.4 — gesture catcher sized to the cropped preview only, so shutter
                // and bottom-area controls are never intercepted. Snap-only — in Roll the
                // gear/flip are rendered always-visible as siblings of Layer1ChromeView
                // so no tap-to-reveal is needed there. (Re-enabling the catcher in Roll
                // double-fires `layerStore.tap()` when XCUITest taps the layer1-tap-test
                // hook button, retreating Layer 1 immediately.)
                if modeStore.mode == .snap && !activity.isCapturing && !showFormatSelector {
                    Color.clear
                        .frame(width: cropped.width, height: cropped.height * 0.7)
                        .position(x: cropped.midX, y: cropped.minY + cropped.height * 0.35)
                        .contentShape(Rectangle())
                        .simultaneousGesture(viewfinderTapGesture)
                        .simultaneousGesture(pinchGesture)
                        // The accessibility frame for a Color.clear catcher is reported
                        // at parent bounds, which would shadow Layer 1 leaves for
                        // `isHittable` queries. Hide it from the a11y tree; XCUITest
                        // drives the chrome via `piqd-layer1-tap-test` instead.
                        .accessibilityHidden(true)
                }
            }
        }
        .ignoresSafeArea()
        // FR-SNAP-FLIP-02 — 200ms horizontal 3D flip animation on the preview.
        .rotation3DEffect(.degrees(flipRotation), axis: (x: 0, y: 1, z: 0))
    }

    // MARK: - Piqd v0.4 — Layer 1 gestures

    private var isZoomLocked: Bool {
        // FR-SNAP-ZOOM-05 — pinch and pill ignored during Sequence capture.
        modeStore.mode == .snap && activeFormat == .sequence && activity.isCapturing
    }

    private var viewfinderTapGesture: some Gesture {
        TapGesture().onEnded { _ in
            // Don't intercept taps during capture — Clip/Dual tap-toggle relies on the
            // shutter receiving the second tap unobstructed (FR-CLIP-04 / Dual analogue).
            // Snap-only: Roll's gear/flip render outside Layer 1 (always-visible),
            // so Roll-mode viewfinder taps need do nothing. (Re-enabling Roll here
            // also breaks XCUITest's `piqd-layer1-tap-test` button — both paths
            // would call `layerStore.tap()` simultaneously and double-toggle.)
            guard modeStore.mode == .snap, !showFormatSelector, !activity.isCapturing else { return }
            layerStore.tap()
        }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Piqd v0.6 — relaxed Snap-only gate to match UIUX §4.2
                // (Roll Layer 1 includes the zoom pill at the same Y as Snap).
                guard !isZoomLocked, !activity.isCapturing else { return }
                if pinchBaseFactor == 0 { pinchBaseFactor = max(1.0, currentAdapterZoom()) }
                let target = clampedZoomFactor(pinchBaseFactor * Double(value))
                applyContinuousZoom(target)
                checkLensBoundaryCrossing(from: lastPinchFactor, to: target)
                lastPinchFactor = target
                layerStore.interact()
            }
            .onEnded { _ in
                pinchBaseFactor = currentAdapterZoom()
                lastPinchFactor = pinchBaseFactor
            }
    }

    private func currentAdapterZoom() -> Double {
        container.captureAdapter.currentZoomFactor()
    }

    private func clampedZoomFactor(_ factor: Double) -> Double {
        // Lens-swap model: each physical lens has its own native 1.0×; pinch is a
        // digital ramp on the currently-active lens, NOT a cross-lens zoom. Min is
        // always 1.0 (lens's natural state). Max:
        //   • Front: cap at 2× per FR-SNAP-ZOOM-04 (front is single-lens, digital crop)
        //   • Back: 2× when on the wide lens (pill's "2×" is digital crop on wide);
        //          1× when on UW so pinch can't accidentally cross into the wide range
        //          (use the pill to switch lenses).
        let position = container.captureAdapter.currentZoomLevel()
        let maxF: Double
        if container.captureAdapter.currentCameraPosition() == .front {
            maxF = 2.0
        } else {
            switch position {
            case .ultraWide: maxF = 1.0    // pinch stays within UW's optical range
            case .wide:      maxF = 2.0    // wide → digital crop up to "2×" pill mark
            case .telephoto: maxF = 2.0    // already at 2× crop on wide; pinch is no-op
            }
        }
        return max(1.0, min(factor, maxF))
    }

    private func applyContinuousZoom(_ factor: Double) {
        do { try container.captureAdapter.setZoomContinuous(factor) }
        catch { /* lock contention — drop frame */ }
        currentZoom = nearestLevel(for: factor)
    }

    private func nearestLevel(for factor: Double) -> ZoomLevel {
        let candidates = availableZoomLevels
        return candidates.min(by: { abs($0.factor - factor) < abs($1.factor - factor) }) ?? .wide
    }

    private func checkLensBoundaryCrossing(from previous: Double, to next: Double) {
        let boundaries = container.captureAdapter.lensSwitchOverFactors()
        for b in boundaries {
            if (previous < b && next >= b) || (previous > b && next <= b) {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
            }
        }
    }

    private func selectZoomLevel(_ level: ZoomLevel) {
        guard !isZoomLocked, availableZoomLevels.contains(level) else { return }
        // Optimistic UI update — pill highlights immediately, lens swap completes ~150ms later.
        currentZoom = level
        pinchBaseFactor = 1.0
        lastPinchFactor = 1.0
        layerStore.interact()
        Task {
            do { try await container.captureAdapter.setZoom(level) }
            catch { /* swap failed — leave pill state alone, user can retry */ }
        }
    }

    private func refreshAvailableZoomLevels() {
        availableZoomLevels = container.captureAdapter.availableZoomLevels()
        if !availableZoomLevels.contains(currentZoom) {
            currentZoom = .wide
        }
    }

    // MARK: - Piqd v0.4 — Flip (FR-SNAP-FLIP-01..05)

    private func handleFlip() {
        guard !activity.isCapturing, !isFlipping else { return }
        guard activeFormat != .dual else { return }   // FR-SNAP-FLIP-04
        layerStore.interact()
        isFlipping = true
        // 3D flip animation runs in parallel with the actual session input swap.
        // Animation duration = 200ms per FR-SNAP-FLIP-02; matches Apple Camera.
        withAnimation(.easeInOut(duration: 0.20)) {
            flipRotation += 180
        }
        Task {
            do {
                try await container.captureAdapter.switchCamera()
                // FR-SNAP-FLIP-03 — zoom resets to 1× on flip. Refresh pill (front
                // returns [.wide] only) and snap zoom factor back to 1×.
                refreshAvailableZoomLevels()
                currentZoom = .wide
                pinchBaseFactor = 1.0
                lastPinchFactor = 1.0
                try? await container.captureAdapter.setZoom(.wide)
            } catch {
                // Swap failed — animation already ran; leave UI as-is, user can retry.
            }
            isFlipping = false
        }
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
        HStack(alignment: .top) {
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
                // Roll top-right cluster: FilmCounter on top, Flip + Gear
                // below (always visible — no Layer 1 reveal needed in Roll).
                VStack(alignment: .trailing, spacing: 12) {
                    FilmCounterView(used: rollUsed, limit: rollLimit)
                    FlipButtonView(onTap: handleFlip)
                        .opacity(activity.isCapturing ? 0.4 : 1.0)
                        .allowsHitTesting(!activity.isCapturing)
                    GearIconView(onTap: { showSettingsMenu = true })
                        .opacity(activity.isCapturing ? 0.4 : 1.0)
                        .allowsHitTesting(!activity.isCapturing)
                }
            }
        }
    }

    /// Dual sub-mode segmented control — visible only when activeFormat == .dual and
    /// the capture pipeline is idle. Switching reconfigures the session (photo outputs
    /// vs movie outputs).
    @ViewBuilder
    private var dualMediaKindToggle: some View {
        Picker("Dual media", selection: $dualMediaKind) {
            Text("Still").tag(DualMediaKind.still)
            Text("Video").tag(DualMediaKind.video)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.black.opacity(0.4), in: Capsule())
        .accessibilityIdentifier("piqd.dual.kind")
        .onChange(of: dualMediaKind) { _, newKind in
            UserDefaults(suiteName: "piqd")?.set(newKind.rawValue, forKey: "piqd.dualMediaKind")
            guard ProcessInfo.processInfo.environment["UI_TEST_MODE"] != "1" else { return }
            Task {
                do {
                    try await container.captureUseCase.configure(
                        for: .dual,
                        config: container.config,
                        dualKind: newKind,
                        dualLayout: dev.dualLayout
                    )
                } catch {
                    errorText = "dual switch failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Shutter + gesture surface. Wraps ShutterButtonView in a DragGesture for swipe-up
    /// (Snap-only) and a long-press for Still→selector (Snap-only) / Clip & Dual press-hold.
    @ViewBuilder
    private var shutterControl: some View {
        let disabled = isShutterDisabled
        let effectiveState: ShutterState = disabled ? .disabled : shutterState
        let a11yValue = "\(activeFormat.rawValue).\(effectiveState.rawValue)"
        ZStack {
            ShutterButtonView(
                format: activeFormat,
                state: effectiveState,
                progress: clipProgress
            )
            .contentShape(Circle())
            .allowsHitTesting(!disabled)
            .gesture(shutterGesture)
            .accessibilityIdentifier("piqd.shutter")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(a11yValue)
            // Drives `piqd.shutter`'s `isEnabled` in XCUITest (v0.1 UI9 relies on this).
            .disabled(disabled)

            if let counter = sequenceCounterText {
                VStack {
                    Spacer()
                    Text(counter)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("piqd.sequenceFrameCounter")
                        .offset(y: 30)
                }
                .allowsHitTesting(false)
            }
        }
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
        // If a dwell/press is already tracking, watch for swipe-up to cancel a pending
        // Clip/Dual dwell (swipe intent supersedes press-hold intent).
        if pressStartedAt != nil {
            if value.translation.height <= -20 {
                clipDwellTask?.cancel()
                clipDwellTask = nil
            }
            return
        }
        pressStartedAt = CFAbsoluteTimeGetCurrent()

        // Clip / Dual-Video use tap-toggle (not press-hold). Start/stop is handled in
        // onShutterTouchEnded; touch-down only arms the long-press Still branch below.
        // Dual-Still falls through to a regular tap (handled like .still).
        if modeStore.mode == .snap &&
            (activeFormat == .clip || (activeFormat == .dual && dualMediaKind == .video)) {
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
        clipDwellTask?.cancel()
        clipDwellTask = nil

        let elapsed = startedAt.map { CFAbsoluteTimeGetCurrent() - $0 } ?? 0
        let dy = value.translation.height

        // Swipe-up ≥40pt (Snap-only) → present selector. UI19 asserts Roll does nothing.
        if modeStore.mode == .snap && dy <= -40 {
            // Safety: if a Clip/Dual recording slipped through (e.g. dwell fired right
            // before the swipe passed threshold), end it without persisting so the
            // selector can open cleanly.
            if activity.isCapturing &&
               (activity.reason == .clip || activity.reason == .dual) {
                activity.endCapture()
                shutterState = .idle
                clipStartedAt = nil
                clipProgress = 0
            }
            presentFormatSelector()
            return
        }

        // Clip / Dual-Video tap-toggle: tap to start; tap again to stop early.
        // Ceiling auto-stop still fires via the progress-tick task in beginVideoRecording.
        if modeStore.mode == .snap &&
            (activeFormat == .clip || (activeFormat == .dual && dualMediaKind == .video)) {
            if activity.isCapturing {
                Task { await endVideoRecording(autoStopped: false) }
            } else {
                Task { await beginVideoRecording(format: activeFormat) }
            }
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
        layerStore.enterFormatSelector()
        armSelectorIdleCollapse()
    }

    private func collapseFormatSelector(reason: String) {
        guard showFormatSelector else { return }
        selectorIdleCollapseTask?.cancel()
        selectorIdleCollapseTask = nil
        withAnimation(.easeIn(duration: 0.15)) { showFormatSelector = false }
        layerStore.exitFormatSelector()
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
        let previous = modeStore.snapFormat
        modeStore.setSnapFormat(format)
        collapseFormatSelector(reason: "picked")
        guard format != previous else { return }
        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" { return }
        Task {
            do {
                try await container.captureUseCase.configure(
                    for: format,
                    config: container.config,
                    dualKind: dualMediaKind,
                    dualLayout: dev.dualLayout
                )
            } catch {
                errorText = "format switch failed: \(error.localizedDescription)"
            }
        }
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
            // If the persisted Snap format is not .still (e.g. Clip or Sequence from last
            // launch), the session is currently photo-output from startPreview. Align the
            // session outputs with the persisted format so tap-hold recording finds
            // AVCaptureMovieFileOutput attached. pickFormat() skips this on relaunch because
            // format == previous, so we do it here at mount.
            if modeStore.mode == .snap, activeFormat != .still,
               ProcessInfo.processInfo.environment["UI_TEST_MODE"] != "1" {
                try await container.captureUseCase.configure(
                    for: activeFormat,
                    config: container.config,
                    dualKind: dualMediaKind,
                    dualLayout: dev.dualLayout
                )
            }
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
            case .clip:
                // Should never be reached — Clip is gesture-driven (tap-toggle).
                break
            case .dual:
                // Dual-Still falls through to the same captureStill() path; the adapter's
                // dual photo session fans out to both photo outputs internally.
                if dualMediaKind == .still {
                    await captureStill()
                }
            }
            return
        }

        // Roll — always Still, gated by the daily counter. Piqd v0.6 also
        // gates the FIRST tap on the storage-warning sheet (FR-STORAGE-08);
        // the sheet appears, the in-flight tap is consumed, and the user
        // taps shutter again to capture.
        if modeStore.mode == .roll {
            if container.firstRollWarningGate.interceptShutterTap(mode: .roll) {
                showFirstRollWarning = true
                return
            }
            await captureRollStill()
        }
    }

    /// Piqd v0.5 — enroll a Snap-mode capture in the drafts tray. No-op for Roll.
    /// Called from every Snap completion site (Still / Sequence / Clip / Dual) after
    /// the vault write returns. Best-effort: a drafts insert failure must not
    /// surface to the user; the asset bytes are already safe in the vault.
    private func enrollDraftIfNeeded(asset: Asset, mode: CaptureMode) async {
        guard DraftEnrollmentPolicy.shouldEnroll(mode: mode) else { return }
        // `draftsBindings.enroll` writes through to the GRDB repo AND updates
        // the in-memory store + bumps `now`, so the unsent badge appears within
        // one render frame.
        await container.draftsBindings.enroll(asset: asset)
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
            return
        }

        do {
            let asset = try await container.captureUseCase.captureAsset(
                preset: nil,
                aspectRatio: aspect,
                encoder: container.imageEncoder,
                locked: false
            )
            await enrollDraftIfNeeded(asset: asset, mode: .snap)
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

    /// Sequence tap: fires `dev.sequenceFrameCount` frames at `dev.sequenceIntervalMs` through
    /// `SequenceCaptureController`, assembles them into a looping 9:16 MP4 via
    /// `StoryEngine.assembleSequence`, and writes a `.sequence` vault row with
    /// `sequenceAssembledURL` populated. In UI_TEST_MODE writes a single SEQ stub row;
    /// on `forceSequenceAssemblyFailure` writes nothing.
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
        let intervalMs = dev.sequenceIntervalMs
        let interval = Double(intervalMs) / 1000.0

        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
            // Sim path — legacy sleep loop so UI tests see the counter animate.
            for i in 1...frames {
                sequenceFrameIndex = i
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
            }
            guard !dev.forceSequenceAssemblyFailure else { return }
            await persistTestStub(type: .sequence, duration: Double(frames) * interval)
            return
        }

        // Cosmetic per-frame counter — not driven by the controller's internal ticker, but
        // close enough for the UI (counter is a 1…N overlay with no timing contract).
        let counterTask = Task { @MainActor in
            for i in 1...frames {
                sequenceFrameIndex = i
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
            }
        }
        defer { counterTask.cancel() }

        let controller = SequenceCaptureController(
            capturer: container.sequenceFrameCapturer,
            ticker: container.makeSequenceTicker(),
            frameCount: frames,
            intervalMs: intervalMs
        )
        controller.tap(zoom: 0)  // 0 → skip zoom application (see AVCaptureAdapter.captureFrame)
        let outcome = await controller.outcome()

        switch outcome {
        case .interrupted:
            errorText = "sequence interrupted"
            return
        case .completed(let urls, _):
            guard !dev.forceSequenceAssemblyFailure else {
                for u in urls { try? FileManager.default.removeItem(at: u) }
                return
            }
            await assembleAndPersistSequence(frameURLs: urls, frameDurationSeconds: interval)
        }
    }

    /// Composes captured frames into an MP4 via StoryEngine, then writes the `.sequence` vault
    /// row. Always deletes the per-frame temp files, whether assembly succeeded or not.
    private func assembleAndPersistSequence(frameURLs: [URL], frameDurationSeconds: Double) async {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sequence-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        defer {
            for u in frameURLs { try? FileManager.default.removeItem(at: u) }
        }
        do {
            let strip = try await container.storyEngine.assembleSequence(
                frameURLs: frameURLs,
                outputURL: outputURL,
                frameDurationSeconds: frameDurationSeconds
            )
            let asset = Asset(
                type: .sequence,
                capturedAt: Date(),
                duration: strip.durationSeconds,
                sequenceAssembledURL: strip.assembledVideoURL
            )
            try await container.vaultManager.saveVideoFile(asset, sourceURL: strip.assembledVideoURL)
            // Piqd v0.5 — Sequence is Snap-only (PRD §5.4); enroll once shareReady is implied
            // by `assembleSequence` returning successfully.
            await enrollDraftIfNeeded(asset: asset, mode: .snap)
            // Create a Moment wrapping the sequence asset so it surfaces in the vault grid.
            // CaptureMomentUseCase's still path runs classification/ambient/geocode/merge — none
            // of that applies to a pre-assembled sequence MP4 here, so we stamp a minimal
            // moment directly. Matches the shape of persistTestStub.
            let df = DateFormatter()
            df.dateFormat = "EEEE"
            let moment = Moment(
                label: df.string(from: asset.capturedAt),
                assets: [asset],
                centroid: GPSCoordinate(latitude: 0, longitude: 0),
                startTime: asset.capturedAt,
                endTime: asset.capturedAt,
                heroAssetID: asset.id
            )
            try await container.graphManager.saveMoment(moment)
            NotificationCenter.default.post(name: .niftyMomentCaptured, object: nil)
            withAnimation(.easeOut(duration: 0.15)) { flashAssetID = asset.id.uuidString }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeIn(duration: 0.15)) { flashAssetID = nil }
        } catch {
            errorText = "sequence assembly failed: \(error.localizedDescription)"
        }
    }

    /// Press-hold start for Clip/Dual. Opens a CaptureActivity, arms the ceiling auto-stop,
    /// and (outside UI_TEST_MODE) calls `captureUseCase.startVideoRecording` which attaches
    /// `AVCaptureMovieFileOutput` and begins writing to a temp `.mov`. Dual is intentionally
    /// not wired yet — it needs `DualMovieRecorder` / `DualCompositor` concretes plus
    /// `.dualCamera` in AppConfig.piqd. The format-selector's `configure(for: .dual)` already
    /// throws `dualCamUnavailable`, so we should not reach this method with `format == .dual`
    /// in production, but UI_TEST_MODE still uses the stub path below.
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

        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" { return }

        // Clip and Dual both drive the same .clip recording path on the adapter.
        // For Dual, the adapter fans out to two AVCaptureMovieFileOutputs internally
        // (set up by `configure(for: .dual)`); the companion MOV URL is retained on the
        // adapter for Stage B's PIP compositor.
        do {
            try await container.captureUseCase.startVideoRecording(mode: .clip, config: container.config)
        } catch {
            errorText = "\(format == .dual ? "dual" : "clip") start failed: \(error.localizedDescription)"
            activity.endCapture()
            shutterState = .idle
            clipStartedAt = nil
        }
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
        guard reason == .clip || reason == .dual else { return }

        // AVCaptureMovieFileOutput throws -11805 "Cannot Record" if stopped before ~0.5s of
        // frames are written (seen on-device with brief taps). Hold here until the recording
        // has had enough wall-clock to produce a valid MP4. The 0.6s floor is conservative.
        let minRecordingSeconds: Double = 0.6
        if elapsed < minRecordingSeconds {
            let deficit = minRecordingSeconds - elapsed
            try? await Task.sleep(nanoseconds: UInt64(deficit * 1_000_000_000))
        }

        do {
            let asset = try await container.captureUseCase.stopVideoRecording(config: container.config)
            // Piqd v0.5 — Clip + Dual are Snap-only formats (PRD §5.4); the only path that
            // reaches this completion is a Snap-mode recording.
            await enrollDraftIfNeeded(asset: asset, mode: .snap)
            withAnimation(.easeOut(duration: 0.15)) { flashAssetID = asset.id.uuidString }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeIn(duration: 0.15)) { flashAssetID = nil }
        } catch {
            errorText = "clip save failed: \(error.localizedDescription)"
        }
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
        // Piqd v0.5 — UI-test stubs respect the same enrollment rule as live captures.
        await enrollDraftIfNeeded(asset: asset, mode: locked ? .roll : .snap)
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
