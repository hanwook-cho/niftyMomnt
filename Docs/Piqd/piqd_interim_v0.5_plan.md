# Piqd v0.5 — Drafts Tray + iOS Share Hand-off

# 24h Local Vault · Unsent Badge · Tray Sheet · Save to Photos · iOS Share Sheet · Snap-vault Retention Enforcement

_Parent plan: [piqd_interim_version_plan.md](piqd_interim_version_plan.md)_
_Reference: piqd_PRD_v1.1.md §5.5 (Drafts Tray, FR-SNAP-DRAFT-01..10), §5.2.1 FR-SNAP-STILL-05 · piqd_SRS_v1.0.md §3.3 (EphemeralPolicy) · piqd_UIUX_Spec_v1.0.md §2.8 (Unsent Badge), §2.14 (Drafts Tray Sheet), §3.2 (Layer 1 layout)_
_Prior status: [project_piqd_v04_status.md] — v0.4 shipped + verified 2026-04-26_
_Status: ⬜ Pending — kickoff 2026-04-27_

---

## 1. Purpose

v0.4 wrapped the viewfinder in chrome. v0.5 turns the **post-shutter** path into a real holding area instead of a fire-and-forget pipe. Every Snap-mode capture now lands in a 24-hour local drafts tray, surfaces in a Layer 1 unsent badge, and exits via either iOS Photos save or the iOS share sheet. The trusted-circle UI doesn't exist until v0.6 — v0.5 deliberately uses `UIActivityViewController` as the interim send path so the post-capture queue, lifecycle policy, and share contract get exercised end-to-end without network complexity.

Five things must be true at the end of v0.5:

1. Every Snap-mode capture (Still / Sequence / Clip / Dual) is recorded in a `drafts` table at completion time. Roll-mode captures bypass the tray entirely (FR-SNAP-DRAFT-10).
2. The Layer 1 chrome shows an unsent badge with the live count when ≥1 draft exists. Tap opens the `.medium`-detent drafts tray sheet. Badge urgency tint flips to recordRed at <1h remaining (UIUX §2.8).
3. Each tray row renders the spec'd four-state timer label (hidden / labelSecondary / amber <1h / red <15min), a "save" link that exports to the iOS Photo Library, and a "send →" link that opens `UIActivityViewController` with the asset.
4. Items reaching their 24h hard ceiling are silently purged — the drafts row, the underlying Snap-vault bytes, and the GraphRepository sidecar — within the next foreground sweep window. No recovery, no user prompt.
5. Roll Mode is unaffected: no badge, no tray entry, no purge of `roll/assets/`. The locked Roll vault keeps its v0.2 immutability semantics intact.

The version validates four risks:

1. **Capture-completion ↔ drafts insert atomicity** — a draft row must only exist if the underlying vault bytes also exist. A crash between the vault write and the GRDB insert must not leak orphan files or empty rows.
2. **Sequence MP4 readiness** — `assembledVideoURL` is the tray's playback source (FR-SNAP-DRAFT-04, FR-SNAP-SEQ-09). Insert into drafts must wait for `shareReady = true`; an interrupted sequence must never enter the tray (FR-SNAP-SEQ-10).
3. **Foreground purge sweep timing** — the 60s active-tick must reconcile timer-driven UI updates (badge color flips, row label colors) with the actual GRDB purge, so the tray never shows a row whose bytes have already been deleted.
4. **Photos-library save permissions** — `PHPhotoLibrary.requestAuthorization(for: .addOnly)` must be requested lazily on first "save" tap, must persist across launches, and must not block the tray sheet's main thread while the system prompt is up.

---

## 2. Verification Goal

**End-to-end on iPhone 17 / iOS 26.4:**

