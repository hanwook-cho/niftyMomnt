# Piqd

## Product Requirements Document (PRD)

**Gen Z Camera App · Two Modes · One Emotional Truth**

Version 1.0 | April 2026 | Confidential

SRS reference: piqd_SRS_v1.0.md | Architecture base: niftyMomnt NiftyCore SRS v1.2

Author: Han Wook Cho | hwcho99@gmail.com

---

## Document Control — v1.0

This PRD is the authoritative source for Piqd's functional behavior, user experience requirements, and acceptance criteria. It is written for product, design, and engineering teams. Technical implementation details are in `piqd_SRS_v1.0.md` — this document references the SRS but does not duplicate it.

**Sections:**
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

### 1.4 Product Bets — v1.0

1. **The mode switch is a physical gesture, not a setting.** Gen Z will engage with Piqd as a dual-identity object — a camera that becomes something else when you swipe.
2. **The 9 PM unlock is the product.** The delayed reveal is not a constraint — it is the reason to use Roll Mode. The ritual of opening together is irreplaceable.
3. **Privacy through architecture, not policy.** No user content ever touches a Piqd server. This is a technical commitment, not a promise in a terms of service.
4. **Imperfection is the aesthetic.** Grain, light leaks, motion blur, and "messy" photos are not bugs — they are the brand. Piqd does not try to make every photo look perfect.

---

## 2. Target User

### 2.1 Primary User — Gen Z, 16–26

Gen Z's relationship with cameras and social media is defined by three tensions:

- **Performance vs authenticity:** They are exhausted by curated, perfect social media but still want to share. Piqd resolves this by making the imperfect the default.
- **FOMO vs presence:** They want to document experiences without being on their phone during them. Roll Mode resolves this — capture without reviewing.
- **Public broadcast vs intimate sharing:** They are moving away from public feeds toward smaller, trusted circles. Piqd is built for 2–10 people, not 2,000 followers.

### 2.2 User Archetypes

**The Reactor (Snap Mode primary)**
- Age: 16–22
- Context: urban, socially active, constantly with a friend group
- Behavior: captures fast, shares faster. Humor, reactions, pranks, "you had to be there" moments.
- Pain point with current apps: too many taps to share to a specific person. Feels like posting, not sending.
- What Piqd gives them: a shutter that's always hot and a trusted circle that's always one tap away.

**The Experiencer (Roll Mode primary)**
- Age: 18–26
- Context: concerts, travel, nights out, events
- Behavior: wants to be present, not on their phone. Takes photos but doesn't want to be the person checking them all night.
- Pain point with current apps: reviewing photos mid-experience kills the vibe. But not capturing at all means nothing to show afterward.
- What Piqd gives them: shoot without reviewing. The 9 PM reveal becomes the second experience of the event.

**The Nostalgic (both modes)**
- Age: 20–26
- Context: values analog aesthetics — disposable cameras, film photography, vintage prints
- Behavior: deliberately chooses imperfect over polished. Appreciates grain, unexpected exposures, "happy accidents."
- Pain point with current apps: too much AI cleanup. The imperfect moment gets smoothed away.
- What Piqd gives them: grain baked in, AI enhancement off by default, motion blur embraced not corrected.

### 2.3 Out of Scope Users

- Professional photographers (Piqd is not a pro camera tool)
- Users wanting public broadcast or follower-based social (Piqd has no public feed)
- Users wanting video-first content creation (Piqd is photo-primary with short clips as a supporting format)

---

## 3. Core Product Principles

These principles are the filter for every product decision in Piqd. If a proposed feature conflicts with a principle, the principle wins.

### P1 — Speed is respect

In Snap Mode, any lag over 100ms at the shutter is a product failure. Gen Z will abandon an app that hesitates. The shutter must always be ready. There is no acceptable "loading" state in the viewfinder.

### P2 — The mode is the message

Switching between Snap and Roll must feel physical and deliberate — like picking up a different camera. It must never feel like changing a setting. The UI, aesthetic, sound, and behavior must be entirely distinct between modes.

### P3 — Imperfection is the product

Grain, light leaks, motion blur, and "messy" photos are stylistically correct in Piqd. AI enhancement and cleanup are off by default. The goal is authenticity, not perfection.

### P4 — The ritual matters more than the algorithm

The 9 PM unlock ritual — the shared opening, the group notification, the developing metaphor — is more valuable than any AI curation of photos. StoryEngine curates, but the ritual is the reason users come back.

### P5 — Privacy by architecture

No user photo, video, or personal content ever touches a Piqd server. This is a technical constraint, not a marketing claim. The iCloud encrypted package for Roll Mode delivery uses Apple's E2EE infrastructure — Piqd has no server-side key access.

### P6 — Intimacy over scale

Piqd is built for a trusted circle of 2–10 people. It has no public feed, no follower count, no like count, no public profile. Every sharing interaction is directed at a specific person or group — never broadcast.

### P7 — Scarcity creates intention

