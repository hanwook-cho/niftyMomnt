# Piqd

## Product Requirements Document (PRD)

**Gen Z Camera App · Two Modes · One Emotional Truth**

Version 1.1 | April 2026 | Confidential

SRS reference: piqd_SRS_v1.0.md | Architecture base: niftyMomnt NiftyCore SRS v1.2
UI/UX reference: piqd_UIUX_Spec_v1.0.md | UX Requirements: piqd_UIUX_Requirements_v1.1.md | UX state diagrams: piqd_integration_diagrams_v1.0.html | UI reference design: piqd_onboarding_v1.0.html, piqd_reference_ui_v1.1.html

---


Author: Han Wook Cho | hwcho@gmail.com

---

## Document Control — v1.1

This is the v1.1 revision of the Piqd PRD. It supersedes `piqd_PRD_v1.0.md`.

**Changes from v1.0 — 19 tracked deltas applied:**

| # | Change | Section |
|---|--------|---------|
| 1 | Still Photos added as primary Snap Mode format | §5.2 |
| 2 | Format selector — Still → Sequence → Clip → Dual | §5.3 |
| 3 | Snap Mode has no shot limit of any kind | §5.2 |
| 4 | Zoom — 0.5×/1×/2× optical levels, zoom pill + pinch gesture | §5.4 new |
| 5 | Camera flip — front/rear switch, all formats except Dual | §5.4 new |
| 6 | Shutter color: white = photo formats, red = video formats | §5.4 new |
| 7 | Shutter shape per format (aperture, split, etc.) | §5.4 new |
| 8 | Aspect ratio: Snap 9:16 default/1:1 optional; Roll 4:3 default/1:1 optional | §5.4 new |
| 9 | Sequence always 9:16 regardless of selected ratio | §5.2 |
| 10 | Social sharing via iOS share sheet (secondary action post-capture) | §8.4 new |
| 11 | Photo Library export — opt-in per send (Snap), batch post-unlock (Roll) | §8.4 new |
| 12 | Storage lifecycle policy — vault purge, Film Archive local only in v1.0 | §8.5 new |
| 13 | iCloud scope — Roll delivery only, no vault sync in v1.0 | §8.5 new |
| 14 | Film Archive iCloud encrypted backup deferred to v2.0 | §11 |
| 15 | Layered reveal UI system — rest/secondary/tertiary chrome | §5.4 new |
| 16 | No thumbnail in viewfinder — confirmation via shutter animation + counter | §5.4 new |
| 17 | Drafts tray — 24h expiry, local only, badge indicator, per-asset playback | §5.5 new |
| 18 | Safe Render zone during Sequence capture (UX-STATE-06) | §5.2 |
| 19 | Receiver experience fully specified — notification, inbox, view, response, purge | §8.3 new |
| 20 | Dual-mode user cohort as a tracked retention metric | §12.2 |
| 21 | Mode switch — long-hold mode pill + confirmation sheet replaces swipe gesture | §4.2 |
| 22 | Settings access — gear icon in Layer 1 (viewfinder) + ⋯ icon on all non-viewfinder screens | §8 new |

---

## Sections

1. Product Vision and Strategy
2. Target User
3. Core Product Principles
4. Feature: Mode System
5. Feature: Snap Mode
6. Feature: Roll Mode
7. Feature: Pre-Shutter System
8. Feature: Sharing
9. Feature: Trusted Circle
10. Feature: Film Archive
11. Out of Scope — v1.0
12. Success Metrics
13. Risks and Mitigations
14. Acceptance Criteria

---

## 1. Product Vision and Strategy

### 1.1 Vision

Piqd is the camera app that understands why Gen Z takes photos. Not to document — to feel. Not to post — to share with the people who were there.

### 1.2 The Core Insight

Gen Z uses a camera for two fundamentally different emotional jobs:

**"See what I'm doing"** — reactive, immediate, social. A photo sent to a friend thirty seconds after it was taken. A reaction captured live. A moment too funny not to share right now. This is Snap Mode.

**"Remember how this felt"** — intentional, nostalgic, present. Shooting all day at a concert without checking the results. Discovering your photos at 9 PM with your friends, together, like developing a roll of film. This is Roll Mode.

Most camera apps treat all capture as the same act. Piqd does not. The two modes are not filters or settings — they are different cameras, different aesthetics, different relationships with time.

### 1.3 Strategic Position

Piqd is not competing with Apple Camera on image quality. It is not competing with Instagram on social reach. It is competing for the emotional space between: the moment something happens, and the moment it becomes a memory.

| Competitor | What they own | What Piqd owns |
|------------|--------------|----------------|
| Apple Camera | Raw quality, computational photography | The ritual around capture |
| Snapchat | Ephemeral messaging at scale | Intimate trusted-circle sharing |
| Instagram | Public broadcast, aesthetic curation | Private, unfiltered, present-moment |
| BeReal | Dual capture, authentic moment | Deliberate mode choice, analog identity |
| Lapse | Delayed reveal, disposable aesthetic | Fixed ritual time, dual-mode daily loop, P2P privacy |

### 1.4 Product Bets — v1.1

1. **The mode switch is a deliberate choice, not a setting.** Gen Z will engage with Piqd as a dual-identity object — two cameras, one device. Switching requires intent, not an accidental gesture.
2. **The 9 PM unlock is the product.** The delayed reveal is not a constraint — it is the reason to use Roll Mode. The ritual of opening together is irreplaceable.
3. **Privacy through architecture, not policy.** No user content ever touches a Piqd server. This is a technical commitment, not a promise in a terms of service.
4. **Imperfection is the aesthetic.** Grain, light leaks, motion blur, and "messy" photos are not bugs — they are the brand. Piqd does not try to make every photo look perfect.
5. **Dual-mode is the retention mechanic.** Users who use both Snap and Roll in the same week retain significantly better than single-mode users. Onboarding must introduce both modes and the daily loop from day one.

---

## 2. Target User