Cold launch into Snap → no badge (drafts table empty) → tap shutter (Still) → Layer 1 reveals → unsent badge appears reading "1 unsent" → capture again (Sequence) → wait for shareReady → badge reads "2 unsent" → tap badge → tray sheet slides up at `.medium` detent → Still row shows static thumbnail, "save" + "send →" → Sequence row shows silently looping MP4 thumbnail → tap "save" on Still row → first-time `PHPhotoLibrary` permission prompt → grant → Still row remains in tray (FR-SNAP-DRAFT-06) → confirm in Photos app that HEIC is saved → tap "send →" on Sequence row → `UIActivityViewController` presents the assembled MP4 → cancel → row still present → tap-to-dismiss tray → background-then-foreground app → injected clock advances to 23h after first capture → Still row's timer turns amber ("59m left") → badge background tints recordRed → advance clock to 23h 46m → row turns red ("14m left"), "send →" turns red → advance clock to 24h 1m → next foreground sweep purges Still row + its `Documents/{ns}/assets/{id}.heic` + sidecar JSON → badge updates to "1 unsent" → Sequence still alive at 23h 30m. **Roll mode:** long-hold mode pill → switch to Roll → no badge ever appears, even with Snap drafts queued. Capture in Roll → no drafts row written; Roll vault file lands as before. Confirm.

**Success = all automated tests green + every §6 device checklist row passes on iPhone 17 (iOS 26.4).**

---

## 3. Scope

### AppConfig

`AppConfig.piqd_v0_5` extends `piqd_v0_4` by adding a single `.draftsTray` feature flag (bit 16). All drafts-tray UI, the Snap-vault purger, and the iOS share hand-off activate together at this version. Per-feature dev toggles live in `DevSettingsStore`. No new asset-type or capture-format change.

```swift
public extension FeatureSet {
    static let draftsTray = FeatureSet(rawValue: 1 << 16) // Piqd v0.5
}

features:    [.snapMode, .rollMode, .sequenceCapture, .dualCamera,
              .preShutterChrome, .draftsTray]
```

All other v0.4 capabilities preserved.

### In Scope

- **Domain models** (`DraftItem`, `DraftExpiryState`, `DraftBadgeState`) and a pure `DraftsStore` state machine (insert / remove / list-sorted / count / urgency derivation) in NiftyCore. Time is injected via `NowProvider` so the suite is deterministic.
- **`DraftExpiryEvaluator`** — pure helper computing `(remainingSeconds, displayState)` from `capturedAt + now + hardCeilingHours`. Covers the four FR-SNAP-DRAFT-05 thresholds (>3h hidden, 1–3h secondary, <1h amber, <15min red) plus expired.
- **`DraftsRepository`** (NiftyData, GRDB) — new `drafts` table keyed on `assetID` with columns for `mode` (always `.snap` in v0.5; column is forward-looking), `assetType`, `capturedAt`, `assembledVideoPath` (Sequence/Clip/Dual). Schema namespace lives under existing Piqd GRDB scope. Insert is gated on capture completion + `shareReady = true`. Query returns non-expired rows ordered oldest-first.
- **`DraftPurgeScheduler`** — foreground-only sweep. Three triggers: (a) `application(didFinishLaunching)`, (b) `UIScene.willEnterForegroundNotification`, (c) `Timer.publish(every: 60, on: .main, in: .common)` while `scenePhase == .active`. Each tick calls `purgeExpired(now:)` which deletes the drafts row, the underlying Snap-vault bytes via `VaultRepository.purgeSnapAsset(id:)`, and the GraphRepository sidecar. Background `BGAppRefreshTask` deferred to v1.0 hardening (see §7).
- **`VaultRepository.purgeSnapAsset(id:)`** seam — new method on the Snap path only; touches `Documents/{ns}/assets/` + sidecar JSON for the matching ID. Roll path (`Documents/{ns}/roll/assets/`) is untouched. Reuses the existing v0.2 directory split — no new vault structure.
- **CaptureEngine wiring** — Snap-mode `captureMoment` completion (Still immediate, Sequence/Clip/Dual on `shareReady`) calls `DraftsRepository.insert(asset:)` after the vault write. Roll bypasses (FR-SNAP-DRAFT-10). Failed/interrupted captures (FR-SNAP-SEQ-10) don't insert.
- **`UnsentBadgeView`** (Layer 1, left of mode pill per UIUX §3.2) — 28pt height, ultra-thin material, "{N} unsent" caption. `recordRed` background at 60% opacity when any draft is <1h. Hidden when count = 0 or `mode == .roll`. Wires into the existing `Layer1ChromeView.draftsBadge` slot reserved in v0.4.
- **`DraftsTraySheetView`** — `.sheet` w/ `.presentationDetents([.medium])`, `surface` background, "Unsent · {N} items" header. Lists `DraftRowView` instances in the live-sorted oldest-first order from `DraftsStore`.
- **`DraftRowView`** — 72pt row, 0.5pt divider. 52pt thumbnail (`thumbRadius`):
    - Still → static `Image(uiImage:)` from HEIC frame
    - Sequence → `AVPlayerLayer` looping `assembledVideoURL` silently (one player per visible row)
    - Clip / Dual → static thumbnail with 18pt play-icon overlay; tap to play inline with audio (does not auto-play, FR-SNAP-DRAFT-04)
    - Asset-type label + timer label (4-state color), "save" + "send →" text links