The 24-shot Roll limit per day is not a technical constraint — it is a design decision. Fewer shots means each one is more considered. The film counter counting down is part of the Roll Mode identity.

---

## 4. Feature: Mode System

### 4.1 Overview

Piqd has exactly two capture modes: Snap Mode and Roll Mode. The mode system is the central product mechanic. Everything else in the app flows from which mode the user is in.

### 4.2 Mode Switch

**User story:** As a Piqd user, I want to switch between Snap and Roll Mode with a single gesture so that the transition feels like a physical change in what I'm holding, not a settings change.

**Requirements:**

- FR-MODE-01: The mode switch is triggered by a single deliberate horizontal swipe on the viewfinder surface.
- FR-MODE-02: The transition animation must complete within 150ms of gesture recognition.
- FR-MODE-03: The viewfinder aesthetic changes completely on mode switch: grain overlay fades in (Roll) or out (Snap), UI chrome changes, shutter sound changes.
- FR-MODE-04: The mode switch is reversible at any time — switching back to Roll Mode mid-day does not clear in-progress Roll assets.
- FR-MODE-05: The current mode is persistently indicated by a subtle, always-visible mode indicator. The user always knows which mode they are in.
- FR-MODE-06: On cold app launch, the app opens in the mode the user was last using.

**Acceptance criteria:**
- [ ] Mode switch gesture completes in ≤150ms on iPhone 15
- [ ] Grain overlay is visible within 1 frame of Roll Mode activation
- [ ] Shutter sound changes audibly between modes
- [ ] Mode persists across app backgrounding and foreground
- [ ] In-progress Roll assets are not affected by switching to Snap and back

### 4.3 Mode Distinction Summary

| Attribute | Snap Mode | Roll Mode |
|-----------|-----------|-----------|
| Primary emotion | Reactive, social | Nostalgic, present |
| Viewfinder | Clean, no grain | Grain + light leak overlay |
| Shutter sound | Sharp, modern click | Soft, analog shutter sound |
| Formats available | Dual, Clip, Sequence | Still, Live Photo, Moving Still |
| Review | Immediate | Locked until unlock event |
| Sharing | Ephemeral P2P, instant | iCloud encrypted, 9 PM ritual |
| Shot limit | None | 24 stills per day |
| Film simulation | Off | On — pre-shutter and baked |
| Subject guidance | On | Off |
| Night behavior | Standard | Auto-routes to Roll, grain applied |

---

## 5. Feature: Snap Mode

### 5.1 Overview

Snap Mode is for reactive, in-the-moment capture and immediate sharing to a trusted circle. The defining characteristic is speed — at every step from capture to send, the experience must feel instant.

### 5.2 Capture Formats

#### 5.2.1 Sequence (Primary Format)

**User story:** As a Snap Mode user, I want to capture 6 frames over 3 seconds with a single tap so that I can share a micro-story of a fast-moving moment without any manual effort.

**What it is:** A single tap fires 6 frames automatically at 333ms intervals over a 3-second window. The app assembles these frames into a looping short video strip (MP4) and presents it immediately for sharing.

**Requirements:**

- FR-SNAP-SEQ-01: A single tap on the shutter triggers the Sequence. No hold required.
- FR-SNAP-SEQ-02: Exactly 6 frames are captured at 333ms intervals (3-second total window).
- FR-SNAP-SEQ-03: A subtle visual indicator acknowledges each frame capture (a brief flash or frame counter: "1…2…3…4…5…6").
- FR-SNAP-SEQ-04: StoryEngine assembles the 6 frames into a looping MP4 within 2 seconds of the final frame capture.
- FR-SNAP-SEQ-05: The share button is disabled until assembly is complete (shareReady = true).
- FR-SNAP-SEQ-06: The assembled MP4 is presented as a looping preview in a bottom sheet immediately after assembly. The preview auto-loops.
- FR-SNAP-SEQ-07: The bottom sheet auto-dismisses after 8 seconds if no action is taken.
- FR-SNAP-SEQ-08: The raw HEIF frames are stored in the local vault but are never transmitted. Only the assembled MP4 is shared.
- FR-SNAP-SEQ-09: If the Sequence is interrupted (app backgrounded, call received) before all 6 frames are captured, the incomplete sequence is discarded silently.

**Acceptance criteria:**
- [ ] Single tap triggers full 6-frame sequence without additional input
- [ ] Frame intervals are 333ms ± 20ms
- [ ] Assembly completes within 2 seconds on iPhone 15
- [ ] Share button is disabled until shareReady = true
- [ ] Assembled MP4 loops continuously in preview
- [ ] Incomplete sequences do not appear in vault or preview

#### 5.2.2 Video Clips

**User story:** As a Snap Mode user, I want to hold the shutter to record a short video clip so that I can capture moving moments for immediate sharing.

**Requirements:**

