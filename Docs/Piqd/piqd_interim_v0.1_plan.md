# Piqd v0.1 — Minimum Viable Snap Still Capture
# Skeleton + AppConfig.piqd + Snap Still → Vault

_Parent plan: [piqd_interim_version_plan.md](piqd_interim_version_plan.md)_
_Reference: piqd_SRS_v1.0.md §2, §4.3, §10 · piqd_PRD_v1.1.md §5.2.1, §5.4 · piqd_UIUX_Spec_v1.0.md (Viewfinder / Layer 0)_
_Status: ⬜ Not started_

---

## 1. Purpose

Establish the Piqd Xcode target, wire it to the existing NiftyCore SDK, and prove the single narrowest end-to-end path: a user taps the shutter in Snap Mode (Still format), a HEIF asset is captured, encrypted, and persisted in a Piqd-namespaced local vault, and the app can relaunch and show the captured asset on a dev-only Vault Debug screen.

No mode switching, no sharing, no sequence/clip/dual, no pre-shutter features, no UI chrome layering beyond a shutter button and a thumbnail. This version is about the **wiring**, not the product.

---

## 2. Verification Goal

**End-to-end wiring verified on a real iPhone 15+ device:**
Launch Piqd → viewfinder appears in Snap Mode with Still as the only format → tap shutter → HEIF file written to encrypted Piqd vault at `Documents/piqd/assets/{id}.heic` + metadata sidecar in GRDB → relaunch app → Vault Debug screen lists the captured assets → no crash, no console errors.

**Success = all automated tests green + every device checklist row passes.**

---

## 3. Scope

### AppConfig

`AppConfig.piqd_v0_1` — `AppConfig.piqd` with the following FeatureSet mask:

```
features: [.snapMode]         // mode system stub — always snap in v0.1
assetTypes: [.still]          // sequence/live/clip/dual/movingStill off
sharing: SharingConfig.disabled(maxCircleSize: 0)
storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false, ...)
```

All other `AppConfig.piqd` capabilities are gated off by leaving their flags out of the v0.1 mask. This keeps subsequent versions additive — each turns on one flag cluster.

### In Scope

- New Xcode target `Piqd` under `Apps/Piqd/`, bundle ID `com.piqd.app`, minimum iOS 26.0
- `AppConfig+Piqd.swift` with `AppConfig.piqd` (full) and `AppConfig.piqd_v0_1` (masked)
- `PiqdApp.swift` composition root — instantiates NiftyCore engines with `AppConfig.piqd_v0_1`
- `PiqdRootView` → `PiqdCaptureView` (v0.1 skeleton viewfinder)
- Snap Still capture via existing `AVCaptureAdapter` (back camera only, no flip)
- Piqd-namespaced `VaultRepository` paths: `Documents/piqd/assets/{id}.heic`
- Piqd-namespaced GRDB file: `Documents/piqd/piqd.sqlite`
- `CaptureMomentUseCase` wired for Snap Still path (reuses existing NiftyCore implementation)
- `PiqdVaultDebugView` — dev-only list of captured assets, reached via a small "debug" button in the top-left safe area (hidden behind `#if DEBUG`)
- `Info.plist` privacy strings: `NSCameraUsageDescription`, `NSPhotoLibraryAddUsageDescription`
- `Piqd.entitlements` — no iCloud / no App Group in v0.1 (deferred to v0.6/v0.8)

### Out of Scope (deferred to later versions)

| Feature | Deferred to |
|---------|-------------|
| Mode system (long-hold pill, confirmation sheet, Roll viewfinder, grain) | v0.2 |
| Format selector, Sequence, Clip, Dual | v0.3 |
| Zoom, camera flip, invisible level, subject guidance, backlight, vibe hint | v0.4 |
| Drafts tray UI, 24h expiry, iOS share sheet, save-to-Photos | v0.5 |
| Trusted Circle, Curve25519 keys, onboarding | v0.6 |
| Any form of sharing (P2P or iCloud) | v0.7 / v0.8 |
| Film simulation presets, grain overlay, light leak, ambient metadata | v0.9 |
| Film Archive Moment view | v0.8 / v0.9 |
| Layered chrome auto-retreat | v0.2 (Layer 0 only in v0.1) |
| App Group entitlement | v0.6+ (when keys are shared) |

---

## 4. Implementation Tasks