### 2.1 Primary User — Gen Z, 16–26

Gen Z's relationship with cameras and social media is defined by three tensions:

- **Performance vs authenticity:** They are exhausted by curated, perfect social media but still want to share. Piqd resolves this by making the imperfect the default.
- **FOMO vs presence:** They want to document experiences without being on their phone during them. Roll Mode resolves this — capture without reviewing.
- **Public broadcast vs intimate sharing:** They are moving away from public feeds toward smaller, trusted circles. Piqd is built for 2–10 people, not 2,000 followers.

### 2.2 User Archetypes

**The Reactor (Snap Mode primary)**
- Age: 16–22. Captures fast, shares faster. Humor, reactions, pranks.
- Pain point: too many taps to share to a specific person. Feels like posting, not sending.
- What Piqd gives them: a shutter that's always hot and a trusted circle that's always one tap away.

**The Experiencer (Roll Mode primary)**
- Age: 18–26. Wants to be present, not on their phone at concerts or travel.
- Pain point: reviewing photos mid-experience kills the vibe.
- What Piqd gives them: shoot without reviewing. The 9 PM reveal becomes the second experience.

**The Nostalgic (both modes)**
- Age: 20–26. Values analog aesthetics — grain, unexpected exposures, happy accidents.
- Pain point: too much AI cleanup.
- What Piqd gives them: grain baked in, AI enhancement off by default, motion blur embraced.

### 2.3 Out of Scope Users

- Professional photographers
- Users wanting public broadcast or follower-based social
- Users wanting video-first content creation

---

## 3. Core Product Principles

### P1 — Speed is respect
In Snap Mode, any lag over 100ms at the shutter is a product failure.

### P2 — The mode is the message
Switching between Snap and Roll must feel physical — like picking up a different camera. Never like changing a setting.

### P3 — Imperfection is the product
Grain, light leaks, motion blur, and "messy" photos are stylistically correct. AI enhancement is off by default.

### P4 — The ritual matters more than the algorithm
The 9 PM unlock ritual is more valuable than any AI curation. StoryEngine curates, but the ritual is the reason users come back.

### P5 — Privacy by architecture
No user photo, video, or personal content ever touches a Piqd server. Technical constraint, not marketing claim.

### P6 — Intimacy over scale
Piqd is built for 2–10 people. No public feed, no follower count, no like count, no public profile.

### P7 — Scarcity creates intention
The 24-shot Roll limit is a design decision, not a technical constraint. Fewer shots = more considered captures.

---

## 4. Feature: Mode System

### 4.1 Overview

Piqd has exactly two capture modes. The mode system is the central product mechanic.

### 4.2 Mode Switch

Piqd has exactly two modes — two distinct cameras. Switching between them is a deliberate, conscious act, not an accidental gesture. The mode switch mechanism reflects this: it requires sustained intent to trigger and explicit confirmation before executing.

