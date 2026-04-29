# Piqd v0.6 — Trusted Circle Foundation

# Curve25519 Identity · QR + Custom-Scheme Invite · Trusted Friends List · Onboarding O0–O4 · First-Roll Storage Warning · Settings Circle Section

_Parent plan: [piqd_interim_version_plan.md](piqd_interim_version_plan.md)_
_Reference: piqd_PRD_v1.1.md §9 (Trusted Circle, FR-CIRCLE-01..08, FR-CIRCLE-KEY-01..04), §11 FR-STORAGE-08 · piqd_SRS_v1.0.md §6.3.4 (Key Management), §6.4 (Trusted Friends System) · piqd_UIUX_Spec_v1.0.md §7 (Onboarding O0–O4), §8 (Settings → CIRCLE)_
_Prior status: [project_piqd_v05_status.md] — v0.5 shipped + verified 2026-04-26_
_Status: ⬜ Pending — kickoff 2026-04-27_

---

## 1. Purpose

v0.5 closed the post-shutter loop with the Drafts Tray and `UIActivityViewController`. v0.6 lays the **identity and circle foundation** that v0.7 (Snap P2P) and v0.8 (Roll unlock) both depend on, plus the first-launch onboarding that introduces both modes and the daily loop. No actual P2P transport ships in v0.6 — the Drafts "send →" stays on `UIActivityViewController` until v0.7 plugs in the encrypted send path.

Five things must be true at the end of v0.6:

1. On first launch, a Curve25519 keypair is generated. The private key lives in the iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; the public key is exposed via a service for invite payloads (FR-CIRCLE-KEY-01..02). Reinstall regenerates a fresh keypair (FR-CIRCLE-KEY-04) — no recovery path.
2. The user can generate a personal invite (QR + sharable `piqd://invite/<token>` URL) and accept an incoming invite by scanning a QR or opening a `piqd://invite/...` deep link. Symmetric add: both sides write each other to their local trusted-friends list with the exchanged public keys (FR-CIRCLE-03).
3. A local `TrustedCircle` aggregate enforces `maxCircleSize = 10` (FR-CIRCLE-01), persists in a dedicated `circle.sqlite` namespace (mirroring the Drafts pattern, deviating from SRS §6.3.4's GraphRepository wording — see §7.3), and supports remove (FR-CIRCLE-05). No public usernames, no search-by-handle (FR-CIRCLE-06).
4. First-launch routing presents Onboarding O0 → O4 per UIUX §7. Skip on O0 jumps to O4 (Invite). Each screen teaches by doing where possible: O2 captures a real Snap, O3 shows the live Roll viewfinder + film counter. Permission prompts fire contextually (camera at O2, notifications deferred until first Roll capture).
5. The first time the user attempts a Roll Mode capture, a non-skippable, dismissible storage warning sheet appears: "Roll Mode photos live in Piqd only — export to Photos to keep them forever." (FR-STORAGE-08). Persisted; never re-shown after first dismiss.

The version validates four risks:

1. **Keychain durability** — the keypair must survive cold launch, app update, and `scenePhase` transitions, but be cleared on uninstall (default Keychain behavior with the chosen access class). A reinstall regression that orphans an old key would silently break v0.7 sends.
2. **Custom-scheme deep-link routing** — `piqd://invite/<token>` must route through `SceneDelegate` / `onOpenURL` regardless of cold-launch vs. warm state, validate the token signature, and present the accept-friend sheet without colliding with onboarding presentation.
3. **AVCaptureSession reuse** — onboarding O2 (Snap teach) holds a live capture session; the Settings/onboarding-O4 QR scanner needs its own session lifecycle so the two never contend. Same risk surfaces if the user opens "Add friend" while the viewfinder is mounted.
4. **Onboarding gating** — `hasCompletedOnboarding` must be set atomically only after O4's "Start shooting →" tap. A crash or background mid-flow must resume the user back to the same screen, not silently skip them into the camera.

---

## 2. Verification Goal

**End-to-end on iPhone 17 / iOS 26.4:**

Cold install → launch → Onboarding O0 (split aesthetic, "Continue") → O1 Snap teach: tap shutter, brief capture confirmation, "Next →" → O2 Roll teach: grain visible, "24 left" counter, "Next →" → O3 Invite: 200pt QR rendered from the freshly-minted public key, "Share invite link instead →" opens iOS share sheet w/ `piqd://invite/<token>` → "Start shooting →" → camera opens in Snap Mode → no more onboarding on subsequent launches. From a second device (or simulator instance) cold-install → reach O3 → tap "Add friend instead" → QR scanner opens, scan device A's QR → confirmation sheet shows device A's display name + truncated key fingerprint → Accept → device B's circle now contains device A. Open `piqd://invite/<token-from-B>` on device A via mobile Safari → app foregrounds → confirmation sheet → Accept → device A's circle contains device B. Both circles symmetric. Settings → CIRCLE → "My friends" shows the friend; tap-to-remove with confirm → row gone. Long-hold mode pill → switch to Roll → tap shutter → storage warning sheet appears, "Got it" dismiss → Roll capture proceeds → switch back and forth + capture again → no warning. Force-quit + relaunch → no onboarding, no warning, friend list intact, keypair intact (verified by re-rendering own QR — same payload). Reinstall → onboarding from O0, fresh keypair (different QR payload), friends list empty.

**Success = all automated tests green + every §6 device checklist row passes on iPhone 17 (iOS 26.4).**

---

## 3. Scope

### AppConfig

`AppConfig.piqd_v0_6` extends `piqd_v0_5` by adding `.trustedCircle` (bit 17) and `.onboarding` (bit 18). The two ship together — onboarding O4 depends on the invite/keypair plumbing, and CIRCLE settings depend on the friends repo.

```swift
public extension FeatureSet {
    static let trustedCircle = FeatureSet(rawValue: 1 << 17) // Piqd v0.6
    static let onboarding    = FeatureSet(rawValue: 1 << 18) // Piqd v0.6
}

features:    [.snapMode, .rollMode, .sequenceCapture, .dualCamera,
              .preShutterChrome, .draftsTray, .trustedCircle, .onboarding]
```

All other v0.5 capabilities preserved.

### In Scope

- **Domain models** in NiftyCore — `IdentityKey` (`publicKey: Data`, `createdAt: Date`), `Friend` (`id: UUID`, `displayName: String`, `publicKey: Data`, `addedAt: Date`, `lastActivityAt: Date?`), `TrustedCircle` (pure aggregate: `friends`, `add`, `remove`, `contains`, `count`, `maxSize = 10`), `InviteToken` (`senderID`, `displayName`, `publicKey`, `nonce: Data`, `createdAt`).
- **`InviteTokenCodec`** — pure NiftyCore encode/decode of `InviteToken` ↔ URL-safe base64 payload + signature verification using sender's claimed public key. Stable wire format documented in `Docs/Piqd/invite_token_v1.md` (additive for v0.7).
- **`IdentityKeyService`** — protocol seam: `currentKey() async -> IdentityKey`, `regenerate() async throws`, `sign(_ payload: Data)`, `verify(_ signature: Data, payload: Data, publicKey: Data)`. Concrete impl uses `Curve25519.Signing.PrivateKey` from `CryptoKit`. Generated lazily on first call; cached in memory.
- **`KeychainStore`** — NiftyData adapter; protocol seam `KeychainStoreProtocol` with `data(forKey:) -> Data?`, `set(_:forKey:)`, `delete(_:)`. Concrete impl wraps `SecItemAdd/Copy/Delete` with `kSecClassGenericPassword` + `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + service `com.piqd.identity`. In-memory mock for tests.
- **`TrustedFriendsRepository`** — GRDB-backed; protocol seam `TrustedFriendsRepositoryProtocol` with `all() async throws -> [Friend]`, `insert(_:)`, `remove(id:)`, `contains(id:)`, `count()`. Stored in a dedicated `circle.sqlite` under the Piqd namespace (deviates from SRS §6.3.4 — rationale in §7.3). In-memory impl for tests.
- **`InviteCoordinator`** — composes `IdentityKeyService` + `TrustedFriendsRepository` + `InviteTokenCodec`. Methods: `myInviteToken() async -> InviteToken`, `myInviteURL() async -> URL` (`piqd://invite/<base64>`), `accept(_ token: InviteToken, displayName: String?) async throws -> Friend` (validates signature, rejects self, rejects duplicate, enforces `maxSize`).
- **QR rendering** — `QRCodeImageRenderer` (`CIQRCodeGenerator` + `CIFilter.qrCodeGenerator`); produces a `UIImage` at requested point size. Pure helper in `Apps/Piqd`. Reused by Onboarding O3 + Settings → "My invite QR".
- **QR scanning** — `QRScannerView` (UIViewRepresentable wrapping `AVCaptureSession` + `AVCaptureMetadataOutput` w/ `.qr` type). Single-shot: emits the first valid `piqd://invite/...` payload, then stops the session. Owns its own session, never shares with the main `CaptureEngine`. Camera permission requested lazily on present.
- **Custom-scheme deep-link handler** — register `piqd` URL scheme in Info.plist; `PiqdApp` `onOpenURL` decodes via `InviteTokenCodec`, surfaces `IncomingInviteSheet`. Cold-launch path: scene activation passes `URLContexts` through to the same handler. App-links / Universal Links explicitly deferred (see §7.4).
- **`IncomingInviteSheet`** — modal sheet showing sender's display name + 8-hex-char public-key fingerprint (`SHA256(publicKey).prefix(4).hexEncodedString()`); Accept / Decline. Accept calls `InviteCoordinator.accept(...)`. Errors (max size, duplicate, self) render inline; no toast.
- **Onboarding flow** (`OnboardingCoordinator` + `OnboardingRootView`) — owns `OnboardingStep` (`.twoModes / .snap / .roll / .invite`), persists progress to `UserDefaults` key `piqd.onboarding.completed: Bool` and `piqd.onboarding.lastStep: String` (resume on relaunch). All four screens per UIUX §7.1–§7.4. O0 "Skip" jumps to `.invite`. O4 "Start shooting →" sets completed = true atomically and routes to `PiqdCaptureView` in Snap Mode.
- **`piqdRootView` switcher** — top-level scene root chooses between `OnboardingRootView` (when `!hasCompletedOnboarding`) and `PiqdCaptureView`. Replaces v0.5's direct mount of `PiqdCaptureView`.
- **First-Roll storage warning** (`FirstRollStorageWarningSheet`) — UserDefaults flag `piqd.firstRollWarning.shown: Bool`. Presented from `PiqdCaptureView` on first capture attempt while `mode == .roll && !shown`. Sheet has a single "Got it" button that sets the flag and dismisses; tapping outside the sheet does NOT dismiss (per FR-STORAGE-08 "not skippable on first Roll"). After dismiss, the in-flight shutter tap is consumed — user must tap shutter again to capture (chosen for clarity; documented in §8 risks).
- **Settings — CIRCLE section** (`PiqdSettingsView` + `CircleSettingsView`) — first user-facing Settings view in Piqd. Sections per UIUX §8 but only **CIRCLE** is wired; CAPTURE / ROLL MODE / SNAP MODE rows render as static read-only display per spec (UI shipped; toggles live in DevSettings until v0.9). Gear icon entry from Layer 1 top-left + ⋯ from non-viewfinder screens. CIRCLE rows: My friends (NavigationLink → `FriendsListView` w/ tap-to-remove + confirm), Add friend (action sheet: "Scan QR" / "Share my invite link"), My invite QR (NavigationLink → `MyInviteView` rendering the QR + "Share link" button).
- **`FriendsListView`** — list of `FriendRowView`s (40pt avatar w/ initials, display name, "Last activity" date or "—"); swipe-to-delete + tap-to-detail w/ "Remove from circle" confirm dialog. Per-leaf `piqd.circle.friend.{id}.remove` IDs.
- **`Layer1ChromeView` gear icon** — adds `⚙` SF Symbol button at top-left safe area (cy=87pt, x=44pt, 32pt diameter, `surfaceSecondary` bg, `labelSecondary` weight) per UIUX §8. Tap → action menu sheet w/ "Settings" (and "Inbox" placeholder, disabled until v0.7). Obeys Layer 1 auto-retreat.
- **`DevSettingsStore` additions** — `onboardingForceShow: Bool` (debug: re-show onboarding on next launch), `firstRollWarningForceShow: Bool` (debug: reset the storage warning flag), `circleClearAll` (debug: wipe friends + keypair). Launch-arg overrides `PIQD_DEV_ONBOARDING_RESET` / `PIQD_DEV_ROLL_WARNING_RESET` / `PIQD_DEV_CIRCLE_CLEAR` / `PIQD_DEV_INVITE_TOKEN=<base64>` (UI-test seed for the accept-invite flow without scanning).
- **Tests** — see §5 task table. Coverage targets: NiftyCore 30+ new tests (TrustedCircle, InviteTokenCodec, IdentityKeyService contract). NiftyData 12+ (KeychainStore round-trip, TrustedFriendsRepository CRUD, max-size enforcement at repo layer). PiqdUITests 10+ (onboarding O0→O4 happy path, O0 skip, O4 share-link, accept-invite via launch arg, first-Roll warning, Settings → CIRCLE add/remove, gear icon reveal/retreat).

### Out of Scope (deferred — see §7)

- **Actual P2P send transport** — Drafts "send →" stays on `UIActivityViewController` until v0.7 (MPC LAN + WebRTC + APNs).
- **Universal Links / AASA** — v0.6 ships custom scheme `piqd://` only. AASA file + `applinks:` entitlement land with v0.7's invite-from-iMessage path (real domain provisioning still pending — open item §7.4).
- **`rollCircle` snapshot logic** — FR-CIRCLE-08 immutability is a v0.8 concern (no Roll asset is ever shared in v0.6 — the Roll vault stays local). Hooks reserved on `RollManifest` but no behavior wired.
- **Friend display-name editing** — set once at invite acceptance; no rename UI in v0.6. Defer to v0.9 polish.
- **Friend "last activity" actual data** — column ships nullable; populated by v0.7 send/receive events. v0.6 always renders "—".
- **CAPTURE / ROLL MODE / SNAP MODE Settings toggles** — UI rows render per UIUX §8 but are read-only display in v0.6. Wiring lives in DevSettings until v0.9.
- **Notifications permission prompt** — UIUX §7.4 says it fires on first Roll capture, not in onboarding. v0.6 wires the deferred prompt at the same callsite as the storage warning, but Roll notifications themselves are a v0.7/v0.8 concern.
- **Inbox** — gear-icon menu shows "Inbox" disabled until v0.7.
- **Key fingerprint verification UI** — accept-invite shows a truncated fingerprint for transparency, but there's no separate "verify in person" comparison flow. Defer to a hardening pass.

---

## 4. Architecture

### Domain (NiftyCore)

- `IdentityKey` — value type wrapping the public key bytes + creation date.
- `Friend`, `TrustedCircle` — pure aggregate; `add(_:) throws`, `remove(id:)`, `contains(id:)`, `friends: [Friend]`, `count: Int`. Throws `TrustedCircleError.{full, duplicate, selfInvite}`.
- `InviteToken` — Codable; `encode()` produces a deterministic byte payload signed by the sender; `verify(against:)` validates the signature against the embedded public key.
- `InviteTokenCodec` — `encode(_ token: InviteToken) -> String` (URL-safe base64 of `signed-payload-v1`), `decode(_ s: String) throws -> InviteToken`. Versioned magic byte at offset 0 so v0.7 can extend without breaking compat.
- `IdentityKeyServiceProtocol` — pure-Swift protocol; concrete `CryptoKitIdentityKeyService` uses `Curve25519.Signing.PrivateKey` w/ raw representation persisted via injected `KeychainStoreProtocol`.

### Platform (NiftyData)

- `KeychainStore` — wraps `SecItem*` with `service: "com.piqd.identity"`, `account: "primary"`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Returns `Data?` on read, `Bool` on write/delete. `InMemoryKeychainStore` for tests.
- `TrustedFriendsRepository` — GRDB; new `circle.sqlite` under `Documents/{ns}/circle.sqlite`. Schema: `friends(id TEXT PK, display_name TEXT, public_key BLOB, added_at REAL, last_activity_at REAL NULL)`. Migration v1. `InMemoryTrustedFriendsRepository` for tests.
- `InviteURLParser` — pure helper to split a `piqd://invite/<base64>` URL into the codec input.

### UI (Apps/Piqd)

- `OnboardingCoordinator` (`@Observable`) — owns `step: OnboardingStep`, `advance()`, `skipToInvite()`, `complete()`. `complete()` sets `UserDefaults` flag.
- `OnboardingRootView` — switches on `step` to render `O0TwoModesView`, `O1SnapTeachView`, `O2RollTeachView`, `O3InviteView`. Each child view receives a `@Bindable` coordinator.
- `O1SnapTeachView` reuses `PiqdCaptureView` in a special `.onboardingSnap` mode (no chrome, real shutter, single-tap → confirmation overlay → "Next →"). `O2RollTeachView` similarly uses `.onboardingRoll`.
- `O3InviteView` — renders QR via `QRCodeImageRenderer.image(for: inviteCoordinator.myInviteURL(), size: 200)`. "Share invite link instead →" opens `UIActivityViewController` w/ the URL.
- `PiqdAppContainer` registers `keychainStore`, `identityKeyService`, `trustedFriendsRepository`, `inviteCoordinator`, `qrCodeRenderer`. Existing `draftsRepository` etc. preserved.
- `piqdRootView` (in `PiqdApp`) — `if onboardingCoordinator.isComplete { PiqdCaptureView } else { OnboardingRootView }`.
- `IncomingInviteSheet` — driven by `PiqdApp`-level `incomingInvite: InviteToken?` set from `onOpenURL`.
- `Layer1ChromeView` — adds `gearButton` slot at top-left; tap publishes `LayerStore.showSettingsMenu = true`. Action menu → "Settings" pushes `PiqdSettingsView`.
- `PiqdSettingsView` (UIKit-style `Form`/`List` SwiftUI) — sections per UIUX §8. CIRCLE section is the only interactive section in v0.6.
- `FirstRollStorageWarningSheet` — presented from `PiqdCaptureView` shutter handler when entering Roll first time.

### Wiring

- `PiqdApp.scenePhaseObserver` — preserved from v0.5; adds first-launch identity-key warm-up on `.active` (`Task { _ = try? await identityKeyService.currentKey() }`) so the QR is instantly available at O3.
- Onboarding completion → camera scene transition uses the existing `PiqdCaptureView` mount point; no scene re-creation.
- Custom-scheme handler is registered at the `Scene` level via `.onOpenURL { url in app.handleIncomingURL(url) }`.
- Drafts "send →" path is **unchanged** — v0.6 explicitly does not touch `ShareHandoffCoordinator`.

---

## 5. Tasks

| # | Task | Files | Owner | Done |
|---|------|-------|-------|------|
| 1 | `AppConfig.piqd_v0_6` adds `.trustedCircle` (bit 17) + `.onboarding` (bit 18); supersets piqd_v0_5; tests for the v0.5→v0.6 superset | `Apps/Piqd/Piqd/AppConfig+Piqd.swift`, `Apps/Piqd/Piqd/PiqdApp.swift`, `NiftyCore/Sources/Domain/AppConfig.swift`, `NiftyCore/Tests/AppConfigPiqdTests.swift` | Eng | ⬜ |
| 2 | Domain types: `IdentityKey`, `Friend`, `TrustedCircle` (pure aggregate w/ `maxSize = 10`, throws on full/dup/self), `InviteToken`; 12 unit tests covering add/remove/contains/full/duplicate/self/count boundaries | `NiftyCore/Sources/Domain/Models/TrustedCircle.swift`, `NiftyCore/Sources/Domain/Models/IdentityKey.swift`, `NiftyCore/Sources/Domain/Models/InviteToken.swift`, `NiftyCore/Tests/TrustedCircleTests.swift` | Eng | ⬜ |
| 3 | `InviteTokenCodec` — versioned magic byte + base64 URL-safe + signature; encode/decode/verify; 8 tests covering round-trip, signature mismatch, version-byte rejection, malformed base64, oversized payload | `NiftyCore/Sources/Domain/InviteTokenCodec.swift`, `NiftyCore/Tests/InviteTokenCodecTests.swift`, `Docs/Piqd/invite_token_v1.md` | Eng | ⬜ |
| 4 | `IdentityKeyServiceProtocol` + `CryptoKitIdentityKeyService` (Curve25519 signing key, raw-rep persistence via `KeychainStoreProtocol`); lazy `currentKey()`, `regenerate()`, `sign()`, `verify()`; 6 unit tests w/ in-memory keychain | `NiftyCore/Sources/Services/IdentityKeyService.swift`, `NiftyCore/Tests/IdentityKeyServiceTests.swift` | Eng | ⬜ |
| 5 | `KeychainStoreProtocol` + `KeychainStore` (`SecItem*`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`); `InMemoryKeychainStore`; 5 unit tests covering set/get/delete/missing/overwrite (concrete impl gets a single device smoke test, not in CI unit suite) | `NiftyData/Sources/Platform/KeychainStore.swift`, `NiftyData/Sources/Platform/InMemoryKeychainStore.swift`, `NiftyData/Tests/KeychainStoreTests.swift` | Eng | ⬜ |
| 6 | `TrustedFriendsRepositoryProtocol` + GRDB impl (new `circle.sqlite`, schema migration v1); `InMemoryTrustedFriendsRepository`; 8 tests covering insert/all/remove/contains/count + max-size at repo layer + sort by `addedAt` ascending | `NiftyData/Sources/Repositories/TrustedFriendsRepository.swift`, `NiftyData/Sources/Repositories/InMemoryTrustedFriendsRepository.swift`, `NiftyData/Tests/TrustedFriendsRepositoryTests.swift` | Eng | ⬜ |
| 7 | `InviteCoordinator` (composes identity + repo + codec); `myInviteToken()`, `myInviteURL()`, `accept()` w/ self-reject + duplicate-reject + max-size error mapping; 6 unit tests against in-memory deps | `NiftyCore/Sources/Services/InviteCoordinator.swift`, `NiftyCore/Tests/InviteCoordinatorTests.swift` | Eng | ⬜ |
| 8 | `QRCodeImageRenderer` (`CIQRCodeGenerator`-backed UIImage helper) + `QRScannerView` (UIViewRepresentable, owns its own `AVCaptureSession`, single-shot emit, lazy camera permission); device-only smoke test for scanner, unit test for renderer (1pt deterministic output) | `Apps/Piqd/Piqd/UI/Circle/QRCodeImageRenderer.swift`, `Apps/Piqd/Piqd/UI/Circle/QRScannerView.swift`, `Apps/Piqd/PiqdTests/QRCodeImageRendererTests.swift` | Eng | ⬜ |
| 9 | Custom-scheme registration (`piqd` in Info.plist `CFBundleURLTypes`); `PiqdApp.onOpenURL` → decode → publish `incomingInvite`; cold-launch path via scene `URLContexts`; `IncomingInviteSheet` w/ Accept/Decline + 8-hex-char fingerprint | `Apps/Piqd/Piqd/Info.plist`, `Apps/Piqd/Piqd/PiqdApp.swift`, `Apps/Piqd/Piqd/UI/Circle/IncomingInviteSheet.swift` | Eng | ⬜ |
| 10 | `OnboardingCoordinator` (@Observable) + `OnboardingStep` enum + `UserDefaults` resume key; `piqdRootView` switcher; container registration; first-launch `identityKeyService.currentKey()` warm-up | `Apps/Piqd/Piqd/UI/Onboarding/OnboardingCoordinator.swift`, `Apps/Piqd/Piqd/PiqdApp.swift`, `Apps/Piqd/Piqd/PiqdAppContainer.swift` | Eng | ⬜ |
| 11 | `O0TwoModesView` (split aesthetic, "Continue" / "Skip"), `O1SnapTeachView` (live Snap Mode, real shutter, "Next →"), `O2RollTeachView` (Roll Mode, grain on, "24 left", "Next →"); per-leaf accessibility IDs `piqd.onboarding.{step}.{action}` | `Apps/Piqd/Piqd/UI/Onboarding/O0TwoModesView.swift`, `Apps/Piqd/Piqd/UI/Onboarding/O1SnapTeachView.swift`, `Apps/Piqd/Piqd/UI/Onboarding/O2RollTeachView.swift` | Eng | ⬜ |
| 12 | `O3InviteView` — 200pt QR rendered from `inviteCoordinator.myInviteURL()`, "Share invite link instead →" opens activity sheet w/ URL, "Add friend instead" presents `QRScannerView`, "Start shooting →" calls `coordinator.complete()` → mount `PiqdCaptureView` | `Apps/Piqd/Piqd/UI/Onboarding/O3InviteView.swift` | Eng | ⬜ |
| 13 | `FirstRollStorageWarningSheet` + `UserDefaults` flag (`piqd.firstRollWarning.shown`); `PiqdCaptureView` shutter-handler gate (Roll mode + flag-not-set → present sheet, consume tap, set flag on dismiss); "not skippable" enforced via `.interactiveDismissDisabled(true)`; 4 unit tests on the gate logic | `Apps/Piqd/Piqd/UI/Capture/FirstRollStorageWarningSheet.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift`, `Apps/Piqd/PiqdTests/FirstRollWarningGateTests.swift` | Eng | ⬜ |
| 14 | `Layer1ChromeView` gear icon — 32pt `⚙` at top-left (cy=87pt, x=44pt) per UIUX §8; obeys Layer 1 auto-retreat; tap → action menu sheet w/ "Settings" (and "Inbox" disabled placeholder); per-leaf `piqd.layer1.gear` ID; layout audit (Task 18) gets a new chrome element | `Apps/Piqd/Piqd/UI/Capture/Layer1ChromeView.swift`, `Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift`, `Apps/Piqd/PiqdUITests/Layer1LayoutAuditUITests.swift` | Eng | ⬜ |
| 15 | `PiqdSettingsView` skeleton w/ all UIUX §8 sections (CAPTURE / ROLL MODE / SNAP MODE rendered as static read-only display); navigation entry from gear-icon action menu + ⋯ on non-viewfinder screens (placeholder for v0.7) | `Apps/Piqd/Piqd/UI/Settings/PiqdSettingsView.swift` | Eng | ⬜ |
| 16 | `CircleSettingsView` (the wired CIRCLE section) — "My friends" → `FriendsListView` (tap-row → confirm-remove), "Add friend" → action sheet (Scan QR / Share my invite link), "My invite QR" → `MyInviteView` (re-renders user's invite + share link button); per-leaf `piqd.circle.{action}` IDs | `Apps/Piqd/Piqd/UI/Settings/CircleSettingsView.swift`, `Apps/Piqd/Piqd/UI/Settings/FriendsListView.swift`, `Apps/Piqd/Piqd/UI/Settings/MyInviteView.swift` | Eng | ⬜ |
| 17 | `DevSettingsStore` additions: `onboardingForceShow`, `firstRollWarningForceShow`, `circleClearAll`, `inviteTokenSeed: String?` (#if DEBUG); launch-arg overrides `PIQD_DEV_ONBOARDING_RESET`, `PIQD_DEV_ROLL_WARNING_RESET`, `PIQD_DEV_CIRCLE_CLEAR`, `PIQD_DEV_INVITE_TOKEN`; Dev section "Circle (v0.6)" in `PiqdDevSettingsView` | `Apps/Piqd/Piqd/UI/Debug/DevSettingsStore.swift`, `Apps/Piqd/Piqd/UI/Debug/PiqdDevSettingsView.swift`, `Apps/Piqd/Piqd/PiqdApp.swift` | Eng | ⬜ |
| 18 | XCUITest `OnboardingUITests` — 5 tests: O0→O4 happy path, O0 skip jumps to O3, O3 share-link opens activity sheet, O3 "Add friend" + `PIQD_DEV_INVITE_TOKEN` seed accepts a synthetic invite (friend appears in repo), `piqd.onboarding.completed` survives relaunch | `Apps/Piqd/PiqdUITests/OnboardingUITests.swift` | Eng | ⬜ |
| 19 | XCUITest `CircleSettingsUITests` — 5 tests: gear icon reveals + obeys Layer 1 retreat, Settings → CIRCLE → My friends list reflects seeded friends, tap-to-remove w/ confirm, "Share my invite link" opens activity sheet, "My invite QR" renders a QR view (visibility, not pixel match) | `Apps/Piqd/PiqdUITests/CircleSettingsUITests.swift` | Eng | ⬜ |
| 20 | XCUITest `FirstRollWarningUITests` — 3 tests: first Roll capture presents non-dismissible sheet, "Got it" sets flag + dismisses, second Roll capture does NOT re-present, `PIQD_DEV_ROLL_WARNING_RESET` re-arms | `Apps/Piqd/PiqdUITests/FirstRollWarningUITests.swift` | Eng | ⬜ |
| 21 | XCUITest regression sweep — re-run v0.5 `DraftsTrayUITests`, `Layer1LayoutAuditUITests` (extended w/ gear icon + onboarding bypass via `PIQD_DEV_ONBOARDING_RESET=false`), v0.4 `Layer1ChromeUITests` + `PreShutterChromeUITests`, v0.3 `PiqdFormatSelectorUITests` (known Clip flake remains baseline) | `Apps/Piqd/PiqdUITests/*` | Eng | ⬜ |

---

## 6. Verification Checklist

| § | Row | Expected | Automated | Pass |
|---|-----|----------|-----------|------|
| 1.1 | Cold install + first launch routes to Onboarding O0 (split aesthetic) | Y | ⬜ |
| 1.2 | O0 "Continue" advances to O1 Snap teach (live viewfinder, camera permission prompt fires) | Y (auth mocked) + N (prompt manual) | ⬜ |
| 1.3 | O1 shutter tap captures a Snap; "Next →" advances to O2 | Y | ⬜ |
| 1.4 | O2 shows Roll grain + "24 left" film counter; "Next →" advances to O3 | Y | ⬜ |
| 1.5 | O3 renders 200pt QR encoding `piqd://invite/<token>` with own public key | Y (codec round-trip from rendered token) | ⬜ |
| 1.6 | O0 "Skip" jumps directly to O3 | Y | ⬜ |
| 1.7 | O4 "Start shooting →" sets `piqd.onboarding.completed = true` and mounts Snap-mode `PiqdCaptureView` | Y | ⬜ |
| 1.8 | Force-quit during O2 → relaunch resumes at O2 (resume key honored) | Y | ⬜ |
| 1.9 | Subsequent launches skip onboarding entirely | Y | ⬜ |
| 2.1 | First launch generates a Curve25519 keypair; private key persisted in Keychain w/ `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Y (keychain mock) + N (device class verify) | ⬜ |
| 2.2 | Re-render own QR after relaunch → identical payload | Y | ⬜ |
| 2.3 | Reinstall → fresh keypair (different QR payload), friends list empty | N (manual on iPhone 17) | ⬜ |
| 3.1 | Tap "Share invite link instead →" → activity sheet w/ `piqd://invite/...` URL | Y | ⬜ |
| 3.2 | Open `piqd://invite/<valid-token>` from mobile Safari → app foregrounds → `IncomingInviteSheet` shows sender display name + 8-hex fingerprint | N (manual) + Y (launch-arg seed path) | ⬜ |
| 3.3 | Cold-launch with `piqd://invite/<token>` → onboarding does NOT block; sheet defers until O3 → Accept | partial (Y for warm; N manual cold) | ⬜ |
| 3.4 | Accept invite → both devices' circles contain each other's `Friend` w/ correct public key | Y (two in-memory simulators) | ⬜ |
| 3.5 | Accept own invite → rejected w/ inline error (FR-CIRCLE: implicit self-guard) | Y | ⬜ |
| 3.6 | Accept duplicate invite → rejected w/ "already in your circle" | Y | ⬜ |
| 3.7 | Accept 11th invite → rejected w/ "Circle is full (10)" (FR-CIRCLE-01) | Y | ⬜ |
| 3.8 | Malformed token (bad base64 / wrong magic byte / signature mismatch) → rejected w/ generic "Invalid invite" | Y | ⬜ |
| 4.1 | Layer 1 reveals → gear icon visible at top-left (cy=87pt, x=44pt); obeys 3s auto-retreat | Y | ⬜ |
| 4.2 | Tap gear → action menu shows "Settings" + disabled "Inbox" placeholder | Y | ⬜ |
| 4.3 | Tap "Settings" → `PiqdSettingsView` pushes; CIRCLE section visible | Y | ⬜ |
| 4.4 | CIRCLE → "My friends" lists seeded friends in `addedAt` ascending order | Y | ⬜ |
| 4.5 | Tap a friend row → confirm-remove dialog → confirm removes from local repo | Y | ⬜ |
| 4.6 | "Add friend" → action sheet (Scan QR / Share my invite link) | Y | ⬜ |
| 4.7 | "My invite QR" → `MyInviteView` renders QR + "Share link" button works | Y (visibility) + N (manual visual) | ⬜ |
| 4.8 | CAPTURE / ROLL MODE / SNAP MODE rows render as read-only display per UIUX §8 | Y | ⬜ |
| 5.1 | First-ever Roll-mode shutter tap presents `FirstRollStorageWarningSheet` (non-interactive-dismiss) | Y | ⬜ |
| 5.2 | "Got it" sets `piqd.firstRollWarning.shown = true` and dismisses | Y | ⬜ |
| 5.3 | Subsequent Roll captures do NOT re-present the sheet | Y | ⬜ |
| 5.4 | Snap-mode captures never present the sheet | Y | ⬜ |
| 5.5 | `PIQD_DEV_ROLL_WARNING_RESET` re-arms the warning | Y | ⬜ |
| 6.1 | Layer 1 layout audit — gear icon does not overlap zoom pill, ratio pill, flip, drafts badge, shutter | Y (extended audit) | ⬜ |
| 6.2 | All v0.5 drafts-tray flows still pass (regression) | Y | ⬜ |
| 6.3 | All v0.4 Layer 1 chrome flows still pass | Y | ⬜ |
| 6.4 | All v0.3 format-selector flows still pass (Clip simulator flake remains pre-existing baseline) | Y | ⬜ |
| 7.1 | QR scanner held open in Settings does not contend with viewfinder `AVCaptureSession` (kill scanner → viewfinder resumes cleanly) | N (manual on device) | ⬜ |
| 7.2 | Notifications permission prompt does NOT fire during onboarding | Y | ⬜ |

**v0.6 complete = all rows ✅ on iPhone 17 / iOS 26.4 + CI green.**

---

## 7. Deferred / Open Decisions

1. **P2P send transport → v0.7.** Drafts "send →" stays on `UIActivityViewController` in v0.6 by explicit decision (chat 2026-04-26). All identity + circle plumbing lands in v0.6 so v0.7 can drop in MPC LAN + WebRTC + APNs without scaffolding work.
2. **`rollCircle` snapshot logic → v0.8.** FR-CIRCLE-08 requires the day's circle to be frozen at first Roll capture. v0.6 has no Roll-asset transmission anywhere (Roll vault stays local through v0.7 too), so the snapshot is dead code until v0.8's `RollPackage` pipeline.
3. **Friends list lives in `circle.sqlite`, not GraphRepository.** SRS §6.3.4 wording is "stored locally in the intelligence graph (GraphRepository)" — but the v0.5 Drafts precedent of a dedicated SQLite per concern (mirrors test isolation, simpler resets, matches the Piqd namespace pattern) is a better fit. GraphRepository in v0.5 is already coupled to Moments/Assets; overloading it with identity-adjacent rows blurs the boundary. **Decision recorded here; no SRS amendment required since v0.6 is interim.** Revisit at v1.0 if the graph integration ever genuinely needs the join.
4. **Universal Links / AASA → v0.7.** Custom scheme `piqd://invite/<token>` is sufficient for v0.6's device-only invite flow. AASA + `applinks:` requires (a) a registered domain (e.g., `piqd.app`) — open item, not yet provisioned, and (b) a hosted `apple-app-site-association` JSON. Bundles with v0.7's invite-from-iMessage requirements where a real https-style preview matters.
5. **Friend display-name editing → v0.9 polish.** Set once at accept time; no rename in v0.6.
6. **Friend "last activity" → v0.7.** Column ships nullable; populated by send/receive events. v0.6 always renders "—".
7. **CAPTURE / ROLL MODE / SNAP MODE Settings toggles → v0.9.** UI rows render per UIUX §8 but don't write back. DevSettings remains the active path until v0.9.
8. **Notifications permission prompt → first Roll capture (v0.7 wires real notifications).** v0.6 deliberately defers the prompt; firing it during onboarding burns the user's one chance to grant before there's a reason to.
9. **Inbox UI → v0.7.** Gear-icon action menu shows "Inbox" disabled.
10. **Key fingerprint side-channel verification → hardening (post-v1.0).** v0.6 shows a 4-byte SHA256 fingerprint on the accept sheet for transparency; an out-of-band "compare in person" flow isn't proportionate for a device-tested interim build.
11. **First-Roll warning consumes the in-flight shutter tap.** Alternative: present the sheet, then auto-fire the shutter on dismiss. Chosen path (require a second tap) is clearer about consent semantics — the warning is informational, not a confirmation step. Documented for §8 risks.
12. **Re-using `PiqdCaptureView` in onboarding.** O1/O2 mount `PiqdCaptureView` with new `.onboardingSnap` / `.onboardingRoll` flags that hide chrome (no zoom pill, no Drafts badge, no gear icon) but keep shutter wired. Risk of leakage: capture write through the onboarding flow lands in the real vault. **Decision: yes, by design — a real first photo is a better hook than a synthetic confirmation, and the asset gets enrolled in Drafts like any other Snap.** Storage warning still applies on first Roll regardless of where it triggers.

---

## 8. Risks

| Risk | Mitigation |
|------|------------|
| Keypair generated but Keychain write fails silently → next launch generates a different keypair, breaking already-shared invites | `IdentityKeyService.currentKey()` round-trips through Keychain on every cold-launch warm-up; cache mismatch logs an error in Debug. Concrete impl smoke-tested on device per checklist row 2.1. |
| Custom-scheme deep-link arrives mid-onboarding → `IncomingInviteSheet` collides with onboarding presentation | `PiqdApp.handleIncomingURL` defers `incomingInvite` publication until `onboardingCoordinator.isComplete || step == .invite`; queued and re-posted on completion. Checklist row 3.3. |
| QR scanner session contends with the main `CaptureEngine` AVCaptureSession when launched from Layer 1 → black viewfinder on dismiss | `QRScannerView` owns its own `AVCaptureSession` and stops it on `dismantleUIView`; main capture engine pauses on Settings push and resumes on pop. Manual device verification (row 7.1) — XCUITest cannot exercise camera contention. |
| Onboarding completion flag set before O4's "Start shooting →" → user can't re-render their QR if they background mid-O4 | `complete()` is called only by O4's primary CTA; O3 progress is tracked in `lastStep`. Resume key path covers backgrounding mid-screen. |
| Reinstall keeps friends list (GRDB file in `Documents/`) but loses keypair → orphan circle | Onboarding O0 unconditionally clears `circle.sqlite` if `IdentityKeyService.currentKey()` was just generated (i.e., no Keychain entry pre-launch). Test seam `circleClearOnFreshIdentity` covers it. |
| Invite token replay (saved old QR re-scanned by the same recipient) → no harm but error UX should be clear | `accept()` returns `.duplicate` on existing public-key match; `IncomingInviteSheet` renders "Already in your circle" instead of generic error. Row 3.6. |
| First-Roll warning fires during the v0.5 Drafts enrollment path → orphan draft if user doesn't tap "Got it" | Warning gate runs **before** `enrollDraftIfNeeded` — the shutter handler short-circuits, no asset is captured, no draft row is written. Row 5.1. |
| `circle.sqlite` migration v1 fails on a device with an old development build → repo init crashes | Fresh-create-or-open pattern (mirrors Drafts repo); no v0 → v1 migration exists since v0.6 is the first introduction. Old dev installs are wiped by reinstall (consistent with FR-CIRCLE-KEY-04). |
| `PIQD_DEV_INVITE_TOKEN` launch arg leaks into release | All Dev launch-arg parsing wrapped in `#if DEBUG`; release builds compile out the seed accessor. Compile-time guard, not runtime. |

---

*— End of v0.6 plan draft · Next: piqd_interim_v0.7_plan.md (Snap P2P: MPC LAN + WebRTC STUN/TURN + APNs pending; ephemeral inbox; reaction chips) —*
