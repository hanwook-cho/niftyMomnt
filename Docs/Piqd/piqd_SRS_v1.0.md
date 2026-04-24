# Piqd

## Software Requirements Specification (SRS)

**Modular Clean Architecture · NiftyCore SDK · iOS Platform**

Version 1.0 | April 2026 | Confidential

Platform: iOS 26.0+ | Language: Swift 5.9+ | Architecture base: niftyMomnt NiftyCore SRS v1.2

Author: Han Wook Cho | hwcho99@gmail.com

---

## Document Control — v1.0

This is the initial SRS for **Piqd**, a new iOS camera application built on the NiftyCore SDK established in `niftyMomnt_SRS_v1.2.docx.md`. Piqd is a standalone app variant sharing NiftyCore's Clean Architecture, domain models, protocol contracts, and platform adapters. All NiftyCore internals are treated as read-only dependencies — Piqd adds no new business logic to NiftyCore itself. All Piqd-specific additions are confined to a new AppConfig variant, a new Xcode target, and a new Presentation layer.

**What this document defines:**
- Piqd's AppConfig variant and capability set
- Snap Mode and Roll Mode — interaction models, capture formats, and UX contracts
- New domain model additions: `AssetType.sequence`, `SequenceStrip`, `AssetType.dual`, `AssetType.movingStill`, `EphemeralPolicy`, `RollPackage`
- P2P sharing architecture — transport layers, ephemeral policy, Roll unlock ritual
- iCloud encrypted package fallback for Roll Mode reliability
- Non-functional requirements specific to Piqd

**What this document inherits from niftyMomnt SRS v1.2 (not repeated here):**
- Clean Architecture layer definitions and dependency rule (§1.2–1.3)
- Full NiftyCore package and module structure (§2)
- All existing domain models: Asset, Moment, AmbientMetadata, etc. (§4)
- All protocol contracts: CaptureEngineProtocol, VaultProtocol, GraphProtocol, etc. (§5)
- Engine specifications: CaptureEngine, IndexingEngine, StoryEngine, NudgeEngine (§6)
- Data layer specifications: VaultRepository, GraphRepository, Platform Adapters (§7)
- Dependency injection and composition root pattern (§8)
- Concurrency model (§9)
- Security and privacy architecture (§10)

---

## 1. Product Overview

### 1.1 Purpose

Piqd is a Gen Z-focused iOS camera application built around two emotionally distinct capture modes. It is not a general-purpose camera — it is a social memory tool designed around a single insight: Gen Z uses a camera for two fundamentally different jobs.

| Job | Mode | Core feeling |
|-----|------|-------------|
| See what I'm doing | Snap Mode | Instant · reactive · ephemeral |
| Remember how this felt | Roll Mode | Delayed · nostalgic · ritual |

Every product decision in Piqd flows from this distinction. The two modes are not settings — they are different cameras with different aesthetics, different capture formats, different sharing behaviors, and a different relationship with time.

### 1.2 App Identity

| Attribute | Value |
|-----------|-------|
| App name | Piqd |
| Bundle ID | com.piqd.app |
| App Group | com.piqd.group |
| NiftyCore variant | AppConfig.piqd |
| Primary market | Gen Z iOS users, 16–26 |
| Platform minimum | iOS 26.0 / iPhone 15 |

### 1.3 Name Rationale

Piqd derives from "piqued" — a moment that caught your attention, sparked curiosity, demanded capture. The past tense is intentional: the moment already happened, which is Roll Mode's entire philosophy. Phonetically one syllable. Works as noun ("my Piqd from last night"), verb ("Piqd me that"), and brand ("Shot on Piqd").

---

## 2. AppConfig — Piqd Variant

### 2.1 Capability Set

```swift
// Apps/Piqd/AppConfig+Piqd.swift

extension AppConfig {
    static let piqd = AppConfig(
        appVariant:  .custom("piqd"),
        assetTypes:  [.still, .live, .clip, .sequence, .movingStill, .dual],
        aiModes:     [.onDevice],
        features:    [.rollMode, .snapMode, .trustedSharing,
                      .sequenceCapture, .p2pSharing, .iCloudRollPackage],
        sharing:     SharingConfig(
                         maxCircleSize: 10,
                         labEnabled: false,
                         ephemeralPolicy: EphemeralPolicy(
                             expiresOnView: true,
                             hardCeilingHours: 24
                         )
                     ),
        storage:     StorageConfig(
                         smartArchiveEnabled: true,
                         iCloudSyncEnabled: true,
                         clipQuality: ClipQualityConfig(
                             maxResolution: .uhd4K,
                             maxFrameRate: 60,
                             proOnlyHighFPS: true
                         )
                     )
    )
}
```

### 2.2 New FeatureSet Flags

The following flags are added to `NiftyCore/Sources/Domain/AppConfig.swift` as additive extensions to the existing `FeatureSet` OptionSet:

