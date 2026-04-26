# Piqd v0.4 — Pre-shutter Layer 1 Chrome

# Zoom Pill · Flip · Ratio Toggle · Invisible Level · Subject Guidance · Backlight Correction · Vibe Hint · Layer 0/1 Auto-retreat

_Parent plan: [piqd_interim_version_plan.md](piqd_interim_version_plan.md)_
_Reference: piqd_PRD_v1.1.md §5.4 (Layered chrome, Zoom, Ratio, Flip), §7 (Pre-Shutter System) · piqd_SRS_v1.0.md §4.3.4 (Pre-Shutter Features) · piqd_UIUX_Spec_v1.0.md §2.10–§2.12 (Level, Guidance, Vibe), §3 (Layer system / auto-retreat)_
_Status: ⬜ Pending — kickoff 2026-04-24_

---

## 1. Purpose

v0.3 closed the capture-format matrix. v0.4 wraps the viewfinder in the **three-layer chrome system** (PRD §5.4) and lands the five **pre-shutter assists** (PRD §7) that make the camera feel guided without feeling guarded. No new asset types, no new capture paths — every change is on the UI/sensor-feedback side of the shutter line.

Five things must be true at the end of v0.4:

1. The viewfinder has a real Layer 0 / Layer 1 / Layer 2 architecture, not just per-feature show/hide flags. Tap toggles Layer 1, 3-second idle retreats it. Layer 2 (format selector) and the mode pill long-hold continue to work unchanged.
2. Snap users can switch lens (0.5×/1×/2× + pinch), flip camera (front/rear), and toggle aspect ratio (9:16 ↔ 1:1) from Layer 1 chrome that didn't exist before.
3. Invisible level, subject guidance, backlight correction, and the vibe hint glyph all surface in Snap Mode at the spec-defined thresholds, with no jank on the capture path.
4. The vibe classifier has a **clean injection seam** (`VibeClassifying` protocol) but ships with a quiet-default stub. The CoreML scene classifier is deferred — see §7.
5. Roll Mode is unchanged except for the invisible level (which is mode-agnostic per UIUX §2.10). No subject guidance, no vibe hint, no flip, no ratio toggle in Roll. This is intentionally asymmetric per PRD §5.4.

The version validates four risks:

1. **Zoom-driven lens switching under `AVCaptureMultiCamSession` constraints** — pinch must drive `virtualDeviceSwitchOverVideoZoomFactors` cleanly when only one back camera is bound, and degrade to `1×` only when the session graph is Dual or front-camera.
2. **Layer 1 auto-retreat must not race the format selector (Layer 2)** — opening Layer 2 must not be interpreted as "idle" and dismiss Layer 1 mid-interaction, and dismissing Layer 2 must reset Layer 1's idle clock.
3. **`CMMotionManager` + `VNDetectFaceRectanglesRequest` running concurrently with active capture** — both must run off the capture queue, and both must pause cleanly during Sequence/Clip/Dual recording windows.
4. **Pinch gesture conflict with Sequence capture window** — pinch is locked at zoom-at-tap-time during the 3-second Sequence window (FR-SNAP-ZOOM-05); the Layer 1 tap gesture must not consume taps that should fire the shutter.

---

## 2. Verification Goal

**End-to-end on iPhone 17 / iOS 26.4:**

Cold launch into Snap → Layer 0 only (shutter + mode pill + vibe glyph if social) → tap viewfinder → Layer 1 fades in within 220ms (zoom pill, ratio indicator, flip button, unsent badge) → tap 0.5× → ultra-wide engages, signal-yellow highlight on 0.5× → pinch outward → continuous zoom past 1× with haptic clicks at 1.0 and 2.0 → 3 seconds idle → Layer 1 fades out (150ms) → tilt phone 5° → invisible level line appears centered → tilt back → line fades → tap viewfinder → tap flip → 200ms 3D flip animates, zoom resets to 1×, zoom pill shows 1× only → frame your face within 15% of the edge → "Step back for the full vibe" pill appears, auto-dismisses at 1.5s → tap viewfinder → tap ratio → cycles 9:16 → 1:1 (preview crops, capture honors) → swipe-up to format selector → pick Sequence → ratio pill greys to 9:16 non-interactive → tap shutter → 6 frames fire, pinch ignored mid-window, vibe glyph paused mid-window → resume after assembly → swipe-up → pick Dual → flip button **hidden** (not just disabled) → background app during Clip recording → recording aborts cleanly per v0.3 behavior. **Roll mode:** long-hold mode pill → switch to Roll → Layer 1 tap reveals only flip + level (no ratio, no zoom pill, no guidance, no vibe). Confirm.