- FR-SNAP-CLIP-01: Holding the shutter begins clip recording. Releasing stops recording.
- FR-SNAP-CLIP-02: Maximum clip duration is user-selectable: 5s, 10s, 15s. Default is 10s.
- FR-SNAP-CLIP-03: A duration indicator shows remaining time during recording.
- FR-SNAP-CLIP-04: Recording stops automatically at the selected maximum duration.
- FR-SNAP-CLIP-05: Clip quality is up to 4K/60fps. 120fps is available on iPhone 15 Pro+ only.
- FR-SNAP-CLIP-06: The clip is available for sharing immediately after recording stops. No processing delay.

**Acceptance criteria:**
- [ ] Hold-to-record begins within 50ms of shutter press
- [ ] Recording auto-stops at configured ceiling
- [ ] 120fps option does not appear in UI on non-Pro devices
- [ ] Clip is shareable within 1 second of recording stop

#### 5.2.3 Dual Capture

**User story:** As a Snap Mode user, I want to record from both the front and rear cameras simultaneously so that I can capture my reaction alongside the subject.

**Requirements:**

- FR-SNAP-DUAL-01: Dual Capture records front and rear cameras simultaneously via AVCaptureMultiCamSession.
- FR-SNAP-DUAL-02: Output is a composite MP4 with picture-in-picture layout (rear camera primary, front camera inset). Layout is not user-configurable in v1.0.
- FR-SNAP-DUAL-03: Dual Capture is available on all iPhone 15+ models.
- FR-SNAP-DUAL-04: Dual Capture is activated by a dedicated button in the Snap Mode viewfinder — it does not replace the default single-camera capture.
- FR-SNAP-DUAL-05: Maximum Dual Capture duration is 15 seconds. Not user-configurable in v1.0.
- FR-SNAP-DUAL-06: The composite clip is available for sharing immediately after recording stops.

**Acceptance criteria:**
- [ ] Both camera feeds are synchronized within 1 frame
- [ ] Composite MP4 is shareable within 1 second of stop
- [ ] Dual Capture button is not visible on unsupported devices (none expected on iPhone 15+)

### 5.3 Shutter Interaction Model

| Gesture | Action |
|---------|--------|
| Single tap | Sequence (6 frames, 333ms intervals, auto-assemble) |
| Hold | Video clip recording |
| Release hold | Stop recording |
| Dual Capture button + hold | Dual capture clip |

### 5.4 Snap Mode Viewfinder

**Requirements:**

- FR-SNAP-VF-01: The viewfinder is clean — no grain, no film simulation, no vintage overlay.
- FR-SNAP-VF-02: Technical stats (ISO, shutter speed) are hidden. Exposure compensation indicator is visible only when backlit.
- FR-SNAP-VF-03: The invisible level appears when device tilt exceeds ±3°. It is a thin, glowing horizontal line at the center of the viewfinder. It disappears when level is restored.
- FR-SNAP-VF-04: Subject guidance text ("Step back for the full vibe") appears when a face is detected near the frame edge. Maximum display duration: 1.5 seconds. Auto-dismisses. Does not repeat for the same face position within 10 seconds.
- FR-SNAP-VF-05: A subtle ambient vibe glyph pulses when the on-device scene classifier detects a high-energy social scene. This is an ambient hint only — it does not switch modes or change the UI. The glyph is small and peripheral.
- FR-SNAP-VF-06: The shutter button is always visible and always tappable. There is no loading state that disables the shutter.

---

## 6. Feature: Roll Mode

### 6.1 Overview

Roll Mode is for intentional, present-moment capture without immediate review. The user shoots throughout the day. At 9 PM (or 24 hours after the first capture, whichever is first), the Roll unlocks and is shared with their trusted circle. The delayed reveal is not a limitation — it is the product.

### 6.2 Capture Formats

#### 6.2.1 Still Photos (Primary Format)

**User story:** As a Roll Mode user, I want to take still photos that are immediately locked away so that I can stay present in the experience without being tempted to review and re-shoot.

**Requirements:**

- FR-ROLL-STILL-01: A single tap captures a still photo. The photo is immediately added to the Roll and is not viewable until unlock.
- FR-ROLL-STILL-02: The film simulation preset (kodakWarm, fujiCool, or ilfordMono) is applied pre-shutter (visible in viewfinder) and baked into the output HEIF at capture time.
- FR-ROLL-STILL-03: The Roll has a maximum capacity of 24 stills per calendar day. The film counter decrements with each capture.
- FR-ROLL-STILL-04: When the counter reaches 0, the shutter button is visually disabled. A message appears: "Roll's full. See you at 9." No further stills can be added to today's Roll.
- FR-ROLL-STILL-05: Motion blur is not corrected. OIS is not applied in Roll Mode stills. The "imperfect" result is intentional.
- FR-ROLL-STILL-06: Night Mode applies automatically when AmbientMetadata indicates a night scene. The analog grain simulation is applied on top of the Night Mode output.

**Acceptance criteria:**
- [ ] Captured still is immediately hidden (not visible in any review UI)
- [ ] Film simulation is visible in viewfinder before shutter tap
- [ ] Film simulation matches output — what the user sees pre-shutter matches the saved image
- [ ] Counter decrements correctly and disables shutter at 0
- [ ] Night Mode activates automatically without user action in low-light