```swift
public extension FeatureSet {
    static let snapMode           = FeatureSet(rawValue: 1 << 8)
    static let sequenceCapture    = FeatureSet(rawValue: 1 << 9)
    static let p2pSharing         = FeatureSet(rawValue: 1 << 10)
    static let iCloudRollPackage  = FeatureSet(rawValue: 1 << 11)
}
```

### 2.3 ClipQualityConfig

```swift
// NiftyCore/Sources/Domain/AppConfig.swift — additive

public struct ClipQualityConfig: Equatable {
    public enum Resolution { case hd1080, uhd4K }
    public let maxResolution:   Resolution
    public let maxFrameRate:    Int     // 30, 60, 120
    public let proOnlyHighFPS:  Bool    // gates 120fps to Pro devices
}

extension StorageConfig {
    public var clipQuality: ClipQualityConfig { ... }
}
```

---

## 3. New Domain Model Additions

All types below are added to `NiftyCore/Sources/Domain/Models/`. They follow existing conventions: pure Swift value types, zero platform imports, no Codable in the domain layer.

### 3.1 AssetType Extensions

```swift
// NiftyCore/Sources/Domain/Models/Asset.swift — additive

public extension AssetType {
    // 6-frame strip, tap-to-start, 3-second window
    static let sequence    = "sequence"

    // Subtle motion applied to a still post-capture (assembled by StoryEngine)
    static let movingStill = "movingStill"

    // Simultaneous front + rear capture via AVCaptureMultiCamSession
    static let dual        = "dual"
}

public extension AssetTypeSet {
    static let sequence    = AssetTypeSet(rawValue: 1 << 5)
    static let movingStill = AssetTypeSet(rawValue: 1 << 6)
    static let dual        = AssetTypeSet(rawValue: 1 << 7)

    // Updated .all to include new types
    static let all: AssetTypeSet = [.still, .live, .clip, .echo,
                                     .atmosphere, .sequence,
                                     .movingStill, .dual]
}
```

### 3.2 SequenceStrip

The primary output of Snap Mode's Sequence capture format. Six still frames captured at 333ms intervals from a single tap event, auto-assembled into a looping MP4 by StoryEngine.

```swift
// NiftyCore/Sources/Domain/Models/SequenceStrip.swift

public struct SequenceStrip: Identifiable, Equatable {
    public let id:           UUID
    public let frames:       [Asset]      // exactly 6, all AssetType.still
    public let capturedAt:   Date         // tap timestamp — frame 0
    public let intervalMs:   Int          // 333ms default
    public var outputURL:    URL?         // nil until StoryEngine assembles
    public var shareReady:   Bool         // true when outputURL is populated
    public var mode:         CaptureMode  // .snap or .roll
}
```

**Constraints:**
- `frames.count` must equal exactly 6. CaptureEngine enforces this — a SequenceStrip with fewer than 6 frames due to interruption is discarded, not surfaced to the user.
- `intervalMs` is 333 by default and not user-configurable in v1.0. Reserved for future tuning.
- `shareReady` gates the send action in Snap Mode. The share button is disabled until StoryEngine sets `outputURL` and flips `shareReady` to `true`. Target assembly time: under 2 seconds on iPhone 15.
- `mode` determines assembly behavior: Snap assembles immediately post-capture; Roll assembles at unlock time (9 PM or 24h).

### 3.3 EphemeralPolicy

Defines the disappear behavior for Snap Mode shared assets. Attached to `SharingConfig`.

```swift
// NiftyCore/Sources/Domain/Models/EphemeralPolicy.swift

public struct EphemeralPolicy: Equatable {
    public let expiresOnView:      Bool   // true = delete on first view
    public let hardCeilingHours:   Int    // hard expiry regardless of view
                                          // 0 = no ceiling (Roll Mode)
}

// Snap Mode default
public extension EphemeralPolicy {
    static let snap = EphemeralPolicy(expiresOnView: true, hardCeilingHours: 24)
    static let roll = EphemeralPolicy(expiresOnView: false, hardCeilingHours: 0)
}
```

### 3.4 RollPackage

The assembled output of Roll Mode at unlock time. Encrypted and written to iCloud for reliable delivery.

```swift
// NiftyCore/Sources/Domain/Models/RollPackage.swift

public struct RollPackage: Identifiable, Equatable {
    public let id:              UUID
    public let momentID:        UUID
    public let assets:          [Asset]
    public let sequences:       [SequenceStrip]
    public let assembledAt:     Date          // StoryEngine completion time
    public let unlockTime:      Date          // 9 PM or 24h from first capture
    public let rollCircle:      [FriendID]    // locked at first capture, immutable
    public var iCloudPackageURL: URL?         // nil until uploaded
    public var encryptedFor:    [FriendID]    // recipients with decryption keys
}
```

**Key constraint — `rollCircle` is immutable after first capture.** The circle is set when the first asset is added to the Roll and cannot be changed mid-day. This prevents a friend added after the Roll started from receiving a notification for a Roll they were not part of.

### 3.5 FriendID

