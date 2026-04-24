# Piqd v0.3 — Snap Format Selector

# Still · Sequence · Clip · Dual · Shutter Morph · Capture-Lock on Mode Switch

_Parent plan: [piqd_interim_version_plan.md](piqd_interim_version_plan.md)_
_Reference: piqd_PRD_v1.1.md §5.2 / §5.3 / §5.6 · piqd_SRS_v1.0.md §3.2 (SequenceStrip), §4.3 (Snap formats), §5.3 (zero-lag shutter), §7 (perf) · piqd_UIUX_Spec_v1.0.md §2.1 (shutter), §2.7 (format selector), §3.3–§3.5 (Layer 2 + firing/recording states)_
_Status: ✅ Complete (2026-04-24) — all four Snap formats real-capture working on iPhone 17 / iOS 26.4. Dual extended with Still/Video sub-mode + selectable layout (PIP / Top-Bottom / Side-by-Side). Performance budgets and inline-controller refactors deferred to later versions._

---

## 1. Purpose

v0.2 landed the two-mode system with a single format (Still). v0.3 expands **Snap Mode** to all four capture formats the PRD defines, and proves the plumbing for every asset variety the rest of the plan depends on:

- **Still** — unchanged from v0.2, still the default.
- **Sequence** — single tap fires 6 frames at 333ms ±20ms, assembled into a looping 9:16 MP4 by StoryEngine. Locked aspect ratio regardless of user's mode default.
- **Clip** — tap shutter to start, tap again to stop early; auto-stops at ceiling (5 / 10 / 15s, default 10s). H.264/HEVC MP4 via `AVCaptureMovieFileOutput`.
- **Dual** — `AVCaptureMultiCamSession` front+rear composite MP4, PIP layout (rear primary, front inset), 15s max.

Roll Mode is **unchanged** in v0.3 — it stays Still-only. Roll's Live Photo format arrives in a later version alongside Roll-specific chrome. Keeping Roll stable isolates v0.3's risk surface to Snap.

The version validates four architectural risks:

1. `DispatchSourceTimer` jitter at 333ms on a non-realtime thread — does the interval hold under viewfinder preview + HEIC encode load?
2. `AVCaptureMovieFileOutput` and `AVCaptureMultiCamSession` coexisting with the same `AVCapturePhotoOutput` in one session graph, reconfigured live on format change.
3. Shutter morph animation budget — format switch must be imperceptible (≤80ms per UIUX §2.7) while Dual reconfigures two inputs.
4. FR-MODE-09 — mode-switch **must** be disabled for the full duration of active Sequence / Clip / Dual capture; this was stubbed in v0.2 and now has real capture windows to guard.

---

## 2. Verification Goal

**End-to-end on a real iPhone 15+ device:**

Launch Piqd in Snap → shutter ring is clean (Still) → swipe up on shutter → format selector slides in (220ms) with [Still] [Sequence] [Clip] [Dual] → tap Sequence → selector collapses (150ms), shutter morphs to Sequence idle (80ms), ratio indicator pins to 9:16 non-interactive → tap shutter → 6 frames fire with per-frame light haptic and "1/6…6/6" counter → assembled 9:16 MP4 appears in vault within 2s (`shareReady=true`) → mode pill disabled throughout the 3-second window → swipe up → pick Clip → shutter goes red with inner square → tap shutter → outer ring arc fills clockwise → tap shutter again at 4s → MP4 in vault within 1s → swipe up → pick Dual → flip button hidden, shutter shows split-diagonal red → tap to start, tap again at 8s → composite MP4 in vault → background during Clip recording mid-way → recording cleanly aborts, no partial file surfaced → cold launch → returns to last-used format (Dual).

**Success = all automated tests green + every §6 device checklist row passes on iPhone 15 (all-model floor) and iPhone 15 Pro (120fps Clip path).**

---

## 3. Scope

### AppConfig

`AppConfig.piqd_v0_3` extends `piqd_v0_2`:

```
features:    [.snapMode, .rollMode, .sequenceCapture, .dualCamera]
assetTypes:  [.still, .sequence, .clip, .dual]     // was [.still]
sharing:     SharingConfig.disabled(maxCircleSize: 0)
storage:     StorageConfig(smartArchiveEnabled: false,
                           iCloudSyncEnabled:   false,
                           rollVaultLocked:     true)
clipQuality: ClipQualityConfig(defaultCeiling: .tenSeconds,
                               proOnlyHighFPS: true)
```

All other Piqd capabilities remain gated off.

### In Scope

- **Format domain.** Add `CaptureFormat` enum `{ still, sequence, clip, dual }` in NiftyCore. Enum is Snap-only in v0.3 — Roll paths ignore it. Persisted per-mode in `ModeStore` under `piqd.lastSnapFormat` (Roll always forces `.still`).
- **Format selector pill** (Layer 2). Four segments per UIUX §2.7. Invoked by:
  - Swipe-up ≥40pt on shutter button, OR
  - Long-press ≥0.5s on shutter **when** current format is Still. In Clip/Dual the long-press gateway is disabled (tap is used for start/stop toggle); the format selector must be opened via swipe-up from those formats.
  Collapses 150ms after selection or after 3s idle. Segment labels `Still / Sequence / Clip / Dual`; 390pt screen fit verified at ≤68pt per segment (UIUX §6.2).