#### 6.2.2 Apple Live Photos

**User story:** As a Roll Mode user, I want to capture Live Photos so that the ambient sound and motion of a moment are preserved alongside the image.

**Requirements:**

- FR-ROLL-LIVE-01: Live Photos are available as a selectable format in Roll Mode (edge swipe to select).
- FR-ROLL-LIVE-02: Live Photo capture counts as 1 shot against the 24-shot daily limit.
- FR-ROLL-LIVE-03: The Live Photo (both still frame and motion component) is immediately locked. Neither is viewable until unlock.
- FR-ROLL-LIVE-04: The film simulation is applied to both the still frame and the video component of the Live Photo.
- FR-ROLL-LIVE-05: At unlock time, StoryEngine may select a Live Photo as a candidate for Moving Still conversion (see §6.2.3). The user is not asked to choose — selection is automatic.
- FR-ROLL-LIVE-06: Post-unlock, the user can export a Live Photo as a Boomerang-style looping MP4 via a share action. This export is available from the Film Archive, not at capture time.

#### 6.2.3 Hybrid Moving Stills

**User story:** As a Roll Mode user, I want some of my Live Photos to come alive at unlock time so that the reveal feels surprising and magical — discovering that a photo I thought was still is actually moving.

**What it is:** At unlock time, StoryEngine automatically selects the best Live Photo candidate from the Roll and converts it to a Moving Still — a subtle animation where background elements (steam, hair, leaves, fabric) move while the subject stays sharp. The user shot a Live Photo; they discover a moving image at 9 PM.

**Requirements:**

- FR-ROLL-MS-01: Moving Still conversion is performed by StoryEngine at unlock time, not at capture time.
- FR-ROLL-MS-02: StoryEngine automatically selects up to 3 Live Photo candidates per Roll for Moving Still conversion based on motion content and subject stability. The user does not choose.
- FR-ROLL-MS-03: The conversion process must complete before the unlock reveal screen is shown. Target: under 10 seconds per Moving Still on iPhone 15.
- FR-ROLL-MS-04: At the unlock reveal, Moving Stills are presented with a subtle animation — the movement begins automatically, creating the "alive" surprise.
- FR-ROLL-MS-05: If Moving Still conversion fails for a candidate, the original Live Photo is shown instead. Failure is silent — the user is not notified of the conversion attempt.
- FR-ROLL-MS-06: Moving Stills are available in v2.0 only. In v1.0, Live Photos are shown as standard Live Photos at unlock. The v1.0 unlock reveal should be designed to accommodate Moving Stills when they land in v2.0.

### 6.3 Roll Mode Viewfinder — Ghost Preview

**User story:** As a Roll Mode user, I want the viewfinder to feel like looking through an analog camera so that the act of shooting feels intentional and different from Snap Mode.

**Requirements:**

- FR-ROLL-VF-01: The viewfinder displays a real-time grain overlay via CIFilter. The grain drifts per-frame (time-varying seed) — it does not look like static noise.
- FR-ROLL-VF-02: A light leak overlay appears at a corner of the viewfinder at 10–15% opacity. It is triggered probabilistically when Roll Mode is entered — not on every session. The specific corner and intensity vary.
- FR-ROLL-VF-03: All technical stats are hidden: ISO, shutter speed, focus distance indicators, exposure histogram. The user sees composition only.
- FR-ROLL-VF-04: The film simulation preset is applied to the viewfinder in real time. The user sees the film look before they shoot.
- FR-ROLL-VF-05: The film simulation preset is selectable by an edge swipe on the viewfinder (not a menu). Three presets in v1.0: kodakWarm (warm tones, moderate grain), fujiCool (cool tones, fine grain), ilfordMono (black and white, heavy grain).
- FR-ROLL-VF-06: Subject guidance text is disabled in Roll Mode. Imperfect framing is acceptable.
- FR-ROLL-VF-07: The Vibe-Check ambient hint glyph is disabled in Roll Mode. The aesthetic is fixed — the user chose Roll Mode intentionally.

**Acceptance criteria:**
- [ ] Grain is visibly different frame-to-frame (not static)
- [ ] Light leak appears on at least 50% of Roll Mode sessions but not all
- [ ] Film simulation visible in viewfinder matches the output image
- [ ] Preset swipe changes simulation within 100ms
- [ ] No technical stats visible in Roll Mode viewfinder

### 6.4 Film Counter

**Requirements:**

- FR-ROLL-COUNTER-01: The film counter displays the number of shots remaining in the day's Roll. Initial value: 24.
- FR-ROLL-COUNTER-02: The counter decrements by 1 after each successful still or Live Photo capture.
- FR-ROLL-COUNTER-03: When 5 or fewer shots remain, the counter color changes to amber.
- FR-ROLL-COUNTER-04: When 0 shots remain, the shutter button is visually disabled and the counter shows "Roll full."
- FR-ROLL-COUNTER-05: A message appears when the Roll is full: "Roll's full. See you at 9." This message is persistent until the unlock.
- FR-ROLL-COUNTER-06: The counter resets at midnight local time for the new day's Roll.
- FR-ROLL-COUNTER-07: The counter is displayed as a physical film counter aesthetic — not a progress bar or percentage.