**Requirements:**
- FR-MODE-01: Mode switch triggered by long-hold (1.5 seconds) on the mode indicator pill. The pill is the only mode switch trigger. There is no swipe gesture for mode switching. Note: the mode pill long-hold is a distinct gesture from Layer 1 chrome — it activates in Layer 0 (no tap required first) and is differentiated from the gear icon access by duration (1.5s vs any shorter interaction).
- FR-MODE-02: During the 1.5s hold, a circular progress arc animates around the pill border, giving clear feedback that a switch is pending. The user can abort by releasing before the arc completes.
- FR-MODE-03: On arc completion, a confirmation sheet slides up from the bottom. Sheet content: target mode name (e.g. "Switch to Roll?"), target mode aperture symbol, a primary CTA ("Switch", styled in the target mode's accent color), and a secondary dismiss action ("Stay in [current mode]"). Tapping outside the sheet also dismisses.
- FR-MODE-04: Transition animation executes only after the user confirms via the sheet CTA. Animation completes within 150ms of confirmation tap.
- FR-MODE-05: Full viewfinder aesthetic changes on confirmed switch: grain fades in (Roll) or out (Snap), UI chrome updates, shutter sound changes, shutter button morphs between styles.
- FR-MODE-06: Mode switch is reversible at any time. Switching back to Roll mid-day does not clear in-progress Roll assets.
- FR-MODE-07: Mode indicator pill always visible at Layer 0 — single aperture symbol per mode (open aperture = Snap in signal yellow; stopped-down aperture = Roll in darkroom amber). No text labels on the pill.
- FR-MODE-08: App opens in the last-used mode on cold launch.
- FR-MODE-09: Mode switch is disabled during active Sequence capture (3-second window), active Clip/Dual recording, and during the Roll unlock sequence.

**Acceptance criteria:**
- [ ] Short tap on mode pill: no action (not a switch trigger)
- [ ] Hold <1.5s then release: arc aborts, no sheet, no switch
- [ ] Hold 1.5s: confirmation sheet appears
- [ ] Confirm: mode switches, transition completes within 150ms
- [ ] Dismiss/cancel: returns to viewfinder, no mode change
- [ ] Shutter sound changes audibly between modes
- [ ] Mode persists across app backgrounding and cold launch
- [ ] In-progress Roll assets unaffected by mid-day mode switch
- [ ] Mode switch pill disabled during Sequence capture, recording, and unlock

### 4.3 Mode Distinction Summary

| Attribute | Snap Mode | Roll Mode |
|-----------|-----------|-----------|
| Primary emotion | Reactive, social | Nostalgic, present |
| Viewfinder | Clean, no grain | Grain + light leak overlay |
| Shutter sound | Sharp, modern click | Soft, analog shutter click (±3% pitch variation) |
| Formats | Still, Sequence, Clip, Dual | Still, Live Photo, Moving Still (v2.0) |
| Default format | Still | Still |
| Shot limit | None | 24 stills per day |
| Review | Immediate | Locked until 9 PM or 24h |
| Sharing | Ephemeral P2P, instant | iCloud E2EE, 9 PM ritual |
| Film simulation | Off | On — pre-shutter and baked into output |
| Subject guidance | On (disableable) | Off |
| Vibe hint | On (disableable) | Off |
| Night behavior | Standard | Auto-routes, grain applied on top |
| Aspect ratio default | 9:16 | 4:3 |

---

## 5. Feature: Snap Mode

### 5.1 Overview

Snap Mode is for reactive, in-the-moment capture and immediate sharing to a trusted circle. The defining characteristic is speed — capture to send must feel instant. **Snap Mode has no shot limit of any kind.** There is no daily, weekly, or session cap on any Snap Mode format.

### 5.2 Capture Formats

Snap Mode has four formats selectable via the format selector pill above the shutter button. The format selector cycles: **Still → Sequence → Clip → Dual.** The selected format persists across sessions.

#### 5.2.1 Still Photos (Primary Format — NEW in v1.1)

**User story:** As a Snap Mode user, I want to take a single still photo that I can immediately send to friends.

**Requirements:**
- FR-SNAP-STILL-01: A single tap on the shutter captures a still photo when Still is the selected format.
- FR-SNAP-STILL-02: The still is immediately available for sharing. No lock, no delay.
- FR-SNAP-STILL-03: No film simulation applied. No grain. Clean digital output.
- FR-SNAP-STILL-04: The still is governed by EphemeralPolicy.snap — expires on first view or 24h ceiling.
- FR-SNAP-STILL-05: If not immediately sent, the still enters the drafts tray (see §5.5). It is not added to the Film Archive.
- FR-SNAP-STILL-06: Still is the default format on first launch and on format reset. It is the most familiar and least friction format for new users.

**Acceptance criteria:**
- [ ] Tap captures still in ≤100ms
- [ ] Still immediately shareable via circle selector
- [ ] No grain or film simulation applied
- [ ] Still enters drafts tray if not sent immediately

#### 5.2.2 Sequence

**User story:** As a Snap Mode user, I want to capture 6 frames over 3 seconds with a single tap so that I can share a micro-story of a fast-moving moment.

**Requirements:**
- FR-SNAP-SEQ-01: A single tap on the shutter triggers the Sequence when Sequence is the selected format.
- FR-SNAP-SEQ-02: Exactly 6 frames captured at 333ms intervals (3-second total window, tap-to-start).
- FR-SNAP-SEQ-03: Visual feedback per frame: brief viewfinder flash (40ms) + haptic pulse + frame counter "1…6".
- FR-SNAP-SEQ-04: Safe Render zone — a subtle 9:16 crop indicator (1pt border, 15% opacity) appears during the 3-second capture window. Navigation chrome dissolves when CMMotionManager detects motion >2°/s. Disappears on sequence completion.
- FR-SNAP-SEQ-05: Sequence always captures and assembles in 9:16 aspect ratio regardless of the user's selected aspect ratio setting.
- FR-SNAP-SEQ-06: StoryEngine assembles 6 frames into a looping MP4 within 2 seconds of final frame capture.
- FR-SNAP-SEQ-07: Share button disabled (shareReady = false) until assembly completes. A thin animated arc around the send button indicates assembly progress.
- FR-SNAP-SEQ-08: Assembled MP4 presented as floating strip preview (28% of safe area height) at bottom of viewfinder. Preview auto-loops silently. Auto-dismisses after 8 seconds if no action.
- FR-SNAP-SEQ-09: Raw HEIF frames stored in local vault but never transmitted. Only assembled MP4 is shared (~1–2MB).
- FR-SNAP-SEQ-10: Interrupted sequence (app backgrounded, call received before 6 frames) discarded silently.

**Acceptance criteria:**
- [ ] Single tap triggers full 6-frame sequence
- [ ] Frame intervals 333ms ±20ms
- [ ] Assembly completes within 2 seconds on iPhone 15 Pro
- [ ] Share button disabled until shareReady = true
- [ ] Assembled MP4 loops in preview
- [ ] Sequence aspect ratio always 9:16
- [ ] Incomplete sequences do not appear in vault or preview

#### 5.2.3 Video Clips

**Requirements:**
- FR-SNAP-CLIP-01: Hold shutter to record. Release to stop.
- FR-SNAP-CLIP-02: Maximum duration user-selectable: 5s / 10s / 15s. Default 10s.
- FR-SNAP-CLIP-03: Duration arc fills clockwise around shutter ring during recording.
- FR-SNAP-CLIP-04: Recording auto-stops at selected ceiling.
- FR-SNAP-CLIP-05: Quality up to 4K/60fps. 120fps gated to iPhone 15 Pro+ via ClipQualityConfig.proOnlyHighFPS.
- FR-SNAP-CLIP-06: Clip shareable within 1 second of recording stop. No processing delay.
- FR-SNAP-CLIP-07: Shutter button visual: red ring + square inside (universal video record convention).

**Acceptance criteria:**
- [ ] Hold-to-record begins within 50ms
- [ ] Auto-stops at configured ceiling
- [ ] 120fps absent from UI on non-Pro devices
- [ ] Shareable within 1 second of stop

#### 5.2.4 Dual Capture

**Requirements:**
- FR-SNAP-DUAL-01: Simultaneously records front and rear cameras via AVCaptureMultiCamSession.
- FR-SNAP-DUAL-02: Output: composite MP4, picture-in-picture (rear primary, front inset). Layout not user-configurable in v1.0.
- FR-SNAP-DUAL-03: Available on all iPhone 15+ models.
- FR-SNAP-DUAL-04: Activated by selecting Dual in the format selector. Flip button hidden when Dual is active.
- FR-SNAP-DUAL-05: Maximum duration 15 seconds.
- FR-SNAP-DUAL-06: Composite clip shareable within 1 second of stop.
- FR-SNAP-DUAL-07: Shutter button visual: red ring + split diagonal circle (communicates dual-camera nature).

### 5.3 Format Selector

- FR-SNAP-FORMAT-01: Format selector pill appears above the shutter button on Layer 2 invocation (swipe-up gesture on shutter or long-press on shutter).
- FR-SNAP-FORMAT-02: Four segments: [Still] [Sequence] [Clip] [Dual]. Active segment highlighted in signal yellow (#F5C420).
- FR-SNAP-FORMAT-03: Format switch is instant — 80ms shutter button morph, no transition animation.
- FR-SNAP-FORMAT-04: Format selector collapses 150ms after selection. 3-second idle auto-collapse.
- FR-SNAP-FORMAT-05: Selected format persists across sessions.

### 5.4 Snap Mode Viewfinder and Controls

#### Layered Chrome System

Snap Mode uses a three-layer chrome system. At rest (Layer 0), only essential persistent elements are visible. Secondary and tertiary chrome appear on demand and retreat automatically.

**Layer 0 — always visible (rest state):**
- Shutter button (shape and color encode the selected format)
- Mode indicator pill (center bottom, open aperture symbol in signal yellow)

**Layer 1 — single tap on viewfinder, auto-retreats after 3 seconds idle:**
- Zoom pill (0.5× · 1× · 2×) — see FR-SNAP-ZOOM
- Aspect ratio indicator — see FR-SNAP-RATIO
- Flip button (front/rear camera switch)
- Unsent badge (shows count of items in drafts tray, if any)
- Invisible level indicator (if device tilted >±3°)

**Layer 2 — format selector gesture, collapses on selection:**
- Format selector pill (Still · Sequence · Clip · Dual)

#### Zoom (NEW in v1.1)

- FR-SNAP-ZOOM-01: Three zoom levels supported: 0.5× (ultra-wide), 1× (main), 2× (telephoto). All are hardware-optical on iPhone 15+. No 1.5× — digital crop with no optical benefit.
- FR-SNAP-ZOOM-02: Zoom pill in Layer 1. Tap a level to jump. Active level highlighted in signal yellow.
- FR-SNAP-ZOOM-03: Pinch anywhere on viewfinder for continuous zoom between 0.5× and 2×. Haptic click at each optical transition boundary.
- FR-SNAP-ZOOM-04: On front camera flip: zoom pill shows only 1× (front camera is fixed focal length). Pinch still works as digital crop, capped at 2×.
- FR-SNAP-ZOOM-05: During Sequence capture (3-second window): zoom level locked at moment of tap. Pinch gesture ignored during sequence.

#### Aspect Ratio (NEW in v1.1)

- FR-SNAP-RATIO-01: Two aspect ratios in Snap Mode: 9:16 (default) and 1:1 (optional). No 16:9 or 4:3 in Snap.
- FR-SNAP-RATIO-02: Aspect ratio indicator sits in Layer 1 beside the zoom pill. Tap to cycle between 9:16 and 1:1.
- FR-SNAP-RATIO-03: Selected ratio persists across sessions independently per mode.
- FR-SNAP-RATIO-04: Sequence format always 9:16 regardless of selected ratio. When Sequence is the active format, ratio indicator shows "9:16" and is non-interactive (50% opacity).

#### Camera Flip (NEW in v1.1)

- FR-SNAP-FLIP-01: Flip button in Layer 1 (top-right safe area). Switches between front and rear camera.
- FR-SNAP-FLIP-02: Flip animates with a horizontal 3D flip of the viewfinder (200ms).
- FR-SNAP-FLIP-03: Zoom resets to 1× on flip.
- FR-SNAP-FLIP-04: Flip button hidden (not just disabled) when Dual Capture is the selected format — Dual uses both cameras simultaneously.
- FR-SNAP-FLIP-05: Available in all formats except Dual.

#### Shutter Button Visual Language (NEW in v1.1)

The shutter button communicates format through both color and shape. Color encodes video vs photo. Shape encodes the specific format.

| Format | Color | Shape |
|--------|-------|-------|
| Still | White ring | Clean thin circle, no fill |
| Sequence (idle) | White ring | Clean thin circle + subtle signal yellow accent ring on active |
| Sequence (firing) | Signal yellow ring | Yellow fill, pulses per frame |
| Clip (idle, selected) | Red ring | Red outer ring + square inside |
| Clip (recording) | Red ring + arc | Inner square shrinks; arc fills clockwise |
| Dual (idle, selected) | Red ring | Red outer ring + split diagonal circle |
| Dual (recording) | Red ring + arc | As Clip recording |

- FR-SNAP-SHUTTER-01: Shutter button color changes within 80ms of format selection. Morph animation (inner shape transforms, outer ring color transitions).
- FR-SNAP-SHUTTER-02: Red is always used for any video-recording format (Clip, Dual). This is a universal learned convention — Gen Z expects it.
- FR-SNAP-SHUTTER-03: Pressed state: 0.92× scale transform + haptic pulse (80ms).
- FR-SNAP-SHUTTER-04: Minimum touch target: 72pt × 72pt. Non-negotiable.

#### No Thumbnail

- FR-SNAP-NO-THUMB-01: No thumbnail element in the Snap Mode viewfinder. There is no bottom-left preview of the last captured asset.
- FR-SNAP-NO-THUMB-02: Post-capture confirmation is delivered through shutter button animation only: a brief checkmark pulse (delivered) or arrow pulse (queued).
- FR-SNAP-NO-THUMB-03: Film Archive accessed via swipe-up on viewfinder, not via thumbnail.

### 5.5 Drafts Tray (NEW in v1.1)

**User story:** As a Snap Mode user, I want to capture photos or sequences and send them later — within the same day — without them disappearing or cluttering my Photo Library.

**What it is:** A temporary holding area for Snap Mode assets that have been captured but not yet sent. Each item has a 24-hour expiry timer. The tray is local, encrypted, never synced to iCloud.

**Requirements:**
- FR-SNAP-DRAFT-01: All Snap Mode assets not immediately sent enter the drafts tray automatically.
- FR-SNAP-DRAFT-02: Each tray item has a 24-hour expiry timer starting from capture time. On expiry: silently purged from vault. No recovery.
- FR-SNAP-DRAFT-03: Tray accessible from viewfinder Layer 1 via the unsent badge. Badge shows item count. Tapping opens the tray as a bottom sheet.
- FR-SNAP-DRAFT-04: Tray sheet rows (72pt height each):
  - Still: static thumbnail
  - Sequence: 6-frame contact-sheet thumbnail, auto-plays silently as looping MP4
  - Clip/Dual: static thumbnail with play button overlay; tap to play inline with audio (does not auto-play)
  - Each row: asset type label, timer, text-link "save" and "send →" actions (no full buttons)
- FR-SNAP-DRAFT-05: Timer display:
  - >3 hours remaining: no timer shown (no urgency)
  - 1–3 hours: "[Xh Ym] left" in secondary label color
  - <1 hour: "[Xm] left" in amber (#C97B2A)
  - <15 minutes: "[Xm] left" in red (#E5372A); "send →" text shifts to red
- FR-SNAP-DRAFT-06: "save" exports the asset to iOS Photo Library. Asset remains in tray after save — it can still be sent.
- FR-SNAP-DRAFT-07: "send →" opens the circle selector for that asset.
- FR-SNAP-DRAFT-08: No delete button. Expiry handles cleanup. The user's only actions are send or save.
- FR-SNAP-DRAFT-09: Tray is never synced to iCloud. Local only. If app uninstalls or crashes, tray items are gone.
- FR-SNAP-DRAFT-10: Tray is Snap Mode only. Roll Mode has no drafts concept — assets go directly to the locked Roll vault.

**Acceptance criteria:**
- [ ] Unsent assets appear in tray immediately after capture
- [ ] Timer accurate to ±60 seconds
- [ ] Timer color shifts at <1h and <15min thresholds
- [ ] Assets purged from vault at 24h with no user action
- [ ] Sequence strips auto-play silently in tray
- [ ] Clips/Dual do not auto-play audio in tray

---

## 6. Feature: Roll Mode

### 6.1 Overview

Roll Mode is for intentional, present-moment capture without immediate review. The user shoots throughout the day. At 9 PM (or 24 hours after first capture, whichever is first), the Roll unlocks and is shared with the trusted circle. The delayed reveal is not a limitation — it is the product.

### 6.2 Capture Formats

Roll Mode has two formats selectable by edge swipe on the left 20% of the viewfinder.

#### 6.2.1 Still Photos (Primary Format)

**Requirements:**
- FR-ROLL-STILL-01: Single tap captures a still. Immediately added to locked Roll. Not viewable until unlock.
- FR-ROLL-STILL-02: Film simulation preset (kodakWarm, fujiCool, ilfordMono) applied pre-shutter and baked into output HEIF.
- FR-ROLL-STILL-03: Maximum 24 stills per calendar day. Counter decrements on each capture.
- FR-ROLL-STILL-04: At counter=0: shutter visually disabled, "Roll's full. See you at 9." message appears persistently.
- FR-ROLL-STILL-05: OIS not applied. Motion blur is stylistically correct. Not corrected.
- FR-ROLL-STILL-06: Night Mode activates automatically from AmbientMetadata. Grain applied on top of Night Mode output.

#### 6.2.2 Apple Live Photos

**Requirements:**
- FR-ROLL-LIVE-01 through FR-ROLL-LIVE-06: unchanged from v1.0.

#### 6.2.3 Hybrid Moving Stills (v2.0)

Unchanged from v1.0. Deferred to v2.0.

### 6.3 Roll Mode Viewfinder — Ghost Preview

Unchanged from v1.0.

**Additional requirement (v1.1):**
- FR-ROLL-VF-08: Roll Mode aspect ratio default is 4:3 (natural iPhone sensor ratio, more photographic, less social-media-native). Optional: 1:1. No 9:16 in Roll Mode — Roll Mode photos are not optimized for Stories sharing.

### 6.4 Film Counter

Unchanged from v1.0.

### 6.5 The 9 PM Unlock Ritual

Unchanged from v1.0.

---

## 7. Feature: Pre-Shutter System

### 7.1 Zero-Lag Shutter

Unchanged from v1.0.

### 7.2 Invisible Level

Unchanged from v1.0.

### 7.3 Subject Guidance

Unchanged from v1.0. Snap Mode only.

### 7.4 Backlight Correction

Unchanged from v1.0.

### 7.5 Vibe Hint

Unchanged from v1.0. Snap Mode only, 2fps classifier.

---

## 8. Feature: Sharing

### 8.1 Overview

Piqd sharing is always private, always directed at specific people, and never touches a Piqd server for content. Snap Mode sharing is ephemeral and instant. Roll Mode sharing is persistent and ritual.

### 8.2 Snap Mode Sharing — Sender

Unchanged from v1.0 (FR-SHARE-SNAP-01 through FR-SHARE-SNAP-09).

### 8.3 Receiver Experience (NEW in v1.1)

**User story:** As a Snap Mode recipient, I want to receive, view, respond to, and have shared assets automatically disappear — with no configuration on my part.

#### 8.3.1 Notification

- FR-SHARE-RECV-01: APNs notification on receipt. Content: sender first name + "sent you something" / "Tap to open before it's gone." No photo content in notification payload.
- FR-SHARE-RECV-02: Notification vibration only by default. No sound. User can enable sound in Settings.
- FR-SHARE-RECV-03: Two notification actions: "open" (deep-links to asset view) and "later" (dismisses to inbox).
- FR-SHARE-RECV-04: Roll Mode notification is different in tone: "[Name]'s Piqd from today is ready." / "Open it with your circle." No urgency language.

#### 8.3.2 Inbox

- FR-SHARE-RECV-05: Inbox accessible from viewfinder Layer 1 via the gear icon (⚙) that appears alongside Layer 1 chrome → tapping gear reveals a menu with "Inbox" and "Settings" options. Also accessible via notification deep-link from any screen.
- FR-SHARE-RECV-06: Inbox rows show: sender name, asset type only (no content preview), unread dot (not a count badge), timestamp. Timer appears in place of timestamp when <3 hours remaining.
- FR-SHARE-RECV-07: Tapping a row opens the asset view. This is the irreversible view trigger — viewed flag fires on screen appear.

#### 8.3.3 Asset View

- FR-SHARE-RECV-08: Asset fills full screen. Minimal chrome: sender name (center), "← inbox" (left), "viewing now" (right muted label).
- FR-SHARE-RECV-09: Still: static full-screen. Sequence: silent looping MP4, full-screen. Clip: plays with audio, full-screen. Dual: composite MP4, full-screen.
- FR-SHARE-RECV-10: Four quick reaction chips: [haha] [love] [wow] [fire]. Tap fires reaction as APNs text notification back to sender.
- FR-SHARE-RECV-11: Short free-text reply field below chips. Reply sends as APNs text notification to sender. Short-form only — no multi-line input, no media attachments.
- FR-SHARE-RECV-12: Screenshot detection: recipient sees no change. Sender receives APNs notification: "[Name] screenshotted your Snap." Piqd does not block screenshots.

#### 8.3.4 Purge Lifecycle

- FR-SHARE-RECV-13: Recipient copy deleted when the view session closes (app backgrounded or navigating away). Not mid-view — user can look as long as they want.
- FR-SHARE-RECV-14: Sender receives "viewed" confirmation APNs immediately on view trigger.
- FR-SHARE-RECV-15: Sender copy purged within 5 minutes of viewed confirmation. Response thread cleared simultaneously.
- FR-SHARE-RECV-16: Hard ceiling: if recipient never opens, both copies purged 24 hours after send time. Sender receives "expired unviewed" APNs. Recipient gets no notification — item disappears from inbox silently.
- FR-SHARE-RECV-17: Purged state on recipient side: "Piqd has left the chat." — shown if user navigates back to a purged item.

#### 8.3.5 Response Thread

- FR-SHARE-RECV-18: Sender can reply to a reaction or text reply — one level only. Not a full chat thread. Maximum two exchanges, then thread closes.
- FR-SHARE-RECV-19: Response thread cleared when sender copy is purged. No orphaned conversations.
- FR-SHARE-RECV-20: Piqd is not a messaging app. The response layer exists to close the loop on a shared moment, not to start a conversation.

### 8.4 Social Sharing and Photo Library Export (NEW in v1.1)

**User story:** As a Piqd user, I want to share assets to Instagram, iMessage, or my Photos library when I choose to — without it being the default behavior.

**Requirements:**
- FR-SHARE-SOCIAL-01: Post-capture (Snap) and post-unlock (Roll), a secondary "Share elsewhere" action opens the iOS standard share sheet. This is a secondary action — visually subordinate to the Piqd circle send. Piqd does not push to social directly — it hands off to iOS.
- FR-SHARE-SOCIAL-02: In Snap Mode, "Save to Photos" is an opt-in option at time of send (toggle on the circle selector sheet). Off by default. If saved, the vault copy is still purged after delivery per normal lifecycle.
- FR-SHARE-SOCIAL-03: In Roll Mode, individual assets can be shared via the iOS share sheet from the Film Archive Moment view post-unlock.
- FR-SHARE-SOCIAL-04: A "Save all to Photos" batch action is available on the full Roll in the Moment view post-unlock. Exports all assets to iOS Photo Library.
- FR-SHARE-SOCIAL-05: Sharing to social is available only after the Roll unlocks. The user cannot share a Roll photo to Instagram before the group reveal. This preserves the ritual.
- FR-SHARE-SOCIAL-06: No Piqd-specific social integrations. No direct-to-Instagram, direct-to-TikTok, or platform-specific formatting. All social sharing goes through the standard iOS share sheet.

### 8.5 Storage Lifecycle (NEW in v1.1)

**Requirements:**
- FR-STORAGE-01: All captured assets are written to the local encrypted vault (AES-256-GCM) immediately on capture.
- FR-STORAGE-02: Snap Mode assets delivered and confirmed: auto-purged from vault within 24 hours of delivery confirmation. If never sent: remains in vault until manually cleared via Settings or Smart Archive compression.
- FR-STORAGE-03: Roll Mode assets: remain in locked vault until 9 PM unlock. After unlock and StoryEngine assembly: move to Film Archive (permanent local encrypted storage). Vault copy replaced by Film Archive entry.
- FR-STORAGE-04: Film Archive is permanent local storage. Assets do not expire. User must manually delete from Piqd or export to Photos.
- FR-STORAGE-05: Film Archive does not sync to iCloud in v1.0. If the user loses their device and reinstalls Piqd, the Film Archive is gone unless they exported to Photos. This is communicated clearly in onboarding and after every Roll unlock.
- FR-STORAGE-06: iCloud in Piqd v1.0 is used for two purposes only: (a) RollPackage delivery (encrypted, temporary, deleted after recipient acknowledgment); (b) assets the user explicitly exports to Photos (synced per user's own iCloud Photos settings — Piqd has no control over this).
- FR-STORAGE-07: Location data (GPS coordinates) is captured into AmbientMetadata at shoot time. Used for Moment labeling only. Stays on-device. Never transmitted to Piqd servers.
- FR-STORAGE-08: Onboarding warning shown before first Roll Mode capture: "Roll Mode photos live in Piqd only — export to Photos to keep them forever." Dismissible but not skippable on first Roll.
- FR-STORAGE-09: Film Archive iCloud encrypted backup (Option A, full E2EE vault sync) is deferred to v2.0. See §11 Open Items.

### 8.6 Roll Mode Sharing — iCloud Package

Unchanged from v1.0 (FR-SHARE-ROLL-01 through FR-SHARE-ROLL-08).

---

## 9. Feature: Trusted Circle

Unchanged from v1.0.

**Additional requirement (v1.1):**
- FR-CIRCLE-08: The rollCircle for each Roll is set at first capture of that day and is immutable. Adding a friend mid-day does not add them to the current day's Roll — only to future Rolls.

---

## 10. Feature: Film Archive

Unchanged from v1.0.

**Additional requirements (v1.1):**
- FR-ARCHIVE-10: "Save all to Photos" batch export available on any Moment view. Exports all assets in that Moment to iOS Photos library.
- FR-ARCHIVE-11: Live Photos can be exported as Boomerang-style looping MP4 from the Film Archive via the iOS share sheet.
- FR-ARCHIVE-12: Film Archive displays ambient metadata detail per Moment where available: day of week, weather condition, temperature, Now Playing track. Fields that have no data are not shown — no "Unknown" placeholders.

---

## 11. Out of Scope — v1.0

| Feature | Reason | Target |
|---------|--------|--------|
| Moving Still conversion | Processing complexity | v2.0 |
| Ring buffer / pre-capture | Memory and complexity | v2.0 |
| Film Archive iCloud encrypted backup | Sync conflict complexity | v2.0 |
| Dual Capture in Roll Mode | Roll Mode is stills-primary | Not planned |
| Cinematic Mode | Apple Camera does this better. Piqd's "cinematic" is the ritual. | Not planned |
| Spatial photos / Video | Low Gen Z demand currently | v3.0+ |
| Public feed or follower system | Conflicts with P6 | Never |
| Video in Roll Mode | Roll Mode is stills-primary | Not planned |
| Group video chat | Out of scope | Never |
| AI caption generation | NudgeEngine out of scope | v2.0 |
| Community feed | Conflicts with P6 | Never |
| Web app | iOS only | Not planned |
| Android | iOS only | Not planned |
| 1.5× zoom | Digital crop, no optical benefit over pinch | Not planned |
| 16:9 or 4:3 aspect ratio in Snap | Gen Z shoots 9:16 for social, 1:1 for feed | Not planned |

**Open items for v2.0:**

| # | Item | Notes |
|---|------|-------|
| 1 | Film Archive iCloud encrypted backup | Option A — full E2EE vault sync to private iCloud container. Restore Film Archive on reinstall. StorageConfig.iCloudSyncEnabled flag already in AppConfig — set true in v2.0. |
| 2 | Moving Still conversion | VNGenerateForegroundInstanceMask + Metal shader. Assemble at unlock time. |
| 3 | Ring buffer zero-lag | AVCaptureVideoDataOutput + CMSampleBuffer queue. Gated to iPhone 15 Pro+ via FeatureSet.ringBuffer. |
| 4 | Configurable unlock time | Options: 6 PM / 9 PM / midnight. Per-user setting. |
| 5 | AI caption / NudgeEngine | Text-only Enhanced AI. No visual content transmitted. |

---

## 12. Success Metrics

### 12.1 Acquisition

| Metric | v1.0 Target (90 days post-launch) |
|--------|----------------------------------|
| Total installs | 10,000 |
| Organic install rate | ≥60% |
| Invite conversion rate | ≥40% |

### 12.2 Engagement

| Metric | Target |
|--------|--------|
| D1 retention | ≥40% |
| D7 retention | ≥20% |
| D30 retention | ≥12% |
| Daily Roll completion rate | ≥50% |
| Daily unlock engagement (opens within 30min of 9PM notification) | ≥60% |
| Snap Mode sends per active user per day | ≥3 |
| Average circle size at D30 | ≥3 friends |
| **Dual-mode users at D30 (NEW)** | **≥35%** — users who used both Snap and Roll in the same week. Tracked as a separate retention cohort. Hypothesis: dual-mode users show significantly higher D30 retention than single-mode users. This validates the two-mode architecture and informs onboarding investment. |

### 12.3 Quality

| Metric | Target |
|--------|--------|
| Shutter response time (p95) | <100ms |
| Sequence assembly time (p95) | <2 seconds |
| Roll iCloud upload success rate | ≥98% |
| Crash-free session rate | ≥99.5% |
| App Store rating | ≥4.5 |

### 12.4 Privacy

| Metric | Target |
|--------|--------|
| Piqd server content requests | 0 (architectural guarantee) |
| User privacy-related support tickets | <0.5% of DAU |

---

## 13. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| iCloud upload fails at 9 PM (no connectivity) | Medium | High | Retry logic, 5-min intervals, 2-hour window. Local notification on failure. |
| Sender offline at recipient retrieval (Snap) | Medium | Low — ephemeral content | APNs ping informs recipient. 24h expiry communicated. |
| Curve25519 key loss on reinstall | Low | Medium | Friends list cleared on reinstall. Re-invite required. Clear onboarding communication. |
| WebRTC NAT traversal failure >20% | Low | Medium | TURN fallback. Content still delivered, slightly slower. Monitor TURN usage. |
| 24-shot Roll limit too restrictive | Medium | Medium | Monitor. If ≥30% hit limit before 9PM and churn: increase to 36 or add one-time daily top-up. |
| Mode switch discoverability (long-hold pill) | Low | Medium | Onboarding screen explicitly teaches the long-hold gesture. First-time hint appears on pill after 3 sessions if mode has never been switched. |
| 9 PM unlock time wrong for user timezone / lifestyle | Medium | Medium | Configurable unlock time (6PM / 9PM / midnight) in v2.0. |
| Grain overlay drops viewfinder frame rate | Low | High | CIFilter performance testing on iPhone 15 (minimum device). Target 30fps minimum. |
| Film Archive lost on reinstall (no iCloud backup in v1.0) | Medium | Medium | Strong onboarding warning. Export to Photos prompt after every Roll unlock. iCloud backup in v2.0. |
| Single-mode user churn (uses only Snap or only Roll) | Medium | Medium | Track dual-mode cohort from day one. If dual-mode users retain better, invest in cross-mode discovery features in v1.1. |
| Lapse-style failure: becoming a social platform | Low | High | Never add public feed, public profiles, or Featured pages. P6 is a permanent principle. |

---

## 14. Acceptance Criteria — Full Feature Set

### 14.1 Mode System
- [ ] Short tap on mode pill: no action
- [ ] Long-hold 1.5s: confirmation sheet appears
- [ ] Confirm: mode switches within 150ms
- [ ] Abort before arc completes: no switch
- [ ] Snap viewfinder: clean, no grain. Roll viewfinder: drifting grain visible
- [ ] Mode persists across cold launch and backgrounding
- [ ] In-progress Roll assets unaffected by mode switch

### 14.2 Snap Mode — Capture
- [ ] Still captures in ≤100ms on single tap (Still format selected)
- [ ] Format selector cycles Still → Sequence → Clip → Dual
- [ ] Single tap triggers full 6-frame Sequence (333ms ±20ms)
- [ ] Sequence always captures and assembles in 9:16
- [ ] Sequence MP4 assembles within 2 seconds on iPhone 15 Pro
- [ ] Share button disabled until shareReady = true
- [ ] Hold-to-record begins within 50ms (Clip format)
- [ ] Clip auto-stops at configured ceiling
- [ ] 120fps absent from UI on non-Pro devices
- [ ] Dual Capture: synchronized composite within 1 frame
- [ ] Shutter button white for Still/Sequence, red for Clip/Dual
- [ ] Shutter button shape morphs within 80ms of format change
- [ ] Snap Mode: no shot limit enforced at any level
- [ ] Safe Render zone appears during Sequence window and dismisses on completion

### 14.3 Snap Mode — Viewfinder Controls
- [ ] Layer 0 (rest): shutter + mode pill only
- [ ] Layer 1 (single tap): zoom pill, ratio indicator, flip button, unsent badge appear within 220ms
- [ ] Layer 1 auto-retreats after 3 seconds idle
- [ ] Zoom pill: 0.5× / 1× / 2× tap-to-jump functional
- [ ] Pinch zoom: continuous, haptic at 0.5×, 1×, 2× boundaries
- [ ] Zoom locks during Sequence capture window
- [ ] Flip animates 200ms. Zoom resets to 1× on flip
- [ ] Flip button hidden when Dual is selected format
- [ ] Aspect ratio cycles 9:16 ↔ 1:1 on tap. Persists per mode.

### 14.4 Drafts Tray
- [ ] Unsent assets enter tray immediately after capture
- [ ] Tray badge count accurate and visible in Layer 1
- [ ] Sequence auto-plays silently in tray
- [ ] Clips do not auto-play audio in tray
- [ ] Timer shifts to amber at <1h, red at <15min
- [ ] Assets purged at 24h automatically
- [ ] "save" exports to Photos, asset remains in tray
- [ ] "send →" opens circle selector

### 14.5 Roll Mode
- [ ] Captured assets immediately hidden, not visible pre-unlock
- [ ] Film simulation matches viewfinder preview to output
- [ ] Film counter decrements correctly; shutter disables at 0
- [ ] Roll Mode aspect ratio default 4:3, optional 1:1
- [ ] Unlock fires within 60 seconds of 9 PM local time
- [ ] iCloud upload completes before APNs notification fires
- [ ] Empty Roll: no unlock, no notification
- [ ] Roll assets appear in Film Archive post-unlock
- [ ] rollCircle immutable after first capture of the day

### 14.6 Pre-Shutter
- [ ] Shutter response ≤100ms (p95) in Snap Mode
- [ ] Invisible level at >±3° tilt; disappears when level restored
- [ ] Subject guidance: max 1.5s, no repeat within 10s, Snap Mode only
- [ ] Backlight correction viewfinder matches captured output

### 14.7 Sharing — Sender
- [ ] No photo content transmitted to any Piqd server
- [ ] Snap asset inaccessible after first view + 24h ceiling
- [ ] Sender copy purged within 5 minutes of viewed confirmation
- [ ] Roll iCloud package deleted after recipient acknowledgment
- [ ] iOS share sheet accessible as secondary action post-capture (Snap) and post-unlock (Roll)
- [ ] "Save to Photos" opt-in on Snap circle selector (off by default)
- [ ] "Save all to Photos" batch export available on Roll Moment view

### 14.8 Sharing — Receiver
- [ ] APNs payload: no photo content (metadata only)
- [ ] Notification: vibration only by default
- [ ] Inbox shows asset type only, no content preview
- [ ] Unread indicator is a dot, not a count badge
- [ ] Timer appears in inbox when <3h remaining
- [ ] Asset fills full screen on view
- [ ] Sequence auto-plays silent loop in asset view
- [ ] Clip plays with audio, does not auto-play audio in inbox
- [ ] Reaction chips fire APNs text to sender
- [ ] Recipient copy deleted on view session close
- [ ] Hard ceiling: both copies purged 24h from send if never viewed
- [ ] Purged state: "Piqd has left the chat." copy on recipient side

### 14.9 Storage
- [ ] All assets encrypted at rest (AES-256-GCM)
- [ ] Snap delivered assets auto-purged within 24h of confirmation
- [ ] Film Archive is local only — no iCloud sync in v1.0
- [ ] Location data stays on-device, never transmitted
- [ ] Onboarding storage warning shown before first Roll capture

### 14.10 Trusted Circle
- [ ] Friends added only via QR or deep link
- [ ] Maximum 10 friends enforced
- [ ] Key exchange completes at invite time
- [ ] Private key never leaves device (Keychain only)

### 14.11 Film Archive
- [ ] Moments in reverse chronological order
- [ ] Hero asset user-replaceable post-unlock
- [ ] Individual assets exportable to Photos
- [ ] Batch "Save all to Photos" functional
- [ ] Archive has no public visibility option
- [ ] Ambient metadata shown where available, hidden where not

---

*— End of Document — Piqd PRD v1.1 · SRS: piqd_SRS_v1.0.md · UIUX Spec: piqd_UIUX_Spec_v1.0.md · April 2026 —*