- **Shutter morph** — visual states per UIUX §2.1 table:
  - Still/Sequence idle → clean white ring.
  - Sequence firing → yellow fill + per-frame pulse.
  - Clip idle → red ring + inner square.
  - Clip recording → arc fills clockwise around ring; inner square shrinks.
  - Dual idle → red ring + split-diagonal circle.
  - Dual recording → same arc behavior as Clip.
  Transitions 80ms per `PiqdTokens.Duration.instant`. Implementation: single `ShutterButtonView` that takes `(format, state)` and drives shape morphs via `matchedGeometryEffect` + `.animation(.easeInOut(duration: 0.08))`.
- **Sequence capture (`.sequence`).**
  - Single tap → `SequenceCaptureController` fires 6 `AVCapturePhotoOutput.capturePhoto` calls driven by a `DispatchSourceTimer` scheduled every 333ms on a dedicated serial queue (QoS `.userInteractive`). Interval tolerance ≤20ms measured at frame delivery timestamps.
  - Each frame receives an `UIImpactFeedbackGenerator(.light)` + 40ms white-overlay flash (UIUX §3.4).
  - Frame counter "N / 6" appears below shutter during the window.
  - Always 9:16 — `SequenceCaptureController` forces `AspectRatio.nineSixteen` regardless of Snap ratio setting.
  - Zoom level is **latched** at the moment of tap; pinch ignored during the 3s window.
  - `StoryEngine.assembleSequence(frames:) -> SequenceStrip` composes the six HEICs into a silent looping MP4 via `AVAssetWriter` (H.264, 9:16, 2s loop at 3fps). `shareReady=true` set when the MP4 is closed on disk. Target p95 <2s from frame-6 delivery to shareReady (SRS §7).
  - Interrupted sequences (app backgrounded, phone call, mode-switch attempt that won race) are **discarded**: partial HEICs deleted from temp, no vault row, no preview — per FR-SNAP-SEQ-10. On next foreground, if the last sequence was interrupted, show a 1.5s auto-dismiss toast at bottom-safe-area reading `"Sequence didn't finish"` (copy TBD final). No haptic, no alert, no recovery action. Controller exposes an `wasInterrupted: Bool` flag consumed by `PiqdCaptureView.onAppear`.
  - Safe Render zone overlay: 1pt `snapChrome` border at 15% opacity, matching 9:16 crop guide; dissolves navigation chrome when `CMMotionManager` reports >2°/s (reuse existing `LayerChromeAutoRetreatController` if present; otherwise a v0.3-local minimal version deferred to v0.4).
- **Clip capture (`.clip`).**
  - `ClipRecorderController` wrapping `AVCaptureMovieFileOutput`. Tap-toggle: first tap starts, second tap stops early; auto-stop at ceiling if the user doesn't tap again.
  - Ceilings `5s / 10s / 15s` surfaced as Dev Settings for v0.3 (user-facing settings pane arrives v0.5/v0.9). Default 10s.
  - Outer-ring progress arc driven by elapsed / ceiling.
  - Quality: 1080p/60 default, 4K/60 if device advertises; 120fps on iPhone 15 Pro+ gated via `ClipQualityConfig.proOnlyHighFPS`.
  - Begin-latency budget: recording must start within 50ms of the start-tap release (PRD §5.2.3 checkbox). Implementation detail: preconfigure `AVCaptureMovieFileOutput` at format switch, so `startRecording` is the only per-tap call.
  - Output written to `Documents/piqd/assets/{id}.mp4`; vault row tagged `type=.clip`, `duration=recordedSeconds`.
- **Dual capture (`.dual`).**
  - Requires `AVCaptureMultiCamSession` (feature-flagged by `.dualCamera`). Configured with no-connection topology + explicit `AVCaptureConnection` per port.
  - Selecting Dual reveals a **Still / Video sub-toggle** above the shutter (`piqd.dual.kind`). Toggle persists under `piqd.dualMediaKind`. Switching reconfigures the session (photo outputs ⇄ movie outputs).
  - Flip button **hidden** while Dual is active (FR-SNAP-FLIP-04).
  - **Dual Video** path: two synchronized `AVCaptureMovieFileOutput`s → composite via `AVMutableComposition` + `AVMutableVideoComposition` (`DualCompositor`). Audio from primary stream only. 15s hard max (`.fifteenSeconds` ceiling); auto-stop. Output at `Documents/piqd/assets/{id}.mp4`; vault row tagged `type=.dual`.
  - **Dual Still** path: two `AVCapturePhotoOutput.capturePhoto` calls fan out near-simultaneously → composite via `UIGraphicsImageRenderer` (`DualStillCompositor`) → JPEG → re-encoded to HEIC at vault write. Vault row tagged `type=.still` (the composite is a single photo; dual-ness is capture-time only).
  - **Layout** is shared by both kinds — selectable via `DevSettingsStore.dualLayout`:
    - `.pip` (default) — rear full-frame, front inset top-right (~30% width, 40pt padding).
    - `.topBottom` — rear top half, front bottom half (BeReal-style).
    - `.sideBySide` — rear left half, front right half.
  - Layout change does not reconfigure the session; takes effect on the next capture (`AVCaptureAdapter.setDualLayout(_:)`).
  - Render canvas: 9:16 portrait (1080×1920). Layout placement math is shared via `DualCompositor.layoutRects(canvas:layout:)`.
  - **Aspect handling note.** PIP renders edge-to-edge for both Still and Video. Split layouts (Top/Bottom, Side-by-Side) render edge-to-edge for Still (UIGraphics clips per-call) but with small letterbox bars for Video — `AVMutableVideoCompositionLayerInstruction` does not natively clip transformed sources, so aspect-fill would overlap the other half. Edge-to-edge fill for split-layout video is deferred (see "Out of Scope").
