# niftyMomnt — Current Progress & Architecture Decisions

_Last updated: 2026-04-08 (v0.1–v0.3 signed off · v0.3.5 in progress)_

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
| `UseCases/` — `CaptureMomentUseCase` (full 7-step pipeline), `FixAssetUseCase`, `AssembleReelUseCase`, `ShareMomentUseCase`, `GenerateNudgeUseCase` | ✅ |
| `Engines/` — `CaptureEngine`, `IndexingEngine` (classifyImmediate), `StoryEngine`, `NudgeEngine`, `VoiceProseEngine` | ✅ |
| `Managers/` — `VaultManager`, `GraphManager` (fetchMoments), `LabClient` | ✅ |
| `SupportingTypes` — `Notification.Name.niftyMomentCaptured` | ✅ |

### 3. Platform Layer — NiftyData (adapters)
| Adapter | Status |
|---|---|
| `AVCaptureAdapter` | ✅ live — real `AVCaptureSession`, photo capture via `AVCapturePhotoOutput`, `PhotoDelegate` bridging async/await, camera flip |
| `CoreMLIndexingAdapter` | ✅ live — `VNClassifyImageRequest` → identifier → `VibeTag` keyword mapping |
| `VaultRepository` | ✅ live — `Documents/assets/{id}.jpg` + `{id}.json` sidecar, `AssetRecord` Codable |
| `GraphRepository` | ✅ live — GRDB SQLite at `Documents/graph.sqlite`, WAL via `prepareDatabase`, schema: `assets` / `moments` / `moment_assets` |
| `SoundStampAdapter`, `CoreImageFixAdapter` | 🔲 stub |
| `LabNetworkAdapter`, `MapKitGeocoderAdapter`, `MusicKitAdapter`, `WeatherKitAdapter`, `SpeechAdapter`, `JournalSuggestionsAdapter` | 🔲 stub |

### 4. UI Layer — Spec v1.8 (complete)

#### CaptureHub (`UI/CaptureHub/`)
- **Zone A (top bar)** — glass overlay on live preview; Flash · Timer · Film Strip Counter · Flip Camera · More
- **Zone B (viewfinder)** — `CameraPreviewView` with live camera feed; focus/exposure lock wired on 600ms long-press via transparent gesture overlay + `AVCaptureDevice` point-of-interest configuration
- **Zone C (preset bar)** — amber accent strip, preset name, 5 peek swatches; swipe to cycle, long-press to open picker
- **Zone D (shutter row)** — 84pt shutter; last-captured thumbnail shown left of shutter (loaded from vault after capture)
- **§4.5 Post-Capture Overlay** — location chip, 4 tilted vibe sticker chips, quick share pill
- **Capture Controls deck** — top-right `More` pill opens a floating glass control panel with mode-aware asset settings from PRD §2.3; selections persist via `@AppStorage`

#### Journal (`UI/Journal/`)
- `JournalContainerView` — `#0F0D0B` shell; glass tab bar; swipe-down dismisses
- `FilmFeedView` — loads real `[Moment]` from `GraphManager`; refreshes on `niftyMomentCaptured` notification; grouped THIS WEEK / LAST WEEK / MONTH
- `MomentCardView` — loads hero + thumbnails from `Documents/assets/{id}.jpg` via async `.task`
- `MomentDetailView` — loads hero from vault; glass nav bar; vibe chips; Fix / Share / ··· actions; `UIActivityViewController` share sheet

#### Other UI
- `VaultView`, `SettingsView`, `DesignSystem.swift`, `RootView.swift` — complete

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

---

## v0.1 — Verification Status ✅ SIGNED OFF

| Section | Tests | Status |
|---------|-------|--------|
| 1 — Capture | 1.1–1.4 | ✅ |
| 2 — Persist (Vault) | 2.1–2.2 | ✅ |
| 3 — Classify (VibeTags) | 3.1–3.3 | ✅ |
| 4 — Film Feed | 4.1–4.4 (incl. 4.3 persistence) | ✅ |
| 5 — Share | 5.1–5.4 | ✅ |
| 6 — Edge Cases | 6.1–6.2 | ✅ |

---

## v0.2 — Persistent Metadata & Feed Quality 🔄 IN PROGRESS