```swift
// NiftyCore/Sources/Domain/Models/TrustedCircle.swift

public struct FriendID: Identifiable, Equatable, Hashable {
    public let id:          UUID
    public let displayName: String
    public let publicKey:   Data    // for E2EE encryption of RollPackage
}
```

---

## 4. Capture Modes

### 4.1 Mode Overview

Piqd has exactly two capture modes. The mode switch is a deliberate physical gesture — not a settings toggle. The UI, viewfinder aesthetic, available formats, and sharing behavior are entirely different between modes. Switching modes should feel like picking up a different camera.

| Attribute | Snap Mode | Roll Mode |
|-----------|-----------|-----------|
| Emotional job | See what I'm doing | Remember how this felt |
| Review | Immediate | Locked until unlock time |
| Formats | Dual, Clip, Sequence | Still, Live Photo, Moving Still |
| Aesthetic | Clean, fast, reactive | Analog grain, light leak, imperfect |
| Sharing | Ephemeral P2P, instant | Encrypted iCloud package, 9 PM ritual |
| Night behavior | Standard | Auto-routed to Roll, grain applied |
| Film simulation | Off | On — baked pre-shutter and post-capture |

### 4.2 Mode Switch Gesture

The mode switch is a single deliberate swipe gesture on the viewfinder — not a tab, not a button, not a settings menu. The transition must feel physical: the viewfinder aesthetic morphs on swipe (grain fades in, UI chrome changes, shutter sound changes). Target transition time: under 150ms from gesture recognition to first frame of new aesthetic. This matches the niftyMomnt SRS v1.2 §11.1 mode switch animation target.

**Implementation:** Handled entirely in the Presentation layer. CaptureEngine.switchMode() is called on gesture completion. No NiftyCore changes required.

### 4.3 Snap Mode

#### 4.3.1 Purpose and Persona

Snap Mode is for reactive, social, in-the-moment capture. The shutter is always hot. The UI is minimal. Every interaction optimizes for speed. Gen Z is "allergic" to slow apps — any lag over 100ms at the shutter is a product failure in this mode.

#### 4.3.2 Capture Formats

**Dual Capture** (`AssetType.dual` for video; `AssetType.still` for still composite)
- Simultaneous front and rear capture via `AVCaptureMultiCamSession` (no-connection topology, explicit `AVCaptureConnection` per port).
- Two media kinds, selected via a Still/Video sub-toggle above the shutter when Dual is active:
  - **Dual Video** — two `AVCaptureMovieFileOutput` streams composited by `DualCompositor` into one MP4. Audio from primary only. Vault asset type `.dual`.
  - **Dual Still** — two `AVCapturePhotoOutput` photos composited by `DualStillCompositor` into one JPEG (re-encoded to HEIC at vault-write). Vault asset type `.still`.
- Composite **layout** is shared by both kinds: `.pip` (default), `.topBottom`, `.sideBySide`. Stored in `DevSettingsStore.dualLayout`.
- Render canvas: 9:16 portrait (1080×1920). Layout placement math is shared via `DualCompositor.layoutRects(canvas:layout:)`.
- Split layouts (Top/Bottom, Side-by-Side) currently use aspect-fit for video — `AVMutableVideoCompositionLayerInstruction` does not clip transformed sources, so aspect-fill would overlap the other half. Stills aspect-fill via `UIGraphicsImageRenderer` clipping.
- Gated to devices reporting `AVCaptureMultiCamSession.isMultiCamSupported`.
- Use case: reaction content, "POV + subject" moments, BeReal-style stills, vlog-style video.
- AppConfig flag: `.dualCamera` in `features`; `.dual` in `assetTypes` (still composite uses `.still`).

**Video Clips** (`AssetType.clip`)
- Fixed short duration — user-configurable between 5s, 10s, 15s (default 10s)
- Quality: up to 4K/60fps. 120fps gated to Pro devices via `ClipQualityConfig.proOnlyHighFPS`
- Interaction: hold shutter to record, release to stop. Duration cap enforced by CaptureEngine telemetry ceiling.
- Sent immediately after capture. No lock.

**Sequence** (`AssetType.sequence`)
- 6 frames at 333ms intervals, tap-to-start, 3-second total window
- Interaction: single tap triggers the full 6-frame sequence automatically. No hold required.
- Visual feedback: subtle frame-flash indicator on viewfinder for each of the 6 captures
- StoryEngine assembles frames into a looping MP4 (~1–2MB) within 2 seconds of capture completion
- Share button disabled (`shareReady: false`) until assembly completes
- Sent as assembled MP4, never as raw HEIF frames (raw frames are ~18MB — too large for Snap)
- Capture trigger: `AVCaptureAdapter` fires 6 sequential `capturePhoto()` calls on a `DispatchSourceTimer` at 333ms spacing. Not burst/bracket mode.

#### 4.3.3 Interaction Model