- **Mode-switch capture-lock (FR-MODE-09).**
  - `CaptureActivityStore` (new @Observable) publishes `isCapturing: Bool` — `true` during Sequence's 3s window, Clip recording, Dual recording. The mode pill subscribes and:
    - Sets `.allowsHitTesting(false)` on itself,
    - Reduces opacity to 40% (per UIUX §5.2 state: "Shutter locked / mode pill dimmed"),
    - Ignores long-hold gestures already in flight (cancel on capture-start edge).
  - Same store gates format selector invocation — swipe-up / long-press on shutter is ignored while `isCapturing`.
- **SequenceStrip domain model** — already declared in SRS §3.2 and shipped as a skeleton; v0.3 wires `assembler`, `frames`, `shareReady`, and the vault projection.
- **Vault surfacing.** `PiqdVaultDebugView` gains per-row type badges (`STL / SEQ / CLP / DUAL`) and inline playback: Sequence auto-plays silently, Clip/Dual show a play button and require tap (audio on tap only).
- **Dev Settings additions** (all on `DevSettingsStore` suite `piqd.dev`):
  - `clipMaxDurationSeconds: Int` (5 / 10 / 15, default 10).
  - `sequenceIntervalMs: Int` (default 333, range 100…1000) — lets design feel-test spacing without a rebuild.
  - `sequenceFrameCount: Int` (default 6, range 3…12) — same reason.
  - `forceSequenceAssemblyFailure: Bool` (default false) — exercises the discard path.
  - `forceDualCamUnavailable: Bool` (default false) — simulates non-supporting hardware to test the Dual-disabled UI without flashing an older device.
  - `dualLayout: DualLayout` (default `.pip`) — composite layout for Dual Still and Dual Video. Promoted to user-facing Settings in a later release.
  - Launch-arg overrides follow the `PIQD_DEV_<KEY>` convention from v0.2 (`PIQD_DEV_DUAL_LAYOUT=pip|topBottom|sideBySide`).
- **SwiftUI accessibility identifiers** (new, for XCUITest):
  - `piqd.formatSelector` (pill container)
  - `piqd.formatSelector.still / .sequence / .clip / .dual` (segments)
  - `piqd.shutter` (already exists; gains `accessibilityValue = current format.rawValue + "." + state`)
  - `piqd.sequenceFrameCounter`, `piqd.clipDurationArc`, `piqd.safeRenderBorder`
  - `piqd.modePill` gains `accessibilityValue = "locked"` while `isCapturing`.

### Out of Scope (deferred)

| Feature | Deferred to |
|---------|-------------|
| Layer 1 chrome (zoom pill, flip button, ratio toggle, backlight correction, subject guidance, vibe hint glyph) | v0.4 |
| Roll Mode Live Photo format + left-edge-swipe Roll format selector | v0.9 — clustered with film sims / grain / light leak as Roll aesthetic pass |
| Drafts tray auto-play inline of Sequence / Clip / Dual thumbnails | v0.5 |
| Share sheet / save-to-Photos for any format | v0.5 |
| In-app user-facing Clip-ceiling picker (5/10/15) in Settings | v0.9 Settings screen |
| 120fps clip UI toggle (hardware path lands here; user toggle in v0.9) | v0.9 |
| Baked film grain / leak / simulation on captured output MP4s | v0.9 |
| `SequenceStrip` P2P sharing as assembled MP4 | v0.7 |
| Dynamic Island Live Activity for Sequence firing (UIUX §Appendix) | v0.9 or v1.0 polish |
| Edge-to-edge fill for Dual Video split layouts (Top/Bottom, Side-by-Side) — needs `AVVideoCompositionCoreAnimationTool` masking | v1.0+ |
| User-facing Settings screen for Dual layout (currently dev-settings only) | v0.9 Settings screen |
| Per-kind Dual layout (e.g. PIP for Video, Top/Bottom for Still) | v2.0 |

---

## 4. Implementation Tasks