**Success = all automated tests green + every §6 device checklist row passes on iPhone 17 (iOS 26.4).**

---

## 3. Scope

### AppConfig

`AppConfig.piqd_v0_4` extends `piqd_v0_3` by adding a single `.preShutterChrome` feature flag (bit 15). All Layer 1 chrome features activate together at this version, so per-feature flags would only bloat `FeatureSet` without buying gating value. Per-feature dev toggles live in `DevSettingsStore`. No asset-type or capture-format change.

```
features:    [.snapMode, .rollMode, .sequenceCapture, .dualCamera,
              .preShutterChrome]
```

All other v0.3 capabilities preserved.

### In Scope

- **Layered chrome state machine** (`LayerStore`): Layer 0 (rest) / Layer 1 (revealed) / Layer 2 (format selector). Tap-on-viewfinder toggles 0↔1. 3s idle timer auto-retreats 1→0. Layer 2 entry/exit pauses + resets the Layer 1 idle clock.
- **Zoom pill** (`ZoomPillView`): three buttons (0.5×/1×/2×). Active state in `snapYellow`. Tap jumps to the discrete zoom level via `AVCaptureDevice.videoZoomFactor` keyed against the active device's `virtualDeviceSwitchOverVideoZoomFactors`. Front camera renders 1× only.
- **Pinch gesture** on viewfinder for continuous zoom 0.5×–2× (rear) or 1×–2× digital (front). Haptic click at each `virtualDeviceSwitchOverVideoZoomFactors` boundary. Locked during Sequence capture.
- **Aspect ratio toggle** (`AspectRatioPillView`): 9:16 ↔ 1:1, persisted per-mode under `piqd.snap.aspectRatio`. Locked to 9:16 (non-interactive, 50% opacity) when `activeFormat == .sequence`. Affects preview crop AND capture-time crop. 1:1 not yet supported in Sequence/Clip/Dual — those format paths force 9:16 in v0.4 and will revisit in v0.5+ if the spec asks for it. (Tracked as deferred — see §7.)
- **Camera flip button** (`FlipButtonView`): top-right safe area in Layer 1. 200ms 3D horizontal flip animation on the viewfinder layer. Resets zoom to 1×. **Hidden** (not just disabled) when `activeFormat == .dual`. Reuses existing `AVCaptureAdapter.switchCamera()` (already shipped in v0.3).
- **Invisible level** (`LevelIndicatorView` + `MotionMonitor`): subscribes to `CMMotionManager.deviceMotion` at ~30Hz off the capture queue. Renders a 40%-width 1pt horizontal line when `|roll| > 3°`, fades in/out at 150ms. Snap **and** Roll. Pauses during all video-recording formats (Clip/Dual) — line stays visible if already shown but motion subscription drops to 5Hz to save power.
- **Subject guidance** (`SubjectGuidanceController`): wraps `VNDetectFaceRectanglesRequest` running on the existing AVCapture video data output's sample buffer at ≤2fps. When any detected face's bounding box intersects within 15% of any frame edge, shows `SubjectGuidancePillView` ("Step back for the full vibe") for 1.5s. 10s cooldown per face position bucket. Snap-only. Disabled during Sequence/Clip/Dual recording.
- **Backlight correction** (`AVCaptureAdapter.setBacklightCorrection(_:)`): wires `AVCaptureDevice.exposureMode = .continuousAutoExposure` plus a small EV bias (`setExposureTargetBias(+0.5, completionHandler:)`) when the metering reports a strong dark foreground / bright background ratio. The viewfinder already shows the actual output exposure (preview is the metering output). Add a Dev Settings toggle to disable EV bias for verification.
- **Vibe hint glyph** (`VibeHintView` + `VibeClassifying` protocol): `VibeHintView` renders the spec'd 16pt three-bar glyph at the spec'd position. Pulses scale 1.0→1.2→1.0 over 600ms × 3 iterations on `social` state, hidden on `quiet` / `neutral`. **Classifier ships as a stub** (`StubVibeClassifier` always returns `.quiet`) — protocol seam (`VibeClassifying`) injected via `PiqdAppContainer`. CoreML implementation deferred — see §7. Snap-only.
- **Layer 1 / Layer 0 auto-retreat coordinator**: 3s idle timer reset by any Layer 1 chrome interaction (zoom pill tap, flip tap, ratio tap, pinch start, gear tap). Pinch end does NOT reset the timer — match the PRD's "interaction completes" semantic.
- **Settings injection**: dev settings additions for invisible-level toggle, subject-guidance toggle, vibe-hint toggle, backlight EV bias toggle. User-facing settings sheet still deferred to v0.9.
- **Tests**: unit tests for `LayerStore` state transitions, `MotionMonitor` thresholding, `SubjectGuidanceController` debounce + cooldown, `VibeClassifying` protocol contract. XCUITest for Layer 1 tap-reveal, zoom pill cycling, flip animation (presence not pixel), ratio toggle, level appearance under simulated motion (UI test mode injects motion fixtures).

