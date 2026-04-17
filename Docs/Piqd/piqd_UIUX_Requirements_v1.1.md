# Piqd

## UI/UX Requirements Specification

**Gen Z Camera App · Two Modes · One Emotional Truth**

Version 1.1 | April 2026 | Confidential

PRD reference: piqd_PRD_v1.0.md | SRS reference: piqd_SRS_v1.0.md

Author: Han Wook Cho | hwcho@gmail.com

---

## Document Control — v1.1

**Changes from v1.0:**
- Added Part 0 — Device Compatibility and Screen Geometry (new section, all fixed pixel values replaced with adaptive system)
- Added Part 5 — Dynamic Island Integration (new section)
- All fixed pt values removed from v1.0 requirements and replaced with relative, safe-area-aware expressions
- UX-STATE-06 added (Safe Render zone during Sequence capture — from Lapse analysis session)
- UX-NAV-08, UX-NAV-09 added (layered reveal system, no thumbnail policy)
- Part 4 Open Design Decisions updated: item 6 resolved (full bleed + floating strip)

---

## Part 0 — Device Compatibility and Screen Geometry

This section is new in v1.1 and is the authoritative reference for all layout decisions. Every requirement in this document must be validated against all devices in the support matrix below. No fixed pixel or point value may appear in the UI/UX Specification unless it is listed here as a device-constant.

### 0.1 Target Device Support Matrix

All devices share the Dynamic Island. All run iOS 26+. All use @3x pixel density. Design in points (pt) only.

| Device | Screen (pt) | Safe area top (portrait) | Safe area bottom | Notes |
|--------|-------------|--------------------------|------------------|-------|
| iPhone 15 | 390 × 844 | 59pt | 34pt | Baseline device — minimum supported |
| iPhone 15 Plus | 430 × 932 | 59pt | 34pt | Same safe area as iPhone 15 |
| iPhone 15 Pro | 393 × 852 | 59pt | 34pt | ProMotion, Always-On |
| iPhone 15 Pro Max | 430 × 932 | 59pt | 34pt | Largest 2023 screen |
| iPhone 16 | 390 × 844 | 59pt | 34pt | Same as iPhone 15 |
| iPhone 16 Plus | 430 × 932 | 59pt | 34pt | Same safe area as iPhone 15 Plus |
| iPhone 16 Pro | 402 × 874 | 62pt | 34pt | Larger Dynamic Island top inset |
| iPhone 16 Pro Max | 440 × 956 | 62pt | 34pt | Largest supported screen |
| iPhone 17 | 393 × 852 | 62pt | 34pt | Same size as 16 Pro |
| iPhone 17 Pro | 393 × 852 | 62pt | 34pt | Same size as 16 Pro |
| iPhone 17 Pro Max | 440 × 956 | 62pt | 34pt | Same as 16 Pro Max |

**Key observations for layout:**
- Screen widths range from **390pt to 440pt** — a 50pt spread (12.8%)
- Screen heights range from **844pt to 956pt** — a 112pt spread (13.3%)
- Safe area top is either **59pt** (iPhone 15 family, iPhone 16 base) or **62pt** (iPhone 16 Pro+, iPhone 17 family)
- Safe area bottom is **34pt** across all supported devices
- Dynamic Island physical size is consistent across all models — the 3pt difference in safe area top reflects the larger Island on Pro models only

### 0.2 The No-Fixed-Value Rule

No layout dimension in Piqd may be specified as a fixed point value. Every dimension must be expressed as one of:

- **Percentage of screen width:** `n% of screenWidth`
- **Percentage of safe area height:** `n% of safeAreaHeight` (where safeAreaHeight = screenHeight − safeAreaTop − safeAreaBottom)
- **System constant:** `safeAreaTop`, `safeAreaBottom`, `screenWidth`, `screenHeight`
- **Touch target constant:** minimum 44pt (iOS HIG) or 72pt (shutter) — these are the only permitted fixed values, as they are Apple-defined accessibility minimums, not layout values
- **Motion duration constant:** values in UX-MOTION-02 are in milliseconds, not points — they are device-independent and exempt from this rule

**Forbidden:** any value like "28pt tray", "200px button", "16px padding", "0.3 * 375" — these break on devices outside the reference frame they were designed for.

### 0.3 Safe Area Coordinate System

The following named regions are used throughout this document. All measurements are relative to these regions, never to absolute screen coordinates.