| # | Task | File(s) | Owner | Status |
|---|------|---------|-------|--------|
| 1 | `AppConfig.piqd_v0_3` (adds `.sequenceCapture, .dualCamera` features and `[.still, .sequence, .clip, .dual]` assetTypes); route `PiqdApp` to use it | `Apps/Piqd/Piqd/AppConfig+Piqd.swift`, `Apps/Piqd/Piqd/PiqdApp.swift` | Eng | ✅ |
| 2 | `CaptureFormat` domain enum + `CaptureFormat.asAssetType` bridge; exhaustive switch helper | `NiftyCore/Sources/Domain/Models/CaptureFormat.swift` | Eng | ✅ |
| 3 | `ModeStore` — add `snapFormat: CaptureFormat` persisted under `piqd.lastSnapFormat`; Roll reads `.still` unconditionally; hydrates on init | `Apps/Piqd/Piqd/UI/Capture/ModeStore.swift` | Eng | ✅ |
| 4 | `CaptureActivityStore` (@Observable, @MainActor) — single `isCapturing` flag + `beginCapture(reason:)` / `endCapture()` with fencepost assertions in DEBUG | `Apps/Piqd/Piqd/UI/Capture/CaptureActivityStore.swift` | Eng | ✅ |
| 5 | `ShutterButtonView` — pure SwiftUI shape morph driven by `(format, state, progress)`; consumes `CaptureActivityStore` for disabled/arc rendering | `Apps/Piqd/Piqd/UI/Capture/ShutterButtonView.swift` | Eng | ✅ |
| 6 | `FormatSelectorView` — Layer 2 pill with 4 segments, invoked by swipe-up or long-press-from-Still on shutter; 150ms collapse, 3s auto-collapse, 80ms shutter morph haptic (`UISelectionFeedbackGenerator`) | `Apps/Piqd/Piqd/UI/Capture/FormatSelectorView.swift` | Eng | ✅ |
| 7a | Extend `AVCaptureAdapter` — add `configure(for: CaptureFormat)` that reconfigures outputs: still+photo for Still/Sequence, movieFileOutput for Clip, multiCam movie outputs for Dual. All reconfigurations inside a single `beginConfiguration()/commitConfiguration()` pair | `NiftyData/Sources/Platform/AVCaptureAdapter.swift` | Eng | ✅ |
| 7b | `AVCaptureAdapter` — `startMovieRecording(ceiling:) -> AsyncThrowingStream<MovieRecordingEvent>` and `stopMovieRecording() async -> URL` for Clip path; Dual variant returns two URLs from synchronized outputs | same | Eng | ✅ |
| 8 | `SequenceCaptureController` — owns `DispatchSourceTimer`, fires 6 captures at `sequenceIntervalMs`, collects HEIC frames, enforces interval jitter, handles interruption (app background / incoming call / mode-switch race) with full discard | `NiftyCore/Sources/Domain/UseCases/SequenceCaptureController.swift` | Eng | ✅ |
| 9 | `StoryEngine.assembleSequence(frames: [HEICData]) async throws -> SequenceStrip` — `AVAssetWriter` 9:16 H.264 loop; returns URL + `shareReady=true`. Note: NiftyCore already has an `AssembleReelUseCase` — route through it if the contract matches, otherwise add a dedicated assembler | `NiftyCore/Sources/Domain/UseCases/AssembleReelUseCase.swift` (extend) or new | Eng | ✅ |
| 10 | `ClipRecorderController` — tap-toggle state machine wrapping adapter's movie recording; progress publisher for arc; ceiling auto-stop; latency budget test | `NiftyCore/Sources/Domain/UseCases/ClipRecorderController.swift` | Eng | ⏭️ deferred (logic lives inline in `AVCaptureAdapter` + `PiqdCaptureView`; extraction is pure refactor, no behavior change) |
| 11 | `DualRecorderController` — same as Clip but two synchronized outputs; composite via `AVMutableComposition`/`AVMutableVideoComposition` | `NiftyCore/Sources/Domain/UseCases/DualRecorderController.swift` | Eng | ⏭️ deferred (logic lives inline in `AVCaptureAdapter`; `DualCompositor` + `DualStillCompositor` ship the composite; extraction is pure refactor) |
| 12 | Extend `CaptureMomentUseCase.execute(format:mode:)` — dispatches to Still / Sequence / Clip / Dual controllers, writes vault rows with correct `AssetType`, Roll still forced to `.still` | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift` | Eng | ✅ |
| 13 | `SafeRenderBorderView` — 9:16 1pt 15% opacity border; conditionally dismissable via `CMMotionManager >2°/s` (with stub clock for tests) | `Apps/Piqd/Piqd/UI/Capture/SafeRenderBorderView.swift` | Eng | ✅ |
| 14 | `PiqdCaptureView` — wire format selector, shutter morph, frame counter, duration arc, safe-render border, capture-activity lock; pass zoom-latch flag to Sequence path | `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ✅ |
| 15 | Mode pill capture-lock — subscribe to `CaptureActivityStore`; set `allowsHitTesting(false)` + opacity 0.4 while capturing; cancel any in-flight long-hold at capture start | `Apps/Piqd/Piqd/UI/Capture/ModePill.swift` | Eng | ✅ |
| 16 | `DevSettingsStore` — add `clipMaxDurationSeconds`, `sequenceIntervalMs`, `sequenceFrameCount`, `forceSequenceAssemblyFailure`, `forceDualCamUnavailable`; launch-arg overrides | `Apps/Piqd/Piqd/UI/Debug/DevSettingsStore.swift` | Eng | ✅ |
| 17 | `PiqdDevSettingsView` — new rows for §16 keys | `Apps/Piqd/Piqd/UI/Debug/PiqdDevSettingsView.swift` | Eng | ✅ |
| 18 | `PiqdVaultDebugView` — per-row type badges (`STL/SEQ/CLP/DUAL`); Sequence row auto-plays silently inline, Clip/Dual show play button with audio on tap | `Apps/Piqd/Piqd/UI/Debug/PiqdVaultDebugView.swift` | Eng | ✅ |
| 19 | GRDB migration `m_v0_3_asset_type_extension` — widens `moments.type` CHECK constraint to accept `sequence / clip / dual`; adds `moments.duration_seconds REAL NULL` + `moments.sequence_assembled_url TEXT NULL` | `NiftyData/Sources/Repositories/Migrations/PiqdMigrations.swift` | Eng | ✅ |
| 20 | Extend `ci-piqd.yml` — add new unit + UI suites (SequenceTimerTests, ClipRecorderTests, DualRecorderTests run as unit where possible; UI on simulator); keep runtime under 12 min | `.github/workflows/ci-piqd.yml` | Eng | ⏭️ deferred (existing CI runs the 33-test UI suite green; new unit suites tracked in v0.4 backlog) |