```
Tap   → Still photo (if .still is in assetTypes — Snap does not use still by default)
Tap   → Sequence trigger (primary Snap action — 6 frames auto-fire)
Hold  → Video clip recording begins
Release hold → Clip recording stops, asset ready
Mode switch swipe → Transition to Roll Mode
```

#### 4.3.4 Pre-Shutter Features (Snap)

- **Zero-lag shutter:** `AVCaptureDevice.focusMode = .continuousAutoFocus` + Vision face tracking via `AVCaptureAdapter`. Sub-100ms shutter response target.
- **Invisible level:** `CMMotionManager.deviceMotion` roll/pitch. Thin glowing line appears only when phone is off-level by more than 3°. Disappears when level. Snap Mode only.
- **Subject guidance:** `VNDetectFaceRectanglesRequest` detects face cut-off or proximity. "Step back for the full vibe" tip appears for maximum 1.5s then auto-dismisses. Snap Mode only.
- **Backlight correction:** `AVCaptureDevice.exposureMode = .continuousAutoExposure` with automatic EV compensation. Viewfinder shows the actual output exposure in real time.
- **Vibe hint (subtle):** CoreML scene classifier runs at 2fps (throttled). Detects social vs quiet scene context. Surfaces a small ambient glyph pulse — does NOT auto-morph the full UI. User retains mode control.

#### 4.3.5 Sharing — Snap Mode

Snap Mode sharing is immediate, ephemeral, and P2P. See §6 for full transport architecture.

- `EphemeralPolicy.snap`: expires on first view + 24h hard ceiling
- Asset sent as encrypted payload over MultipeerConnectivity (nearby) or WebRTC DataChannel (remote)
- Sender copy purged on delivery confirmation
- Circle selection: pre-set trusted friends, one tap. Max 10 recipients (AppConfig)
- Sequence strips: shared as assembled MP4 only, never raw frames

### 4.4 Roll Mode

#### 4.4.1 Purpose and Persona

Roll Mode is for intentional, nostalgic, present-moment capture. The user focuses on framing and clicking. The developing happens in the background. Review is locked until the unlock event. The analog aesthetic is baked in from the moment the viewfinder opens — grain, light leak, muted tones. This is not a filter applied after the fact. It is the camera's identity in this mode.

#### 4.4.2 Capture Formats

**Still Photos** (`AssetType.still`)
- Primary Roll Mode format
- "Raw / imperfect" aesthetic: analog grain VibePreset applied pre-shutter (viewfinder) and baked post-capture
- Motion blur is acceptable and stylistically encouraged — no optical image stabilization override
- Shot limit: 24 stills per Roll (per day). A visible "roll counter" in the UI counts down remaining shots. Scarcity drives intention.
- Night Mode: when `AmbientMetadata.sunPosition` indicates night, Apple's computational Night Mode applies automatically. Analog grain applied on top of the Night Mode output.

**Apple Live Photos** (`AssetType.live`)
- 1.5s motion + ambient audio before and after shutter
- Captured with analog grain overlay on the video component
- Post-unlock: StoryEngine can export as a looping Boomerang MP4 via `AVAssetExportSession`
- Use case: authentic micro-moments with real background sound

**Hybrid Moving Stills** (`AssetType.movingStill`)
- Not captured directly — assembled by StoryEngine from a Live Photo at unlock time
- Process: `VNGenerateForegroundInstanceMaskRequest` segments subject from background → Metal shader applies subtle warp/drift to background elements (steam, hair, leaves) → output is an APNG or short MP4 loop
- User shoots a Live Photo normally. The Moving Still is a surprise at unlock — the user discovers the photo is alive.
- Assembly triggered at unlock time alongside the rest of the Roll package
- v1.0: automatic selection (StoryEngine picks the best Live Photo candidate for Moving Still conversion). User cannot manually select in v1.0.

#### 4.4.3 Viewfinder Aesthetic — Ghost Preview

The Roll Mode viewfinder is the "ghost" — it shows composition without technical precision. The user sees the world through an analog lens before they shoot.

- **Grain overlay:** `CIFilter` with `CIRandomGenerator` applied to `AVCaptureVideoPreviewLayer`. Grain seed is time-varying per-frame (authentic drifting grain, not static noise). Subtle — not overwhelming.
- **Light leak:** semi-transparent asset composited at 10–15% opacity at a viewfinder corner. Triggered probabilistically on mode entry (not every session). Adds surprise and authenticity.
- **Hidden technical stats:** ISO, shutter speed, exposure indicators hidden in Roll Mode. The user sees composition only.
- **Film simulation presets:** named VibePresets applied to the viewfinder and baked into the output image. v1.0 ships with three presets: `.kodakWarm` (warm tones, moderate grain), `.fujiCool` (cool tones, fine grain), `.ilfordMono` (black and white, heavy grain). Selectable via a subtle swipe on the viewfinder edge — no menu.
- **Implementation:** VibePreset enum in `CaptureEngineProtocol.applyPreset()`. AVCaptureAdapter applies the CIFilter chain to both the preview layer and the output HEIF. Zero NiftyCore domain changes.