```
┌─────────────────────────┐  ← y=0 (screen top)
│   Dynamic Island zone   │  ← safeAreaTop (59pt or 62pt)
├─────────────────────────┤  ← content origin
│                         │
│      SAFE AREA          │  ← safeAreaHeight = screenHeight − safeAreaTop − safeAreaBottom
│    (viewfinder lives    │
│       here)             │
│                         │
├─────────────────────────┤  ← content bottom
│   Home indicator zone   │  ← safeAreaBottom (34pt, all devices)
└─────────────────────────┘  ← y=screenHeight
```

**safeAreaHeight reference values (for validation only — do not hardcode):**

| Device | safeAreaHeight |
|--------|---------------|
| iPhone 15 / 16 | 844 − 59 − 34 = 751pt |
| iPhone 15 Plus / 16 Plus / 15 Pro Max | 932 − 59 − 34 = 839pt |
| iPhone 15 Pro | 852 − 59 − 34 = 759pt |
| iPhone 16 Pro | 874 − 62 − 34 = 778pt |
| iPhone 16 Pro Max / 17 Pro Max | 956 − 62 − 34 = 860pt |
| iPhone 17 / 17 Pro | 852 − 62 − 34 = 756pt |

### 0.4 Landscape Orientation

Piqd v1.0 is portrait-only. Landscape orientation is not supported. The viewfinder does not rotate. This is explicitly stated in onboarding. The Dynamic Island becomes a side inset in landscape — Piqd never enters this state so no landscape safe area handling is required in v1.0.

---

## Part 1 — 2026 Design Trend Alignment

*(All requirements from v1.0 §Part 1 are retained unchanged. Only fixed value references have been removed. See Part 0 for the replacement coordinate system.)*

### Trend 1 — Liquid Glass and Adaptive Transparency
- UX-GLASS-01: Liquid Glass materials are used for system-layer UI only — navigation overlays, the mode indicator pill, the share sheet, and the circle selector.
- UX-GLASS-02: The viewfinder surface uses no Liquid Glass. The viewfinder is raw, material-free.
- UX-GLASS-03: In Snap Mode, the shutter button and format selector use subtle translucency (iOS 26 system material).
- UX-GLASS-04: In Roll Mode, the shutter button uses a matte, non-transparent surface. No glass.
- UX-GLASS-05: The unlock reveal screen uses no Liquid Glass. Warm, matte dark surface only.

### Trend 2 — Ambient AI
- UX-AI-01: All AI outputs are ambient — periphery only, never center of viewfinder.
- UX-AI-02: AI indicators use motion to communicate, not text. Exception: subject guidance text (1.5s max).
- UX-AI-03: No AI feature makes an irreversible decision at capture time.
- UX-AI-04: AI indicators disappear automatically. No dismissal required.
- UX-AI-05: Vibe Hint and subject guidance have explicit off toggles in settings.
- UX-AI-06: All AI ambient hints disabled in Roll Mode.

### Trend 3 — Real-Time Personalization
- UX-PERS-01: App does not auto-switch modes. Mode is always user-initiated.
- UX-PERS-02: Time-of-day adaptation at three moments only: 9 PM unlock-imminent state, unlock reveal, midnight roll reset.
- UX-PERS-03: Last-used film simulation preset persists across sessions.
- UX-PERS-04: Circle selector pre-populates with last-used selection.
- UX-PERS-05: Mode persists on cold launch.

### Trend 4 — Motion as Functional Cognitive Guide
- UX-MOTION-01: Every motion has a functional purpose. No decorative animations.
- UX-MOTION-02: Motion duration budget (device-independent milliseconds):
  - Mode switch hold arc: 1500ms linear fill
  - Mode switch confirm + transition: 150ms maximum
  - Shutter response feedback: 80ms
  - Sequence frame flash: 40ms per frame
  - Bottom sheet (Sequence preview): 220ms ease-out
  - Roll unlock reveal per asset: 400ms film-advance
  - Film counter decrement: 120ms tick
  - Navigation transitions: 280ms maximum
  - Dynamic Island expand/contract: 300ms (matches system spring)
- UX-MOTION-03: Snap transitions use crossfade. Roll transitions use crossfade with warm color temperature shift.
- UX-MOTION-04: Mode switch grain crossfades (not slides) on confirmed switch after the 1.5s hold arc + confirmation sheet.
- UX-MOTION-05: Micro-haptics: shutter tap (sharp), sequence frame (6 light pulses at 333ms), mode switch (single medium), Roll unlock (slow deep rumble), Dynamic Island activity start (single brief pulse).
- UX-MOTION-06: Easing curves — Snap: spring easing. Roll: ease-out cubic with imperceptible overshoot. System overlays: iOS 26 default spring.
- UX-MOTION-07: All animations respect iOS Reduce Motion. No feature becomes non-functional.
- UX-MOTION-08: Unlock reveal uses organic, irregular cadence with randomized per-asset delays (±80ms variance).