### Out of Scope (deferred — see §7)

- CoreML scene classifier for vibe hint (placeholder stub ships).
- 1:1 aspect ratio for Sequence / Clip / Dual (only Still gets 1:1 in v0.4).
- User-facing Settings screen (v0.9).
- Roll-specific Layer 1 chrome polish beyond flip + level (v0.9 paired with film sims).
- Performance budgets for pre-shutter features (measure in v0.6 when we add the Trusted Circle UI).
- v0.3 carry-over: `ClipRecorderController` / `DualRecorderController` extraction (still pure-refactor, non-blocking; track separately).

---

## 4. Architecture

### Domain (NiftyCore)

| Type | Location | Purpose |
|------|----------|---------|
| `LayerChromeState` | `NiftyCore/Sources/Domain/Models/LayerChromeState.swift` | enum `{ rest, revealed, formatSelector }`. Pure state. No timing logic. |
| `ZoomLevel` | `NiftyCore/Sources/Domain/Models/ZoomLevel.swift` | enum `{ ultraWide, wide, telephoto }` with `factor: Double` accessor. Front-only contexts can `.constrain(to: .frontOnly)`. |
| `SnapAspectRatio` | `NiftyCore/Sources/Domain/Models/SnapAspectRatio.swift` | enum `{ portrait916, square11 }`. Persists per-mode. |
| `VibeSignal` | `NiftyCore/Sources/Domain/Models/VibeSignal.swift` | enum `{ quiet, neutral, social }`. |
| `VibeClassifying` | `NiftyCore/Sources/Domain/Protocols/VibeClassifying.swift` | `func classify(frame: CMSampleBuffer) async -> VibeSignal`. |
| `FaceFramingSignal` | `NiftyCore/Sources/Domain/Models/FaceFramingSignal.swift` | enum `{ ok, edgeProximity(side: Edge) }`. |

### Platform (NiftyData)

| Type | Location | Purpose |
|------|----------|---------|
| `MotionMonitor` | `NiftyData/Sources/Platform/MotionMonitor.swift` | Wraps `CMMotionManager`. Publishes `roll` + `pitch` at 30Hz (5Hz during recording). |
| `SubjectGuidanceDetector` | `NiftyData/Sources/Platform/SubjectGuidanceDetector.swift` | Wraps `VNDetectFaceRectanglesRequest`. Throttles to 2fps. Emits `FaceFramingSignal`. |
| `StubVibeClassifier` | `NiftyData/Sources/Platform/StubVibeClassifier.swift` | Conforms `VibeClassifying`. Always returns `.quiet`. Real CoreML lands later. |
| `AVCaptureAdapter+Zoom` | `NiftyData/Sources/Platform/AVCaptureAdapter+Zoom.swift` | `setZoom(_:animated:)`, `availableZoomLevels(for: position)`, pinch ramp helper. |
| `AVCaptureAdapter+Backlight` | `NiftyData/Sources/Platform/AVCaptureAdapter+Backlight.swift` | `setBacklightCorrection(enabled:)`. |

### UI (Apps/Piqd)

| Type | Location | Purpose |
|------|----------|---------|
| `LayerStore` | `Apps/Piqd/Piqd/UI/Capture/LayerStore.swift` | `ObservableObject`, drives `LayerChromeState`. Owns the 3s idle timer, exposes `tap()`, `interact()`, `enterFormatSelector()`, `exitFormatSelector()`. |
| `Layer1ChromeView` | `Apps/Piqd/Piqd/UI/Capture/Layer1ChromeView.swift` | Container that composes zoom pill, ratio pill, flip button, level, drafts badge slot. Drives entry/exit fade. |
| `ZoomPillView` | `Apps/Piqd/Piqd/UI/Capture/ZoomPillView.swift` | Three-segment control. Snap-only. |
| `AspectRatioPillView` | `Apps/Piqd/Piqd/UI/Capture/AspectRatioPillView.swift` | 9:16 ↔ 1:1 toggle. Disabled state when format is Sequence. |
| `FlipButtonView` | `Apps/Piqd/Piqd/UI/Capture/FlipButtonView.swift` | Top-right safe area. Hidden when Dual. |
| `LevelIndicatorView` | `Apps/Piqd/Piqd/UI/Capture/LevelIndicatorView.swift` | Subscribes to `MotionMonitor`. Mode-agnostic. |
| `SubjectGuidancePillView` | `Apps/Piqd/Piqd/UI/Capture/SubjectGuidancePillView.swift` | Snap-only. 1.5s display + 10s cooldown. |
| `VibeHintView` | `Apps/Piqd/Piqd/UI/Capture/VibeHintView.swift` | Bottom-left glyph. Pulse animation on `social`. |