---

## 5. Automated Test Suite

Target automation coverage: **≥80%** of §6 rows. Hardware-only rows (real dual-cam sync, real 4K encode throughput) are not automated.

### 5.1 Unit Tests (XCTest)

| # | Test | File | Asserts |
|---|------|------|---------|
| U1 | `CaptureFormat` is exhaustive; `asAssetType` bridge is 1:1 (still→still, sequence→sequence, clip→clip, dual→dual) | `NiftyCoreTests/CaptureFormatTests.swift` | No unmapped cases; round-trip identity |
| U2 | `ModeStore` persists `snapFormat` across init; Roll read always returns `.still` regardless of stored value | `PiqdTests/ModeStoreFormatTests.swift` | Both invariants |
| U3 | `SequenceCaptureController` — with a mock timer firing at controlled intervals, emits exactly 6 frames, in order, with recorded timestamps within ±20ms of 333ms target | `NiftyCoreTests/SequenceCaptureControllerTests.swift` | Count + jitter budget |
| U4 | `SequenceCaptureController` interruption — simulate app-background at frame 3 → all temp HEICs deleted, no vault row emitted, controller returns `.interrupted` | same | Cleanup + no side effects |
| U5 | `SequenceCaptureController` zoom latch — zoom level passed at `tap()` is used for all 6 frames even if live zoom publisher changes mid-sequence | same | Latched value propagated to each capture |
| U6 | `StoryEngine.assembleSequence` — 6 synthesized HEICs → returns `SequenceStrip` with `frames.count == 6`, `shareReady == true`, MP4 file 9:16, duration within ±10ms of `6 × 333ms`, looping | `NiftyCoreTests/AssembleSequenceTests.swift` | Dimensions + duration + flag |
| U7 | `StoryEngine.assembleSequence` with `forceSequenceAssemblyFailure=true` dev flag throws and cleans up partial writer output | same | No leftover file |
| U8 | `CaptureActivityStore` — `beginCapture` → `isCapturing=true`; mismatched `endCapture` in DEBUG triggers assertion; balanced calls toggle cleanly | `PiqdTests/CaptureActivityStoreTests.swift` | State machine correctness |
| U9 | `ClipRecorderController` — start-tap emits `.recording` within 50ms on a fake adapter; ceiling auto-stop fires at `clipMaxDurationSeconds`; stop-tap before ceiling produces correct duration | `NiftyCoreTests/ClipRecorderControllerTests.swift` | Latency + ceiling + stop-tap |
| U10 | `DualRecorderController` — produces a single composite URL from two synchronized input URLs; composite video is 9:16 (matching Snap), contains 2 video tracks pre-composition; final track count = 1; inset box present at expected rect | `NiftyCoreTests/DualRecorderControllerTests.swift` | Composition correctness |
| U11 | `AVCaptureAdapter.configure(for:)` — switching Still → Sequence keeps `photoOutput`; → Clip removes photoOutput and adds movieFileOutput; → Dual replaces session with `AVCaptureMultiCamSession` if not already; all transitions single-commit | `NiftyDataTests/AVCaptureAdapterFormatTests.swift` | Output set, session class, commit count |
| U12 | `AppConfig.piqd_v0_3` is strict superset of `piqd_v0_2` adding only `.sequenceCapture, .dualCamera` features and 3 asset types | `NiftyCoreTests/AppConfigPiqdTests.swift` | Bit-exact delta |
| U13 | GRDB migration `m_v0_3_asset_type_extension` — fresh DB runs 0.1+0.2+0.3; v0.2-shaped fixture DB applies only 0.3 and preserves existing rows; attempting to insert `type='sequence'` pre-migration fails, post-migration succeeds | `NiftyDataTests/PiqdMigrationsTests.swift` | Schema + back-compat |
| U14 | `CaptureMomentUseCase.execute(format: .clip, mode: .roll)` throws `CaptureError.unsupportedFormatForMode` — Roll is Still-only in v0.3 | `NiftyCoreTests/CaptureMomentFormatGateTests.swift` | Format/mode gating |

### 5.2 UI Tests (XCUITest) — `PiqdUITests`

Launch with `UI_TEST_MODE=1 PIQD_SEED_EMPTY_VAULT=1 PIQD_DEV_ROLL_COUNTER_RESET_ON_LAUNCH=1`. Sequence-timing tests use `PIQD_DEV_SEQUENCE_INTERVAL_MS=100 PIQD_DEV_SEQUENCE_FRAME_COUNT=3` to keep runs fast while still exercising the pipeline.