### Trend 5 — Multi-Modal Interfaces
- UX-MULTI-01: Gesture-first. Every core action reachable with one hand, one thumb, no grip reposition.
- UX-MULTI-02: Gesture vocabulary:
  - Tap: capture selected format
  - Hold (shutter): clip recording (Snap only)
  - Long-hold (mode indicator pill, 1.5s): triggers mode switch — arc fills, then confirmation sheet slides up
  - Edge swipe left/right (outer 20% of viewfinder width): film simulation preset (Roll only)
  - Swipe up on viewfinder: circle selector (Snap) / Roll counter detail (Roll)
  - Pinch: zoom (both modes)
  - Single tap on viewfinder: reveal secondary chrome layer (3s idle timeout)
- UX-MULTI-03: No viewfinder swipe gesture for mode switch. Long-hold on mode pill is the only trigger. This eliminates conflict with iOS back gesture, Control Center, and other swipe-based app interactions.
- UX-MULTI-04: No voice input in v1.0.
- UX-MULTI-05: Haptic feedback is a co-equal input channel.

### Trend 6 — Ultra-Contextual Navigation
- UX-NAV-01: Viewfinder occupies 100% of screen in both modes. No persistent navigation bar, tab bar, or toolbar.
- UX-NAV-02: Persistent UI at rest: shutter button, mode indicator pill, film counter (Roll only). Everything else retreats.
- UX-NAV-03: Secondary controls appear only on gesture invocation. Auto-retreat after 3s idle or action completion.
- UX-NAV-04: Film Archive accessed by swipe up from bottom of viewfinder. Returns on swipe down.
- UX-NAV-05: Circle selector slides up as compact sheet. Abandoned by swipe down.
- UX-NAV-06: Mode switch accessed via long-hold (1.5s) on the mode indicator pill only. Settings accessed via short long-press (0.5s) on mode indicator pill — a context action distinct from the 1.5s mode switch hold. Deliberate friction on both.
- UX-NAV-07: No hamburger menu, no sidebar, no tab bar. Navigation is gesture and context-driven.
- UX-NAV-08 (NEW): Layered reveal system — three chrome layers:
  - Layer 0 (rest): shutter button + mode indicator pill + film counter (Roll only)
  - Layer 1 (single tap on viewfinder): zoom pill + aspect ratio indicator + flip button + unsent badge. Auto-retreats after 3s.
  - Layer 2 (gesture on shutter): format selector expands. Collapses on selection.
- UX-NAV-09 (NEW): No thumbnail preview element in the viewfinder. Post-capture confirmation is delivered through shutter button animation (Snap) and film counter decrement (Roll). Film Archive accessed via swipe-up gesture only.

### Trend 7 — AI-Assisted Creative Tools
- UX-AI-CREATIVE-01: Hero asset is a suggestion. User can replace with a tap.
- UX-AI-CREATIVE-02: Moving Still (v2.0) presented as reveal surprise, not a configurable setting.
- UX-AI-CREATIVE-03: Film simulation preset selection is entirely human.
- UX-AI-CREATIVE-04: No AI confidence scores, processing indicators, or "AI-enhanced" labels shown.

### Trend 8 — Calm UX
- UX-CALM-01: No notification badges on in-app UI elements.
- UX-CALM-02: Only intentional time-pressure: film counter approaching 0.
- UX-CALM-03: Error states use calm language. No alarming icons for non-critical errors.
- UX-CALM-04: Progressive disclosure. First launch shows viewfinder and shutter only.
- UX-CALM-05: Film Archive is not a feed. No infinite scroll, no algorithm.
- UX-CALM-06: UI chrome palette does not compete with viewfinder content.
- UX-CALM-07: Unlock reveal is quiet, not celebratory. No confetti, no gamification.

### Trend 9 — Narrative Interfaces
- UX-NARR-01: Film Archive Moment cards: hero image, label, friend avatars, ambient detail. Not a thumbnail grid.
- UX-NARR-02: Unlock reveal is a narrative sequence — beginning, middle, end — not a gallery.
- UX-NARR-03: Moment view sequenced narratively (StoryEngine order). User can switch to capture order.
- UX-NARR-04: No statistics, streak counters, or gamification metrics in the Film Archive.