### 6.5 The 9 PM Unlock Ritual

**User story:** As a Roll Mode user, I want my photos to unlock at 9 PM and be shared with my circle simultaneously so that opening the Roll together is an experience, not just a notification.

This is the most important feature in Piqd. Every other Roll Mode decision exists in service of this moment.

**Requirements:**

- FR-ROLL-UNLOCK-01: The unlock trigger fires at 9 PM local time, OR 24 hours after the first asset was added to the Roll — whichever comes first.
- FR-ROLL-UNLOCK-02: At unlock trigger, StoryEngine begins assembling the Roll: film simulation baked, Moment clusters labeled, hero asset selected, Moving Stills processed (v2.0+).
- FR-ROLL-UNLOCK-03: The assembled RollPackage is encrypted per-recipient and uploaded to the sender's private iCloud container before the APNs notification is sent.
- FR-ROLL-UNLOCK-04: An APNs metadata-only notification is sent to all members of the rollCircle: "Your Piqd from today is ready." The notification contains no photo content.
- FR-ROLL-UNLOCK-05: When a rollCircle member opens Piqd after receiving the notification, the app retrieves and decrypts their RollPackage from iCloud and begins the reveal sequence.
- FR-ROLL-UNLOCK-06: The reveal sequence presents assets one by one with a film-advance animation and sound. Moving Stills animate on reveal (v2.0+).
- FR-ROLL-UNLOCK-07: Each rollCircle member's "opened" status is visible to the sender as a subtle avatar indicator on the Roll — similar to read receipts, but non-intrusive.
- FR-ROLL-UNLOCK-08: Roll assets are persistent after unlock. They are not ephemeral. They land in the Film Archive as a shared Moment.
- FR-ROLL-UNLOCK-09: If the sender has no captures in a day's Roll at 9 PM, no unlock occurs and no notification is sent.
- FR-ROLL-UNLOCK-10: The rollCircle is set when the first asset is added to the day's Roll and is immutable for that Roll. Adding a friend after the first capture does not add them to the current day's Roll.

**Acceptance criteria:**
- [ ] Unlock fires at exactly 9 PM local time (within 60 seconds tolerance)
- [ ] iCloud upload completes before APNs notification is sent
- [ ] APNs payload contains no photo content — metadata only
- [ ] Reveal sequence plays asset-by-asset with animation
- [ ] Roll assets appear in Film Archive after unlock
- [ ] Sender sees friend opened-status indicators
- [ ] Empty Roll produces no unlock and no notification

---

## 7. Feature: Pre-Shutter System

### 7.1 Zero-Lag Shutter

**User story:** As a Snap Mode user, I want the shutter to respond instantly every time I tap so that I never miss a moment because the app was slow.

**Requirements:**

- FR-PSS-LAG-01: Shutter response time (tap to capture) must be under 100ms in Snap Mode.
- FR-PSS-LAG-02: The viewfinder must never show a loading or initializing state after cold launch. Capture-ready state must be achieved within 1.5 seconds of app launch.
- FR-PSS-LAG-03: Continuous autofocus is always active in Snap Mode. Focus must be locked before the shutter tap, not after.
- FR-PSS-LAG-04: Face tracking is active — when a face enters the frame, focus locks to the face automatically without user tap.
- FR-PSS-LAG-05: Photo quality prioritization is set to speed in Snap Mode. Image quality is secondary to capture latency.

### 7.2 Invisible Level

**Requirements:**

- FR-PSS-LEVEL-01: A thin, glowing horizontal line appears in the center of the viewfinder when device tilt exceeds ±3° from horizontal.
- FR-PSS-LEVEL-02: The level disappears automatically when device tilt returns within ±3°.
- FR-PSS-LEVEL-03: The level appears in both Snap Mode and Roll Mode.
- FR-PSS-LEVEL-04: The level animation (appear/disappear) is subtle — a fade, not a pop.
- FR-PSS-LEVEL-05: The level can be disabled in user settings for users who find it distracting.

### 7.3 Subject Guidance

**Requirements:**

- FR-PSS-GUIDE-01: When a face is detected near the edge of the frame (within 15% of any edge), a brief text tip appears: "Step back for the full vibe."
- FR-PSS-GUIDE-02: The tip auto-dismisses after 1.5 seconds maximum.
- FR-PSS-GUIDE-03: The tip does not repeat for the same face position within 10 seconds.
- FR-PSS-GUIDE-04: Subject guidance is active in Snap Mode only. It is always off in Roll Mode.
- FR-PSS-GUIDE-05: Subject guidance can be disabled in user settings.

### 7.4 Backlight Correction

**Requirements:**

