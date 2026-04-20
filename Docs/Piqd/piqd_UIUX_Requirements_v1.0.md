# Piqd

## UI/UX Requirements Specification

**Gen Z Camera App · Two Modes · One Emotional Truth**

Version 1.0 | April 2026 | Confidential

PRD reference: piqd_PRD_v1.0.md | SRS reference: piqd_SRS_v1.0.md

Author: Han Wook Cho | hwcho@gmail.com

---

## Document Control — v1.0

This document defines the UI/UX requirements for Piqd. It bridges the PRD (what the product does) and the UI/UX Specification (how it looks and behaves in detail). It is written for design leads, interaction designers, and motion designers before detailed screen design begins.

Requirements are grouped into two layers:

**Layer 1 — 2026 Design Trend Alignment:** Requirements derived from the current design landscape (Orizon 2026 trends report, Artonest 2026 analysis, and cross-referenced sources). Each trend is evaluated for Piqd relevance and translated into specific requirements or explicit rejections with rationale.

**Layer 2 — Piqd-Specific Requirements:** Requirements that emerge from Piqd's own product principles, modes, and Gen Z audience. These are the non-negotiables that override trend alignment where they conflict.

---

## Part 1 — 2026 Design Trend Alignment

### Trend 1 — Liquid Glass and Adaptive Transparency

**Source:** Orizon (Trend 1) — iOS 26 Liquid Glass introduces interfaces as living materials: translucency, depth, micro-refraction, and surfaces that respond to motion and light.

**Piqd relevance: Selective adoption.**

Liquid Glass is the design language of iOS 26, Piqd's platform. Ignoring it entirely would make Piqd feel out of place on the OS. However, full adoption conflicts with Piqd's analog-imperfect aesthetic — glass and translucency read as polished and digital, the opposite of Roll Mode's identity.

**Requirements:**

- UX-GLASS-01: Liquid Glass materials are used for system-layer UI only — navigation overlays, the mode indicator pill, the share sheet, and the circle selector. These elements feel native to iOS 26.
- UX-GLASS-02: The viewfinder surface — the primary canvas in both modes — uses no Liquid Glass. The viewfinder is raw, material-free. Nothing between the user and the frame.
- UX-GLASS-03: In Snap Mode, the shutter button and format selector use subtle translucency (iOS 26 system material) so they feel present but do not compete with the viewfinder content.
- UX-GLASS-04: In Roll Mode, the shutter button uses a matte, non-transparent surface. No glass. The Roll Mode UI intentionally rejects the digital polish of Liquid Glass — it is the analog counterpart.
- UX-GLASS-05: The unlock reveal screen (9 PM ritual) uses no Liquid Glass. It uses a warm, matte dark surface — like a darkroom developing tray.

**Rejected:** Micro-refraction effects on the viewfinder, Liquid Glass film counter, glass-style asset cards in the Film Archive. These conflict with the imperfect analog identity.

---

### Trend 2 — Ambient AI: Assistive Interfaces That Disappear

**Source:** Orizon (Trend 2), Artonest — AI stops being a button and becomes an invisible layer. Interfaces fill fields based on intent, predict next actions, surface context without prompts.

**Piqd relevance: High — but with strict restraint.**

The Vibe Hint, scene classifier, and subject guidance features already embody ambient AI. The risk is over-reach — AI that talks too much, shows too much, or makes decisions the user wanted to make. Gen Z reads heavy AI suggestion as condescending.

**Requirements:**