### Trend 10 — Anti-Perfect UI
- UX-IMPERF-01: Roll Mode viewfinder grain drifts per-frame. Never static.
- UX-IMPERF-02: Light leak overlay position, intensity, and corner randomized per session.
- UX-IMPERF-03: Unlock reveal uses organic, irregular timing (see UX-MOTION-08).
- UX-IMPERF-04: Analog shutter sound in Roll Mode has subtle pitch/speed variation ±3% per fire.
- UX-IMPERF-05: Film simulation presets are intentionally approximate, not mathematically precise.
- UX-IMPERF-06: Roll Mode motion curves use slightly asymmetric easing with single imperceptible overshoot.
- UX-IMPERF-07: Snap Mode UI is clean and precise. The contrast with Roll is intentional and must be maintained.

---

## Part 2 — Piqd-Specific UI/UX Requirements

### 2.1 Speed and Responsiveness
*(All unchanged from v1.0)*
- UX-SPEED-01: Shutter response ≤100ms in Snap Mode.
- UX-SPEED-02: No splash screen. Camera live within 1.5s of launch.
- UX-SPEED-03: Viewfinder never shows loading state after first launch.
- UX-SPEED-04: Format switching within 80ms. No transition animation.
- UX-SPEED-05: Circle selector opens within 100ms of swipe-up completing.

### 2.2 The Two-Screen Philosophy
- UX-2SCR-01: Mode identifiable from aesthetic alone within 1 second. No text needed.
- UX-2SCR-02: Grain overlay alone is not sufficient mode distinction — full chrome, color temperature, and shutter button must differ.
- UX-2SCR-03: Snap — clean, geometric, bright, high-contrast. Roll — warm, organic, low-contrast, imperfect.
- UX-2SCR-04: Mode indicator uses a single symbol per mode. Text labels in onboarding only.

### 2.3 Adaptive Layout — Screen Geometry Requirements (NEW in v1.1)

These requirements replace all fixed layout values from v1.0 and apply universally across the device support matrix.

**Viewfinder:**
- UX-LAYOUT-01: The viewfinder fills 100% of screen width and 100% of screen height. It extends behind the Dynamic Island and behind the home indicator zone. The capture preview occupies the full screen — the camera sees all of it.
- UX-LAYOUT-02: UI chrome (shutter, mode pill, counter) is positioned within the safe area only. No interactive element is placed within the Dynamic Island zone or the home indicator zone.
- UX-LAYOUT-03: The viewfinder capture region (what actually gets saved) matches the selected aspect ratio. A 9:16 crop indicator appears during Sequence capture within the safe area, never overlapping the Dynamic Island zone.

**Shutter button:**
- UX-LAYOUT-04: The shutter button center is positioned at `screenHeight − safeAreaBottom − (safeAreaBottom × 1.5)` from the top of the screen. In plain terms: comfortably above the home indicator, reachable by right thumb without grip adjustment on the smallest supported device (390pt wide).
- UX-LAYOUT-05: The shutter button outer diameter is `min(screenWidth × 0.185, 80pt)`. This produces approximately 72pt on a 390pt-wide screen and scales proportionally on wider screens without becoming oversized.
- UX-LAYOUT-06: The shutter button touch target (invisible tappable area) extends beyond the visible button by 8pt in all directions, regardless of button size.

**Zoom pill:**
- UX-LAYOUT-07: The zoom pill appears centered horizontally. Its vertical position is `safeAreaTop + safeAreaHeight × 0.88` — in the lower safe area, above the shutter button. It retreats with Layer 1 chrome after 3s idle.
- UX-LAYOUT-08: The zoom pill width scales with content (3 zoom levels × label width + padding). It does not have a fixed width.

**Aspect ratio indicator:**
- UX-LAYOUT-09: Aspect ratio indicator sits to the right of the zoom pill in the same horizontal row, separated by `screenWidth × 0.04` gap.

**Film counter (Roll Mode):**
- UX-LAYOUT-10: The film counter is positioned at `safeAreaTop + safeAreaHeight × 0.04` from the top of the safe area — just below the Dynamic Island zone, in the upper right quadrant of the viewfinder. It must not overlap the Dynamic Island on any device.
- UX-LAYOUT-11: Film counter uses a relative font size: `max(15pt, screenWidth × 0.038)`. On iPhone 15 (390pt): ~15pt. On iPhone 16 Pro Max (440pt): ~17pt. Always readable in sunlight.

