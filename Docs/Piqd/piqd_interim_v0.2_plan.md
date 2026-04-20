# Piqd v0.2 — Mode System

# Long-Hold Mode Pill · Roll Mode viewfinder · 24-shot counter · Per-mode aspect ratio

_Parent plan: [piqd_interim_version_plan.md](piqd_interim_version_plan.md)_
_Reference: piqd_PRD_v1.1.md §4.2, §5.4 (Aspect Ratio), §6 (Roll Mode) · piqd_SRS_v1.0.md §4.2, §4.4, §7.2 · piqd_UIUX_Spec_v1.0.md (Layer 0, Mode Switch Animation)_
_Status: ⬜ Not Started_

---

## 1. Purpose

Introduce the mode system that is Piqd's core architectural premise: two cameras, one device. v0.2 adds Roll Mode alongside the Snap Mode shipped in v0.1, the long-hold-pill gesture that switches between them, the analog viewfinder aesthetic that defines Roll, and the per-mode capture constraints (24-shot daily Roll limit, per-mode default aspect ratio). Still the only capture format — Sequence / Clip / Dual arrive in v0.3. No sharing, no drafts, no onboarding.

The version validates four architectural risks at once:
1. Mode state persistence and hydration on cold launch (FR-MODE-08).
2. Mode-aware vault separation — Roll assets route to a locked Roll vault distinct from Snap assets, even within the same Piqd namespace.
3. SwiftUI transition from Snap chrome → Roll chrome under the <150ms budget (SRS §7.2).
4. Grain overlay performance — `CIFilter` on `AVCaptureVideoPreviewLayer` holding ≥30fps on iPhone 15 (SRS §8).

---

## 2. Verification Goal

**End-to-end on a real iPhone 15+ device:**

Launch Piqd → opens in last-used mode (Snap on first launch) → long-hold mode pill 1.5s → progress arc completes → confirmation sheet slides up → tap "Switch to Roll" → within 150ms the viewfinder morphs to Roll (grain overlay, amber pill, 4:3 frame, 24-shot counter visible) → tap shutter → counter decrements to 23 → background and relaunch → still in Roll Mode, counter still 23 → exhaust 24 captures → shutter disables, "Roll's full. See you at 9." shown → switch back to Snap (long-hold, confirm) → 9:16 frame, no grain, no counter → counter state preserved on next Roll entry.

**Success = all automated tests green + every §6 device checklist row passes.**

---

## 3. Scope

### AppConfig

`AppConfig.piqd_v0_2` extends `piqd_v0_1`:

```
features:    [.snapMode, .rollMode]
assetTypes:  [.still]                          // sequence/live/clip/dual still gated off
sharing:     SharingConfig.disabled(maxCircleSize: 0)
storage:     StorageConfig(smartArchiveEnabled: false,
                           iCloudSyncEnabled:   false,
                           rollVaultLocked:     true)   // new flag, see task 4
```

All other Piqd capabilities remain gated off.

### In Scope