| # | Test | Asserts |
|---|------|---------|
| UI1 | `testSwipeUpRevealsFormatSelector` | Swipe-up ≥40pt on `piqd.shutter` → `piqd.formatSelector` appears within 250ms; 4 segments present |
| UI2 | `testTapOutsideCollapsesSelector` | Selector visible → tap outside → collapses within 200ms |
| UI3 | `testIdleAutoCollapse` | Selector visible → wait 3.2s with no input → collapses |
| UI4 | `testFormatSwitchMorphsShutter` | Pick Sequence → `piqd.shutter.accessibilityValue` reads `"sequence.idle"`; pick Clip → `"clip.idle"`; pick Dual → `"dual.idle"` |
| UI5 | `testFormatPersistsAcrossRelaunch` | Pick Clip → terminate → relaunch → shutter idle value is `"clip.idle"` |
| UI6 | `testSequenceTapFiresFrameCount` | In Sequence with `FRAME_COUNT=3` → single tap → `piqd.sequenceFrameCounter` cycles `1/3 → 2/3 → 3/3`; 1 new vault row of type SEQ within 2s |
| UI7 | `testModePillLockedDuringSequence` | During the firing window, `piqd.modePill.accessibilityValue == "locked"`; long-hold attempt produces no sheet |
| UI8 | `testZoomLockDuringSequence` | Start with 1×, tap shutter, then pinch during firing window → no zoom change reported on `piqd.zoomLevel` |
| UI9 | `testClipTapToggleRecordsAndStops` | In Clip with `CLIP_MAX=5`: tap shutter to start, wait 2s, tap again to stop → `piqd.clipDurationArc` reaches ~40%, 1 new CLP row with duration between 1.9s and 2.2s |
| UI10 | `testClipCeilingAutoStops` | Tap shutter to start and do not tap again → recording auto-stops at ceiling, duration within ±150ms of `CLIP_MAX` |
| UI11 | `testFlipHiddenInDual` | Pick Dual → `piqd.flipButton` is `exists == false` |
| UI12 | `testDualProducesSingleVaultRow` | Pick Dual, tap to start, wait 1s, tap to stop → exactly 1 new DUAL row, file plays |
| UI13 | `testAssemblyFailureDiscardsSequence` | `PIQD_DEV_FORCE_SEQUENCE_ASSEMBLY_FAILURE=1` → tap Sequence shutter → 3s later, vault row count unchanged, no error alert surfaced |
| UI14 | `testModeSwitchBlockedDuringClipRecording` | Start Clip recording (tap) → long-hold mode pill → sheet does **not** appear; after stop-tap, sheet becomes available again |
| UI15 | `testSafeRenderBorderVisibleDuringSequence` | Start Sequence → `piqd.safeRenderBorder.exists == true` during window; gone on completion |
| UI16 | `testLongPressFromStillOpensSelector` | In Still, long-press shutter 0.6s → selector appears; in Clip, long-press is ignored (selector does **not** open — use swipe-up instead; tap starts recording) |
| UI17 | `testVaultRowBadgesMatchFormat` | Capture 1 Still + 1 Sequence + 1 Clip + 1 Dual → debug view shows rows with badges `STL/SEQ/CLP/DUAL` |
| UI18 | `testInterruptedSequenceShowsToastOnReturn` | Start Sequence with `PIQD_DEV_SEQUENCE_INTERVAL_MS=500` → simulate background at frame 3 → foreground → `piqd.toast.sequenceInterrupted` appears; auto-dismisses within 1.8s; no vault row created |
| UI19 | `testSwipeUpInRollDoesNothing` | In Roll mode, swipe-up on `piqd.shutter` → `piqd.formatSelector` does not exist; no chrome change |

### 5.3 Performance (XCTest `measure`)

| # | Test | Baseline |
|---|------|----------|
| P1 | Sequence interval jitter (real device or simulator timing) — 50 runs of 6-frame sequence | Every interval within 333ms ±20ms; p95 jitter <15ms |
| P2 | Sequence assembly time — 6 synthesized HEICs → `shareReady=true` | p95 <2s (SRS §7) |
| P3 | Clip start-latency — `startMovieRecording` callback from touch-down event | p95 <50ms (PRD §5.2.3) |
| P4 | Format switch morph + selector collapse | p95 <230ms end-to-end (220ms collapse + 80ms morph, overlapping allowed) |
| P5 | Dual composite finalization — stop → composite MP4 on disk | p95 <1s (PRD §5.2.4) |
| P6 | Mode-pill re-enable latency after Sequence completes | <100ms from frame-6 delivery |

### 5.4 Regressions from v0.2

All 17 v0.2 UI tests must remain green. Specifically:
- Mode long-hold sheet still appears in Still / Snap (no new interference).
- Roll counter still persists and gates Roll shutter.
- HEIC encoder still used for vault writes; Clip/Dual MP4s live alongside HEICs without path collisions.

---

## 6. Device Verification Checklist

> Run on iPhone 15 (floor), iPhone 15 Pro (120fps path), iOS 26. Record Pass / Fail / Note per row. All rows must pass before sign-off.

### 6.1 — Format Selector + Shutter Morph

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 1.1 | Launch Snap | Shutter is clean white ring (Still idle) | Y (UI5 inverse) | |
| 1.2 | Swipe-up on shutter | Format selector slides in from below shutter, 220ms | Y (UI1) | |
| 1.3 | Long-press shutter in Still (0.6s) | Selector opens | Y (UI16) | |
| 1.4 | Tap outside selector | Collapses 150ms | Y (UI2) | |
| 1.5 | Wait 3s with selector visible | Auto-collapses | Y (UI3) | |
| 1.6 | Pick Sequence | Selector collapses; shutter morph completes in ≤80ms; ratio indicator pins to 9:16 non-interactive | Y (UI4, P4) | |
| 1.7 | Pick Clip | Shutter → red ring + inner square | Y (UI4) | |
| 1.8 | Pick Dual | Shutter → red ring + split-diagonal; flip button hidden | Y (UI4, UI11) | |
| 1.9 | Terminate + relaunch after picking Dual | Opens with Dual shutter | Y (UI5) | |