- FR-PSS-BACK-01: When the scene is backlit (subject significantly darker than background), the viewfinder automatically adjusts exposure to show the subject correctly.
- FR-PSS-BACK-02: What the user sees in the viewfinder matches the captured output. There is no surprise darkening after the shutter tap.
- FR-PSS-BACK-03: Backlight correction is active in both Snap Mode and Roll Mode.
- FR-PSS-BACK-04: A small EV compensation indicator appears only when backlight correction is actively applied. It disappears when lighting is balanced.

### 7.5 Vibe Hint

**Requirements:**

- FR-PSS-VIBE-01: The on-device scene classifier runs at 2fps in Snap Mode only.
- FR-PSS-VIBE-02: When a high-energy social scene is detected with sufficient confidence, a small ambient glyph pulses at the edge of the Snap Mode viewfinder.
- FR-PSS-VIBE-03: The glyph is a subtle indicator only. It does not switch modes, change UI layout, or make a sound.
- FR-PSS-VIBE-04: The glyph disappears when the scene returns to neutral or quiet.
- FR-PSS-VIBE-05: Vibe Hint is off in Roll Mode. The Roll Mode aesthetic is fixed.
- FR-PSS-VIBE-06: Vibe Hint can be disabled in user settings.

---

## 8. Feature: Sharing

### 8.1 Overview

Piqd sharing is always private, always directed at specific people, and never touches a Piqd server for content. Snap Mode sharing is ephemeral and instant. Roll Mode sharing is persistent and ritual.

### 8.2 Snap Mode Sharing

**User story:** As a Snap Mode user, I want to send a photo or strip to specific friends instantly so that sharing feels like a message, not a post.

**Requirements:**

- FR-SHARE-SNAP-01: After capture, the share action is available immediately (or after Sequence assembly completes).
- FR-SHARE-SNAP-02: The circle selector shows the trusted friends list. Friends can be selected with a single tap. The last-used selection is pre-populated.
- FR-SHARE-SNAP-03: Transport is automatic — MultipeerConnectivity for nearby friends, WebRTC for remote friends, deferred P2P for offline friends. The user never sees or configures transport.
- FR-SHARE-SNAP-04: All content is end-to-end encrypted before transmission. No content touches a Piqd server.
- FR-SHARE-SNAP-05: Shared assets expire on first view by the recipient OR after 24 hours — whichever comes first.
- FR-SHARE-SNAP-06: The sender's copy is purged after confirmed delivery.
- FR-SHARE-SNAP-07: When a recipient views the asset, it is deleted from their device after the view session ends (app backgrounded or next asset opened).
- FR-SHARE-SNAP-08: Sequence strips are shared as assembled MP4 only. Raw HEIF frames are never transmitted.
- FR-SHARE-SNAP-09: If a recipient is offline, the sender device holds the asset and an APNs metadata notification is sent. The recipient retrieves directly from the sender device when online. If the asset expires (24h) before retrieval, it is purged and the recipient receives an "expired" notification.

**Acceptance criteria:**
- [ ] LAN transfer for Sequence strip MP4 completes in under 1 second
- [ ] Remote WebRTC transfer completes in under 5 seconds on typical mobile connection
- [ ] Recipient cannot view asset after expiry (both first-view and 24h ceiling enforced)
- [ ] Sender copy is purged — not accessible in vault after confirmed delivery
- [ ] No Piqd server receives photo content at any point in the flow

### 8.3 Roll Mode Sharing — iCloud Package

**User story:** As a Roll Mode user, I want my circle to receive my Roll at 9 PM regardless of whether my phone is on or connected so that the ritual is reliable.

**Requirements:**

- FR-SHARE-ROLL-01: The assembled RollPackage is encrypted with each rollCircle member's public key on the sender's device before upload.
- FR-SHARE-ROLL-02: The encrypted package is uploaded to the sender's private iCloud container. One encrypted blob per recipient.
- FR-SHARE-ROLL-03: Piqd has no access to the encryption keys. iCloud stores opaque encrypted blobs only.
- FR-SHARE-ROLL-04: The .rollpkg file is deleted from iCloud automatically after the recipient successfully decrypts and acknowledges receipt.
- FR-SHARE-ROLL-05: iCloud upload must complete before the APNs group notification is sent.
- FR-SHARE-ROLL-06: Recipients retrieve their RollPackage from iCloud on next app open after notification. Sender device does not need to be online for retrieval.
- FR-SHARE-ROLL-07: Roll assets are persistent on the recipient's device — they are not ephemeral. They appear in the recipient's Film Archive.
- FR-SHARE-ROLL-08: If iCloud upload fails (no connectivity at unlock time), the app retries at 5-minute intervals for up to 2 hours. If upload fails after 2 hours, a local notification informs the sender: "Your Roll couldn't deliver — we'll try again when you're connected."

**Acceptance criteria:**
- [ ] iCloud upload completes within 30 seconds for a full 24-shot Roll
- [ ] APNs notification is sent only after upload confirmation
- [ ] Recipient can retrieve Roll when sender device is offline
- [ ] .rollpkg deleted from iCloud after recipient acknowledgment
- [ ] Retry logic activates on upload failure — user notified if 2-hour window exceeded

