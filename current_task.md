# niftyMomnt — Current Progress & Architecture Decisions

_Last updated: 2026-04-09 (v0.1–v0.3 signed off · v0.3.5 in progress · Atmosphere Architecture Pivot)_

---

## What's Done

### 1. Project Scaffold
- `niftyMomnt.xcworkspace` wiring **NiftyCore** and **NiftyData** as local Swift packages alongside two app targets (`niftyMomnt`, `niftyMomntLite`)
- `AppContainer` (`@MainActor @Observable`) as the composition root — all use cases, managers, and the shared `AVCaptureSession` injected here and passed down the SwiftUI environment
- `NiftyMomntApp` wires all concrete adapters → engines → use cases → container in one place; no SwiftUI view ever creates a concrete dependency

### 2. Domain Layer — NiftyCore (complete scaffold)
| File | Status |
|---|---|
| `Models/` — `Moment`, `Asset`, `VibeTag`, `AppConfig`, `FeatureSet`, `AssetTypeSet`, `AmbientMetadata` | ✅ |
| `Protocols/` — `CaptureEngineProtocol`, `VaultProtocol`, `GraphProtocol`, `SoundStampPipelineProtocol`, `FixRepositoryProtocol`, `IndexingProtocol`, `LabClientProtocol`, `NudgeEngineProtocol` | ✅ |
| `UseCases/` — `CaptureMomentUseCase` (full 8-step pipeline incl. Live MOV step 5b + Echo .m4a path), `FixAssetUseCase`, `AssembleReelUseCase`, `ShareMomentUseCase`, `GenerateNudgeUseCase` | ✅ |
| `Engines/` — `CaptureEngine`, `IndexingEngine` (classifyImmediate), `StoryEngine`, `NudgeEngine`, `VoiceProseEngine` | ✅ |
| `Managers/` — `VaultManager` (incl. `saveAudioFile`, `saveLiveMovieFile`), `GraphManager` (fetchMoments), `LabClient` | ✅ |
| `SupportingTypes` — `Notification.Name.niftyMomentCaptured`, `.niftyMomentDeleted` | ✅ |

### 3. Platform Layer — NiftyData (adapters)
| Adapter | Status |
|---|---|
| `AVCaptureAdapter` | ✅ live — real `AVCaptureSession`, photo capture via `AVCapturePhotoOutput`, `PhotoDelegate` bridging async/await, camera flip, Live Photo (`livePhotoMovieFileURL`), Echo via `EchoRecordingSession` (AVAudioRecorder), Clip/Atmosphere via `AVCaptureMovieFileOutput` |
| `CoreMLIndexingAdapter` | ✅ live — `VNClassifyImageRequest` + `CIAreaAverage` palette + Open-Meteo weather |
| `VaultRepository` | ✅ live — `Documents/assets/{id}.jpg/.mov/.m4a` + `.json` sidecar, `saveVideoFile`, `saveAudioFile`, `saveLiveMovieFile`, `exportToPhotoLibrary` (PHPhotoLibrary), full `delete` |
| `GraphRepository` | ✅ live — GRDB SQLite, WAL, schema: `assets`/`moments`/`moment_assets`/`place_history`, L4C tables |
| `SoundStampAdapter`, `CoreImageFixAdapter` | 🔲 stub |
| `LabNetworkAdapter`, `MapKitGeocoderAdapter`, `WeatherKitAdapter` (→ Open-Meteo), `SpeechAdapter`, `JournalSuggestionsAdapter` | ✅/🔲 |

### 4. UI Layer — Spec v1.8 (complete)