- **`PhotoLibraryExporter`** (NiftyData) — `PHPhotoLibrary.shared().performChanges` for HEIC (Still) and MP4 (Sequence assembled video / Clip / Dual). Lazy `requestAuthorization(for: .addOnly)` on first save. Returns `(saved: Bool, requiresSettings: Bool)` so the UI can route a permission-denied case to a settings link.
- **`ShareHandoffCoordinator`** — wraps `UIActivityViewController` for "send →". Excluded activity types: `.assignToContact`, `.print`, `.openInIBooks`. Uses `assembledVideoURL` for Sequence/Clip/Dual, source HEIC URL for Still. Source row stays in the tray after sharing — only the 24h ceiling or explicit user save decides lifecycle.
- **`DraftRowView` playback hygiene** — Sequence row mounts an `AVPlayerLayer` only when visible (`onAppear` start, `onDisappear` pause + nil player). Avoids N concurrent `AVPlayer` instances when N rows scroll off-screen.
- **Dev Settings toggles** — `draftsTrayEnabled` (default ON), `draftPurgeIntervalSeconds` (default 60, allows test override), `draftFakeNowOffset` (test-only date injection for verification §6).
- **Tests** — NiftyCore: `DraftsStoreTests` (insert/remove/sort/badge derivation), `DraftExpiryEvaluatorTests` (threshold boundaries at 3h, 1h, 15min, 0). NiftyData: `DraftsRepositoryTests` (insert/query/purge w/ in-memory GRDB), `DraftPurgeSchedulerTests` (clock injection, multiple triggers, idempotent), `PhotoLibraryExporterTests` (auth flow w/ mock authorization). PiqdUITests: badge appears post-capture, urgency tint at <1h (clock-injected), tray opens / dismisses, save triggers permission prompt, send opens activity sheet, Roll Mode shows no badge.

### Out of Scope (deferred — see §7)