---

## 9. Feature: Trusted Circle

### 9.1 Overview

The trusted circle is the only social graph in Piqd. It is local, private, and small. There are no followers, no public profiles, no discoverability. Every sharing interaction in Piqd is directed at specific people from this list.

### 9.2 Requirements

- FR-CIRCLE-01: Maximum circle size is 10 friends.
- FR-CIRCLE-02: Friends are added by QR code scan or deep link only. There is no search-by-username or phone number lookup.
- FR-CIRCLE-03: The invitation flow: sender generates an invite token → shares via QR or link → recipient opens link or scans QR → Piqd launches → Curve25519 key exchange completes → friend is added to both users' local lists.
- FR-CIRCLE-04: The friends list is stored locally on the device in the intelligence graph (GraphRepository). It is not stored on any Piqd server.
- FR-CIRCLE-05: Friends can be removed at any time. Removal takes effect immediately for future Rolls. It does not retract already-delivered content.
- FR-CIRCLE-06: There are no public usernames, public profiles, or discoverability in Piqd. A user cannot be found unless they share an invite directly.
- FR-CIRCLE-07: The friends list displays each friend's display name (set at invite time) and their last Piqd activity (last Roll sent — date only, no content preview).

### 9.3 Key Management

- FR-CIRCLE-KEY-01: Each user generates a Curve25519 keypair on first app launch.
- FR-CIRCLE-KEY-02: The private key is stored in iOS Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly. It never leaves the device.
- FR-CIRCLE-KEY-03: The public key is shared with friends at invite time and stored in the local friends list.
- FR-CIRCLE-KEY-04: If a user reinstalls Piqd, a new keypair is generated. Existing friends must re-invite to exchange new keys. Piqd does not attempt to recover old keys.

---

## 10. Feature: Film Archive

### 10.1 Overview

The Film Archive is where completed Rolls live after unlock. It is the persistent memory layer of Piqd. It is not a social feed — it is a personal and shared archive.

### 10.2 Requirements

- FR-ARCHIVE-01: Each unlocked Roll appears in the Film Archive as a Moment — a named collection of assets with a hero image, date, and location label.
- FR-ARCHIVE-02: Moments are presented in reverse chronological order. There is no algorithmic reordering.
- FR-ARCHIVE-03: The hero asset is selected by StoryEngine (highest AssetScore composite). The user can replace the hero asset manually after unlock.
- FR-ARCHIVE-04: Each Moment displays which rollCircle members received it, indicated by friend avatars.
- FR-ARCHIVE-05: Received Rolls from friends appear in the Film Archive alongside the user's own Rolls, differentiated by a friend attribution label.
- FR-ARCHIVE-06: Assets within a Moment can be individually exported to the iOS Photos library.
- FR-ARCHIVE-07: Live Photos can be exported as Boomerang-style looping MP4 from the Film Archive.
- FR-ARCHIVE-08: The Film Archive has no public visibility. It is never shared beyond the rollCircle. There is no "make public" option.
- FR-ARCHIVE-09: Assets in the Film Archive are encrypted at rest (AES-256-GCM, per niftyMomnt SRS v1.2 §10.1).

---

## 11. Out of Scope — v1.0

The following are explicitly excluded from Piqd v1.0:

| Feature | Reason | Target |
|---------|--------|--------|
| Moving Still conversion | Processing complexity — requires v2.0 | v2.0 |
| Ring buffer / pre-capture | Memory and complexity — requires v2.0 | v2.0 |
| Dual Capture in Roll Mode | Roll Mode is stills-primary. Dual is reactive and belongs in Snap. | Not planned |
| Cinematic Mode | Dropped — Apple Camera does this better. Piqd's "cinematic" is the ritual, not the codec. | Not planned |
| Spatial photos / Video | Gen Z demand currently low. Vision Pro adoption niche. | v3.0+ |
| Public feed or follower system | Conflicts with P6 (intimacy over scale). Not planned for any version. | Never |
| Video in Roll Mode | Roll Mode is stills-primary. Video belongs in Snap. | Not planned |
| Group video chat | Out of scope for a camera app. | Never |
| AI caption generation | NudgeEngine is out of scope for Piqd v1.0. | v2.0 |
| Community feed | Conflicts with P6. | Never |
| Web app | iOS only. | Not planned |
| Android | iOS only. | Not planned |

---

## 12. Success Metrics

### 12.1 Acquisition

| Metric | v1.0 Target (90 days post-launch) |
|--------|----------------------------------|
| Total installs | 10,000 |
| Organic install rate | ≥ 60% (word of mouth and invite-driven) |
| Invite conversion rate | ≥ 40% (invites sent → installs) |

### 12.2 Engagement