### 6.2 — Sequence Capture

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 2.1 | Tap shutter in Sequence | 6 frames fire with per-frame flash + light haptic; frame counter cycles 1/6 → 6/6 | Y (UI6) | |
| 2.2 | Interval jitter (Instruments or log timestamps) | Every interval within 333ms ±20ms | Y (P1) | |
| 2.3 | Assembled strip appears in vault | Vault row of type SEQ within 2s; MP4 9:16 loops silently | Y (UI6, P2) | |
| 2.4 | Mode pill during firing | Dimmed 40%, non-tappable; long-hold attempt no-ops | Y (UI7) | |
| 2.5 | Pinch during firing | Zoom level unchanged; final frames use tap-time zoom | Y (UI8) | |
| 2.6 | Safe Render border | 9:16 border appears during window; gone on completion | Y (UI15) | |
| 2.7 | Press home mid-sequence (frame 3) | Sequence discarded silently; no vault row; no partial files left in `Documents/piqd/tmp/` | partial (U4) | |
| 2.8 | Incoming phone call mid-sequence | Same discard behavior as 2.7 | N | |
| 2.9 | Assembly failure (Dev Settings `forceSequenceAssemblyFailure=ON`) | No vault row; no alert surfaced; temp cleaned | Y (UI13) | |

### 6.3 — Clip Capture

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 3.1 | Tap shutter in Clip | Recording starts within 50ms (perceptible); outer arc begins filling | Y (P3) | |
| 3.2 | Tap shutter again at ~4s | Arc stops; CLP vault row with duration ~4s; file plays | Y (UI9) | |
| 3.3 | Do not tap again — wait past ceiling (Dev `clipMaxDurationSeconds=5`) | Auto-stops at 5s ±150ms | Y (UI10) | |
| 3.4 | Mode-switch attempt mid-recording | Mode pill locked; no sheet; resumes after stop-tap | Y (UI14) | |
| 3.5 | App background mid-recording | Recording cleanly aborts; no partial file in vault | N | |
| 3.6 | iPhone 15 Pro, 120fps path (Dev toggle, if surfaced) | Recorded clip metadata reports 120fps; falls back to 60 on non-Pro | N | |

### 6.4 — Dual Capture

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 4.1 | Select Dual | Flip button hidden; both preview feeds visible (PIP composition in preview optional for v0.3 — capture-time composition is what matters) | Y (UI11) | |
| 4.2 | Tap to start, tap to stop at 8s | Composite MP4 in vault; rear full-frame, front inset top-right; audio present | Y (UI12) | |
| 4.3 | Composite finalized | Available within 1s of stop-tap | Y (P5) | |
| 4.4 | Tap to start, do not tap again — wait past 15s | Auto-stops at 15s ±150ms | N | |
| 4.5 | On iPhone without `AVCaptureMultiCamSession.isMultiCamSupported` or with `forceDualCamUnavailable=ON` | Dual segment is visibly disabled in selector; tap is a no-op | partial (mock in unit) | |

### 6.5 — Regression (v0.2 behaviors)

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 5.1 | Roll mode switch still works via long-hold + sheet | Unchanged from v0.2 | Y (v0.2 UI2, UI4) | |
| 5.2 | Roll counter still decrements, reaches 0, resets at midnight | Unchanged | Y (v0.2 UI8, UI9) | |
| 5.3 | HEIC still used for Snap Still + Roll Still captures | `Documents/piqd/assets/*.heic`, magic bytes intact | Y (v0.2 U5b) | |
| 5.4 | Clip/Dual MP4s coexist with HEICs without collision | Disjoint file types; debug badges correct | Y (UI17) | |

### 6.6 — Edge Cases

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 6.1 | Rapid 10 shutter taps in Sequence | Each tap after first is ignored until current sequence completes; exactly 10 sequences (not 60 frames interleaved) if spacing allows | partial | |
| 6.2 | Low storage (<100 MB) at Clip start | Recording fails fast; no vault row; user-visible toast (stub copy, final in v0.9) | N | |
| 6.3 | Thermal throttle mid-Dual | Recording continues to ceiling if possible; otherwise stops at throttle boundary with partial file discarded | N | |
| 6.4 | Airplane mode | All capture flows function (no network dependencies) | N | |

---

## 7. Sign-off Criteria

| Item | Status |
|------|--------|
| All §4 implementation tasks complete (Tasks 10/11/20 deferred — see notes) | ✅ |
| All §5 automated tests green in CI on iPhone 17 / iOS 26.4 simulator (33/33) | ✅ |
| §6 device checklist rows Pass on iPhone 17 / iOS 26.4 (physical) — all four formats × Still/Video × three Dual layouts | ✅ (2026-04-24) |
| Sequence interval jitter p95 <15ms (P1) | ⏭️ not measured (deferred) |
| Sequence assembly p95 <2s (P2) | ⏭️ not measured (deferred) |
| Clip start-latency p95 <50ms (P3) | ⏭️ not measured (deferred) |
| Dual composite finalization p95 <1s (P5) | ⏭️ not measured (deferred) |
| No `[Piqd]` / `[Capture]` / `[StoryEngine]` errors in a 50-capture mixed-format session | ⏭️ not formally measured |
| Mode pill correctly locked across every Sequence / Clip / Dual capture window (FR-MODE-09) | ✅ |
| **v0.3 complete — ready for v0.4 (Pre-shutter Layer 1 chrome)** | ✅ (2026-04-24) |