| # | Task | File(s) | Owner | Status |
|---|------|---------|-------|--------|
| 1 | Create Xcode target `Piqd` under `Apps/Piqd/`, bundle ID `com.piqd.app`, iOS 26 minimum; add NiftyCore + NiftyData as local SPM dependencies | `Apps/Piqd/Piqd.xcodeproj/…` | Eng | ⬜ |
| 2 | Add `AppConfig.piqd` (full spec from SRS §2.1) and `AppConfig.piqd_v0_1` (masked) | `Apps/Piqd/Piqd/AppConfig+Piqd.swift` | Eng | ⬜ |
| 3 | Add new `FeatureSet` flags `.snapMode`, `.sequenceCapture`, `.p2pSharing`, `.iCloudRollPackage` per SRS §2.2 | `NiftyCore/Sources/Domain/AppConfig.swift` | Eng | ⬜ |
| 4 | Extend `VaultRepository` to accept an app namespace (`niftyMomnt` \| `piqd`) so paths are `Documents/{ns}/assets/…` and GRDB file is `Documents/{ns}/{ns}.sqlite`. Back-compat default keeps niftyMomnt behavior unchanged | `NiftyData/Sources/Repositories/VaultRepository.swift` | Eng | ⬜ |
| 5 | Same namespace parameter added to `GraphRepository` | `NiftyData/Sources/Repositories/GraphRepository.swift` | Eng | ⬜ |
| 6 | `PiqdApp.swift` composition root — mirrors niftyMomntApp structure, passes `AppConfig.piqd_v0_1` to all engines | `Apps/Piqd/Piqd/PiqdApp.swift` | Eng | ⬜ |
| 7 | `PiqdAppContainer` — holds `CaptureMomentUseCase`, `VaultManager`, `GraphManager` | `Apps/Piqd/Piqd/PiqdAppContainer.swift` | Eng | ⬜ |
| 8 | `PiqdRootView` → `PiqdCaptureView` (minimal: viewfinder + shutter + dev debug button) | `Apps/Piqd/Piqd/UI/PiqdRootView.swift`, `UI/Capture/PiqdCaptureView.swift` | Eng | ⬜ |
| 9 | `PiqdCaptureView` wires `AVCaptureVideoPreviewLayer` + shutter tap → `CaptureMomentUseCase.captureAsset(type: .still, mode: .snap)` | `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ⬜ |
| 10 | `PiqdVaultDebugView` — reads `GraphManager.fetchMoments()` and renders an asset grid. `#if DEBUG` only | `Apps/Piqd/Piqd/UI/Debug/PiqdVaultDebugView.swift` | Eng | ⬜ |
| 11 | `Info.plist`: `NSCameraUsageDescription` = "Piqd uses the camera to capture photos you share with your circle." | `Apps/Piqd/Piqd/Info.plist` | Eng | ⬜ |
| 12 | `Piqd.entitlements` — empty for v0.1 (no iCloud, no App Group) | `Apps/Piqd/Piqd/Piqd.entitlements` | Eng | ⬜ |
| 13 | App icon placeholder + launch screen with Piqd aperture glyph | `Apps/Piqd/Piqd/Assets.xcassets/` | Design | ⬜ |
| 14 | CI workflow `ci-piqd.yml` — builds Piqd scheme, runs `PiqdTests` + `PiqdUITests` on `iPhone 15 Pro` simulator, iOS 26 | `.github/workflows/ci-piqd.yml` | Eng | ⬜ |

---

## 5. Automated Test Suite

Target automation coverage for v0.1: **≥90%** of verification rows run in CI.

### 5.1 Unit Tests (XCTest) — `NiftyCoreTests` / `PiqdTests`

| # | Test | File | Asserts |
|---|------|------|---------|
| U1 | `AppConfig.piqd` exposes full capability set per SRS §2.1 | `NiftyCoreTests/AppConfigPiqdTests.swift` | `assetTypes`, `features`, `sharing`, `storage` match spec |
| U2 | `AppConfig.piqd_v0_1` is a strict subset of `AppConfig.piqd` with only `.still` + `.snapMode` | `NiftyCoreTests/AppConfigPiqdTests.swift` | No `.sequence`, `.dual`, `.live`, `.clip`, `.movingStill`; no `.p2pSharing`, `.iCloudRollPackage` |
| U3 | `FeatureSet` new flags `.snapMode`, `.sequenceCapture`, `.p2pSharing`, `.iCloudRollPackage` have unique raw values, no collision with existing | `NiftyCoreTests/FeatureSetTests.swift` | Flag bits 8, 9, 10, 11 per SRS |
| U4 | `VaultRepository(namespace: "piqd")` writes to `Documents/piqd/assets/` | `NiftyDataTests/VaultRepositoryNamespaceTests.swift` | Path equals expected string |
| U5 | `VaultRepository(namespace: "niftyMomnt")` unchanged — back-compat | `NiftyDataTests/VaultRepositoryNamespaceTests.swift` | Path equals legacy `Documents/assets/` |
| U6 | `GraphRepository(namespace: "piqd")` opens `Documents/piqd/piqd.sqlite` | `NiftyDataTests/GraphRepositoryNamespaceTests.swift` | DB file exists at expected path |
| U7 | Piqd and niftyMomnt GRDB files coexist without schema collision | `NiftyDataTests/GraphRepositoryNamespaceTests.swift` | Write to piqd, read from piqd — no cross-contamination |
| U8 | `CaptureMomentUseCase.captureAsset(type: .still, mode: .snap)` writes exactly one HEIF + one moment row | `NiftyCoreTests/CaptureMomentUseCasePiqdTests.swift` | Vault file exists, Graph row count +1 |