**Note:** WeatherKit replaced with Open-Meteo free API (no paid membership required).

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `GeocoderProtocol` + `WeatherProtocol` in NiftyCore | `NiftyCore/Sources/Domain/Protocols/` | ✅ |
| 2 | `MapKitGeocoderAdapter` — `CLGeocoder` → `PlaceRecord` | `NiftyData/Sources/Platform/MapKitGeocoderAdapter.swift` | ✅ |
| 3 | `OpenMeteoWeatherAdapter` — Open-Meteo free API → temp + condition | `NiftyData/Sources/Platform/WeatherKitAdapter.swift` | ✅ |
| 4 | `CoreMLIndexingAdapter.extractPalette()` — `CIAreaAverage` 5-region | `NiftyData/Sources/Platform/CoreMLIndexingAdapter.swift` | ✅ |
| 5 | `CoreMLIndexingAdapter.harvestAmbientMetadata()` — weather + sun position | `NiftyData/Sources/Platform/CoreMLIndexingAdapter.swift` | ✅ |
| 6 | `IndexingEngine` — `extractPaletteImmediate` + `harvestAmbientImmediate` | `NiftyCore/Sources/Engines/IndexingEngine.swift` | ✅ |
| 7 | `CaptureMomentUseCase` — palette + ambient + geocode concurrent in pipeline | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift` | ✅ |
| 8 | `GraphRepository` — ambient/palette columns, `updatePlaceRecord`, `saveMoodPoint` | `NiftyData/Sources/Repositories/GraphRepository.swift` | ✅ |
| 9 | `niftyMomntApp` — wire `OpenMeteoWeatherAdapter` + `MapKitGeocoderAdapter` | `Apps/niftyMomnt/niftyMomntApp.swift` | ✅ |
| 10 | `MomentCardView` — `moment.label` = place name; date subtitle shows weather + sun | `Apps/.../UI/Journal/MomentCardView.swift` | ✅ |

**v0.2 ✅ Signed off.** **v0.3 🔄 Partially verified** — mode switching confirmed on device; full capture/persist/feed verification for all 5 asset types still pending.

---

## v0.3.5 — Life Four Cuts (Photo Booth Mode) 🔄 IN PROGRESS

**AppConfig:** `AppConfig.v0_3_5` — same as v0.3 + `features: .l4c`

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1–14 | All implementation tasks (see `Docs/interim_version_plan.md` §10) | various | ✅ |
| 15 | Frame PNG art assets (3 frames) | `Assets.xcassets/` | ⬜ design deliverable |

**Architecture decisions added during v0.3.5:**

### J — AVCaptureSession on a dedicated serial queue
All `beginConfiguration` / `commitConfiguration` / `startRunning` / `stopRunning` calls are dispatched through a private `sessionQueue: DispatchQueue`. Calling these from ad-hoc Swift concurrency threads causes multi-second stalls (AVFoundation serialises internally on the main thread).

### K — Audio input tracked by instance variable, not `session.inputs` scan
`audioDeviceInput: AVCaptureDeviceInput?` stores the microphone input directly. Iterating `session.inputs` after `stopRunning()` can return invalidated device inputs whose `.device.hasMediaType()` call throws `EXC_BREAKPOINT`.

### L — photoBooth mode switch deferred to START tap
Swiping to `.photoBooth` does **not** fire `switchMode` on `AVCaptureAdapter`. The hardware class-change (video→photo output) is deferred to `BoothCaptureView.prepareAndRunBoothLoop()` which runs it before the first countdown starts. Keeps the UI transition instant (~0.001s from gesture).

### M — Single `CameraPreviewView` instance hoisted above if/else branch
`CameraPreviewView` is placed outside the `if currentMode == .photoBooth { … } else { … }` block in `CaptureHubView.body`. This prevents AVFoundation from tearing down and reconnecting the `AVCaptureVideoPreviewLayer` display path on each mode transition (which caused a ~0.4s black-preview gap).

### N — End-to-end gesture latency instrumentation
`cycleMode` captures `CACurrentMediaTime()` at gesture receipt and threads it through `CaptureMomentUseCase.switchMode → CaptureEngineProtocol.switchMode → AVCaptureAdapter.switchMode`. Logs show: task-start lag, sessionQueue lag, commitConfiguration time, and total-from-gesture time. Measured class-change latency: ~0.31–0.44s (hardware constraint, not addressable further without pre-warming the session).

**Pending:**
- Device verification of full booth flow (countdown → strip → share)
- Frame PNG art assets (design deliverable)

### O — L4C should stay inside the same CaptureHub shell
For v0.3.5 UX consistency, BOOTH should not feel like a separate mini-app or replace the camera surface. The preferred direction is:

- same CaptureHub frame as Still / Live / Clip
- Zone B gets a 4-slot booth strip overlay on top of the live preview
- shutter row stays in the normal place and enters a `START` state for BOOTH
- BOOTH-specific controls live in the same `More` deck (`Featured Frame`, `Border Colour`)
- after shot 4, a review sheet rises over CaptureHub instead of jumping to a totally different full-screen flow

This keeps BOOTH understandable as “another capture mode” and reduces UI fragmentation.

### P — Asset settings separated from asset type in CaptureHub UI
The `More` pill in `CaptureHubView` now opens a compact floating `Capture Controls` deck rather than changing modes or routing to Settings. The deck is mode-aware and scoped to PRD §2.3 defaults:

- Still: Aspect Ratio, Timer, Context Cam, Sound Stamp, Vibe Preview
- Live: Aspect Ratio (read-only `9:16`), Timer, Context Cam, Vibe Preview, Apple Photos export
- Clip: Video Format, Clip Length
- Echo: Echo Limit
- Atmosphere: Loop Length

Implementation notes:

- values persist with `@AppStorage`
- aspect ratio defaults to `9:16`; supported options in the capture deck are `9:16`, `4:5`, and `1:1`
- Live mode is intentionally locked to the default `9:16` ratio for MVP to preserve Apple Live Photo compatibility expectations
- Clip mode now uses SDK-aligned video format choices in the deck: `VGA 4:3`, `HD 16:9`, and `4K 16:9`
- Clip recording now honors the selected duration ceiling in the shutter countdown/progress ring and auto-stops at the configured limit
- Clip recording now maps the selected `VGA` / `HD` / `4K` option to the session preset with safe fallback if a preset is unavailable
- Clip recording now applies output orientation from the user-held device orientation at record start, with portrait fallback
- Clip currently uses tap-to-start / tap-to-stop for v0.3 stabilization; hold-to-record / Slide to Lock is deferred until the recording interaction is made reliable on device
- Clip, Echo, and Atmosphere now show an explicit REC status overlay while recording
- MomentDetailView now loads `.mov` assets for Clip / Echo / Atmosphere with an inline video player instead of falling back to still-only media
- current implementation uses a non-destructive, Apple-like framing treatment in the live preview: soft top/bottom letterbox masks plus a subtle centered ratio chip rather than a boxed frame
- timer pill now reflects the persisted timer default
- Still shutter badge for Sound Stamp now reflects the persisted Sound Stamp toggle
- first pass is UI + persistence focused; not every setting is fully wired into engine behavior yet