#### CaptureHub (`UI/CaptureHub/`)
- **Zone A (top bar)** — glass overlay on live preview; Flash · Timer · Film Strip Counter · Flip Camera · More
- **Zone B (viewfinder)** — `CameraPreviewView` with live camera feed; focus/exposure lock wired on 600ms long-press
- **Zone C (preset bar)** — amber accent strip, preset name, 5 peek swatches; swipe to cycle, long-press to open picker
- **Zone D (shutter row)** — 84pt shutter; last-captured thumbnail shown left of shutter
- **§4.5 Post-Capture Overlay** — location chip, 4 tilted vibe sticker chips, quick share pill
- **Capture Controls deck** — mode-aware floating glass panel; values persist via `@AppStorage`
- **Live Photo pill** (Zone A right ①) — toggles STILL ↔ LIVE mode; active/dim state wired

#### Journal (`UI/Journal/`)
- `JournalContainerView` — `#0F0D0B` shell; glass tab bar; swipe-down dismisses
- `FilmFeedView` — loads real `[Moment]` from `GraphManager`; refreshes on `niftyMomentCaptured` / `niftyMomentDeleted`; grouped THIS WEEK / LAST WEEK / MONTH; interleaves Moments and L4CRecords
- `MomentCardView` — loads hero + type-appropriate thumbnail from vault via async `.task`; **Echo hero renders a `UIGraphicsImageRenderer`-drawn placeholder** (dark amber gradient + waveform icon) so `heroImage` is always non-nil and the card is tappable
- `MomentDetailView` — loads hero from vault; Live → `PHLivePhotoView`; Echo → `EchoAudioPlayerCardView` (AVPlayer on .m4a); Clip/Atmosphere → inline video player; Fix / Share / Export to Photo Library / Delete actions

#### Atmosphere (v0.3.6)
- Pivot to **Still + Looping Audio (JPEG + M4A)**. High-res capture during background audio recording. | ✅ |

---

## Architecture Decisions

### A — Safe area via UIKit, not SwiftUI GeometryProxy
`GeometryProxy.safeAreaInsets` returns 0 inside nested `ignoresSafeArea()` chains. Views read real values from `UIApplication.shared.connectedScenes` → `UIWindow.safeAreaInsets` in `.onAppear`.

### B — AVCaptureSession owned by AVCaptureAdapter, shared via AppContainer
`AVCaptureAdapter` owns `AVCaptureSession` as `public let session`. `AppContainer` exposes `captureSession` so `CameraPreviewView` can attach its preview layer without knowing about the adapter.

### C — CaptureEngine is MainActor, session runs on background queue
`session.startRunning()` / `stopRunning()` dispatched to `DispatchQueue.global(qos: .userInitiated)` inside `CheckedContinuation` wrappers.

### D — NiftyCore has zero platform imports
Only Foundation, Combine, Swift. All OS frameworks isolated to `NiftyData` adapters behind protocols.

### E — Vision inference on detached task
`IndexingEngine.classifyImmediate` wraps `VNImageRequestHandler.perform` (synchronous) in `Task.detached(priority: .userInitiated)` to avoid blocking any actor thread.

### F — GRDB WAL set via prepareDatabase
`PRAGMA journal_mode = WAL` must execute outside a transaction. Set via `Configuration.prepareDatabase` — not inside `queue.write { }`.

### G — DB and assets both in Documents, no App Group needed
`Documents/graph.sqlite` and `Documents/assets/` share the same container. App Group deferred to v0.9+ when a widget/extension target is added.

### H — VibePresetUI is a UI-layer struct, not a domain model
`VibePresetUI` lives in `DesignSystem.swift`. Domain `VibeTag` → accent color mapping done at presentation layer.

### I — Multi-variant via AppConfig, not separate targets
Feature gating at runtime via `container.config.features.contains(...)`. `AppConfig.v0_1` through `AppConfig.v0_9` defined in `AppConfig+Interim.swift`.

### J — AVCaptureSession on a dedicated serial queue
All `beginConfiguration` / `commitConfiguration` / `startRunning` / `stopRunning` calls are dispatched through a private `sessionQueue: DispatchQueue`. Calling these from ad-hoc Swift concurrency threads causes multi-second stalls.