### 5.2 UI Tests (XCUITest) — `PiqdUITests`

Launch with `UI_TEST_MODE=1` + `PIQD_SEED_EMPTY_VAULT=1` to start from a deterministic empty state.

| # | Test | Asserts |
|---|------|---------|
| UI1 | `testLaunchShowsViewfinder` | `PiqdCaptureView` identifier visible within 3s of launch |
| UI2 | `testShutterTapEnqueuesCapture` | Tap shutter → `PiqdCaptureView.lastCaptureIndicator` flashes (checkmark pulse per PRD §5.4 FR-SNAP-NO-THUMB-02) |
| UI3 | `testDebugVaultShowsCapturedAsset` | After tap shutter, open debug screen → 1 asset row present |
| UI4 | `testRelaunchPersistsCapture` | Terminate and relaunch → debug screen still shows 1 asset row |
| UI5 | `testRapidTapDoesNotCrash` | Tap shutter 10× within 2s → app still responsive, debug screen shows 10 rows |
| UI6 | `testCameraPermissionDeniedShowsHint` | With camera permission denied, viewfinder shows "Camera access needed in Settings" |

### 5.3 Performance (XCTest `measure`) — `PiqdPerformanceTests`

| # | Test | Baseline |
|---|------|----------|
| P1 | Capture → file written to vault | <500ms p95 (loose baseline — tightens in v0.4) |
| P2 | Cold launch → `PiqdCaptureView.shutterReady` | <1.5s per SRS §8 |
| P3 | GRDB write of 1 moment | <100ms |

No p95-<100ms shutter test in v0.1 — that gate activates in v0.4 when pre-shutter AF / continuous exposure is wired.

---

## 6. Device Verification Checklist

> Run on a physical iPhone 15 or iPhone 15 Pro, iOS 26. Record Pass / Fail / Note per row. All rows must pass before v0.1 sign-off.

### 6.1 — Build and Launch

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 1.1 | Archive `Piqd` scheme for device | Build succeeds, no warnings in NiftyCore / NiftyData bridge | Y (CI) | |
| 1.2 | Install and launch on device | Piqd app icon visible; tap → launches within 1.5s | partial | |
| 1.3 | First-launch camera permission prompt | System prompt shows `NSCameraUsageDescription` text | N | |
| 1.4 | Viewfinder appears | Live back-camera preview fills safe area; shutter button visible at Layer 0; no grain overlay | Y (UI1) | |

### 6.2 — Capture

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 2.1 | Tap shutter once | Shutter checkmark pulse (80ms); no thumbnail (per FR-SNAP-NO-THUMB-01); no crash | Y (UI2) | |
| 2.2 | Console output during capture | No `[AVCaptureAdapter] error` lines; no `[CaptureUseCase] failed` lines | N | |
| 2.3 | Tap shutter 5× over 10s | Each tap pulses the shutter; all 5 captures complete | Y (UI5) | |
| 2.4 | Tap shutter 10× in 2s (rapid fire) | No crash; captures serialize and persist | Y (UI5) | |

### 6.3 — Persistence

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 3.1 | Xcode Device File Browser → `Documents/piqd/assets/` | One `.jpg` + one `.json` sidecar per capture | N | |
| 3.2 | Xcode Device File Browser → `Documents/piqd/graph.sqlite` | File exists, non-zero size | N | |
| 3.3 | Kill and relaunch app | Debug screen still shows prior captures | Y (UI4) | |
| 3.4 | Install niftyMomnt alongside Piqd on same device, capture in both | No cross-contamination: niftyMomnt vault and Piqd vault are separate directories | N | |

### 6.4 — Debug Surface

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 4.1 | Tap debug button (top-left safe area) | `PiqdVaultDebugView` opens | Y (UI3) | |
| 4.2 | Debug screen lists all captured assets | Grid shows each asset thumbnail, count matches capture count | Y (UI3) | |
| 4.3 | Dismiss debug screen | Returns to viewfinder | N | |

### 6.5 — Edge Cases