**Mode indicator pill:**
- UX-LAYOUT-12: Mode indicator pill is centered horizontally at `safeAreaTop + safeAreaHeight × 0.96` — just above the home indicator zone. It sits above the shutter button, between the shutter and the bottom of the safe area.
- UX-LAYOUT-13: Mode indicator pill height is fixed at 28pt (the only permitted fixed UI value beyond touch targets — it is a symbol container, not a layout reference).

**Format selector:**
- UX-LAYOUT-14: Format selector appears as a compact row above the shutter button when invoked (Layer 2 gesture). Its vertical position is `shutterCenterY − shutterRadius − 16pt − formatSelectorHeight`. It scales horizontally to fill `screenWidth × 0.7`, centered.

**Drafts tray badge:**
- UX-LAYOUT-15: The unsent badge sits to the left of the mode indicator pill in the same horizontal row. It appears only in Layer 1 (single tap reveals it). Gap between badge and pill: `screenWidth × 0.04`.

**Bottom sheets (circle selector, Film Archive, drafts tray):**
- UX-LAYOUT-16: All bottom sheets use `UISheetPresentationController` with system-managed sizing. They respect safeAreaBottom automatically. No fixed heights are specified for sheets — they size to content with a maximum of `safeAreaHeight × 0.75`.
- UX-LAYOUT-17: The Sequence strip preview floats as an overlay at the bottom of the viewfinder, not as a detached sheet. Its height is `safeAreaHeight × 0.28` — approximately 28% of the safe area. It sits above the home indicator zone, inset by safeAreaBottom.

**Flip button:**
- UX-LAYOUT-18: Flip button appears in Layer 1 at top-right of the viewfinder safe area. Position: `screenWidth − safeAreaRight − (screenWidth × 0.06)` from left, `safeAreaTop + (safeAreaHeight × 0.04)` from top. Touch target: minimum 44pt × 44pt.

### 2.4 Onboarding
*(Unchanged from v1.0 — 4 screens maximum, context-permission requests, real app UI)*
- UX-ONBOARD-01 through UX-ONBOARD-04: see v1.0.

### 2.5 Typography
- UX-TYPE-01: Two typefaces maximum. Geometric sans-serif for chrome. Monospaced for film counter and technical indicators.
- UX-TYPE-02: No decorative typography in the capture experience.
- UX-TYPE-03: Film counter minimum contrast ratio 4.5:1 against both light and dark viewfinder backgrounds. Font size uses UX-LAYOUT-11 formula.
- UX-TYPE-04: Moment labels in Film Archive at caption weight, not headline weight.

### 2.6 Color
*(Unchanged from v1.0)*
- UX-COLOR-01 through UX-COLOR-05: see v1.0.

### 2.7 Iconography
*(Unchanged from v1.0)*
- UX-ICON-01 through UX-ICON-04: see v1.0.

### 2.8 Accessibility
- UX-A11Y-01: All interactive elements minimum 44pt × 44pt touch target. This is an iOS HIG absolute — exempt from the no-fixed-value rule.
- UX-A11Y-02: Shutter button minimum 72pt touch target. Exempt from no-fixed-value rule.
- UX-A11Y-03: All animations respect iOS Reduce Motion.
- UX-A11Y-04: VoiceOver labels on all interactive elements.
- UX-A11Y-05: Invisible level and subject guidance compatible with VoiceOver.
- UX-A11Y-06: Color never sole differentiator for any state.
- UX-A11Y-07: Minimum contrast ratios: 4.5:1 body text, 3:1 large text and UI components (WCAG AA).
- UX-A11Y-08 (NEW): Dynamic Island Live Activity content must meet the same 4.5:1 contrast requirement. Dynamic Island text is small — minimum effective text size in the Island is 11pt, rendered at @3x.

### 2.9 Interaction States
- UX-STATE-01: Shutter pressed: scale-down transform (0.92×) with haptic pulse.
- UX-STATE-02: Shutter disabled (Roll, counter=0): 40% opacity, no tap response.
- UX-STATE-03: Share button disabled (Sequence assembling): thin animated arc around send button. Maximum 2 seconds.
- UX-STATE-04: Circle selector friend avatars pulse when friend is nearby (MultipeerConnectivity detected).
- UX-STATE-05: Unlock countdown (within 30min of 9PM): film counter shifts to Roll accent, subtle ambient pulse.
- UX-STATE-06 (NEW): Safe Render zone during Sequence capture — a subtle rounded 9:16 crop indicator appears on the viewfinder for the 3-second capture window. Border: 1pt, 15% opacity. Disappears immediately on sequence completion. Navigation chrome dissolves when CMMotionManager detects motion delta >2°/s during the window.
- UX-STATE-07 (NEW): Mode switch confirmation sheet — appears after 1.5s hold on mode pill arc completes. Sheet contains: target mode name ("Switch to Roll?" / "Switch to Snap?"), target mode aperture symbol (24pt, accent color), primary "Switch" CTA (target mode accent color background), secondary "Stay in [mode]" text-link dismiss. Tapping outside sheet dismisses with no switch. Pill long-hold is disabled during Sequence capture, Clip/Dual recording, and Roll unlock sequence.