### K — Audio input tracked by instance variable, not `session.inputs` scan
`audioDeviceInput: AVCaptureDeviceInput?` stores the microphone input directly. Iterating `session.inputs` after `stopRunning()` can return invalidated device inputs.

### L — photoBooth mode switch deferred to START tap
Swiping to `.photoBooth` does **not** fire `switchMode`. The hardware class-change is deferred to `BoothCaptureView.prepareAndRunBoothLoop()`.

### M — Single `CameraPreviewView` instance hoisted above if/else branch
Prevents AVFoundation from tearing down and reconnecting `AVCaptureVideoPreviewLayer` on mode transitions (~0.4s black-preview gap).

### N — End-to-end gesture latency instrumentation
`cycleMode` captures `CACurrentMediaTime()` at gesture receipt and threads it through to `AVCaptureAdapter.switchMode`. Measured class-change latency: ~0.31–0.44s (hardware constraint).

### O — L4C stays inside the same CaptureHub shell
BOOTH is not a separate full-screen mini-app. Zone B gets the 4-slot overlay on top of live preview; shutter row enters START state; review sheet rises over CaptureHub.

### P — Asset settings separated from asset type in CaptureHub UI
The `More` pill opens a mode-aware `Capture Controls` deck (§2.3 defaults). Values persist with `@AppStorage`.

### Q — Echo is photo-class in AVCaptureSession
`isVideoMode(.echo)` returns `false`. Echo recording uses `AVAudioRecorder` (`EchoRecordingSession`) which manages the `AVAudioSession` independently. Classifying Echo as video-class causes `AVCaptureSession` to add an audio input and reconfigure the shared `AVAudioSession`, which conflicts with `EchoRecordingSession.init` and silently prevents recording from starting.

### R — Echo card hero image is a rendered UIImage placeholder
`MomentCardView.loadThumbnail` for `.echo` calls `echoPlaceholderImage()` — a `UIGraphicsImageRenderer`-drawn 400×260 image (dark amber gradient + waveform icon). This ensures `heroImage` is always non-nil for Echo cards, making the `Image(uiImage:)` branch fire and the card tappable. A pure SwiftUI `ZStack` with gradient is not reliably hit-testable when `heroImage` is nil.

### S — Atmosphere is Photo-class hybrid (JPEG + M4A)
`isVideoMode(.atmosphere)` returns `false`. Atmosphere capture records background audio via `AVAudioRecorder` while maintaining the Photo-output class for high-resolution imagery. `stopVideoRecording()` triggers a `capturePhoto` call to obtain the high-res frame. The vault stores `{id}.jpg` and `{id}.m4a` for this type.

### T — Atmosphere Detail Playback
`MomentDetailView` loads the Atmosphere JPEG as the primary hero and initializes an `AVPlayer` with the companion M4A set to loop indefinitely. This provides a "Living Still" experience.

---

## v0.1 — Verification Status ✅ SIGNED OFF

All rows passing. See `Docs/interim_version_plan.md` §v0.1.

---

## v0.2 — Persistent Metadata & Feed Quality ✅ SIGNED OFF

All rows passing. WeatherKit replaced with Open-Meteo free API. See `Docs/interim_version_plan.md` §v0.2.

---

## v0.3 — Multi-Mode Capture ✅ SIGNED OFF