#### 4.4.4 Interaction Model

```
Tap   → Still photo (primary Roll action)
Tap   → Live Photo (if Live mode selected via edge swipe)
Hold  → NOT supported in Roll Mode (no video recording)
Mode switch swipe → Transition to Snap Mode
```

No hold-to-record in Roll Mode. The mode is about stills and micro-moments, not video.

#### 4.4.5 Roll Capacity and Counter

- 24 stills per Roll per calendar day
- Counter displayed as a physical roll indicator (e.g. "14 left") — not a progress bar
- When counter reaches 0: shutter disabled. A gentle message: "Roll's full. See you at 9."
- Counter resets at midnight local time

#### 4.4.6 The 9 PM Unlock Ritual

The unlock is the emotional core of Roll Mode. It is not a background sync — it is a moment.

1. **Unlock trigger:** 9 PM local time, or 24 hours after the first asset was added to the Roll — whichever comes first.
2. **StoryEngine assembly:** Moving Stills processed. Moment clusters labeled. Hero asset selected. Film simulation baked into all assets.
3. **RollPackage creation:** All assets packaged into a `RollPackage`. Package encrypted with each `rollCircle` friend's public key.
4. **iCloud upload:** Encrypted `RollPackage` written to sender's private iCloud container. See §6.3 for full reliability architecture.
5. **Group notification:** APNs sends metadata-only ping to `rollCircle`: "Your Piqd from today is ready." No content in notification payload.
6. **Friends open simultaneously:** Each friend opens Piqd → retrieves their decrypted copy from iCloud → Roll opens together. The shared opening is the ritual.
7. **Persistent on recipient:** Roll assets land in the recipient's Film Archive as a shared Moment. `EphemeralPolicy.roll` — no expiry.

#### 4.4.7 Pre-Shutter Features (Roll)

- **Ghost Preview grain:** always active in Roll Mode viewfinder. See §4.4.3.
- **Invisible level:** active (same as Snap Mode — CMMotionManager).
- **No subject guidance:** Roll Mode is intentionally unguided. Imperfect framing is stylistically correct. Subject guidance text is Snap Mode only.
- **No Vibe-Check AI:** ambient scene detection is Snap Mode only. Roll Mode's aesthetic is fixed — the user chose the mode intentionally.

---

## 5. Pre-Shutter System

### 5.1 VibeHintPublisher

Added to `CaptureEngineProtocol` as an additive, optional publisher. Throttled at 2fps. Publishes a `VibeHint` enum with cases `.social` and `.quiet`. The Presentation layer subscribes and shows a subtle ambient glyph — it does not trigger mode switching.

```swift
// Additive to CaptureEngineProtocol

public enum VibeHint: Equatable {
    case social   // group, high-energy scene detected
    case quiet    // landscape, low-energy scene detected
    case neutral  // below confidence threshold — no hint shown
}

// Added to CaptureEngineProtocol:
var vibeHint: AnyPublisher<VibeHint, Never> { get }
```

### 5.2 CaptureTelemetry Extensions

The following fields are added additively to `CaptureTelemetry`:

```swift
public extension CaptureTelemetry {
    var isLevel:          Bool     // true when device pitch/roll within ±3°
    var faceDetected:     Bool     // true when VNDetectFaceRectanglesRequest finds a face
    var faceNearEdge:     Bool     // true when detected face is within 15% of frame edge
    var sequenceFrame:    Int?     // 1–6 during sequence capture, nil otherwise
}
```

### 5.3 Zero-Lag Shutter Architecture

| Component | Implementation | Target |
|-----------|---------------|--------|
| Continuous AF | `AVCaptureDevice.focusMode = .continuousAutoFocus` + Vision subject tracking | Lock before tap |
| Exposure | `AVCaptureDevice.exposureMode = .continuousAutoExposure` | Real-time EV |
| Quality priority | `AVCapturePhotoSettings.photoQualityPrioritization = .speed` | Sub-100ms |
| Sequence timer | `DispatchSourceTimer` at 333ms intervals, 6 iterations | Precise spacing |

Ring buffer (pre-capture): explicitly excluded from v1.0. Planned for v2.0 behind `AppConfig.FeatureSet.ringBuffer`, gated to iPhone 15 Pro+.

---

## 6. Sharing Architecture

### 6.1 Overview

Piqd uses a zero-server-content P2P sharing model. No user photo or video is ever stored on a Piqd server. The architecture has three transport layers that activate automatically based on recipient availability and proximity.

| Scenario | Transport | Server touch | Latency |
|----------|-----------|-------------|---------|
| Recipient nearby (same network/BT) | MultipeerConnectivity LAN | None | <1s |
| Recipient online, remote | WebRTC STUN → TURN fallback | TURN relay only (encrypted) | 1–3s |
| Recipient offline (Snap) | APNs metadata ping → deferred P2P | APNs metadata only | On wakeup |
| Roll unlock | iCloud encrypted package | iCloud E2EE (Apple-managed) | On app open |