- `CaptureMode.roll` path end-to-end — preview, capture, vault write, graph row.
- Mode pill component (Layer 0) — aperture glyph, signal-yellow Snap / darkroom-amber Roll, no text.
- Long-hold 1.5s gesture with circular progress arc around the pill; release-to-abort.
- Confirmation sheet — "Switch to Roll?" / "Switch to Snap?" with mode-tinted primary CTA.
- Mode transition animation ≤150ms: grain fade-in/out, chrome swap, shutter button morph.
- Mode persistence across app lifecycle (backgrounding + cold launch) via `UserDefaults.standard` key `piqd.lastMode`.
- Roll vault sub-namespace: `Documents/piqd/roll/assets/` + `locked=true` flag on `Moment` rows; filtered out of `PiqdVaultDebugView` unless a `#if DEBUG` "Show locked" toggle is on.
- 24-shot per-calendar-day counter — persisted as `{ date: "YYYY-MM-DD", count: Int }` in GRDB; resets at midnight device-local.
- Counter-exhausted state — shutter disabled, "Roll's full. See you at 9." overlay.
- Per-mode aspect ratio default: Snap 9:16, Roll 4:3. No runtime toggle yet (arrives in v0.4 along with the Layer 1 ratio indicator). Implementation: **post-capture center-crop** in `CaptureMomentUseCase` between `AVCapturePhotoOutput` delivery and vault write; preview layer renders a matching letterbox mask for WYSIWYG. Roll 4:3 is sensor-native (no-op crop); Snap 9:16 crops from 4:3.
- **HEIF encoder for Piqd vault.** All Piqd captures write `.heic` files via a new `ImageEncoder` abstraction. niftyMomnt namespace defaults to the existing JPEG encoder — no migration, no dual-read. The post-capture crop step outputs encoded bytes directly, so the encoder swap is the same code path as the crop.
- Grain overlay as a **SwiftUI `TimelineView` noise layer** stacked above the untouched `AVCaptureVideoPreviewLayer` — tiled monochrome `Canvas` with time-drifting seed, `.overlay` blend at opacity 0.12, mounted only when `mode == .roll`. Viewfinder-only in v0.2 — grain is not baked into captured HEIFs until v0.9 ships the Metal/CIContext render pipeline that film sims also depend on.
- Film counter readout in Roll — small `23 / 24` style numeral, Layer 0, top-right safe area.
- **Mode state lives in the app layer.** `ModeStore` is the single source of truth; `CaptureMomentUseCase.switchMode(to:)` is renamed `reconfigureSession(for:)` and becomes stateless — it only reconfigures `AVCaptureSession` (preview mask, aspect target) when the store tells it to. NiftyCore stays free of `UserDefaults` and persistence protocols.
- **Hidden Dev Settings screen** (`#if DEBUG` only) — reached via a 5-tap gesture on the mode pill, or a "Dev" row in `PiqdVaultDebugView`. Backed by a single `DevSettingsStore` (`UserDefaults` suite `piqd.dev`) so settings persist across relaunches and can also be pre-seeded via launch args for CI. v0.2 settings:
  - `rollDailyLimit: Int` (default 24, range 1…24) — overrides the hardcoded 24 cap. Lets a tester exhaust the counter in 3 shots instead of 24.
  - `rollCounterResetOnLaunch: Bool` (default false) — resets today's counter on every cold launch.
  - `forceRollFull: Bool` (default false) — counter pinned at 0 regardless of captures.
  - `modeSwitchHoldDuration: TimeInterval` (default 1.5, range 0.3…3.0) — shortens the long-hold for UI iteration.
  - `grainOverlayEnabled: Bool` (default true) — lets design A/B the Roll viewfinder without grain.
  - `grainOpacity: Double` (default 0.12, range 0.00…0.30) — overlay blend opacity for calibration.
  - `grainRefreshHz: Double` (default 24, range 8…60) — seed refresh rate; slower-than-frame-rate reads as grain, not flicker.
  - `hapticsEnabled: Bool` (default true) — disables long-hold haptic; required for deterministic XCUITest runs.
  - `clearPiqdVault: Button` — wipes `Documents/piqd/` and resets GRDB; confirmation required.
  - `resetModeToSnap: Button` — clears `piqd.lastMode`.
  The screen is designed as a list of typed rows so adding a new knob in later versions (e.g. mock 9 PM trigger in v0.8, force APNs path in v0.7) is a one-row change, not a new screen.

### Out of Scope (deferred)