- UX-AI-01: All AI outputs in Piqd are ambient — they appear at the periphery, not the center of attention. No AI output ever occupies the center of the viewfinder.
- UX-AI-02: AI indicators use motion to communicate, not text. The Vibe Hint is a pulsing glyph, not a label. The invisible level is a line, not a message. Exceptions: subject guidance text ("Step back for the full vibe") is one deliberate, short-lived text hint only.
- UX-AI-03: No AI feature makes a decision on the user's behalf in a way that is visible or irreversible at capture time. AI informs — the user decides.
- UX-AI-04: AI indicators disappear automatically. No AI feature requires dismissal. If it needs a close button, it is not ambient — redesign it.
- UX-AI-05: The scene classifier (Vibe Hint) and subject guidance have explicit off toggles in settings. Users who find them distracting can disable them completely.
- UX-AI-06: In Roll Mode, all AI ambient hints are disabled. The aesthetic is fixed and intentional. AI interference in Roll Mode would undermine the "focus on the moment" philosophy.

---

### Trend 3 — Real-Time Personalization and Situational UX

**Source:** Orizon (Trend 3), Artonest, multiple sources — Interfaces adapt based on time of day, behavior patterns, gesture cadence. Thousands of micro-variations based on the moment.

**Piqd relevance: Mode-level personalization only.**