| # | Step | Expected result | Automated | Result |
|---|------|-----------------|:---------:|--------|
| 5.1 | Deny camera permission on first launch | Viewfinder shows clear "Camera access needed" hint with link to Settings; no crash | Y (UI6) | |
| 5.2 | Background app mid-capture | Asset either saves cleanly or is silently discarded — no half-written files in vault | N | |
| 5.3 | Airplane mode — capture still works | v0.1 has no network dependency; all captures succeed offline | N | |
| 5.4 | Low storage (< 100 MB free) | Capture fails gracefully with a user-visible message, no crash | N | |

---

## 7. Sign-off Criteria

| Item | Status |
|------|--------|
| All §4 implementation tasks complete | ⬜ |
| All §5 automated tests green in CI on `iPhone 15 Pro` simulator | ⬜ |
| All §6 device checklist rows Pass | ⬜ |
| No `[Piqd]` / `[CaptureUseCase]` / `[AVCaptureAdapter]` errors in console during a 20-capture session | ⬜ |
| Piqd and niftyMomnt coexist on same device with no data bleed | ⬜ |
| Memory footprint during sustained capture stays under 200 MB (Instruments Allocations run, 50 captures) | ⬜ |
| **v0.1 complete — ready for v0.2 (Mode System)** | ⬜ |

---

## 8. Known Limitations Carried to v0.2

These are intentionally deferred and will be addressed in v0.2:

- No mode indicator pill — app is hard-coded to Snap Mode.
- No long-hold mode switch gesture.
- Roll Mode does not exist yet — `AppConfig.piqd_v0_1` has `.snapMode` only.
- No grain overlay, no film simulation — Roll Mode aesthetic arrives in v0.2/v0.9.
- No 24-shot counter — Snap has no limit, Roll doesn't exist yet.
- No aspect ratio toggle — Still captures at sensor native ratio (4:3); per-mode default (Snap 9:16) arrives in v0.2.

---

## 9. Manual Xcode Target Setup (Option C)

The Swift sources, Info.plist, and entitlements for the Piqd app are scaffolded at
`Apps/Piqd/Piqd/**` but the Xcode project and scheme do not exist yet — creating them via
`pbxproj` hand-edits was judged riskier than a one-time manual setup. Do this once:

1. Open the existing `.xcodeproj` in Xcode (the niftyMomnt workspace, same project file).
2. **File → New → Target… → iOS App**.
   - Product Name: `Piqd`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Bundle Identifier: `com.hwcho99.piqd` (or your preferred id — must be unique)
   - Uncheck "Include Tests" (we use the existing `NiftyCoreTests` / `NiftyDataTests` bundles).
3. Xcode will create a default `Piqd/` folder with its own `App.swift` / `ContentView.swift` /
   `Info.plist` / `Assets.xcassets`. **Delete** the generated `.swift` files and the generated
   `Info.plist` from the target (move to trash) — we're using the scaffolded files instead.
4. In the Project Navigator, right-click the `Piqd` group → **Add Files to "…"** and add:
   - `Apps/Piqd/Piqd/PiqdApp.swift`
   - `Apps/Piqd/Piqd/PiqdAppContainer.swift`
   - `Apps/Piqd/Piqd/PiqdRootView.swift`
   - `Apps/Piqd/Piqd/AppConfig+Piqd.swift`
   - `Apps/Piqd/Piqd/UI/Capture/CameraPreviewView.swift`
   - `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift`
   - `Apps/Piqd/Piqd/UI/Debug/PiqdVaultDebugView.swift`
   - `Apps/Piqd/Piqd/Info.plist`
   - `Apps/Piqd/Piqd/Piqd.entitlements`
   Ensure "Add to target: Piqd" is checked (only Piqd, not niftyMomnt).
5. Target → **General**:
   - Deployment target: iOS 26.0
   - Supported destinations: iPhone
6. Target → **Build Settings**:
   - `INFOPLIST_FILE` = `Apps/Piqd/Piqd/Info.plist`
   - `CODE_SIGN_ENTITLEMENTS` = `Apps/Piqd/Piqd/Piqd.entitlements`
   - `GENERATE_INFOPLIST_FILE` = `NO`
7. Target → **Frameworks, Libraries, and Embedded Content**: add `NiftyCore` and `NiftyData`
   (both are Swift Packages already in the workspace — they should appear in the picker).
8. Scheme: Xcode auto-creates a `Piqd` scheme when the target is created. Verify it builds
   (⌘B) and runs on an `iPhone 15 Pro` simulator before moving on to the §5/§6 test passes.

Once the target builds, §4 tasks 1–14 are already complete in source — the remaining work is
verification: §5 tests in CI, §6 device checklist, and §7 sign-off.

---

*— End of v0.1 plan · Next: piqd_interim_v0.2_plan.md (Mode System) —*