### 6.2 Snap Mode Sharing

#### 6.2.1 Transport Selection

Transport selection is automatic — the user never sees or configures it. `ShareMomentUseCase` evaluates peer availability via the `A2ASharingAdapter` (implementing a new `SharingProtocol`) and selects the optimal path.

```swift
// NiftyCore/Sources/Domain/Protocols/SharingProtocol.swift

public protocol SharingProtocol: AnyObject {
    func send(_ asset: Asset, to friends: [FriendID],
              policy: EphemeralPolicy) async throws -> ShareResult
    func send(_ strip: SequenceStrip, to friends: [FriendID],
              policy: EphemeralPolicy) async throws -> ShareResult
    func retrieveInbox() async throws -> [InboxItem]
    func confirmReceived(_ itemID: UUID) async throws
}

public enum ShareResult: Equatable {
    case delivered(transport: TransportType)
    case pending(reason: PendingReason)
    case failed(Error)
}

public enum TransportType { case lan, webRTC, iCloud }
public enum PendingReason { case recipientOffline, assemblyInProgress }
```

#### 6.2.2 Ephemeral Lifecycle

```
Sender captures → asset encrypted → sent via P2P
Recipient opens → asset decrypted → displayed once
On view: recipient inbox item marked viewed → deletion scheduled
Hard ceiling: 24h from send timestamp → deletion regardless of view status
Sender copy: purged on ShareResult.delivered confirmation
```

#### 6.2.3 Sequence Strip Sharing

- Sequence strips are shared exclusively as the assembled MP4 output
- `shareReady` flag on `SequenceStrip` must be `true` before share action is available
- Raw HEIF frames are never transmitted — they remain in the local vault only
- MP4 output target size: 1–2MB (sufficient for LAN and WebRTC without significant latency)

### 6.3 Roll Mode Sharing — iCloud Encrypted Package

#### 6.3.1 Reliability Problem

The P2P model (sender device must be online) is insufficient for Roll Mode. The 9 PM unlock is a scheduled ritual. If the sender's device is off or in airplane mode at unlock time, every friend receives an APNs notification for a Roll they cannot retrieve. This breaks the emotional core of the product.

#### 6.3.2 Solution — iCloud Encrypted Package

At unlock time, StoryEngine writes the assembled `RollPackage` to the sender's private iCloud container, encrypted per-recipient with each friend's public key. No Piqd server is involved. Apple's iCloud E2EE infrastructure manages the delivery. Recipients retrieve on their next app open — independent of whether the sender's device is online.

```
Unlock trigger (9 PM or 24h)
  → StoryEngine assembles RollPackage
  → For each friend in rollCircle:
      encrypt(RollPackage, friend.publicKey) → encryptedBlob
      write encryptedBlob to iCloud private container
      path: com.piqd.rolls/{momentID}/{friendID}.rollpkg
  → APNs metadata ping to rollCircle
  → RollPackage.iCloudPackageURL populated
  → RollPackage.encryptedFor updated

Friend opens app:
  → Piqd checks iCloud container for pending .rollpkg files
  → Downloads and decrypts with local private key
  → Assets added to Film Archive as shared Moment
  → .rollpkg file deleted from iCloud after successful decrypt
```

#### 6.3.3 Privacy Properties

- Content is encrypted on the sender's device before iCloud upload
- iCloud stores only opaque encrypted blobs — Apple cannot read content
- Piqd has no server-side key access
- `.rollpkg` files auto-deleted from iCloud after recipient decryption confirms
- iCloud entitlement required: `com.apple.developer.icloud-container-identifiers`

#### 6.3.4 Key Management

```swift
// NiftyCore/Sources/Domain/Models/TrustedCircle.swift

public struct FriendID: Identifiable, Equatable, Hashable {
    public let id:          UUID
    public let displayName: String
    public let publicKey:   Data   // Curve25519 public key, received at friend invite
}
```

Key exchange occurs at trusted friend invitation time (QR code or deep link). Each user generates a Curve25519 keypair on first app launch. Private key stored in iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Public key shared with friends at invite time. Public keys stored locally in the trusted friends list — never on a Piqd server.

### 6.4 Trusted Friends System

Inherited from the A2A Sharing PRD. Key Piqd-specific constraints:

- Maximum circle size: 10 (AppConfig.SharingConfig.maxCircleSize)
- Invitation via QR code or deep link only — no username search, no public directory
- Friends list stored locally in the intelligence graph (GraphRepository) — never on a server
- `rollCircle` for each Moment is set at first capture and is immutable. Adding a friend mid-day does not add them to an in-progress Roll.
- Friend removal: removes from future Rolls immediately. Does not retract already-delivered Roll packages.

### 6.5 Offline Recipient — Snap Mode