- **Trusted-circle send path** — v0.5 uses `UIActivityViewController`. v0.6 replaces this with the Curve25519 keypair + circle selector flow.
- **`BGAppRefreshTask` background purge** — foreground-only in v0.5. Adds Info.plist + entitlement work that buys marginal value (worst case: a few items survive minutes past 24h until next launch, well within FR-SNAP-DRAFT-02's "silently purged" intent). Schedule for v1.0 hardening.
- **Per-asset draft delete UI** — there is no delete button (FR-SNAP-DRAFT-08). Settings has a "Clear X items" affordance per UIUX §8 but Settings UI itself is still v0.9.
- **Thumbnail generation pipeline** — v0.5 reads source bytes directly each time the tray sheet appears; a thumbnail cache layer (`CGImageSource` downsampling, Core Data side-table) is a perf optimization for later if profiling demands it.
- **`drafts.mode` column extension to Roll** — Roll has no drafts concept by spec (FR-SNAP-DRAFT-10). The column ships as `.snap`-only but exists so v0.6 / v0.7 can extend it without a schema migration.
- **Sequence "scrub-to-frame" affordance** — `SequenceStrip.frameURLs` remains in the model unused by v0.5 UI. The tray uses `assembledVideoURL` per FR-SNAP-DRAFT-04 + FR-SNAP-SEQ-09.

---

## 4. Architecture

### Domain (NiftyCore)

- `DraftItem` — `id: UUID`, `assetID: UUID`, `assetType: AssetType`, `capturedAt: Date`, `hardCeilingHours: Int = 24`, `playbackURL: URL?` (nil for Still — derived from VaultRepository at row-render time).
- `DraftExpiryState` — `.hidden`, `.normal(remaining: Duration)`, `.amber(remaining: Duration)`, `.red(remaining: Duration)`, `.expired`.
- `DraftBadgeState` — `.hidden`, `.normal(count: Int)`, `.urgent(count: Int)` (urgent when any draft is <1h).
- `DraftsStore` (`@Observable`) — owns `[DraftItem]`, exposes `badgeState(now:) -> DraftBadgeState`, `rows(now:) -> [(DraftItem, DraftExpiryState)]`. Pure — no I/O.
- `DraftExpiryEvaluator` — `evaluate(capturedAt: Date, now: Date, ceiling: Duration) -> DraftExpiryState`.

### Platform (NiftyData)

- `DraftsRepository` — GRDB-backed; protocol seam `DraftsRepositoryProtocol` with `insert(_:)`, `all() async throws -> [DraftItem]`, `purgeExpired(now:) async throws -> [UUID]`. In-memory implementation for tests.
- `DraftPurgeScheduler` — combines `DraftsRepositoryProtocol` + `VaultRepositoryProtocol` + `GraphRepositoryProtocol` + clock. `sweep(now:)` is idempotent.
- `VaultRepository.purgeSnapAsset(id:)` — additive method; resolves Snap-mode bytes (`Documents/{ns}/assets/{id}.{ext}` + sidecar) and deletes. Roll bytes untouched.
- `PhotoLibraryExporter` — protocol seam (`exportToPhotos(_ url: URL, kind: AssetType) async throws`). Concrete impl wraps `PHPhotoLibrary`. Mock for tests.
- `ShareHandoffCoordinator` — view-model-friendly wrapper over `UIActivityViewController`, exposes a `share(item: DraftItem)` method that resolves URL via `VaultRepository`.

### UI (Apps/Piqd)

- `DraftsStoreBindings` — `@Observable` class wrapping `DraftsStore` with a `Timer.publish(every: 1)` driven `now` field so timer labels and badge urgency animate live without re-querying GRDB.
- `UnsentBadgeView` — wired into `Layer1ChromeView.draftsBadge` slot; `accessibilityIdentifier("piqd.draftsBadge")` at the leaf only.
- `DraftsTraySheetView` — presented from `LayerStore.showDraftsTray = true`; dismissal restores Layer 1 idle clock.
- `DraftRowView` — three sub-variants by `assetType`. Sequence variant wraps `AVPlayerLayer` in a UIViewRepresentable (`SilentLoopingPlayerView`) and mounts/unmounts on row visibility.
- `DevSettingsView` — adds a "Drafts" section: `draftsTrayEnabled`, `draftPurgeIntervalSeconds`, `draftFakeNowOffset`.

### Wiring

- `PiqdAppContainer` registers `DraftsRepository`, `DraftPurgeScheduler`, `PhotoLibraryExporter`, `ShareHandoffCoordinator`. Captures: `CaptureEngine.captureMoment` callsite for Snap modes appends `await draftsRepo.insert(...)` after vault write and `shareReady = true` for assembled formats.
- `PiqdApp.scenePhaseObserver` — on `.active` transition, calls `purgeScheduler.sweep(now: Date())` + restarts the 60s `Timer`. On `.background`, cancels the timer.
- `PiqdCaptureView` exposes `draftsStore` to `Layer1ChromeView`'s draftsBadge slot.

---

## 5. Tasks

| # | Task | Files | Owner | Done |
|---|------|-------|-------|------|
| 1 | `AppConfig.piqd_v0_5` adds `.draftsTray` flag (bit 16); route `PiqdApp` to use it; v0.4→v0.5 superset tests | `Apps/Piqd/Piqd/AppConfig+Piqd.swift`, `Apps/Piqd/Piqd/PiqdApp.swift`, `NiftyCore/Sources/Domain/AppConfig.swift`, `NiftyCore/Tests/AppConfigPiqdTests.swift` | Eng | ⬜ |
| 2 | Domain types: `DraftItem`, `DraftExpiryState`, `DraftBadgeState`; `DraftExpiryEvaluator` (pure) + 8 unit tests covering all 4 thresholds + expired + boundaries | `NiftyCore/Sources/Domain/Models/DraftItem.swift`, `NiftyCore/Sources/Domain/DraftExpiryEvaluator.swift`, `NiftyCore/Tests/DraftExpiryEvaluatorTests.swift` | Eng | ⬜ |
| 3 | `DraftsStore` (`@Observable` pure state machine in NiftyCore — insert / remove / rows(now:) / badgeState(now:)); 12 unit tests covering empty / single / sort-by-oldest / urgency derivation / mode-filter | `NiftyCore/Sources/Domain/DraftsStore.swift`, `NiftyCore/Tests/DraftsStoreTests.swift` | Eng | ⬜ |
| 4 | `DraftsRepositoryProtocol` + GRDB impl (new `drafts` table, migration); in-memory impl for tests; insert / all / purgeExpired; 8 tests w/ in-memory GRDB | `NiftyData/Sources/Repositories/DraftsRepository.swift`, `NiftyData/Sources/Repositories/InMemoryDraftsRepository.swift`, `NiftyData/Tests/DraftsRepositoryTests.swift` | Eng | ⬜ |
| 5 | `VaultRepository.purgeSnapAsset(id:)` — Snap-only deletion of `Documents/{ns}/assets/{id}.{ext}` + sidecar; Roll path untouched (assertion test); 4 tests | `NiftyData/Sources/Repositories/VaultRepository.swift`, `NiftyData/Tests/VaultRepositorySnapPurgeTests.swift` | Eng | ⬜ |
| 6 | `DraftPurgeScheduler` — foreground sweep w/ injected clock; combines drafts + vault + graph repos; idempotent `sweep(now:)`; 6 tests covering single sweep, multiple expired, partial-failure recovery | `NiftyData/Sources/Platform/DraftPurgeScheduler.swift`, `NiftyData/Tests/DraftPurgeSchedulerTests.swift` | Eng | ⬜ |
| 7 | `CaptureEngine` wiring — Snap-mode completion calls `draftsRepo.insert(...)` after vault write (Still immediate, Sequence/Clip/Dual on shareReady); Roll bypasses; interrupted-sequence guard; 4 integration tests against in-memory drafts repo | `NiftyCore/Sources/Engines/CaptureEngine.swift` (or its Piqd composition site), `NiftyCore/Tests/CaptureEngineDraftsInsertTests.swift` | Eng | ⬜ |
| 8 | `PhotoLibraryExporterProtocol` + `PHPhotoLibrary` impl; `.addOnly` lazy auth flow; HEIC + MP4 paths; mock impl for tests; 5 tests | `NiftyData/Sources/Platform/PhotoLibraryExporter.swift`, `NiftyData/Tests/PhotoLibraryExporterTests.swift` | Eng | ⬜ |
| 9 | `ShareHandoffCoordinator` — wraps `UIActivityViewController`; resolves URL per asset type; excluded activity types; helper to attach to current key window | `Apps/Piqd/Piqd/UI/Capture/ShareHandoffCoordinator.swift` | Eng | ⬜ |
| 10 | `DraftsStoreBindings` (@Observable wrapper w/ 1Hz timer for live now); container registration; `PiqdApp` scenePhase observer for sweep + timer lifecycle | `Apps/Piqd/Piqd/UI/Capture/DraftsStoreBindings.swift`, `Apps/Piqd/Piqd/PiqdAppContainer.swift`, `Apps/Piqd/Piqd/PiqdApp.swift` | Eng | ⬜ |
| 11 | `UnsentBadgeView` (28pt, ultra-thin material, "{N} unsent", `recordRed` urgency tint); wired into `Layer1ChromeView.draftsBadge` slot; per-leaf `piqd.draftsBadge` ID | `Apps/Piqd/Piqd/UI/Capture/UnsentBadgeView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ⬜ |
| 12 | `SilentLoopingPlayerView` (UIViewRepresentable wrapping `AVPlayerLayer`, mounts on visible, mute, loop, low-power); reused for Sequence row + Clip/Dual play-on-tap state | `Apps/Piqd/Piqd/UI/Capture/SilentLoopingPlayerView.swift` | Eng | ⬜ |
| 13 | `DraftRowView` — 72pt, three sub-variants (Still / Sequence / Clip+Dual); 4-state timer label (hidden / labelSecondary / amber / red); "save" + "send →" text links wired to exporter + share coordinator; per-leaf accessibility IDs `piqd.draftRow.{id}.save` / `.send` | `Apps/Piqd/Piqd/UI/Capture/DraftRowView.swift` | Eng | ⬜ |
| 14 | `DraftsTraySheetView` — `.medium` detent, header + scrollable rows; opens via `LayerStore.showDraftsTray`; dismissal restarts Layer 1 idle | `Apps/Piqd/Piqd/UI/Capture/DraftsTraySheetView.swift`, `Apps/Piqd/Piqd/UI/Capture/LayerStore.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ⬜ |
| 15 | `DevSettingsStore` additions: `draftsTrayEnabled`, `draftPurgeIntervalSeconds`, `draftFakeNowOffset`; `PiqdDevSettingsView` "Drafts" section; launch-arg overrides `PIQD_DEV_DRAFTS_TRAY` / `_PURGE_INTERVAL` / `_FAKE_NOW_OFFSET` | `Apps/Piqd/Piqd/UI/Debug/DevSettingsStore.swift`, `Apps/Piqd/Piqd/UI/Debug/PiqdDevSettingsView.swift` | Eng | ⬜ |
| 16 | XCUITest `DraftsTrayUITests` — 6 tests: badge appears post-capture, badge hidden in Roll, tray opens on tap, urgency tint at <1h via `PIQD_DEV_FAKE_NOW_OFFSET`, save triggers permission prompt (mocked authorization), send opens activity sheet (`.activitySheet` query). Hidden `piqd-drafts-fake-capture` button to seed deterministic drafts without exercising full capture pipeline | `Apps/Piqd/PiqdUITests/DraftsTrayUITests.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift` | Eng | ⬜ |
| 17 | XCUITest regression sweep — re-run v0.4 `Layer1ChromeUITests` + `PreShutterChromeUITests` w/ drafts feature ON to confirm badge slot integration didn't regress chrome reveal/retreat | `Apps/Piqd/PiqdUITests/*` | Eng | ⬜ |
| 18 | **Layer 1 layout audit** — full-reveal screenshot test on iPhone 17 Pro w/ every chrome element simultaneously visible: zoom pill, ratio pill, flip button, drafts badge (count=3, urgent state), invisible level, vibe glyph (.social), subject guidance pill. Verify no overlaps; reconcile any with UIUX spec; revise spec when reality is the better design (as v0.5 did with the drafts badge — UIUX §2.8 + §3.2 already updated bottom-left). Manual + 1 XCUI fixture-driven screenshot baseline | `Apps/Piqd/Piqd/UI/Capture/Layer1ChromeView.swift`, `Docs/Piqd/piqd_UIUX_Spec_v1.0.md`, `Apps/Piqd/PiqdUITests/Layer1LayoutAuditUITests.swift` | Eng | ⬜ |

---

## 6. Verification Checklist

| § | Row | Expected | Automated | Pass |
|---|-----|----------|-----------|------|
| 1.1 | Cold launch w/ empty drafts → Layer 1 reveals → no unsent badge slot rendered | Y | ⬜ |
| 1.2 | Capture Still → badge appears reading "1 unsent" within 1s of vault write | Y | ⬜ |
| 1.3 | Capture Sequence → badge does NOT update until shareReady = true | Y | ⬜ |
| 1.4 | Capture interrupted Sequence (background app mid-window) → no drafts row, no badge update | Y | ⬜ |
| 1.5 | Capture Clip → badge updates at recording stop | Y | ⬜ |
| 1.6 | Capture Dual → badge updates at composition complete | Y | ⬜ |
| 1.7 | Switch to Roll Mode → badge hidden, even with Snap drafts queued | Y | ⬜ |
| 1.8 | Roll-mode capture → no drafts row written; Roll vault file lands in `roll/assets/` as before | Y (regression) | ⬜ |
| 2.1 | Tap badge → tray sheet slides up at `.medium` detent within 220ms | Y | ⬜ |
| 2.2 | Tray rows ordered oldest-first | Y | ⬜ |
| 2.3 | Still row shows static thumbnail; Sequence row plays silently looping MP4 | partial (presence only in UI test) | ⬜ |
| 2.4 | Clip / Dual row shows static thumbnail + 18pt play overlay; tap plays inline w/ audio | partial (presence only) | ⬜ |
| 2.5 | Dismiss tray → Layer 1 idle clock restarts (3s retreat resumes) | Y | ⬜ |
| 3.1 | Item with >3h remaining: timer label hidden | Y (clock injection) | ⬜ |
| 3.2 | Item between 1–3h: "Xh Ym left" in labelSecondary | Y | ⬜ |
| 3.3 | Item <1h: "Xm left" in amber (`#C97B2A`); badge background tints recordRed at 60% opacity | Y | ⬜ |
| 3.4 | Item <15min: "Xm left" in red (`#E5372A`); "send →" turns red | Y | ⬜ |
| 3.5 | Item at 24h 0m 1s: purged on next sweep tick (≤60s) | Y (clock injection + scheduler interval override) | ⬜ |
| 3.6 | Purge removes drafts row + Snap-vault bytes + GraphRepository sidecar | Y | ⬜ |
| 3.7 | Roll vault `roll/assets/` untouched after Snap purge sweep | Y | ⬜ |
| 4.1 | Tap "save" on Still → first-time `PHPhotoLibrary` `.addOnly` prompt; grant → row remains in tray | partial (auth mocked in UI tests; on-device verification for prompt) | ⬜ |
| 4.2 | After save, HEIC visible in iOS Photos app | N (manual on iPhone 17) | ⬜ |
| 4.3 | Tap "save" on Sequence → assembled MP4 visible in iOS Photos | N (manual) | ⬜ |
| 4.4 | Tap "save" w/ permission denied → row stays; settings link surfaced (toast or inline) | Y | ⬜ |
| 5.1 | Tap "send →" on Still → `UIActivityViewController` presents w/ HEIC | Y (`.activitySheet` query) | ⬜ |
| 5.2 | Tap "send →" on Sequence → activity sheet presents w/ assembled MP4 (no raw HEIF frames) | Y | ⬜ |
| 5.3 | Cancel share → row remains in tray | Y | ⬜ |
| 5.4 | Excluded activity types not present (assignToContact, print, openInIBooks) | Y | ⬜ |
| 6.1 | Foreground sweep on app launch purges expired items before tray opens | Y | ⬜ |
| 6.2 | Foreground sweep on `willEnterForegroundNotification` purges items expired during background | Y (scenePhase fixture) | ⬜ |
| 6.3 | 60s active timer runs while scenePhase == .active; cancels on .background | Y (timer fake) | ⬜ |
| 6.4 | Sweep is idempotent — running twice with same `now` yields same vault state | Y | ⬜ |
| 7.1 | All v0.4 capture flows still pass (regression: Layer 1 reveal/retreat, zoom, ratio, flip, level, guidance, vibe glyph) | Y (existing UI suite) | ⬜ |
| 7.2 | All v0.3 format-selector flows still pass | Y (existing UI suite) | ⬜ |

**v0.5 complete = all rows ✅ on iPhone 17 / iOS 26.4 + CI green.**

---

## 7. Deferred / Open Decisions

1. **Trusted-circle send path → v0.6.** v0.5 ships `UIActivityViewController` as the "send →" target. Reason: Curve25519 keypair generation, QR/deep-link invite flow, and the circle selector UI are the entirety of v0.6's scope and would balloon v0.5. Drafts-tray plumbing is independently testable through the iOS share sheet.
2. **`BGAppRefreshTask` background purge → v1.0 hardening.** Foreground-only sweep covers the FR-SNAP-DRAFT-02 "silently purged" intent in practice (worst case: a few items survive minutes past 24h until next launch). BG refresh adds Info.plist `BGTaskSchedulerPermittedIdentifiers`, entitlement, and a separate verification path on device — out of proportion for v0.5 polish.
3. **Per-asset draft delete UI → never (by spec).** FR-SNAP-DRAFT-08 is explicit: no delete button. Settings has "Clear X items" but Settings UI itself remains v0.9.
4. **Thumbnail cache → defer until profiling demands it.** v0.5 reads source bytes per row-render. If `DraftsTraySheetView` shows perceptible jank on a 20-item tray, revisit with `CGImageSource` downsampling + side cache in v0.7 or v0.8.
5. **`drafts.mode` column extension to Roll → never (by spec).** Roll has no drafts concept (FR-SNAP-DRAFT-10). Column ships `.snap`-only; presence reserves the schema slot for forward extensions like draft-from-receiver in v0.7.
6. **Sequence raw-HEIF "scrub-to-frame" affordance → carry forward.** `SequenceStrip.frameURLs` remains in the model unused by v0.5 UI. PRD §5.5 + UIUX §2.14 mandate the assembled MP4 in tray; FR-SNAP-SEQ-09 explicitly forbids transmitting raw frames. Frames stay available for any future "scrub" interaction without schema work.
7. **Per-mode vault lifecycle structure → already shipped (v0.2).** v0.5 layers retention policy on top of the existing `Documents/{ns}/assets/` (Snap) vs `Documents/{ns}/roll/assets/` (Roll) split via `VaultRepository.purgeSnapAsset(id:)`. No vault refactor.
8. **Auto-scrolling/refreshing timer labels** — `DraftsStoreBindings` ticks at 1Hz only while the tray sheet is presented. Outside the sheet the badge urgency state evaluates on scenePhase transitions only; sub-second freshness in the badge isn't worth the wake budget.
9. **UIUX spec — drafts badge position revised.** UIUX §2.8 + §3.2 originally placed the badge "left of mode pill, same Y", but the mode pill is HUD-rendered outside `Layer1ChromeView`'s coordinate space, so the badge collided with it on-device. Spec was revised in v0.5 to "bottom-left, vertically aligned with the shutter row" — closer to the user's thumb and clear of all top-area chrome. Task 18's `XCTAssertNoOverlap` matrix now guards against this regression class.
10. **Layer 1 audit chrome coverage gaps** — Task 18's automated audit covers mode pill, zoom pill, ratio pill, flip button, drafts badge, shutter. It does NOT exercise: invisible level (needs `MotionMonitor.emit()` XCUI seam), vibe glyph `.social` state (needs `StubVibeClassifier.emit()` seam), subject guidance pill (needs `SubjectGuidanceDetector.emit()` seam). All three already on the v0.4 device-checklist deferred list. Adding XCUI seams for them is a separate ticket — defer to v0.6 when the Trusted Circle onboarding work forces another full Layer 1 layout pass anyway.

---

## 8. Risks

| Risk | Mitigation |
|------|------------|
| Capture write succeeds but drafts insert fails → orphan vault bytes | Drafts insert uses GRDB transaction; on insert failure, capture-completion path also rolls back vault write via existing `VaultRepository` cleanup. Add `CaptureEngineDraftsInsertTests` for this path. |
| Sequence inserted at capture-start rather than `shareReady` → row points at non-existent MP4 | Insert is gated on `shareReady = true` via the existing assembly callback. UI-test row 1.4 asserts interrupted-sequence behavior. |
| `AVPlayerLayer` instances accumulate on tray scroll → battery + memory bloat | `SilentLoopingPlayerView` mounts/unmounts on `onAppear`/`onDisappear`; unit-test view-lifecycle hook count under simulated scroll. |
| `PHPhotoLibrary` prompt dismisses tray sheet | Authorization request runs on `Task` off the main actor; prompt presents via the system, sheet retains its sheet-presentation; verified on device per row 4.1. |
| Foreground sweep races a `DraftRowView` save action mid-purge | Repository purge takes a row-level GRDB lock; UI-side `save` reads the asset via `VaultRepository` which returns nil if the file is gone, and the row deletes from the in-memory store on the same tick. UI-test `purge-during-save` row covers this. |
| Clock-injection tests leak `draftFakeNowOffset` into prod builds | `DevSettingsStore` setter is wrapped in `#if DEBUG`; release builds compile out the offset accessor entirely. |
| 1Hz timer wakes the device unnecessarily while drafts pending | `DraftsStoreBindings` only runs the 1Hz timer while the sheet is open; badge urgency outside the sheet flips on scenePhase, not on a continuous timer. |

---

*— End of v0.5 plan draft · Next: piqd_interim_v0.6_plan.md (Trusted Circle: Curve25519 + QR invite + onboarding O0–O4) —*