Full situational UX (the app's entire aesthetic morphing based on detected mood or Friday-night vibes) was explicitly evaluated and rejected in the previous feature review — it conflicts with the intentional mode-switch philosophy. The user chooses their mode deliberately. The app does not choose for them.

However, time-of-day adaptation at specific trigger points is appropriate and meaningful for Piqd.

**Requirements:**

- UX-PERS-01: The app does not auto-switch modes based on detected context. Mode is always a user-initiated gesture.
- UX-PERS-02: Time-of-day adaptation is limited to three moments: (a) at 9 PM, the Roll Mode UI shifts to "unlock imminent" state — the film counter glows, a subtle countdown appears; (b) at unlock, the reveal UI activates; (c) after midnight, the Roll counter resets with a brief "New roll loaded" animation.
- UX-PERS-03: The last-used film simulation preset persists across sessions. The app remembers the user's aesthetic preference without asking.
- UX-PERS-04: The circle selector pre-populates with the last-used friend selection. Sharing to the same people repeatedly should require zero configuration after the first time.
- UX-PERS-05: The mode the user was last in persists on cold launch. No mode reset on restart.

**Rejected:** Full adaptive UI that morphs between aesthetic themes based on detected mood or location. Rejected because it conflicts with Product Principle P2 (the mode is the message) and P3 (imperfection is the product).

---

### Trend 4 — Motion as Functional Cognitive Guide

**Source:** Orizon (Trend 4) — Motion in 2026 is shorter, lighter, purposeful. Directional motion teaches navigation. Micro-motion confirms commands. Elasticity calibrated to physical expectations. Motion stops being decoration and becomes a cognitive guide.

**Piqd relevance: Critical. This is the most directly applicable trend.**

Piqd's entire dual-mode identity depends on motion communicating the difference between modes. The mode switch, the shutter response, the sequence frame flash, the developing reveal — all of these are motion design problems first.

**Requirements:**

- UX-MOTION-01: Every motion in Piqd has a functional purpose. Purely decorative animations are not permitted.
- UX-MOTION-02: Motion duration budget by interaction type:
  - Mode switch: 150ms maximum (physical, decisive)
  - Shutter response feedback: 80ms (imperceptible but felt)
  - Sequence frame flash: 40ms per frame (subtle, rhythmic)
  - Bottom sheet (Sequence preview): 220ms ease-out
  - Roll unlock reveal (per asset): 400ms film-advance
  - Film counter decrement: 120ms tick
  - Navigation transitions: 280ms maximum
- UX-MOTION-03: Motion direction is meaningful. Snap Mode transitions move horizontally (fast, lateral, social). Roll Mode transitions move vertically (slow, falling, deliberate — like paper developing in a tray).
- UX-MOTION-04: The mode switch uses a directional swipe animation that physically "slides" the viewfinder aesthetic in. The grain overlay does not fade — it slides in from the direction of the swipe. This makes the mode switch feel like a physical object changing position.
- UX-MOTION-05: Micro-haptics accompany key motion moments: shutter tap (sharp), sequence frame (6 light pulses at 333ms), mode switch (single medium pulse), Roll unlock (slow, deep rumble).
- UX-MOTION-06: Easing curves:
  - Snap Mode interactions: spring easing (snappy, elastic — matches the reactive personality)
  - Roll Mode interactions: ease-out cubic (slow, deliberate, settling — matches the nostalgic personality)
  - System overlays (sheet, selector): iOS 26 default spring
- UX-MOTION-07: All animations respect iOS Reduce Motion accessibility setting. When Reduce Motion is on: crossfade replaces slide transitions, grain overlay appears instantly, reveal sequence is static. No feature becomes non-functional.
- UX-MOTION-08: The unlock reveal uses an organic, irregular cadence — not uniform timing. Some assets reveal faster, some slower. This mirrors the randomness of pulling prints from a developing tray. The irregularity is intentional and must be implemented with randomized per-asset delays (±80ms variance).

---

### Trend 5 — Multi-Modal Interfaces

**Source:** Orizon (Trend 5), Artonest — Touch, gesture, voice, and AI-driven input coexist. UI orchestrates multiple input methods gracefully.

**Piqd relevance: Gesture-focused, voice excluded.**

Piqd is a camera app — the primary interaction is physical (holding a phone, tapping a shutter). Voice input is inappropriate in a social capture context. However, gesture design is critical and goes beyond the standard tap/swipe.

**Requirements:**

- UX-MULTI-01: The primary input model is gesture-first. Every core action in Piqd is reachable with one hand and one thumb without repositioning grip.
- UX-MULTI-02: Gesture vocabulary for Piqd:
  - Horizontal swipe on viewfinder: mode switch
  - Tap: Sequence capture (Snap) / Still capture (Roll)
  - Hold: Clip recording (Snap only)
  - Edge swipe left/right: Film simulation preset change (Roll only)
  - Swipe up on viewfinder: Circle selector (Snap) / Roll counter detail (Roll)
  - Pinch: Zoom (both modes)
- UX-MULTI-03: Gesture conflict resolution: the mode switch swipe must be disambiguated from the iOS back gesture and Control Center. The mode switch activates only from the center 60% of the viewfinder width. The left and right 20% edges are dead zones for the mode gesture, preventing conflict.
- UX-MULTI-04: No voice input in v1.0. Excluded because the primary use context (social events, concerts, nights out) makes voice commands impractical and socially awkward.
- UX-MULTI-05: Haptic feedback is a co-equal input channel to visual feedback. Every meaningful interaction has a haptic — not as confirmation after the fact, but as part of the interaction itself.

**Rejected:** Voice shortcuts, AR gesture flows. Out of scope for v1.0.

---

### Trend 6 — Ultra-Contextual Navigation (UI That Shrinks Itself)

**Source:** Orizon (Trend 6) — Toolbars dissolve when not needed. Menus appear at the moment of action. Navigation becomes something you feel rather than see.

**Piqd relevance: Very high. This is the camera's natural state.**

The viewfinder should be the entire screen. Navigation chrome should not exist as a persistent element — it should appear only when the user needs it and retreat immediately.

**Requirements:**

- UX-NAV-01: The viewfinder occupies 100% of the screen in both modes. There is no persistent navigation bar, tab bar, or toolbar.
- UX-NAV-02: The only persistent UI elements during capture are: the shutter button, the mode indicator (minimal pill), and the film counter (Roll Mode only). Everything else retreats.
- UX-NAV-03: Secondary controls (format selector, film simulation preset, circle selector) appear only on gesture invocation and retreat after a 3-second idle timeout or on action completion.
- UX-NAV-04: The Film Archive is accessed by a single swipe up from the bottom of the viewfinder. It slides in as a sheet and does not navigate away from the camera. Returning to capture is a swipe down.
- UX-NAV-05: The circle selector (share action) slides up from the bottom as a compact sheet — it does not leave the capture context. The user can abandon the share by swiping it down.
- UX-NAV-06: Settings are accessed via a long-press on the mode indicator pill only. This is a deliberate friction point — settings should not be easy to accidentally open. The long-press invocation means only intentional users reach settings.
- UX-NAV-07: There is no hamburger menu, no sidebar, no tab bar. Navigation is entirely gesture and context-driven.

---

### Trend 7 — AI-Assisted Creative Tools

**Source:** Orizon (Trend 7) — AI enhances creative flow without replacing creative judgment. Real-time layout suggestions, color coaching, motion assistance based on intent.

**Piqd relevance: Narrow application only.**

StoryEngine's hero asset selection, Moving Still candidate selection, and Moment clustering are AI-assisted creative decisions that happen post-capture, not during. These should be presented to the user as creative suggestions, not automatic outputs.

**Requirements:**

- UX-AI-CREATIVE-01: The hero asset selected by StoryEngine is presented as a suggestion at the Film Archive level — the user can replace it with a tap. The AI pick is the default; user override is always available.
- UX-AI-CREATIVE-02: Moving Still conversion (v2.0) should be presented as a reveal-moment surprise — not a setting the user configures. The AI made a creative choice; the user discovers it.
- UX-AI-CREATIVE-03: Film simulation preset selection is entirely human. No AI suggests or changes presets. The user's aesthetic choice is always respected.
- UX-AI-CREATIVE-04: Piqd does not show AI confidence scores, processing indicators, or "AI-enhanced" labels to the user. AI is invisible — the output speaks for itself.

---

### Trend 8 — Calm UX: Interfaces Designed to Reduce Anxiety

**Source:** Orizon (Trend 8), multiple sources — Fewer choices, gentle transitions, progressive disclosure, subdued palettes, predictable behavior. Calm design as competitive advantage.

**Piqd relevance: Extremely high. This is Piqd's emotional posture.**

Roll Mode's core promise — "focus on the experience, not the screen" — is the definition of calm UX. Snap Mode, while fast, should not feel anxious. Speed and calm are not opposites. A calm interface can be fast. An anxious interface cannot be calm.

**Requirements:**

- UX-CALM-01: Piqd has no notification badges on in-app UI elements. No red dots, no unread counts, no "tap here" urgency cues within the app experience.
- UX-CALM-02: The only time-pressure moment in the app is the film counter approaching 0. This pressure is intentional (scarcity drives intention). All other interactions are pressure-free.
- UX-CALM-03: Error states use calm language. No alarming icons, no red warning modals for non-critical errors. A failed share attempt: "Couldn't reach [name] — we'll try again." A failed iCloud upload: "Your Roll is queued for delivery."
- UX-CALM-04: Progressive disclosure everywhere. The first time a user opens Piqd: only the viewfinder and the shutter. Mode switch, formats, and circle selector are discoverable through exploration, not introduced all at once.
- UX-CALM-05: The Film Archive is not a feed. There is no infinite scroll, no algorithmic surfacing, no "you might also like." It is a personal archive in reverse chronological order. Browsing it should feel like opening a physical photo album.
- UX-CALM-06: Color palette is intentionally subdued in UI chrome. Interface colors do not compete with the viewfinder or the photos. The photos are the color — the UI is the frame.
- UX-CALM-07: The unlock reveal is calm, not celebratory. No confetti, no celebration animations, no "You took 24 photos today!" gamification language. The reveal is quiet and intimate — like developing photos in a darkroom, not opening a prize.

---

### Trend 9 — Narrative Interfaces (Post-Dashboard Era)

**Source:** Orizon (Trend 9) — Users want synthesis, not widgets. Smart timelines, narrative summaries, "here's what changed today." Dashboards become stories.

**Piqd relevance: Direct application to the Film Archive and unlock reveal.**

The Film Archive is not a grid of thumbnails — it is a narrative of moments. The unlock reveal is not a photo viewer — it is a story unfolding.

**Requirements:**

- UX-NARR-01: Each Moment in the Film Archive is presented as a narrative card: hero image, Moment label (e.g. "Rainy Walk · April 14 · Shibuya"), friend avatars who received it, and a subtle ambient detail (day of week, weather condition from AmbientMetadata). Not a thumbnail grid.
- UX-NARR-02: The unlock reveal sequence is a narrative, not a gallery. Assets reveal one by one in the order StoryEngine assembled them — not chronologically, but narratively (arc from opening context to emotional peak to quiet ending). The sequence has a beginning, middle, and end.
- UX-NARR-03: Within the Film Archive Moment view, assets are sequenced narratively (StoryEngine order), not in capture order. The user can switch to capture order if preferred.
- UX-NARR-04: The Film Archive has no statistics, no "you took X photos this month" dashboards, no streak counters, no gamification metrics. The archive is the story. Data is not the story.

---

### Trend 10 — Anti-Perfect UI: Interfaces That Embrace Imperfection

**Source:** Orizon (Trend 10) — Users trust interfaces that feel human. Playful micro-latency, organic motion curves, hand-drawn textures, imperfect shadows. Not everything needs to be pristine.

**Piqd relevance: This is the single most aligned trend. It is Piqd's brand.**

Product Principle P3 (imperfection is the product) exists for exactly this reason. The grain, the light leak, the drifting noise, the analog shutter sound — all of this is the interface deliberately not being clean. Piqd should be the most imperfect-feeling camera app on the App Store. That is the differentiator.

**Requirements:**

- UX-IMPERF-01: The Roll Mode viewfinder grain drifts per-frame. It must never look static, uniform, or clean. The grain is alive.
- UX-IMPERF-02: The light leak overlay position, intensity, and corner placement are randomized per Roll Mode session. No two sessions look identical. This is not a bug — it is the design.
- UX-IMPERF-03: The unlock reveal sequence uses organic, irregular timing (per UX-MOTION-08). The irregularity is required — do not smooth it into a uniform cadence.
- UX-IMPERF-04: The analog shutter sound in Roll Mode is not a clean digital click. It is a slightly imprecise, warm mechanical sound — with a small amount of room tone and natural variation. The same sound is not played identically twice (subtle pitch/speed variation ±3%).
- UX-IMPERF-05: The film simulation presets are not mathematically precise color grades. They are intentionally approximate emulations of film stock character — warmth that shifts slightly, grain density that varies, colors that are not quite accurate. Precision is not the goal.
- UX-IMPERF-06: Motion curves in Roll Mode use slightly asymmetric easing — not mathematically perfect ease-in-out. The settle at the end of a Roll Mode transition should have a single imperceptible overshoot, like a physical object coming to rest. This applies to the film counter tick, asset reveal, and mode switch.
- UX-IMPERF-07: The Snap Mode UI, by contrast, is clean and precise. Snap's imperfection is in the content (fast, unplanned) not in the interface. The Snap UI is tight, fast, and predictable. The contrast between Snap's clean UI and Roll's imperfect UI is intentional and must be maintained.

---

## Part 2 — Piqd-Specific UI/UX Requirements

These requirements emerge from Piqd's product principles and Gen Z audience context. They are not derived from trend analysis — they are derived from the product itself.

### 2.1 Speed and Responsiveness

- UX-SPEED-01: The shutter button must respond within 100ms of tap in Snap Mode. This is a hard requirement, not a guideline. If any UI update blocks this, the UI update loses.
- UX-SPEED-02: There is no splash screen. The app opens directly to the viewfinder. The camera is live within 1.5 seconds of launch.
- UX-SPEED-03: The viewfinder never shows a "loading" or "initializing" state after the first launch. Camera access is pre-authorized at onboarding.
- UX-SPEED-04: Format switching (Snap: Sequence → Clip → Dual) happens within 80ms. There is no transition animation for format changes — the format is available instantly.
- UX-SPEED-05: The circle selector opens within 100ms of the swipe-up gesture completing. Friend avatars are pre-loaded — no spinner.

### 2.2 The Two-Screen Philosophy

Piqd is effectively two apps with one shared vault. The visual design must make this duality clear without requiring the user to read any labels.

- UX-2SCR-01: A user who has never seen Piqd before must be able to identify which mode they are in within 1 second of looking at the viewfinder — from the aesthetic alone, without reading any text.
- UX-2SCR-02: The Snap Mode viewfinder and Roll Mode viewfinder must look different enough that switching modes feels like a physical change. The grain overlay alone is not sufficient — the entire UI chrome, color temperature, and shutter button design must differ between modes.
- UX-2SCR-03: Snap Mode UI language: clean, geometric, bright, high-contrast, fast. Roll Mode UI language: warm, organic, low-contrast, imperfect, slow.
- UX-2SCR-04: The mode indicator pill displays a single character or symbol per mode — not a text label. Text labels ("Snap" / "Roll") are used in onboarding only. In-app, the mode indicator is iconic, not textual.

### 2.3 Onboarding

- UX-ONBOARD-01: Onboarding is a maximum of 4 screens. Each screen introduces one concept only.
  - Screen 1: Two modes exist. (The only screen with mode names in text.)
  - Screen 2: Snap — tap to capture, swipe to share.
  - Screen 3: Roll — shoot all day, open at 9.
  - Screen 4: Invite your first friend (QR or link).
- UX-ONBOARD-02: Onboarding is skippable after Screen 1. A user who understands the concept should not be forced through feature tutorials.
- UX-ONBOARD-03: Camera and notification permissions are requested in context — camera at the moment the viewfinder first appears, notifications at the moment the user takes their first Roll Mode photo. Not batched at launch.
- UX-ONBOARD-04: Onboarding uses the actual app UI, not illustrated mockups or custom onboarding screens. The user sees and uses the real interface from the first interaction.

### 2.4 Typography

- UX-TYPE-01: Two typefaces maximum in the entire app. A geometric sans-serif for all UI chrome and labels. A monospaced typeface for the film counter and technical indicators only — evoking a camera LCD display.
- UX-TYPE-02: No decorative or display typography in the capture experience. Typography in the viewfinder and Film Archive must be restrained — the photos are the visual content, not the type.
- UX-TYPE-03: The film counter uses the monospace typeface at a size large enough to read at a glance without squinting, in direct sunlight. Minimum contrast ratio 4.5:1 against both light and dark viewfinder backgrounds.
- UX-TYPE-04: Moment labels in the Film Archive use the geometric sans-serif at a weight that reads as a caption, not a headline. Moments are named, not titled.

### 2.5 Color

- UX-COLOR-01: The UI chrome color palette has exactly two modes — one for each capture mode.
  - Snap Mode chrome: near-white or very light gray tints. Clean, neutral, modern.
  - Roll Mode chrome: warm near-black or deep amber-black tints. Dark, warm, analog.
- UX-COLOR-02: Accent colors are used sparingly — one accent per mode:
  - Snap accent: a single clean, bright color for the shutter button and active states only. Suggest electric blue or clean white.
  - Roll accent: a warm amber or deep red for the film counter and active states only. Evokes a darkroom safelight.
- UX-COLOR-03: The Film Archive uses a neutral palette that does not compete with the photos. Near-white backgrounds in light mode, near-black in dark mode. No colored surfaces in the archive.
- UX-COLOR-04: Both modes support iOS dark mode and light mode. The Snap Mode light variant is the primary design target. The Roll Mode dark variant is the primary design target (Roll Mode naturally reads as a nighttime experience).
- UX-COLOR-05: No gradients in UI chrome. Gradients are reserved for the viewfinder grain overlay and light leak effects only.

### 2.6 Iconography

- UX-ICON-01: Icons are minimal, line-based, and consistent weight. No filled icons except for the active/selected state of the mode indicator.
- UX-ICON-02: The shutter button is the only element that differs significantly between modes:
  - Snap Mode shutter: a clean circle with a thin ring — precise, digital.
  - Roll Mode shutter: a slightly imperfect circle — thicker, with a texture or weight that implies a physical button.
- UX-ICON-03: The film counter icon is a physical film-roll silhouette — immediately recognizable as a film canister or roll. Not an abstract progress indicator.
- UX-ICON-04: There are no social platform icons, share-sheet logos, or third-party brand elements within the Piqd UI. Sharing is Piqd-native — no Instagram, TikTok, or social export in the capture flow.

### 2.7 Accessibility

- UX-A11Y-01: All interactive elements have a minimum touch target of 44×44pt (iOS HIG standard).
- UX-A11Y-02: The shutter button has a minimum touch target of 72×72pt. It must be impossible to miss in a reactive capture moment.
- UX-A11Y-03: All animations respect iOS Reduce Motion. No feature becomes non-functional when Reduce Motion is enabled.
- UX-A11Y-04: VoiceOver labels are defined for all interactive elements. The film counter reads "14 shots remaining." The mode indicator reads "Snap Mode active" or "Roll Mode active."
- UX-A11Y-05: The invisible level and subject guidance text are compatible with VoiceOver — the level announces "Camera level" when horizontal, the guidance announces the tip text.
- UX-A11Y-06: Color is never the sole differentiator for any state. The Snap/Roll mode distinction uses both color and form — not color alone.
- UX-A11Y-07: Minimum contrast ratios: 4.5:1 for all body text, 3:1 for large text and UI components (WCAG AA standard).

### 2.8 Interaction States

Every interactive element must have defined states for: default, pressed, disabled, and loading (where applicable).

- UX-STATE-01: The shutter button pressed state uses a scale-down transform (0.92×) with the haptic pulse. The press state is felt before it is seen.
- UX-STATE-02: The shutter button disabled state (Roll Mode, counter = 0) is visually dim (40% opacity) and does not respond to tap. No error feedback — the film counter state is the explanation.
- UX-STATE-03: The share button disabled state (Sequence, shareReady = false) shows a subtle progress indicator — a thin animated arc around the send button, indicating assembly in progress. Maximum 2 seconds.
- UX-STATE-04: The circle selector friend avatars show a subtle pulse when a friend is currently in proximity (MultipeerConnectivity detected them nearby). This is ambient information — not a notification.
- UX-STATE-05: The unlock countdown state (approaching 9 PM within 30 minutes) changes the film counter color to the Roll accent and adds a very subtle ambient pulse to the counter. Not urgent — atmospheric.

### 2.9 Empty States

- UX-EMPTY-01: Empty Film Archive: "Your first Roll unlocks at 9. Start shooting." — with the Roll Mode viewfinder visible behind the message as a live preview. The empty state teaches the product.
- UX-EMPTY-02: No Rolls today (Roll counter not yet started): no empty state message. The viewfinder is present and ready. The absence of a counter communicates that no Roll has started.
- UX-EMPTY-03: Received Roll that has not been opened yet: a soft glow on the friend's avatar in the Film Archive — not a badge count, not a red dot. A warm, inviting glow. The Roll is waiting, not demanding.

### 2.10 Privacy UX

Privacy is a product principle (P5), not just a legal requirement. The UI must communicate privacy in a way that Gen Z finds credible — not through policy text, but through visible behavior.

- UX-PRIV-01: The app shows no data permission requests beyond Camera, Microphone, Location, Notifications, and iCloud at onboarding. No contacts access, no photo library access by default, no tracking permission.
- UX-PRIV-02: When a Snap asset expires, the recipient sees a gentle indicator: "Piqd has left the chat." — not a technical error or a broken image state. The disappearance is acknowledged, not hidden.
- UX-PRIV-03: The iCloud upload progress during Roll unlock is shown as a simple "Delivering your Roll…" indicator — no bytes transferred, no technical language. The user does not need to know about iCloud. They need to know the Roll is on its way.
- UX-PRIV-04: There is no analytics dashboard, no "your data" section, no ad targeting preferences panel. Piqd collects no behavioral data for third parties. The absence of these screens is itself a privacy statement.
- UX-PRIV-05: The trusted circle list has no "mutual friends," "suggested friends," or "people you may know" section. The list contains only people the user personally invited. The boundary is visible and respected.

---

## Part 3 — Requirements Traceability

| UI/UX Requirement | PRD Reference | SRS Reference | Priority |
|-------------------|--------------|---------------|----------|
| UX-GLASS-01–05 | FR-MODE-03 | §4.4.3 | P1 |
| UX-AI-01–06 | FR-PSS-VIBE-01–06, FR-PSS-GUIDE-01–05 | §5.1–5.2 | P1 |
| UX-MOTION-01–08 | FR-MODE-02, FR-SNAP-SEQ-03 | §11.1 | P1 |
| UX-NAV-01–07 | FR-SNAP-VF-01, FR-ROLL-VF-01 | §7.1 |P1 |
| UX-CALM-01–07 | FR-ROLL-UNLOCK-07 | §6.5 | P1 |
| UX-NARR-01–04 | FR-ARCHIVE-01–03 | §10 | P2 |
| UX-IMPERF-01–07 | FR-ROLL-VF-01–02, FR-ROLL-STILL-05 | §4.4.3 | P1 |
| UX-SPEED-01–05 | FR-PSS-LAG-01–05 | §11.1 | P1 |
| UX-2SCR-01–04 | FR-MODE-03 | §4.1 | P1 |
| UX-ONBOARD-01–04 | — | — | P2 |
| UX-TYPE-01–04 | — | — | P2 |
| UX-COLOR-01–05 | — | — | P1 |
| UX-ICON-01–04 | — | — | P2 |
| UX-A11Y-01–07 | — | — | P1 |
| UX-STATE-01–05 | FR-SNAP-SEQ-05, FR-ROLL-COUNTER-03–04 | — | P1 |
| UX-EMPTY-01–03 | — | — | P3 |
| UX-PRIV-01–05 | — | §10 | P1 |

---

## Part 4 — Open Design Decisions

These are decisions that must be resolved before the UI/UX Spec v1.0 is written. They require product and design alignment.

| # | Decision | Options | Impact |
|---|----------|---------|--------|
| 1 | Mode indicator symbol for Snap vs Roll | Lightning bolt vs arrow vs abstract glyph | Identity, iconography system |
| 2 | Snap Mode accent color | Electric blue, warm white, signal yellow | Brand identity |
| 3 | Roll Mode shutter button texture | Matte circle, leather texture, film-stock circle | Roll Mode identity |
| 4 | Unlock reveal sound design | Darkroom ambient, film advance mechanical, silence + haptic only | Emotional tone of the ritual |
| 5 | Film counter font | Custom monospace, SF Mono, custom bitmap font | Analog identity depth |
| 6 | Snap Mode bottom sheet height for Sequence preview | 30% screen, 50% screen, full bleed | Usability vs immersion |
| 7 | Light leak asset style | Photographic scan of real film, procedural CIFilter, illustrated | Authenticity vs scalability |
| 8 | Friend avatar style in circle selector | Initials circle, photo, abstract shape | Privacy vs social warmth |

---

*— End of Document — Piqd UI/UX Requirements v1.0 · PRD: piqd_PRD_v1.0.md · April 2026 —*