### 2.10 Empty States
*(Unchanged from v1.0)*
- UX-EMPTY-01 through UX-EMPTY-03: see v1.0.

### 2.11 Privacy UX
*(Unchanged from v1.0)*
- UX-PRIV-01 through UX-PRIV-05: see v1.0.

---

## Part 3 — Dynamic Island Integration (NEW in v1.1)

The Dynamic Island is present on every device in the support matrix. It is not a notch to route around — it is an active UI surface. Piqd must treat it as a first-class output channel for state communication.

### 3.1 Dynamic Island Design Principles

- UX-DI-01: The Dynamic Island is used for ambient, glanceable state only. It is never used for navigation, never tappable as a primary action, and never replaces viewfinder chrome.
- UX-DI-02: Dynamic Island states must be meaningful — they appear because the user needs to know something, not because the feature exists. Maximum 3 distinct Piqd states use the Island.
- UX-DI-03: Dynamic Island content follows Apple's Live Activity compact/expanded presentation model. Piqd does not implement a full Lock Screen Live Activity in v1.0 — only the compact Island states.
- UX-DI-04: Dynamic Island animations use system-provided morphing transitions. Piqd does not implement custom Island shape animations — the system handles this. Content inside the Island transitions with a 300ms crossfade.
- UX-DI-05: Dynamic Island content is always legible. Minimum text size inside the Island: 11pt. No text that wraps or truncates — Island copy must be written to fit the compact width (~126pt on standard, ~160pt on Pro Max).
- UX-DI-06: The Dynamic Island must not be covered by any Piqd UI element at any time. The safe area top inset (59pt or 62pt depending on device) guarantees this when respected — see UX-LAYOUT-02.

### 3.2 Piqd Dynamic Island States

Three states are defined for v1.0. Each has a compact (default) and expanded (long-press) presentation.

---

#### State 1 — Sequence Capture in Progress

**Trigger:** User taps shutter in Sequence format. Fires for the 3-second capture window.

**Purpose:** Lets the user glance up and confirm the sequence is running without looking at the viewfinder. Critical for Snap Mode where the user may be watching the subject, not the phone.

**Compact presentation:**
```
┌──[●●●●●●]──────────────────────┐
│  6 dots, filling left to right  │
│  one dot fills every 333ms      │
└─────────────────────────────────┘
```
- Left side: 6 small dots (●○○○○○ → ●●○○○○ → ●●●○○○ etc.)
- Right side: elapsed time "1.3s" in monospaced type, counting up
- Background: Piqd coral accent, semi-transparent
- No text label — the dots are self-explanatory

**Expanded (long-press, rarely used):**
- Same 6 dots, larger
- "Sequence recording — tap to cancel" label
- Cancels the sequence if tapped

**Dismisses:** Automatically when 6th frame captures. Island returns to system default.

---

#### State 2 — Roll Mode Unlock Imminent (9 PM approach)

**Trigger:** Within 30 minutes of the 9 PM unlock time, if the user has at least 1 asset in today's Roll.

**Purpose:** Ambient reminder that the ritual is approaching. Not urgent — atmospheric. The Island becomes a quiet clock face counting toward the moment.

**Compact presentation:**
```
┌──[◐ 9PM]────────────────────────┐
│  Half-moon icon + "9PM" label    │
│  icon slowly fills as time passes│
└─────────────────────────────────┘
```
- Left: a small circular fill indicator that progresses from empty to full as 9 PM approaches. At 30min before: 0% fill. At 9 PM: 100% fill.
- Right: "9PM" in monospaced type
- Background: Roll Mode warm amber accent, very low opacity (barely visible)
- The fill animation is so slow it is not perceived as animation — it simply looks different each time the user glances

**Expanded (long-press):**
- "Your Roll unlocks at 9:00 PM — X shots in today's Roll"
- No action button — informational only

**Dismisses:** At 9 PM when the unlock begins. Replaced by State 3.