### Wiring

- `PiqdCaptureView` owns `LayerStore`; tap gesture on `CameraPreviewView` calls `layerStore.tap()`. Pinch gesture calls `captureAdapter.setZoom(continuous:)` and `layerStore.interact()`.
- `MotionMonitor`, `SubjectGuidanceDetector`, `VibeClassifying` injected via `PiqdAppContainer`. Singleton-per-app — they're sensors, not request-scoped.
- `SubjectGuidanceDetector` and `VibeClassifying` both consume the existing `AVCaptureVideoDataOutput` sample buffer stream that v0.6 of niftyMomnt already pioneered — wire a v0.4 minimal version on Piqd's adapter (one-output, two-consumers fan-out via `dispatchQueue` tap).

---

## 5. Tasks

| # | Task | Files | Owner | Done |
|---|------|-------|-------|------|
| 1 | `AppConfig.piqd_v0_4` adds `.preShutterChrome` flag (bit 15); route `PiqdApp` to use it; v0.3→v0.4 superset tests | `Apps/Piqd/Piqd/AppConfig+Piqd.swift`, `Apps/Piqd/Piqd/PiqdApp.swift`, `NiftyCore/Sources/Domain/AppConfig.swift`, `NiftyCore/Tests/AppConfigPiqdTests.swift` | Eng | ✅ |
| 2 | Domain types: `LayerChromeState`, `ZoomLevel` (+ `CameraPosition`), `VibeSignal`, `FaceFramingSignal` (+ `FrameEdge`); reuse existing `AspectRatio` w/ `snapAllowed` + `nextSnapRatio()` extension; +11 unit tests | `NiftyCore/Sources/Domain/Models/*`, `NiftyCore/Tests/PreShutterChromeDomainTests.swift` | Eng | ✅ |
| 3 | `VibeClassifying` protocol (start/stop + `currentSignal()` + `AsyncStream<VibeSignal> signals`) in NiftyCore; `StubVibeClassifier` (always `.quiet`, `emit(_:)` test hook) in NiftyData; +5 tests | `NiftyCore/Sources/Domain/Protocols/VibeClassifying.swift`, `NiftyData/Sources/Platform/StubVibeClassifier.swift`, `NiftyData/Tests/StubVibeClassifierTests.swift` | Eng | ✅ |
| 4 | `LayerChromeStore` (pure state machine in NiftyCore — tap / interact / enter+exit format selector / shouldRetreat / retreat); 17 unit tests covering all transitions + Layer 2 round-trip + idle-window reset semantics. App-layer @Observable wrapper + Task.sleep timer deferred to Task 5 | `NiftyCore/Sources/Domain/LayerChromeStore.swift`, `NiftyCore/Tests/LayerChromeStoreTests.swift` | Eng | ✅ |
| 5 | `PiqdTokens` (Color/Spacing/Animation/Layer constants); `LayerStore` @Observable wrapper around `LayerChromeStore` w/ Task.sleep idle ticker; `Layer1ChromeView` generic shell w/ 4 view-builder slots (top-right / zoom / ratio / drafts-badge) + 220ms-in / 150ms-out opacity fade off `isRevealed`; build green | `Apps/Piqd/Piqd/UI/PiqdTokens.swift`, `Apps/Piqd/Piqd/UI/Capture/LayerStore.swift`, `Apps/Piqd/Piqd/UI/Capture/Layer1ChromeView.swift` | Eng | ✅ |
| 6 | `AVCaptureAdapter+Zoom` — `setZoom(_:)` (discrete-pill), `setZoomContinuous(_:)` (pinch), `availableZoomLevels()` (front=[wide], back varies by device), `lensSwitchOverFactors()` (haptic boundaries from `virtualDeviceSwitchOverVideoZoomFactors`), `currentZoomFactor()`. Pure helper `availableZoomLevels(position:minFactor:maxFactor:)` exposed for unit testing; +5 tests covering front / triple / dual-wide / dual-tele / single. Internal `activeVideoDevice` accessor added to main file | `NiftyData/Sources/Platform/AVCaptureAdapter.swift`, `NiftyData/Sources/Platform/AVCaptureAdapter+Zoom.swift`, `NiftyData/Tests/AVCaptureAdapterZoomTests.swift` | Eng | ✅ |
| 7 | `ZoomPillView` (3-segment, signal-yellow active); wired into `Layer1ChromeView` slots in `PiqdCaptureView`; tap-toggle viewfinder gesture (Layer 1 reveal) + `MagnificationGesture` pinch w/ continuous `setZoomContinuous` + lens-boundary haptic; gesture catcher sized to cropped preview only (does not intercept shutter); per-leaf `allowsHitTesting(isRevealed)` so Layer 1 chrome doesn't swallow shutter taps; format-selector entry/exit calls `layerStore.enterFormatSelector()` / `exitFormatSelector()`. Full UI test suite re-run: 29/33 pass, same 4 pre-existing Clip failures as baseline (no regressions). xcodegen project regenerated | `Apps/Piqd/Piqd/UI/Capture/ZoomPillView.swift`, `Apps/Piqd/Piqd/UI/Capture/Layer1ChromeView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift`, `Apps/Piqd/Piqd/UI/PiqdTokens.swift`, `Apps/Piqd/Piqd.xcodeproj/project.pbxproj` | Eng | ✅ |
| 8 | Sequence-capture pinch lock (FR-SNAP-ZOOM-05) — `isZoomLocked = activeFormat == .sequence && activity.isCapturing` gates both pinch (closure guard) and pill (`allowsHitTesting(!isZoomLocked)` + 0.4 opacity). Implemented inline as part of Task 7 | `PiqdCaptureView.swift` | Eng | ✅ |
| 9 | `AspectRatioPillView` (32pt ultra-thin material, "9:16"/"1:1" label, snapChrome on white-on-clear, 50%-opacity locked state) wired into Layer 1 ratio slot; `ModeStore.snapAspectRatio` persisted under `piqd.snap.aspectRatio`; new `cycleSnapAspectRatio()` + `effectiveAspectRatio(for:format:)` (Still→user choice, Sequence/Clip/Dual→9:16, Roll→4:3); preview-crop wiring via `aspect` computed prop. Capture-time crop already handled by existing `AspectRatio.centerCropRect(in:)`. Pill hidden in Dual (Dual has its own composition layouts) | `Apps/Piqd/Piqd/UI/Capture/AspectRatioPillView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift`, `Apps/Piqd/Piqd/UI/Capture/ModeStore.swift` | Eng | ✅ |
| 10 | `FlipButtonView` (44pt circular, ultra-thin material, SF Symbol `arrow.triangle.2.circlepath.camera`) wired into Layer 1 top-right slot; hidden when `activeFormat == .dual` (FR-SNAP-FLIP-04); disabled during capture; 200ms `rotation3DEffect` Y-axis flip on the preview (FR-SNAP-FLIP-02); after `switchCamera()` returns, `refreshAvailableZoomLevels()` + `setZoom(.wide)` honor FR-SNAP-FLIP-03 (zoom resets to 1× and front shows pill `[.wide]` only) | `Apps/Piqd/Piqd/UI/Capture/FlipButtonView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ✅ |
| 11 | `MotionMonitor` (CMMotionManager wrapper, 30Hz / 5Hz-during-recording); `MotionSample` model in NiftyCore (rollDegrees from `atan2(gravity.x, -gravity.y)` for portrait); `start()` / `stop()` / `setRecording(_:)` / `samples: AsyncStream<MotionSample>` / `emit(_:)` test seam matching `StubVibeClassifier` shape; container + `PiqdApp` wiring; +7 tests (rate transitions, replay, stream delivery) | `NiftyCore/Sources/Domain/Models/MotionSample.swift`, `NiftyData/Sources/Platform/MotionMonitor.swift`, `NiftyData/Tests/MotionMonitorTests.swift`, `Apps/Piqd/Piqd/PiqdAppContainer.swift`, `Apps/Piqd/Piqd/PiqdApp.swift` | Eng | ✅ |
| 12 | `LevelIndicatorView` subscribes to `MotionMonitor.samples`, fades 40%-width 1pt line in `levelLine` color when `\|roll\| > 3°` (150ms ease-in-out); centered in cropped viewfinder, mode-agnostic; `allowsHitTesting(false)` + `accessibilityHidden(true)`; `PiqdCaptureView` `.task { motionMonitor.start() }` + `.onDisappear { stop() }` + `.onChange(of: activity.isCapturing) { setRecording($0) }` for 30/5Hz switching | `Apps/Piqd/Piqd/UI/Capture/LevelIndicatorView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ✅ |
| 13 | `SubjectGuidanceDetector` — wraps `VNDetectFaceRectanglesRequest`, throttles to ≤2fps via `lastProcessAt`, computes closest edge within 15% margin (pure helper `edgeProximity(forRect:)`), per-edge 10s cooldown via `NowProvider`, `process(_ buffer:)` for real frames + `emit(rect:frame:)` test seam, AsyncStream<FaceFramingSignal>; +10 tests covering geometry, stream delivery, cooldown block + release | `NiftyData/Sources/Platform/SubjectGuidanceDetector.swift`, `NiftyData/Tests/SubjectGuidanceDetectorTests.swift` | Eng | ✅ |
| 14 | `SubjectGuidancePillView` — ultra-thin material pill ("Step back for the full vibe"), 1.5s display via cancellable `Task`, fades 180ms; subscribes to `detector.signals` via `.task`, ignores `.ok`, shows on `.edgeProximity`. Wired into `PiqdCaptureView` bottom VStack between dualMediaKindToggle and shutterControl, gated `mode==.snap && !isCapturing && !showFormatSelector`; lifecycle: `start()` on Snap entry / non-recording, `stop()` on Roll, format selector still open, or any recording start | `Apps/Piqd/Piqd/UI/Capture/SubjectGuidancePillView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift`, `Apps/Piqd/Piqd/PiqdAppContainer.swift`, `Apps/Piqd/Piqd/PiqdApp.swift` | Eng | ✅ |
| 15 | `AVCaptureAdapter+Backlight` — `setBacklightCorrection(enabled:)` toggles `.continuousAutoExposure` + clamped `setExposureTargetBias(±0.5, 0.0)`. Dev Settings toggle `backlightCorrectionEnabled` (default ON). Wired in `PiqdCaptureView` via `.task` (apply persisted value after device configured) + `.onChange(of: dev.backlightCorrectionEnabled)`. Automatic scene-detection deferred per scope cut | `NiftyData/Sources/Platform/AVCaptureAdapter+Backlight.swift`, `Apps/Piqd/Piqd/UI/Debug/DevSettingsStore.swift`, `Apps/Piqd/Piqd/UI/Debug/PiqdDevSettingsView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ✅ |
| 16 | `VibeHintView` — 16pt three-bar capsule mark in `snapYellow`, pulses 1.0→1.2 over 6×0.30s autoreverse on `.social`, hidden otherwise; subscribes via `classifier.signals`. `VibeClassifying` injected via container (ships as `StubVibeClassifier` → `.quiet` → glyph hidden). `PiqdCaptureView` mounts at cropped-preview bottom-left, gated `mode==.snap && !activity.isCapturing && dev.vibeHintEnabled`; classifier started/stopped in view `.task` / `.onDisappear` | `Apps/Piqd/Piqd/UI/Capture/VibeHintView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift`, `Apps/Piqd/Piqd/PiqdAppContainer.swift`, `Apps/Piqd/Piqd/PiqdApp.swift` | Eng | ✅ |
| 17 | Primary preview frame tap: `AVCaptureAdapter` adds an `AVCaptureVideoDataOutput` (alwaysDiscardsLateVideoFrames, BGRA) on the standard non-Dual session in `configureSession`; reuses `SecondaryFrameDelegate` against new `primaryFrameQ`; cleared in all 3 reset paths (`resetSessionStateOnQueue`, leaving-Dual full teardown, `swapSessionClass`). Public `setPrimaryFrameSink((CMSampleBuffer)->Void)` (lock-protected swap). `SubjectGuidanceDetector.process(_:orientation:)` now takes `CGImagePropertyOrientation` (default `.right`) so the portrait viewfinder maps correctly to Vision's coords; PiqdCaptureView picks `.right` (back) / `.leftMirrored` (front) per `currentCameraPosition()`. Recording-window pauses: `onChange(of: activity.isCapturing)` calls `subjectGuidance.stop()` + `vibeClassifier.stop()` on start, restarts both on stop (Snap-only for guidance) | `NiftyData/Sources/Platform/AVCaptureAdapter.swift`, `NiftyData/Sources/Platform/SubjectGuidanceDetector.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ✅ |
| 18 | XCUITest `Layer1ChromeUITests` — 3 tests: tap reveals chrome, idle auto-retreats, leaf-tap (ratio) resets idle clock without toggling state. Uses hidden `piqd-layer1-tap-test` button (XCUITest tap synthesis can't reach SwiftUI `simultaneousGesture` on iOS 26). `PIQD_TEST_LAYER1_IDLE_SECONDS` env var lets each test pick its own idle (5s for reset test, 1.5s default). `isHittable` is the canonical "is chrome revealed" signal — opacity-0 SwiftUI Buttons stay in the a11y tree, so `exists` doesn't work. Removed propagating `accessibilityIdentifier("piqd.layer1.chrome")` from Layer1ChromeView and `piqd.zoomPill` from ZoomPillView's HStack — both were masking per-leaf IDs. Restored `accessibilityHidden` on viewfinder catcher (full-screen a11y frame was occluding `isHittable` of leaves). Bumped `idleRetreatSecondsUITest` from 0.3 → 1.5 so XCTNSPredicateExpectation polling can observe the revealed window | `Apps/Piqd/PiqdUITests/Layer1ChromeUITests.swift`, `Apps/Piqd/Piqd/UI/Capture/Layer1ChromeView.swift`, `Apps/Piqd/Piqd/UI/Capture/ZoomPillView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift`, `Apps/Piqd/Piqd/UI/PiqdTokens.swift` | Eng | ✅ |
| 19 | XCUITest `PreShutterChromeUITests` — 4 tests: zoom pill `wide` segment exists + tappable, ratio pill toggles in Still (verified via `accessibilityValue` change), flip button present in Snap, zoom pill hidden in Roll. All chrome-revealed tests use 30s idle override to immunize them from auto-retreat noise. Level-appearance under fixture motion deferred to device verification (UIUX §2.10) — would need a dev-toggle to drive `MotionMonitor.emit()` from XCUITest, out of scope for v0.4 | `Apps/Piqd/PiqdUITests/PreShutterChromeUITests.swift` | Eng | ✅ |
| 20 | Dev Settings additions completed inline with Tasks 15+16: `backlightCorrectionEnabled`, `levelIndicatorEnabled`, `subjectGuidanceEnabled`, `vibeHintEnabled` toggles in `DevSettingsStore` (default ON, persisted, launch-arg overrides `PIQD_DEV_BACKLIGHT_CORRECTION`/`_LEVEL_INDICATOR`/`_SUBJECT_GUIDANCE`/`_VIBE_HINT`), Pre-shutter chrome section in `PiqdDevSettingsView` with 4 toggles + `resetDefaults()` updated. `PIQD_TEST_LAYER1_IDLE_SECONDS` added in Task 18 for UI-test idle tuning | `Apps/Piqd/Piqd/UI/Debug/DevSettingsStore.swift`, `Apps/Piqd/Piqd/UI/Debug/PiqdDevSettingsView.swift` | Eng | ✅ |

---

## 6. Verification Checklist

| § | Row | Expected | Automated | Pass |
|---|-----|----------|-----------|------|
| 1.1 | Cold launch into Snap → Layer 0 only (shutter + mode pill visible; zoom pill / ratio / flip absent) | Y (UI Layer1ChromeUITests) | ⬜ |
| 1.2 | Tap viewfinder → Layer 1 fades in within 220ms; zoom pill, ratio pill, flip button, drafts badge slot visible | Y | ⬜ |
| 1.3 | 3s idle (UI_TEST_MODE: 0.3s) → Layer 1 fades out (150ms) | Y | ⬜ |
| 1.4 | Tap zoom pill mid-Layer-1 → idle timer resets | Y | ⬜ |
| 1.5 | Swipe-up to format selector mid-Layer-1 → Layer 1 idle paused; selector dismiss resets idle | Y | ⬜ |
| 2.1 | Snap rear: zoom pill shows 0.5× / 1× / 2×; tap each switches lens; active level highlighted in `snapYellow` | Y | ⬜ |
| 2.2 | Pinch outward → continuous zoom; haptic click at 1.0 and 2.0 lens boundaries | partial (haptic confirmed device-only) | ⬜ |
| 2.3 | Snap front: zoom pill renders only 1× (segment); pinch caps at 2× digital | Y | ⬜ |
| 2.4 | Sequence active: zoom pill & pinch ignored during 3-second window | Y | ⬜ |
| 3.1 | Aspect ratio pill: tap cycles 9:16 → 1:1 → 9:16; persists across cold launch (Still only) | Y | ⬜ |
| 3.2 | Sequence active: ratio pill greyed at 50% opacity, non-interactive, shows "9:16" | Y | ⬜ |
| 4.1 | Flip button visible top-right Layer 1 in Still / Sequence / Clip; **hidden** in Dual | Y | ⬜ |
| 4.2 | Tap flip → 200ms 3D flip animation; zoom resets to 1× | Y (presence + zoom value) | ⬜ |
| 5.1 | Tilt phone 5° → invisible level appears centered; tilt back → fades in 150ms | partial (motion fixture in UI mode) | ⬜ |
| 5.2 | Roll Mode: invisible level still active under same threshold | partial | ⬜ |
| 5.3 | During Clip recording: motion sample rate drops to 5Hz; visible state holds | N (instrumented log only) | ⬜ |
| 6.1 | Snap: face within 15% of any edge → "Step back for the full vibe" pill appears, dismisses at 1.5s | partial (Vision fixture in UI mode) | ⬜ |
| 6.2 | Same face position: no repeat within 10s | Y (deterministic fixture clock) | ⬜ |
| 6.3 | Roll: subject guidance never appears | Y | ⬜ |
| 6.4 | During Sequence/Clip/Dual recording: subject guidance suspended | Y | ⬜ |
| 7.1 | Backlight scenario (bright window behind subject): viewfinder lifts subject by ~0.5 EV; matches captured Still | N (manual on iPhone 17) | ⬜ |
| 7.2 | Dev Settings: backlight toggle off → no EV bias applied | Y | ⬜ |
| 8.1 | Vibe glyph at bottom-left position per spec; Snap only | Y | ⬜ |
| 8.2 | Stub classifier returns `.quiet` → glyph hidden at all times in v0.4 | Y | ⬜ |
| 8.3 | Injectable: substitute fake `VibeClassifying` returning `.social` → glyph pulses 3× then fades | Y | ⬜ |
| 8.4 | During Sequence/Clip/Dual recording: classifier suspended | Y | ⬜ |
| 9.1 | All v0.3 capture flows still pass (regression: format selector, mode-switch lock, dual layouts) | Y (existing UI suite) | ⬜ |

**v0.4 complete = all rows ✅ on iPhone 17 / iOS 26.4 + CI green.**

---

## 7. Deferred / Open Decisions

1. **CoreML scene classifier → deferred to v0.5 or later.** v0.4 ships `VibeClassifying` protocol + `StubVibeClassifier` (always `.quiet`). Reason: this is a chrome version; coupling to a CoreML model now would balloon scope and pull in model-management infrastructure that hasn't been justified yet. niftyMomnt's `VibeClassifier` from v0.6 / v0.9 is a candidate to port when we revisit, but it ships out of a separate codebase and shouldn't gate v0.4.
2. **1:1 aspect ratio for Sequence / Clip / Dual → deferred.** Spec only requires 9:16 + 1:1 in Snap "Still" path; non-Still formats are 9:16-locked through v0.4. If 1:1 Clip/Dual ever becomes a requirement, revisit alongside the v0.5 drafts tray work.
3. **User-facing Settings screen → still v0.9.** v0.4 only adds Dev Settings toggles. Pinning all user-facing config to v0.9 (paired with film sims) keeps chrome work cohesive.
4. **Pre-shutter performance budget → measured in v0.6.** v0.4 instruments `MotionMonitor` and `SubjectGuidanceDetector` with `os_signpost` ranges but does not enforce gates. Rationale: shutter latency p95 < 100ms (existing gate from v0.3) covers the user-visible budget; per-feature budgets land when we have realistic combined load (v0.6 adds Trusted Circle + onboarding).
5. **Vibe glyph + backlight correction interaction with Roll Mode** → unchanged from PRD: both Snap-only. Roll's aesthetic is intentionally unguided.
6. **Edge-to-edge Dual Video split layouts (carry-over from v0.3)** → still deferred. Not in v0.4 scope.

---

## 8. Risks

| Risk | Mitigation |
|------|------------|
| `virtualDeviceSwitchOverVideoZoomFactors` empty on iPhone 15 baseline | Fall back to manual `videoZoomFactor` discrete jumps; gate ultra-wide on `device.deviceType == .builtInTripleCamera \|\| .builtInDualWideCamera`. Detect at adapter init and surface available levels to UI. |
| Layer 1 idle timer fights format selector (Layer 2) | `LayerStore.enterFormatSelector()` pauses idle timer; `exitFormatSelector()` restarts with full 3s. Unit-test all transitions including same-tick re-entry. |
| Vision face-detection at 2fps starves capture queue | Run `VNImageRequestHandler` on a dedicated `DispatchQueue(qos: .userInitiated)`; drop frames when handler is busy rather than queue. |
| Pinch gesture conflicts with the Layer 1 tap gesture | Use `simultaneousGesture` on tap+pinch; pinch begin cancels the tap-toggle. UI test for tap+pinch interleavings. |
| EV bias makes captures look unnaturally bright | Cap at +0.5 EV; only apply when metering reports >2 EV foreground/background gap; Dev Settings toggle for QA. |

---

*— End of v0.4 plan draft · Next: piqd_interim_v0.5_plan.md (Drafts Tray) —*