| Feature | Deferred to |
|---------|-------------|
| Format selector (Still → Sequence → Clip → Dual) | v0.3 |
| Layer 1 chrome (zoom pill, flip, ratio toggle) | v0.4 |
| Aspect ratio user toggle (9:16 ↔ 1:1 / 4:3 ↔ 1:1) | v0.4 |
| Drafts tray, share sheet, save-to-Photos | v0.5 |
| First-Roll storage warning dialog | v0.6 (onboarding) |
| Film simulation presets (kodakWarm / fujiCool / ilfordMono) baked into capture | v0.9 |
| Light leak overlay, ambient metadata | v0.9 |
| Roll unlock (9 PM / 24h trigger), StoryEngine, CloudKit delivery | v0.8 |
| Onboarding screen that teaches the long-hold gesture | v0.6 |
| 3-session long-hold hint on the pill | v0.6 |
| Short-tap-on-pill hint text | v0.6 |

---

## 4. Implementation Tasks

| # | Task | File(s) | Owner | Status |
|---|------|---------|-------|--------|
| 1 | Add `AppConfig.piqd_v0_2` with `[.snapMode, .rollMode]` features; route `PiqdApp` to use it | `Apps/Piqd/Piqd/AppConfig+Piqd.swift`, `Apps/Piqd/Piqd/PiqdApp.swift` | Eng | ⬜ |
| 2 | `ModeStore` — observable current-mode source of truth; persists to `UserDefaults` key `piqd.lastMode`; hydrates on init | `Apps/Piqd/Piqd/UI/Capture/ModeStore.swift` | Eng | ⬜ |
| 3a | `NowProvider` protocol + `SystemNowProvider` in NiftyCore; `MockNowProvider` in test support — injected only into the two sites v0.2 needs (`RollCounterRepository`, `ModeStore`'s dev-menu 5-tap gesture) | `NiftyCore/Sources/Domain/Protocols/NowProvider.swift` | Eng | ⬜ |
| 3b | Introduce GRDB `DatabaseMigrator` for the Piqd namespace. Register `m_v0_1_initial_schema` (matches shipped v0.1 tables — no-op on existing installs via `schema_migrations`) and `m_v0_2_roll_counter_and_locked` (creates `roll_counter`, adds `moments.locked` column with `DEFAULT 0`). Run from `GraphRepository.open(namespace:)`. niftyMomnt keeps its existing path until its next schema change | `NiftyData/Sources/Repositories/Migrations/PiqdMigrations.swift`, `GraphRepository.swift` | Eng | ⬜ |
| 3 | `RollCounterRepository` — reads/writes via GRDB using migrated schema; takes `NowProvider` for calendar-day keying; `increment(dailyLimit:)` throws `RollFull` when count ≥ limit | `NiftyData/Sources/Repositories/RollCounterRepository.swift` | Eng | ⬜ |
| 4a | `AspectRatio` domain enum (`.nineSixteen`, `.oneOne`, `.fourThree`) with `centerCrop(_:) -> CGImage` helper | `NiftyCore/Sources/Domain/Models/AspectRatio.swift` | Eng | ⬜ |
| 4b | `ImageEncoder` protocol in NiftyCore; `HEICEncoder` + `JPEGEncoder` impls in NiftyData using `CGImageDestination` with `AVFileType.heic` / `.jpeg` | `NiftyCore/Sources/Domain/Protocols/ImageEncoder.swift`, `NiftyData/Sources/Platform/HEICEncoder.swift`, `NiftyData/Sources/Platform/JPEGEncoder.swift` | Eng | ⬜ |
| 4 | Extend `VaultRepository` config with `locked: Bool` flag **and** `encoder: ImageEncoder`; Piqd namespace uses `HEICEncoder` → writes `.heic`; niftyMomnt defaults to `JPEGEncoder` → writes `.jpg` unchanged; Roll captures write to `Documents/piqd/roll/assets/` with `locked=true` in Graph | `NiftyData/Sources/Repositories/VaultRepository.swift`, `GraphRepository.swift` | Eng | ⬜ |
| 5 | `CaptureMomentUseCase` — rename `switchMode(to:)` → `reconfigureSession(for:)` (stateless); add post-capture crop step: decode `AVCapturePhoto` → `AspectRatio.centerCrop` for mode target → `ImageEncoder.encode` → vault write. When `mode == .roll`: check `RollCounterRepository`, route to locked vault, tag asset as locked; throw `CaptureError.rollFull` when counter is full | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift` | Eng | ⬜ |
| 6 | `ModePill` SwiftUI view — aperture glyph, mode-tinted color, long-hold gesture with circular progress arc, emits `onLongHoldComplete`. Fires `UIImpactFeedbackGenerator(style: .soft)` on arc completion (gated by `DevSettingsStore.hapticsEnabled`). Hold duration reads from `DevSettingsStore.modeSwitchHoldDuration`. Start with SF Symbol placeholders (`camera.aperture` / `camera.aperture.fill`); swap to final `aperture.open` / `aperture.stopped` image-set assets when design delivers — see §9 | `Apps/Piqd/Piqd/UI/Capture/ModePill.swift` | Eng | ⬜ |
| 7 | `ModeSwitchSheet` — bottom sheet with target aperture glyph, primary CTA ("Switch"), dismiss ("Stay in X"); tap-outside dismiss | `Apps/Piqd/Piqd/UI/Capture/ModeSwitchSheet.swift` | Eng | ⬜ |
| 8 | `GrainOverlayView` — SwiftUI `TimelineView` + `Canvas`-rendered tiled monochrome luminance noise (3×3 px tiles in a cached 256×256 image, 2× oversample), `.overlay` blend. Seed refresh rate and opacity read from `DevSettingsStore` (defaults `grainRefreshHz=24`, `grainOpacity=0.12`); Roll-only; mounts/unmounts on mode change | `Apps/Piqd/Piqd/UI/Capture/GrainOverlayView.swift` | Eng | ⬜ |
| 9 | `FilmCounterView` — `"{remaining} / 24"` readout, Layer 0 top-right, Roll-only | `Apps/Piqd/Piqd/UI/Capture/FilmCounterView.swift` | Eng | ⬜ |
| 10 | `RollFullOverlay` — persistent "Roll's full. See you at 9." hint; shutter visually disabled when counter=0 | `Apps/Piqd/Piqd/UI/Capture/RollFullOverlay.swift` | Eng | ⬜ |
| 11 | Update `PiqdCaptureView` — wire `ModeStore`, swap chrome by `mode`, render letterbox mask matching mode's target `AspectRatio`, call `reconfigureSession(for:)` on mode change, mount `GrainOverlayView` in Roll | `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ⬜ |
| 12 | Mode transition — animate grain opacity 0↔1, chrome cross-fade, shutter morph; total ≤150ms measured from confirm tap to first post-transition frame | `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ⬜ |
| 13 | `DevSettingsStore` — typed wrapper over `UserDefaults(suiteName: "piqd.dev")`; `@Observable` so SwiftUI rebinds live; each key also accepts a launch-arg override (`PIQD_DEV_<KEY>=...`) for CI seeding | `Apps/Piqd/Piqd/UI/Debug/DevSettingsStore.swift` | Eng | ⬜ |
| 14 | `PiqdDevSettingsView` — `#if DEBUG` list of typed rows (Stepper for `rollDailyLimit`, Toggles, Slider for `modeSwitchHoldDuration`, destructive buttons). Reached via 5-tap on mode pill **or** "Dev" row in `PiqdVaultDebugView` | `Apps/Piqd/Piqd/UI/Debug/PiqdDevSettingsView.swift` | Eng | ⬜ |
| 15 | Wire dev settings into runtime — `RollCounterRepository` reads `rollDailyLimit`, `ModePill` reads `modeSwitchHoldDuration`, `GrainOverlayView` reads `grainOverlayEnabled`, `ModeStore`/`CaptureMomentUseCase` read `forceRollFull` (short-circuits in the Roll capture path) | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift`, repos, UI | Eng | ⬜ |
| 16 | `PiqdVaultDebugView` — add "Show locked" toggle + "Dev Settings" nav row | `Apps/Piqd/Piqd/UI/Debug/PiqdVaultDebugView.swift` | Eng | ⬜ |
| 17 | Extend `ci-piqd.yml` — add new unit + UI suites; keep runtime under 10 min | `.github/workflows/ci-piqd.yml` | Eng | ⬜ |

---

## 5. Automated Test Suite

Target automation coverage: **≥85%** of §6 rows.

### 5.1 Unit Tests (XCTest)

| # | Test | File | Asserts |
|---|------|------|---------|
| U1 | `ModeStore` hydrates from `UserDefaults`; defaults to `.snap` when unset | `PiqdTests/ModeStoreTests.swift` | Cold init returns `.snap`; after `set(.roll)`, next init returns `.roll` |
| U2 | `RollCounterRepository.increment()` under 24 succeeds; the 25th throws `RollFull` | `NiftyDataTests/RollCounterRepositoryTests.swift` | Counts 1…24 succeed; call 25 throws |
| U3 | Counter keyed by device-local calendar day — rolls over at midnight | `NiftyDataTests/RollCounterRepositoryTests.swift` | Inject `MockNowProvider`; 24 on day D, then `advance(by: 1 day)` allows another 24 |
| U3b | Migrations — opening a fresh DB runs both migrations in order; opening a v0.1-shaped fixture DB applies only `m_v0_2_roll_counter_and_locked` and preserves existing moment rows | `NiftyDataTests/PiqdMigrationsTests.swift` | `schema_migrations` rows + row count preservation |
| U4 | Piqd Roll captures land at `Documents/piqd/roll/assets/{id}.heic` with `locked=true` | `NiftyDataTests/VaultRepositoryLockedTests.swift` | Path, extension, flag |
| U5 | niftyMomnt unchanged — still `Documents/assets/{id}.jpg`, `locked=false` | `NiftyDataTests/VaultRepositoryLockedTests.swift` | Back-compat; JPEGEncoder wired by default |
| U5b | Encoder isolation — Piqd file prefix bytes match HEIC (`66 74 79 70 68 65 69 63` at offset 4, `ftypheic`); niftyMomnt file prefix matches JPEG SOI (`FF D8 FF`) | `NiftyDataTests/ImageEncoderMagicBytesTests.swift` | Both assertions in one test |
| U5c | `AspectRatio.centerCrop` — 4:3 input → 9:16 produces width = `height * 9 / 16` ±1px, centered; 4:3 → 4:3 is a no-op (identity `CGImage`) | `NiftyCoreTests/AspectRatioTests.swift` | Dimensions + pixel-center sanity |
| U6 | `CaptureMomentUseCase.execute(mode: .roll, …)` at counter=24 throws `CaptureError.rollFull`; vault unchanged | `NiftyCoreTests/CaptureMomentUseCaseRollTests.swift` | No file written, no graph row |
| U7 | `CaptureMomentUseCase.reconfigureSession(for: .roll)` updates `AVCaptureSession` aspect target; does **not** read or write `UserDefaults` | `NiftyCoreTests/CaptureMomentReconfigureSessionTests.swift` | Mock session receives target; no persistence side effects |
| U7b | `ModeStore.set(.roll)` persists, publishes on the main actor, and `reconfigureSession(for:)` is called exactly once in response | `PiqdTests/ModeStoreIntegrationTests.swift` | Single-call assertion + publisher emission |
| U8 | `AppConfig.piqd_v0_2` is strict superset of `piqd_v0_1` adding only `.rollMode` | `NiftyCoreTests/AppConfigPiqdTests.swift` | No other flag bits flipped |
| U9 | Per-mode aspect ratio default applied on capture: Snap writes a HEIF with 9:16 dimensions; Roll writes 4:3 | `NiftyCoreTests/CaptureGeometryTests.swift` | Read back file, assert width/height ratio within ±1px |

### 5.2 UI Tests (XCUITest) — `PiqdUITests`

Launch with `UI_TEST_MODE=1 PIQD_SEED_EMPTY_VAULT=1 PIQD_DEV_ROLL_COUNTER_RESET_ON_LAUNCH=1`. Any dev-settings key can be pre-seeded via `PIQD_DEV_<KEY>=<value>` launch args — tests that need to exhaust the Roll counter set `PIQD_DEV_ROLL_DAILY_LIMIT=3` to reach "full" in three shots.

| # | Test | Asserts |
|---|------|---------|
| UI1 | `testShortTapPillDoesNothing` | Single tap on mode pill → no sheet, no mode change, pill identifier unchanged |
| UI2 | `testLongHoldShowsConfirmSheet` | Press mode pill 1.6s → `piqd.modeSwitchSheet` appears; target mode label reads "Switch to Roll?" |
| UI3 | `testReleaseBeforeHoldCompleteAborts` | Press 0.8s then release → no sheet; progress arc resets |
| UI4 | `testConfirmSwitchesMode` | Hold → confirm → `piqd.capture.mode` accessibility value changes from "snap" to "roll" within 200ms |
| UI5 | `testDismissSheetKeepsMode` | Hold → sheet up → tap outside → mode unchanged |
| UI6 | `testModePersistsAcrossRelaunch` | Switch to Roll → terminate → relaunch → viewfinder starts in Roll |
| UI7 | `testRollShowsCounterAndGrain` | In Roll: `piqd.filmCounter` shows `24 / 24`; `piqd.grainOverlay` present; neither present in Snap |
| UI8 | `testCaptureDecrementsCounter` | Tap shutter in Roll → counter reads `23 / 24` |
| UI9 | `testRollFullDisablesShutter` | Launch with `PIQD_DEV_FORCE_ROLL_FULL=1` → shutter `isEnabled = false`; `piqd.rollFullOverlay` visible |
| UI10 | `testLockedAssetsHiddenFromDebug` | Capture 2 in Roll, 1 in Snap → debug screen default view shows 1 row; toggle "Show locked" → 3 rows |
| UI11 | `testSwitchDisallowedDuringCapture` | (Stub for v0.3 integration) — currently asserts no-op; wired for format-selector tests later |
| UI12 | `testDevSettingsReachableVia5Tap` | 5 taps on mode pill within 2s → `piqd.devSettings` screen appears; not reachable from a release build path (guard with `#if DEBUG` asserted in a separate Release smoke test) |
| UI13 | `testDevSettingsRollLimitShortensCounter` | Launch with `PIQD_DEV_ROLL_DAILY_LIMIT=3` → Roll counter reads `3 / 3`; 3 shots → full overlay appears (drop-in fast path for §6.3 row 3.2) |
| UI14 | `testDevSettingsHoldDurationShortensGesture` | Set `modeSwitchHoldDuration=0.3` → 0.4s press triggers confirm sheet |

### 5.3 Performance (XCTest `measure`)

| # | Test | Baseline |
|---|------|----------|
| P1 | Mode switch latency — confirm tap → first frame of new aesthetic | p95 <150ms (SRS §7.2) |
| P2 | Grain overlay sustained frame rate — 10s Roll viewfinder capture | ≥30fps average, no frame >50ms |
| P3 | Cold launch into last-used Roll mode | <1.8s (loose — tightens in v0.4) |
| P4 | `RollCounterRepository.increment()` under concurrent calls | No lost updates across 24 parallel increments |

---

## 6. Device Verification Checklist

> Run on iPhone 15 or 15 Pro, iOS 26. Record Pass / Fail / Note per row. All rows must pass before sign-off.

### 6.1 — Mode Pill + Long-Hold

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 1.1 | Launch in Snap (first install) | Pill shows open-aperture glyph, signal-yellow tint | Y (UI7 inverse) | |
| 1.2 | Short tap pill | No action, no sheet | Y (UI1) | |
| 1.3 | Press pill, release at ~0.8s | Progress arc starts then resets; no sheet | Y (UI3) | |
| 1.4 | Press pill, hold 1.5s | Arc completes, light haptic, sheet slides up reading "Switch to Roll?" | Y (UI2) | |
| 1.5 | Tap outside sheet | Sheet dismisses, mode unchanged | Y (UI5) | |
| 1.6 | Tap "Switch" CTA | Viewfinder transitions within 150ms: grain fades in, chrome recolors amber, shutter morphs | Y (UI4, P1) | |
| 1.7 | Long-hold Roll pill → confirm "Switch to Snap?" | Returns to Snap chrome within 150ms | Y (UI4) | |

### 6.2 — Roll Mode Viewfinder

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 2.1 | Roll viewfinder visible | 4:3 aspect frame; grain overlay drifting (not static); counter `24 / 24` top-right | Y (UI7) | |
| 2.2 | Grain frame rate (Instruments Core Animation 10s) | ≥30fps, no spikes >50ms | Y (P2) | |
| 2.3 | ISO / shutter / exposure indicators | Hidden in Roll (SRS §4.4.3) | N | |

### 6.3 — Capture + Counter

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 3.1 | Tap shutter in Roll | `.heic` file persists to `Documents/piqd/roll/assets/{id}.heic`; counter → `23 / 24`; file ratio matches Roll default (4:3) | Y (UI8, U9) | |
| 3.2 | In Dev Settings set `rollDailyLimit=3`, then capture 3 in Roll | Counter `3 → 2 → 1 → 0`; final shot succeeds | Y (UI13) | |
| 3.2b | In Dev Settings restore `rollDailyLimit=24`, capture 24 (sanity) | Counter reaches `0 / 24`; final shot succeeds | partial | |
| 3.3 | Attempt 25th Roll capture | Shutter visually disabled; overlay "Roll's full. See you at 9." | Y (UI9) | |
| 3.4 | Advance device date by one day (Settings → Date) | Counter resets to `24 / 24`; shutter re-enabled | N | |
| 3.5 | Capture in Snap | Writes to `Documents/piqd/assets/`; Roll counter untouched | Y (U4/U5) | |

### 6.4 — Persistence + Coexistence

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 4.1 | Switch to Roll, background 30s, resume | Still in Roll, counter preserved | partial | |
| 4.2 | Switch to Roll, terminate, cold launch | Opens in Roll with same counter | Y (UI6) | |
| 4.3 | Device file browser — `Documents/piqd/roll/assets/` vs `Documents/piqd/assets/` | Disjoint; each contains only its mode's assets, all `.heic` | N | |
| 4.6 | Coexist with niftyMomnt: capture in both apps | niftyMomnt vault contains `.jpg`; Piqd vault contains `.heic`; no cross-contamination | Y (U5b) | |
| 4.4 | Debug screen default | Only Snap assets listed | Y (UI10) | |
| 4.5 | Debug "Show locked" toggle | Roll assets appear alongside Snap | Y (UI10) | |

### 6.5 — Dev Settings (DEBUG builds only)

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 5.1 | 5-tap mode pill within 2s | Dev Settings screen opens | Y (UI12) | |
| 5.2 | From `PiqdVaultDebugView` → "Dev Settings" row | Same screen opens | N | |
| 5.3 | Change `rollDailyLimit` to 5, back out to viewfinder | Counter immediately reads `5 / 5` (or `min(current, 5)` if mid-day) | Y (UI13) | |
| 5.4 | Toggle `grainOverlayEnabled` off | Roll viewfinder updates live — grain disappears within one frame | N | |
| 5.5 | Tap "Clear Piqd Vault" → confirm | `Documents/piqd/` empty; counter reset; mode reset to Snap | N | |
| 5.6 | Verify Release build has no Dev Settings entry point | 5-tap does nothing; no "Dev Settings" row in debug screen (debug screen itself is `#if DEBUG`) | N | |

### 6.6 — Edge Cases

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 5.1 | Long-hold pill while shutter animation running | Pill gesture takes priority; capture completes; sheet still appears | N | |
| 5.2 | Rapid 10 shutter taps in Roll | Counter decrements exactly 10; no double-decrement, no lost writes | Y (P4) | |
| 5.3 | Background during mode transition | App returns to target mode (never a half-transitioned state) | N | |
| 5.4 | Airplane mode | All mode + capture flows function — no network dependencies in v0.2 | N | |
| 5.5 | Low storage (<100 MB) | Capture fails gracefully; counter does **not** decrement on failed write | N | |

---

## 7. Sign-off Criteria

| Item | Status |
|------|--------|
| All §4 implementation tasks complete | ⬜ |
| All §5 automated tests green in CI on `iPhone 15 Pro` simulator + iOS 26 | ⬜ |
| All §6 device checklist rows Pass | ⬜ |
| Mode switch p95 <150ms (P1), grain ≥30fps (P2) on iPhone 15 | ⬜ |
| No `[Piqd]` / `[ModeStore]` / `[RollCounter]` errors in a 30-capture mixed-mode session | ⬜ |
| Snap and Roll assets verifiably disjoint on device filesystem | ⬜ |
| Roll counter survives backgrounding, cold launch, and a calendar-day rollover | ⬜ |
| **v0.2 complete — ready for v0.3 (Snap Format Selector)** | ⬜ |

---

## 8. Known Limitations Carried to v0.3+

- No format selector pill — Still is the only format in both modes.
- No Layer 1 chrome (zoom pill, flip button, ratio toggle) — arrives in v0.4.
- Aspect ratio is fixed per mode — no in-session 9:16 ↔ 1:1 or 4:3 ↔ 1:1 cycling yet.
- Grain is a SwiftUI `TimelineView` overlay over the preview layer, **not** a CI/Metal render pipeline. Viewfinder-only — not baked into captured HEIFs. Replaced in v0.9 with an `AVCaptureVideoDataOutput` → `CIContext` → `MTKView` pipeline that bakes grain, light leak, and film sims into output HEIFs.
- Piqd captures `.heic` via `HEICEncoder`; niftyMomnt remains on `.jpg` via `JPEGEncoder`. This split is **permanent** — no migration of existing niftyMomnt JPEGs is planned.
- No first-Roll storage warning dialog — arrives with onboarding in v0.6.
- No "teach the long-hold" onboarding, no 3-session hint — v0.6.
- Roll assets remain permanently locked in v0.2 — there is no unlock path until v0.8. Debug screen is the only way to inspect them.
- Mode-switch-disabled-during-capture (FR-MODE-09) is stubbed — fully wires up in v0.3 alongside Sequence capture.

---

## 9. Design Asset Dependencies

Not blocking kickoff — engineering starts with SF Symbol placeholders and swaps in finals on delivery. Required before §6 device checklist sign-off:

| # | Asset | Spec | Owner | Delivery target |
|---|-------|------|-------|-----------------|
| D1 | `aperture.open` (image set) | 6-blade aperture, blades fully open; monochrome, 44pt tappable target, @1x/@2x/@3x; tinted at runtime (signal-yellow in Snap) | Design | Before task 6 final polish |
| D2 | `aperture.stopped` (image set) | 6-blade aperture, blades nearly closed; same size/variants as D1; tinted darkroom-amber in Roll | Design | Before task 6 final polish |
| D3 | Mode-switch sheet aperture glyph | 24pt, target-mode accent color, centered — per UIUX spec §4.2 line 966 | Design | Before task 7 final polish |

If design wants blade-rotation animation later (per UIUX spec §4.2 line 302), engineering swaps the `Image` for a `Canvas`-drawn aperture path — contract on `ModePill` stays identical.

---

*— End of v0.2 plan · Next: piqd_interim_v0.3_plan.md (Snap Format Selector) —*