---

#### State 3 — Roll Unlock in Progress

**Trigger:** At 9 PM unlock time. StoryEngine is assembling the Roll and uploading to iCloud.

**Purpose:** Communicates that something is happening with the Roll — even if the app is backgrounded. The user does not need to open Piqd. The Island tells them the Roll is developing.

**Compact presentation:**
```
┌──[≋ Developing…]────────────────┐
│  Film-strip wave icon + label    │
│  subtle shimmer animation        │
└─────────────────────────────────┘
```
- Left: a small animated film-strip or wave icon (subtle shimmer, 2s loop)
- Right: "Developing…" in geometric sans-serif
- Background: Roll Mode warm amber, slightly higher opacity than State 2
- The word "Developing" is intentional brand language — not "Processing" or "Uploading"

**Expanded (long-press):**
- "Your Roll is developing — we'll notify your circle when it's ready"
- No action button

**Transitions to:** Standard APNs notification when upload completes and friends are notified. Island returns to system default after delivery confirms.

**Dismisses:** When iCloud upload confirms and APNs group ping fires. If upload fails (no connectivity), Island changes text to "Roll queued — will deliver when connected." Stays visible until next delivery attempt succeeds.

---

#### State 4 — Snap Mode Pending Delivery (offline recipient)

**Trigger:** User sends a Snap to a friend who is offline. The asset is held locally pending retrieval.

**Purpose:** Communicates that a sent Snap is pending — without a notification badge or in-app indicator visible when the camera is open.

**Compact presentation:**
```
┌──[→ Jiyeon]─────────────────────┐
│  Arrow icon + recipient name     │
└─────────────────────────────────┘
```
- Left: outbound arrow icon
- Right: recipient first name (truncated at 8 chars if needed)
- Background: Piqd coral, low opacity
- If multiple pending recipients: "→ 3 pending" instead of a name

**Expanded (long-press):**
- Lists pending recipients with individual status
- "Tap to cancel send" action for each

**Dismisses:** When recipient comes online and retrieves the asset. Instant dismiss — no animation, Island returns to default.

### 3.3 Dynamic Island — What Piqd Does NOT Use It For

- Live Photo capture progress — too fast and too minor to warrant Island use
- Zoom level indicator — belongs in viewfinder chrome (Layer 1)
- Mode indicator — belongs in the persistent mode pill at the bottom
- Film counter — belongs in viewfinder chrome (Roll Mode)
- Any error state that requires user action — errors go to a banner or in-app state, never the Island
- Marketing or promotional content — never

### 3.4 Dynamic Island Layout Constraints

When a Piqd Live Activity is active in the Dynamic Island, the Island expands downward. The viewfinder safe area top inset already accounts for the Island physical size. However, the expanded Island can extend further down — up to approximately 84pt from the screen top on standard devices, up to 90pt on Pro devices.

- UX-DI-LAYOUT-01: When any Piqd Dynamic Island state is active and expanded, the film counter (Roll Mode) must reposition downward by `expandedIslandBottom − safeAreaTop` to avoid overlap. This repositioning animates with the Island expansion (300ms system spring).
- UX-DI-LAYOUT-02: No other Piqd viewfinder chrome is affected by Island expansion — only the film counter in its UX-LAYOUT-10 position could potentially conflict on standard devices when expanded.
- UX-DI-LAYOUT-03: In compact (non-expanded) Island state, no Piqd chrome repositioning is needed. The safeAreaTop inset (59pt or 62pt) provides adequate clearance.

---

## Part 4 — Requirements Traceability