### Live Mode — fully implemented
| Task | File(s) | Status |
|------|---------|--------|
| `AVCapturePhotoOutput.isLivePhotoCaptureEnabled` + `livePhotoMovieFileURL` | `AVCaptureAdapter.swift` | ✅ |
| Two-phase `PhotoDelegate` (stores JPEG in `didFinishProcessingPhoto`, resumes in `didFinishCapture`) | `AVCaptureAdapter.swift` | ✅ |
| `VaultProtocol` / `VaultManager` / `VaultRepository` — `saveLiveMovieFile` | various | ✅ |
| `CaptureMomentUseCase` step 5b — move companion MOV from temp to vault | `CaptureMomentUseCase.swift` | ✅ |
| `MomentDetailView` — `PHLivePhotoView` playback via `LivePhotoPlayerView` | `JournalFeedView.swift` | ✅ |
| Live Photo pill (Zone A) toggles STILL ↔ LIVE | `CaptureHubView.swift` | ✅ |
| `VaultRepository.delete` removes both `{id}.jpg` and `{id}.mov` | `VaultRepository.swift` | ✅ |
| `exportToPhotoLibrary` — JPEG+pairedVideo for Live, JPEG for Still, MOV for Clip/Atmosphere | `VaultRepository.swift` | ✅ |

### Echo Mode — fully implemented (two bugs fixed this session)

**Bug 1 — Echo recording silently failed after capture:**
- Root cause: `isVideoMode(.echo) = true` caused `switchMode` to add `AVCaptureMovieFileOutput` + audio input, locking the shared `AVAudioSession`. `EchoRecordingSession.init` then failed to reconfigure it, `recorder.record()` returned false, `activeEchoRecording` stayed nil. On stop tap, `stopRecording()` threw → no `niftyMomentCaptured` notification → no card in feed.
- Fix: `isVideoMode` now returns `false` for `.echo`. Session stays in photo-output class during Echo mode. `EchoRecordingSession` owns the audio session cleanly. (`AVCaptureAdapter.swift`)

**Bug 2 — Echo card not tappable in JournalFeedView:**
- Root cause: `loadThumbnail` returned `nil` for `.echo`, so `heroImage` was nil. The hero section rendered a SwiftUI `LinearGradient` which is not hit-testable by default. Taps did not reach the enclosing `Button`.
- Fix: `loadThumbnail` for `.echo` now calls `echoPlaceholderImage()` — a `UIGraphicsImageRenderer`-drawn `UIImage` (400×260, dark amber gradient + waveform icon). `heroImage` is always non-nil; `Image(uiImage:)` branch fires; card is tappable. (`MomentCardView.swift`)

### Atmosphere Mode — fully implemented
| Task | File(s) | Status |
|------|---------|--------|
| Architecture pivot: JPEG + M4A (Still + Looping Audio) | `AVCaptureAdapter.swift` | ✅ |
| `stopRecording` triggers photo capture for Atmosphere | `AVCaptureAdapter.swift` | ✅ |
| `loadHeroImage` dual-load for Atmosphere | `JournalFeedView.swift` | ✅ |
| `VaultRepository.delete` removes both resources | `VaultRepository.swift` | ✅ |

---

## v0.3.5 — Life Four Cuts (Photo Booth Mode) 🔄 IN PROGRESS

**AppConfig:** `AppConfig.v0_3_5` — same as v0.3 + `features: .l4c`

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1–14 | All implementation tasks (see `Docs/interim_version_plan.md` §10) | various | ✅ |
| 15 | Frame PNG art assets (3 frames) | `Assets.xcassets/` | ⬜ design deliverable |

**Remaining BOOTH quality gap:**
- Preview framing and final captured crop do not yet match closely enough
- Next milestone: unify live preview guide geometry, booth still normalization/cropping, and final strip slot geometry for `4:3` and `3:4`

**Pending:**
- Tighten preview-to-capture crop matching
- Device verification of updated BOOTH framing
- Frame PNG art assets (design deliverable)

---

## Next Steps

1. **Echo verification on device** — now that both bugs are fixed, run the v0.3 §4 Echo checklist in `Docs/interim_version_plan.md`
2. **Atmosphere verification** — v0.3 §5 (still on placeholder `.mov` path; full PRD alignment deferred)
3. **BOOTH framing** — unify preview guide ↔ crop ↔ strip slot geometry
4. **v0.3.5 sign-off** — full booth flow device verification
