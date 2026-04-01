# niftyMomnt — Current Progress & Architecture Decisions

_Last updated: 2026-04-01_

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
| `UseCases/` — `CaptureMomentUseCase` (+ `startPreview`/`stopPreview`), `FixAssetUseCase`, `AssembleReelUseCase`, `ShareMomentUseCase`, `GenerateNudgeUseCase` | ✅ |
| `Engines/` — `CaptureEngine`, `IndexingEngine`, `StoryEngine`, `NudgeEngine`, `VoiceProseEngine` | ✅ scaffold, logic stubbed |
| `Managers/` — `VaultManager`, `GraphManager`, `LabClient` | ✅ scaffold |

### 3. Platform Layer — NiftyData (adapters)
| Adapter | Status |
|---|---|
| `AVCaptureAdapter` | ✅ **live** — real `AVCaptureSession`, permission check, back wide-angle input, background `startRunning()`/`stopRunning()` |
| `SoundStampAdapter`, `CoreMLIndexingAdapter`, `CoreImageFixAdapter` | 🔲 stub |
| `VaultRepository`, `GraphRepository` | 🔲 stub |
| `LabNetworkAdapter`, `MapKitGeocoderAdapter`, `MusicKitAdapter`, `WeatherKitAdapter`, `SpeechAdapter`, `JournalSuggestionsAdapter` | 🔲 stub |

### 4. UI Layer — Spec v1.8 (complete)

#### CaptureHub (`UI/CaptureHub/`)
- **Zone A (top bar)** — glass overlay on live preview; icon order: Flash · Timer · Film Strip Counter · Live Photo · More; heights driven by UIKit safe area (see decision §A below)
- **Zone B (viewfinder)** — `CameraPreviewView` (`UIViewRepresentable` + `AVCaptureVideoPreviewLayer`) replaces gradient placeholder; live camera feed on device
- **Zone C (preset bar)** — amber accent strip, 17pt/900 preset name, 5 peek swatches (active 12pt/1.0, inactive 9pt/0.5); swipe to cycle, long-press to open picker
- **Zone D (shutter row)** — 84pt shutter button (outer ring 84pt, body 70pt, inner ring 58pt); background extends to screen bottom via `88 + bottomSafeArea`
- **§4.1a AF/AE Lock** — 600ms long-press sets amber lock dot + "AE/AF LOCK" banner pill
- **§4.5 Post-Capture Overlay** — location chip, 4 tilted vibe sticker chips (staggered spring entrance), quick share pill

#### Journal (`UI/Journal/`)
- `JournalContainerView` — `Color.niftyFilmBg` (#0F0D0B) shell; floating glass pill tab bar (Film · Vault · Settings); swipe-down dismisses
- `FilmFeedView` — grouped by THIS WEEK / LAST WEEK / MONTH; inline `filmHeader` (26pt/900 + amber rolls badge + glass header buttons)
- `MomentCardView` — dark editorial card; 3pt left accent strip; 130pt hero gradient; thumbnail strip (up to 4 + overflow); preset play circle; vibe tags
- `MomentDetailView` — full-screen detail sheet; glass nav bar; pagination dots; glass bottom sheet with shot info, vibe chips, Fix/Share/··· actions

#### Other UI
- `VaultView` — locked/unlocked states; Face ID stub
- `SettingsView` — feature-gated toggles (Sound Stamp, Roll Mode, Dual Camera, Photo Fix) backed by `@AppStorage`
- `DesignSystem.swift` — all color tokens, typography, spacing enum, animation presets, `VibePresetUI.defaults`
- `RootView.swift` — ZStack navigation; journal slides up over capture; interactive drag-to-dismiss (threshold 120pt / predicted 280pt); `reduceMotion` support

---

## Architecture Decisions

### A — Safe area via UIKit, not SwiftUI GeometryProxy
`GeometryProxy.safeAreaInsets` returns 0 inside nested `ignoresSafeArea()` chains. `CaptureHubView` reads the real values from `UIApplication.shared.connectedScenes` → `UIWindow.safeAreaInsets` in `.onAppear`. Defaults (top: 59, bottom: 34) cover Dynamic Island iPhones so the first frame is correct before `onAppear` fires.

### B — AVCaptureSession owned by AVCaptureAdapter, shared via AppContainer
`AVCaptureAdapter` owns `AVCaptureSession` as `public let session`. `AppContainer` holds `captureSession: AVCaptureSession` so `CameraPreviewView` can attach its `AVCaptureVideoPreviewLayer` without knowing about `AVCaptureAdapter`. No view ever creates or retains a session.

### C — CaptureEngine is MainActor, session runs on background queue
`CaptureEngine` and `AVCaptureAdapter` are both `@MainActor`. `session.startRunning()` / `stopRunning()` are dispatched to `DispatchQueue.global(qos: .userInitiated)` inside `CheckedContinuation` wrappers — they are synchronous blocking calls that must not run on the main thread.

### D — NiftyCore has zero platform imports
`NiftyCore` imports only Foundation, Combine, and Swift. All OS frameworks (AVFoundation, CoreML, CloudKit, WeatherKit, etc.) are isolated to `NiftyData` adapters behind protocols. This makes the domain layer fully testable without a device.

### E — CaptureMode comes from NiftyCore, not the UI layer
The UI uses `NiftyCore.CaptureMode` (.still / .live / .clip / .echo / .atmosphere) directly. Display helpers (`displayName`, `ghostText`) are private extensions in `CaptureHubView.swift` to avoid leaking presentation concerns into the domain.

### F — VibePresetUI is a UI-layer struct, not a domain model
`VibePresetUI` (id, name, accentColor) lives in `DesignSystem.swift`. It is not part of NiftyCore's `VibePreset` — the domain model doesn't know about Colors. The mapping from `VibeTag` → accent color is done at the presentation layer (`derivedPresetAccent(for:)` in `FilmFeedView`).

### G — Multi-variant via AppConfig, not separate targets
Both `niftyMomnt` and `niftyMomntLite` targets share all UI and domain code. Feature gating is done at runtime via `container.config.features.contains(.soundStamp)` etc. `AppConfig.full` and `AppConfig.lite` are the two entry-point configs.

---

## Next Up

| Priority | Task |
|---|---|
| 🔴 High | Wire `AVCapturePhotoOutput` → `captureAsset()` for still capture |
| 🔴 High | Front/back camera switch (reconfigure session input) |
| 🟡 Medium | `VaultRepository` — CoreData / SwiftData persistence for Moments and Assets |
| 🟡 Medium | `GraphRepository` — relationship graph queries for feed grouping |
| 🟡 Medium | `LocalAuthentication` (Face ID) in `VaultView` |
| 🟢 Low | `AVAssetWriter` pipeline for Clip and Echo modes |
| 🟢 Low | `SoundStampAdapter` — ambient audio fingerprint at shutter |
| 🟢 Low | Real Moment data from `GraphManager` into `FilmFeedView` |
| 🟢 Low | Reel Editor flow (`AssembleReelUseCase`) |