| UI/UX Requirement | PRD Reference | SRS Reference | Priority | v1.1 Status |
|-------------------|--------------|---------------|----------|-------------|
| UX-GLASS-01–05 | FR-MODE-03 | §4.4.3 | P1 | Unchanged |
| UX-AI-01–06 | FR-PSS-VIBE-01–06 | §5.1–5.2 | P1 | Unchanged |
| UX-MOTION-01–08 | FR-MODE-02, FR-SNAP-SEQ-03 | §11.1 | P1 | Updated: DI timing added |
| UX-NAV-01–09 | FR-SNAP-VF-01, FR-ROLL-VF-01 | §7.1 | P1 | NAV-08, NAV-09 new |
| UX-CALM-01–07 | FR-ROLL-UNLOCK-07 | §6.5 | P1 | Unchanged |
| UX-NARR-01–04 | FR-ARCHIVE-01–03 | §10 | P2 | Unchanged |
| UX-IMPERF-01–07 | FR-ROLL-VF-01–02 | §4.4.3 | P1 | Unchanged |
| UX-SPEED-01–05 | FR-PSS-LAG-01–05 | §11.1 | P1 | Unchanged |
| UX-LAYOUT-01–18 | FR-MODE-03, FR-SNAP-VF-01 | §11.3 | P1 | All new in v1.1 |
| UX-2SCR-01–04 | FR-MODE-03 | §4.1 | P1 | Unchanged |
| UX-ONBOARD-01–04 | — | — | P2 | Unchanged |
| UX-TYPE-01–04 | — | — | P2 | TYPE-03 updated (references LAYOUT-11) |
| UX-COLOR-01–05 | — | — | P1 | Unchanged |
| UX-ICON-01–04 | — | — | P2 | Unchanged |
| UX-A11Y-01–08 | — | — | P1 | A11Y-08 new (DI contrast) |
| UX-STATE-01–06 | FR-SNAP-SEQ-05, FR-ROLL-COUNTER-03–04 | — | P1 | STATE-06 new |
| UX-EMPTY-01–03 | — | — | P3 | Unchanged |
| UX-PRIV-01–05 | — | §10 | P1 | Unchanged |
| UX-DI-01–06 | FR-ROLL-UNLOCK-04 | §4.4.6, §6.3 | P1 | All new in v1.1 |
| UX-DI-LAYOUT-01–03 | — | §11.3 | P1 | All new in v1.1 |

---

## Part 5 — Open Design Decisions (Updated)

| # | Decision | Options | Impact | Status |
|---|----------|---------|--------|--------|
| 1 | Mode indicator symbol for Snap vs Roll | Lightning bolt vs arrow vs abstract glyph | Identity, iconography system | Open |
| 2 | Snap Mode accent color | Electric blue, warm white, signal yellow | Brand identity | Open |
| 3 | Roll Mode shutter button texture | Matte circle, leather texture, film-stock circle | Roll Mode identity | Open |
| 4 | Unlock reveal sound design | Darkroom ambient, film advance mechanical, silence + haptic only | Emotional tone of the ritual | Open |
| 5 | Film counter font | Custom monospace, SF Mono, custom bitmap font | Analog identity depth | Open |
| 6 | Snap Mode Sequence preview layout | **Resolved: full bleed viewfinder + floating 30% strip overlay** | — | Resolved |
| 7 | Light leak asset style | Photographic scan of real film, procedural CIFilter, illustrated | Authenticity vs scalability | Open |
| 8 | Friend avatar style in circle selector | Initials circle, photo, abstract shape | Privacy vs social warmth | Open |
| 9 | Dynamic Island State 1 dot style | Filled circles, film perforations, simple tick marks | Brand identity in Island | Open |
| 10 | Dynamic Island State 3 "Developing" icon | Film strip, wave form, abstract shimmer | Roll Mode identity in Island | Open |

---

## Appendix A — Formula Quick Reference

For implementation use. All formulas produce results in points.

```swift
// Screen constants (read from UIScreen / UIApplication)
let W = screenWidth          // 390–440pt
let H = screenHeight         // 844–956pt
let safeTop = safeAreaTop    // 59pt or 62pt
let safeBot = safeAreaBottom // 34pt (all devices)
let safeH = H - safeTop - safeBot  // 751–860pt

// Shutter button
let shutterDiameter = min(W * 0.185, 80)     // ~72–80pt
let shutterCenterY = H - safeBot - (safeBot * 1.5)  // above home indicator

// Film counter font size
let counterFontSize = max(15, W * 0.038)     // ~15–17pt

// Zoom pill / ratio indicator vertical position
let zoomPillY = safeTop + safeH * 0.88

// Film counter position
let counterY = safeTop + safeH * 0.04       // top of safe area, below Island

// Mode indicator pill position
let modePillY = H - safeBot - 28 - 8        // 8pt above home indicator zone

// Sequence strip preview height
let stripH = safeH * 0.28

// Bottom sheet max height
let sheetMaxH = safeH * 0.75

// Format selector vertical position (relative to shutter)
let formatSelectorY = shutterCenterY - (shutterDiameter / 2) - 16 - formatSelectorHeight

// Flip button position
let flipX = W - (W * 0.06) - 22            // touch target center x
let flipY = safeTop + (safeH * 0.04)       // touch target center y
```

---

*— End of Document — Piqd UI/UX Requirements v1.1 · PRD: piqd_PRD_v1.0.md · April 2026 —*