When a Snap Mode recipient is offline at send time:
1. Sender device holds the encrypted asset locally
2. APNs metadata-only notification sent: `{reason: "snap_pending", senderId, messageId}`
3. No content in notification payload
4. When recipient comes online: Piqd initiates P2P retrieval from sender device
5. If sender device goes offline before retrieval: asset is lost (acknowledged limitation — acceptable for ephemeral Snap content, not acceptable for Roll)
6. Hard ceiling: if recipient does not retrieve within 24h, sender purges the asset and sends an APNs "expired" notification

---

## 7. Presentation Layer — Piqd UI Contracts

### 7.1 Viewfinder States

The viewfinder has four distinct visual states. These are Presentation layer concerns only — no NiftyCore involvement.

| State | Triggered by | Visual |
|-------|-------------|--------|
| Snap — active | Mode = Snap | Clean viewfinder, minimal chrome, fast shutter UI |
| Snap — sequence firing | sequenceFrame 1–6 published | Subtle flash on each frame, counter overlay "1…2…3…4…5…6" |
| Roll — ghost | Mode = Roll | Grain overlay, light leak, hidden stats, film counter |
| Roll — full | Mode = Roll, counter = 0 | Shutter disabled, "Roll's full. See you at 9." overlay |

### 7.2 Mode Switch Animation

- Gesture: horizontal swipe on viewfinder
- Duration: 150ms maximum (per niftyMomnt SRS v1.2 §11.1)
- Animation: grain fades in (Roll) or out (Snap), UI chrome morphs, shutter sound changes
- No intermediate state — the switch is atomic from the user's perspective

### 7.3 Film Counter (Roll Mode)

- Displayed as a physical roll counter: "14 left" or a film-strip notch indicator
- Counts down from 24 on first capture of the day
- Resets at midnight local time
- When 5 or fewer remain: counter color shifts to amber
- When 0: shutter button dims, counter shows "Roll full"

### 7.4 Sequence Strip Preview (Snap Mode)

- Immediately after assembly (`shareReady = true`): a looping 6-frame strip preview appears as a bottom sheet
- Duration before auto-dismiss: 8 seconds (user can send, save, or dismiss)
- Send action: opens circle selector (pre-populated with last-used friends)
- The strip loops continuously during preview — this is the shareable artifact

### 7.5 Roll Unlock Screen

- Triggered at unlock time (9 PM or 24h)
- Animated "developing" sequence: assets reveal one by one with a film-advance sound
- Moving Stills animate on reveal — the user discovers the photo is alive
- Circle notification sent automatically at reveal start
- Friends join the reveal asynchronously — their "opened" status shows as a subtle avatar ring around the Roll

---

## 8. Non-Functional Requirements — Piqd Specific

All performance targets from niftyMomnt SRS v1.2 §11.1 apply. The following are Piqd-specific additions or tightenings:

| Requirement | Target | Notes |
|-------------|--------|-------|
| Shutter response (Snap) | <100ms | Tighter than niftyMomnt's 300ms capture→preview. Snap Mode identity depends on this. |
| Sequence assembly time | <2 seconds | From frame 6 capture to shareReady = true |
| Mode switch animation | <150ms | Inherited from niftyMomnt SRS v1.2 |
| Roll package iCloud upload | <30 seconds | From unlock trigger to iCloudPackageURL populated |
| Moving Still assembly | <10 seconds | Per asset, runs at unlock time during RollPackage assembly |
| Roll unlock → APNs ping | <5 seconds | From iCloud upload complete to APNs notification sent |
| Grain overlay frame rate | 30fps minimum | CIFilter on preview layer must not drop below viewfinder frame rate |
| App memory (Snap active) | <200MB | Inherited. Sequence capture peak must not exceed this. |
| Cold launch → capture ready | <1.5 seconds | Inherited from niftyMomnt SRS v1.2 |

### 8.1 Supported Devices and OS

| Requirement | Specification |
|-------------|--------------|
| Minimum iOS | iOS 26.0 |
| Minimum device | iPhone 15 |
| Dual Capture | iPhone 15+ (all models — AVCaptureMultiCamSession) |
| 120fps clips | iPhone 15 Pro+ only (proOnlyHighFPS gate) |
| Primary test devices | iPhone 15, iPhone 15 Pro, iPhone 16 family |
| iPadOS | Not supported v1.0 |

### 8.2 Privacy Framework Requirements — Piqd Additions

In addition to niftyMomnt SRS v1.2 §10.2:

| Framework | Permission | Usage description |
|-----------|-----------|------------------|
| iCloud (CloudKit) | `com.apple.developer.icloud-container-identifiers` | Piqd uses your iCloud to deliver encrypted Rolls to friends. Content is encrypted on your device before upload. |
| MultipeerConnectivity | Bluetooth + Local Network | Piqd shares photos directly with nearby friends without using a server. |
| Camera (front) | NSCameraUsageDescription | Piqd uses both cameras simultaneously for reaction capture in Snap Mode. |

---

## 9. Architecture Additions — NiftyData Layer

### 9.1 New Platform Adapters