| Metric | Target |
|--------|--------|
| D1 retention | ≥ 40% |
| D7 retention | ≥ 20% |
| D30 retention | ≥ 12% |
| Daily Roll completion rate (users who open Roll Mode → at least 1 capture) | ≥ 50% |
| Daily unlock engagement (users who open Piqd within 30 min of 9 PM notification) | ≥ 60% |
| Snap Mode sends per active user per day | ≥ 3 |
| Average circle size at D30 | ≥ 3 friends |

### 12.3 Quality

| Metric | Target |
|--------|--------|
| Shutter response time (p95) | < 100ms |
| Sequence assembly time (p95) | < 2 seconds |
| Roll iCloud upload success rate | ≥ 98% |
| Crash-free session rate | ≥ 99.5% |
| App Store rating | ≥ 4.5 |

### 12.4 Privacy

| Metric | Target |
|--------|--------|
| Piqd server content requests | 0 (architectural guarantee) |
| User privacy-related support tickets | < 0.5% of DAU |

---

## 13. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| iCloud upload fails at 9 PM due to connectivity | Medium | High — breaks Roll ritual | Retry logic (5-min intervals, 2-hour window). Local notification if all retries fail. |
| Sender device offline at recipient retrieval time (Snap) | Medium | Low — acceptable for ephemeral content | APNs metadata ping informs recipient. 24h expiry is communicated. |
| Curve25519 key loss on reinstall | Low | Medium — breaks Roll delivery to that friend | On reinstall: friends list is cleared and re-invite is required. Communicated clearly in onboarding. |
| WebRTC NAT traversal failure rate > 20% | Low | Medium — degrades remote Snap sharing latency | TURN fallback handles this. Content is still delivered, slightly slower. Monitor TURN usage. |
| 24-shot limit feels too restrictive | Medium | Medium — Roll Mode abandonment | Monitor. If ≥ 30% of Roll Mode users hit the limit before 9 PM and churn, increase to 36 or introduce a one-time daily top-up. |
| Mode switch gesture conflicts with OS swipe gestures | Medium | High — users can't switch modes | UX validation required pre-launch. Gesture tuning to avoid conflict with iOS back gesture and Control Center. |
| Gen Z finds 9 PM unlock time wrong for their timezone / lifestyle | Medium | Medium | Consider per-user configurable unlock time (fixed options: 6 PM, 9 PM, midnight) in v1.1. |
| Grain overlay causes viewfinder frame rate drop | Low | High — breaks Roll Mode aesthetic | CIFilter performance testing required on iPhone 15 (lowest supported device). Target 30fps minimum. |

---

## 14. Acceptance Criteria — Full Feature Set

### 14.1 Mode System
- [ ] Mode switch gesture completes within 150ms on iPhone 15
- [ ] Snap viewfinder has no grain; Roll viewfinder has visible drifting grain
- [ ] Mode persists across app background/foreground and cold launch
- [ ] Mode switch does not discard in-progress Roll assets

### 14.2 Snap Mode
- [ ] Single tap triggers 6-frame Sequence (333ms ±20ms intervals)
- [ ] Sequence MP4 assembles within 2 seconds on iPhone 15
- [ ] Share button disabled until Sequence shareReady = true
- [ ] Hold-to-record begins within 50ms of shutter hold
- [ ] Dual Capture produces synchronized composite within 1 frame
- [ ] 120fps clip option absent on non-Pro devices

### 14.3 Roll Mode
- [ ] Captured assets are immediately hidden — not accessible pre-unlock
- [ ] Film simulation matches between viewfinder and output
- [ ] Film counter decrements correctly; shutter disables at 0
- [ ] Unlock fires within 60 seconds of 9 PM local time
- [ ] iCloud upload completes before APNs notification fires
- [ ] Empty Roll produces no unlock and no notification
- [ ] Roll assets appear in Film Archive post-unlock
- [ ] rollCircle is immutable after first capture of the day

### 14.4 Pre-Shutter
- [ ] Shutter response ≤100ms (p95) in Snap Mode
- [ ] Invisible level appears at >±3° tilt and disappears when level restored
- [ ] Subject guidance appears for max 1.5s and does not repeat within 10s
- [ ] Backlight correction visible in viewfinder matches captured output

### 14.5 Sharing
- [ ] No photo content transmitted to any Piqd server (verifiable via network inspection)
- [ ] Snap asset inaccessible after first view + 24h ceiling
- [ ] Roll iCloud package deleted after recipient acknowledgment
- [ ] Sender copy purged after Snap delivery confirmation

### 14.6 Trusted Circle
- [ ] Friends added only via QR or deep link — no search
- [ ] Maximum 10 friends enforced
- [ ] Key exchange completes at invite time
- [ ] Private key never leaves device (Keychain only)

### 14.7 Film Archive
- [ ] Unlocked Rolls appear in Archive in reverse chronological order
- [ ] Hero asset is selectable by user post-unlock
- [ ] Assets exportable to iOS Photos library
- [ ] Archive has no public visibility option

---

*— End of Document — Piqd PRD v1.0 · SRS reference: piqd_SRS_v1.0.md · April 2026 —*