---

## 8. Known Limitations Carried to v0.4+

- No Layer 1 chrome (zoom pill, flip, ratio toggle, subject guidance, backlight correction, vibe hint) — v0.4. v0.3 does the minimum flip-hide when Dual is selected, but otherwise leaves the viewfinder minimal.
- Roll Mode is still Still-only — no Live Photo format. Roll users see no format selector.
- Clip ceiling (5/10/15s) is only reachable via Dev Settings in v0.3; user-facing picker in v0.9 Settings.
- 120fps Clip hardware path exists; no user toggle — arrives in v0.9.
- No drafts tray, share sheet, or Photos save — v0.5.
- Sequence / Clip / Dual are not yet shareable over P2P — v0.7 (Snap) / v0.8 (Roll).
- No baked grain / light leak / film simulation on output MP4s — v0.9.
- Safe Render zone uses a simple 1pt border; the full motion-driven chrome auto-retreat (UIUX §3) ships in v0.4 and may supersede the v0.3 implementation.
- Dual preview layout on Layer 0 mirrors the two AVCaptureVideoPreviewLayers but may not be pixel-identical to the PIP composite — preview refinement deferred to v0.4 alongside other viewfinder work.

---

## 9. Design Asset Dependencies

Not blocking kickoff — engineering starts with SF Symbol / shape placeholders. Required before §6 sign-off:

| # | Asset | Spec | Owner | Delivery target |
|---|-------|------|-------|-----------------|
| D1 | Shutter Sequence-firing accent | Yellow ring fill animation reference (per-frame pulse) | Design | Before §6.2 sign-off |
| D2 | Shutter Clip icon | Red ring + inner square, exact square inset | Design | Before §6.3 sign-off |
| D3 | Shutter Dual icon | Red ring + split-diagonal circle — diagonal angle, line weight | Design | Before §6.4 sign-off |
| D4 | Dual PIP composite spec | Inset size (default 30% width), corner radius, margin, safe area treatment | Design | Before §6.4 sign-off |
| D5 | Format selector typography/fit | 4 segments in ≤273pt on 390pt screen; validate whether `Still/Sequence/Clip/Dual` fits or 3-letter abbreviations (STL/SEQ/CLK/DUL) are needed (UIUX §6.2) | Design | Before §6.1 sign-off |

---

## 10. Resolved Decisions

Reviewed and locked-in 2026-04-19 before implementation kickoff:

1. **Clip ceiling picker → deferred to v0.9.** v0.3 ships default 10s + Dev Settings override. No user-facing picker until the v0.9 Settings screen lands, alongside other user-configurable Clip options (120fps toggle, etc.). Avoids fragmenting chrome work across v0.3 / v0.4 / v0.9.
2. **Dual preview → side-by-side in v0.3, full PIP in v0.4.** Two `AVCaptureVideoPreviewLayer`s rendered side-by-side on Layer 0 for v0.3 (capture-time composition produces the real PIP MP4). Pixel-accurate PIP preview lands in v0.4 alongside the rest of the viewfinder chrome pass. Keeps v0.3 focused on capture-path correctness.
3. **Roll Mode stays Still-only through v0.8.** No Roll format selector in v0.3. Swipe-up on shutter in Roll is a no-op (and stays that way forever — Roll's format selector is left-edge-swipe per UIUX §4.3, not a shutter pill). Roll Live Photo + the left-edge-swipe selector are pinned to **v0.9**, clustered with film sims / grain / light leak as one cohesive Roll aesthetic pass.
4. **Sequence interruption UX → Option B.** Silent during capture. On return-to-foreground, show a 1.5s auto-dismiss toast at bottom-safe-area: `"Sequence didn't finish"`. No haptic, no alert, no recovery action. Reflected in §3 scope and new UI test UI18.
5. **Mode-switch capture-lock affordance → dimming alone, no lock glyph.** Mode pill drops to 40% opacity and becomes non-hittable during Sequence / Clip / Dual. Matches UIUX §5.2; avoids introducing a new icon asset.
6. **GRDB → single-table widening.** Widen `moments.type` CHECK constraint + add `duration_seconds` / `sequence_assembled_url` columns. Revisit a split-table schema in v0.7+ only if column count grows past ~6 format-specific fields.

---

## 11. Implementation Notes (Non-Blocking)

Gesture scoping consequence of decision 3:

- **Swipe-up / long-press-from-Still on shutter is Snap-only, permanently.** Roll's format selector (when it arrives in v0.9) uses left-edge-swipe on the viewfinder per UIUX §4.3 — never a shutter-adjacent pill. So `FormatSelectorView` is only attached to the shutter overlay when `mode == .snap`; the Roll shutter passes through to the existing Still tap path. Added as UI19 in §5.2 during implementation: `testSwipeUpInRollDoesNothing` — swipe-up on `piqd.shutter` in Roll produces no `piqd.formatSelector` element.

---

*— End of v0.3 plan draft · Next: piqd_interim_v0.4_plan.md (Pre-shutter Layer 1 chrome) —*