| Adapter | Implements | Wraps |
|---------|-----------|-------|
| `A2ASharingAdapter` | `SharingProtocol` | MultipeerConnectivity + WebRTC + APNs. Handles transport selection, encryption, delivery confirmation. |
| `iCloudRollAdapter` | `RollDeliveryProtocol` | CloudKit private container. Writes/reads encrypted `.rollpkg` files. Handles upload retry on failure. |
| `DualCaptureAdapter` | `CaptureEngineProtocol` (dual mode) | `AVCaptureMultiCamSession`. Manages two synchronized `AVCaptureDeviceInput` streams. |
| `MovingStillAdapter` | `MovingStillProtocol` | `VNGenerateForegroundInstanceMaskRequest` + Metal shader for background warp. Runs at unlock time. |

### 9.2 RollDeliveryProtocol

```swift
// NiftyCore/Sources/Domain/Protocols/RollDeliveryProtocol.swift

public protocol RollDeliveryProtocol: AnyObject {
    func uploadPackage(_ package: RollPackage) async throws -> URL
    func downloadPackage(momentID: UUID,
                         friendID: FriendID) async throws -> RollPackage
    func deletePackage(momentID: UUID, friendID: FriendID) async throws
    func pendingPackages() async throws -> [RollPackage]
}
```

### 9.3 MovingStillProtocol

```swift
// NiftyCore/Sources/Domain/Protocols/MovingStillProtocol.swift

public protocol MovingStillProtocol: AnyObject {
    func convert(_ livePhoto: Asset) async throws -> Asset  // returns AssetType.movingStill
}
```

---

## 10. Composition Root — Piqd

```swift
// Apps/Piqd/PiqdApp.swift

@main
struct PiqdApp: App {
    private let container: AppContainer

    init() {
        let config = AppConfig.piqd

        // Platform adapters
        let captureAdapter    = AVCaptureAdapter(config: config)
        let dualAdapter       = DualCaptureAdapter(config: config)
        let indexingAdapter   = CoreMLIndexingAdapter(config: config)
        let vaultRepo         = VaultRepository(config: config)
        let graphRepo         = GraphRepository(config: config)
        let sharingAdapter    = A2ASharingAdapter(config: config)
        let iCloudAdapter     = iCloudRollAdapter(config: config)
        let movingStillAdapter = MovingStillAdapter(config: config)

        // Core engines
        let captureEngine     = CaptureEngine(config: config,
                                              captureAdapter: captureAdapter,
                                              dualAdapter: dualAdapter)
        let indexingEngine    = IndexingEngine(config: config,
                                               adapter: indexingAdapter,
                                               graph: graphRepo)
        let storyEngine       = StoryEngine(config: config,
                                            vault: vaultRepo,
                                            graph: graphRepo,
                                            movingStill: movingStillAdapter)
        let vaultManager      = VaultManager(vault: vaultRepo)
        let graphManager      = GraphManager(graph: graphRepo)

        // Use cases
        let captureUseCase    = CaptureMomentUseCase(engine: captureEngine,
                                                      vault: vaultManager,
                                                      indexing: indexingEngine)
        let storyUseCase      = AssembleReelUseCase(engine: storyEngine)
        let shareUseCase      = ShareMomentUseCase(sharing: sharingAdapter,
                                                    iCloud: iCloudAdapter,
                                                    config: config)

        container = AppContainer(
            config:         config,
            captureUseCase: captureUseCase,
            storyUseCase:   storyUseCase,
            shareUseCase:   shareUseCase,
            vaultManager:   vaultManager,
            graphManager:   graphManager
        )
    }

    var body: some Scene {
        WindowGroup {
            PiqdRootView(container: container)
        }
    }
}
```

---

## 11. Open Items — v1.0

| # | Item | Owner | Target |
|---|------|-------|--------|
| 1 | Confirm App Store name clearance for "Piqd" | Product | Pre-development |
| 2 | iCloud container provisioning and entitlement setup | Engineering | Sprint 1 |
| 3 | Curve25519 key generation and Keychain storage implementation | Engineering | Sprint 1 |
| 4 | WebRTC STUN/TURN server selection and cost model | Engineering | Sprint 2 |
| 5 | Moving Still quality threshold — minimum Live Photo motion required for conversion | Product + Engineering | Sprint 3 |
| 6 | Film simulation preset tuning — CIFilter parameters for .kodakWarm, .fujiCool, .ilfordMono | Design | Sprint 2 |
| 7 | User research — validate 333ms / 6-frame Sequence feel with Gen Z users | Product | Pre-Sprint 3 |
| 8 | Roll capacity — validate 24 shots/day limit with user testing | Product | Pre-Sprint 3 |
| 9 | Grain overlay intensity calibration — CIRandomGenerator parameters | Design + Engineering | Sprint 2 |
| 10 | APNs certificate and push notification server setup (metadata-only payloads) | Engineering | Sprint 1 |

---

*— End of Document — Piqd SRS v1.0 · NiftyCore base: niftyMomnt SRS v1.2 · April 2026 —*
