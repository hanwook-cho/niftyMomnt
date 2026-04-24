# Piqd

## UI/UX Specification

**Gen Z Camera App · Two Modes · One Emotional Truth**

Version 1.0 | April 2026 | Confidential

Requirements ref: piqd_UIUX_Requirements_v1.1.md
PRD ref: piqd_PRD_v1.0.md
SRS ref: piqd_SRS_v1.0.md

Author: Han Wook Cho | hwcho@gmail.com

---

## Document Control — v1.0

This document is the authoritative specification for Piqd's visual design, interaction behavior, component library, copy, and screen-by-screen layout. It is written for visual designers producing mockups, motion designers specifying animations, and iOS engineers implementing the Presentation layer.

**What this document defines:**
- Design tokens (color, typography, spacing, motion)
- Component library — every reusable UI element
- Screen specifications — every screen and state
- Copy — every user-facing string
- Dynamic Island specifications
- Adaptive layout implementation per device

**What this document does not define:**
- Architecture or engineering implementation (see SRS v1.0)
- Feature behavior or acceptance criteria (see PRD v1.0)
- Layout formulas (see UX Requirements v1.1 Appendix A)

**Document structure:**
1. Design Tokens
2. Component Library
3. Screens — Snap Mode
4. Screens — Roll Mode
5. Screens — Shared / System
6. Film Archive
7. Onboarding
8. Settings
9. Copy Reference
10. Motion Reference
11. Dynamic Island Reference
12. Adaptive Layout Validation

---

## 1. Design Tokens

All tokens are defined in Swift as a `PiqdTokens` enum and as a Figma token set. No hardcoded values appear anywhere in the codebase or design files — only token references.

### 1.1 Color Tokens

#### Brand colors

```swift
// Snap Mode accent
PiqdTokens.Color.snapYellow        // #F5C420  — signal yellow, warm-leaning
PiqdTokens.Color.snapYellowDim     // #F5C420 at 40% opacity — disabled states

// Roll Mode accent
PiqdTokens.Color.rollAmber         // #C97B2A  — darkroom safelight amber
PiqdTokens.Color.rollAmberDim      // #C97B2A at 40% opacity — disabled states

// Video / recording
PiqdTokens.Color.recordRed         // #E5372A  — universal video record signal
PiqdTokens.Color.recordRedDim      // #E5372A at 40% opacity

// Neutral — Snap chrome
PiqdTokens.Color.snapChrome        // #FFFFFF at 92% opacity — shutter ring, pills
PiqdTokens.Color.snapChromeSubtle  // #FFFFFF at 55% opacity — secondary elements

// Neutral — Roll chrome
PiqdTokens.Color.rollChrome        // #1A1208  — warm near-black, all Roll chrome bg
PiqdTokens.Color.rollChromeSubtle  // #FFFFFF at 35% opacity — secondary Roll elements
```

#### Semantic colors (system adaptive)

```swift
PiqdTokens.Color.surface           // UIColor.systemBackground
PiqdTokens.Color.surfaceSecondary  // UIColor.secondarySystemBackground
PiqdTokens.Color.label             // UIColor.label
PiqdTokens.Color.labelSecondary    // UIColor.secondaryLabel
PiqdTokens.Color.labelTertiary     // UIColor.tertiaryLabel
PiqdTokens.Color.separator         // UIColor.separator
```

#### Viewfinder overlay colors

```swift
PiqdTokens.Color.grainOverlay      // #FFFFFF at 6–12% opacity (varies per frame)
PiqdTokens.Color.levelLine         // #FFFFFF at 70% opacity — invisible level indicator
PiqdTokens.Color.safeRenderBorder  // #FFFFFF at 15% opacity — Sequence crop guide
PiqdTokens.Color.lightLeak         // Generated procedurally — warm orange CIFilter output
```

#### Film Archive colors

```swift
PiqdTokens.Color.archiveBg         // #F7F5F0 light / #111008 dark
PiqdTokens.Color.archiveCard       // #FFFFFF light / #1C1A14 dark
PiqdTokens.Color.archiveLabel      // UIColor.label
PiqdTokens.Color.archiveSublabel   // UIColor.secondaryLabel
```

### 1.2 Typography Tokens

Two typefaces only. No exceptions.

```swift
// Primary — geometric sans-serif
// Recommended: DM Sans (open source, geometric, clean)
// Fallback: SF Pro Rounded (system)
PiqdTokens.Font.primary = "DMSans"

// Secondary — OCR-A style monospace (film counter, technical indicators only)
// Recommended: OCR-A (open source)
// Fallback: Courier New
PiqdTokens.Font.mono = "OCRA"
```

#### Type scale

All sizes in points. All adaptive — see UX-LAYOUT-11 for film counter exception.

```swift
// Primary font scale
PiqdTokens.TextStyle.displayLarge   // DMSans 28pt / 500 weight — unlock reveal title
PiqdTokens.TextStyle.title          // DMSans 20pt / 500 weight — archive Moment label
PiqdTokens.TextStyle.body           // DMSans 15pt / 400 weight — general body
PiqdTokens.TextStyle.caption        // DMSans 13pt / 400 weight — sublabels, timestamps
PiqdTokens.TextStyle.micro          // DMSans 11pt / 400 weight — Dynamic Island content

// Mono font scale (Roll Mode only)
PiqdTokens.TextStyle.counter        // OCRA, adaptive size per UX-LAYOUT-11 formula
                                    // min(max(15pt, screenWidth × 0.038), 17pt)
PiqdTokens.TextStyle.counterLabel   // OCRA 11pt / 400 — "left" suffix after number
```

### 1.3 Spacing Tokens

All spacing is relative. These tokens produce absolute values at runtime from screen dimensions.

```swift
// Fixed spacing (touch targets only — exempt from adaptive rule)
PiqdTokens.Spacing.touchMin     // 44pt — iOS HIG minimum
PiqdTokens.Spacing.touchShutter // 72pt — shutter touch target minimum

// Relative spacing tokens (resolved at runtime)
PiqdTokens.Spacing.xs    // screenWidth × 0.02   (~8pt on 390pt screen)
PiqdTokens.Spacing.sm    // screenWidth × 0.03   (~12pt)
PiqdTokens.Spacing.md    // screenWidth × 0.04   (~16pt)
PiqdTokens.Spacing.lg    // screenWidth × 0.06   (~24pt)
PiqdTokens.Spacing.xl    // screenWidth × 0.08   (~32pt)
```

### 1.4 Motion Tokens

All durations in milliseconds — device-independent.

```swift
PiqdTokens.Duration.instant      // 80ms   — shutter feedback, format switch
PiqdTokens.Duration.fast         // 150ms  — mode switch
PiqdTokens.Duration.standard     // 220ms  — sheet appear, Sequence preview
PiqdTokens.Duration.deliberate   // 280ms  — navigation transitions
PiqdTokens.Duration.filmAdvance  // 400ms  — Roll unlock per-asset reveal
PiqdTokens.Duration.systemDI     // 300ms  — Dynamic Island expand (match system)

// Easing
PiqdTokens.Easing.snap    // UISpringTimingParameters(mass:1, stiffness:400, damping:28)
PiqdTokens.Easing.roll    // CAMediaTimingFunction(controlPoints:0.25, 0.1, 0.0, 1.0)
                          // — ease-out cubic with imperceptible overshoot via layer animation
PiqdTokens.Easing.system  // UISpringTimingParameters(dampingRatio:0.85)
```

### 1.5 Shape Tokens

```swift
PiqdTokens.Shape.pillRadius     // 14pt — mode indicator pill, zoom pill, badges
PiqdTokens.Shape.sheetRadius    // 20pt — all bottom sheets (top corners only)
PiqdTokens.Shape.cardRadius     // 12pt — Film Archive Moment cards
PiqdTokens.Shape.thumbRadius    // 8pt  — asset thumbnails, tray items
PiqdTokens.Shape.shutterRing    // 3pt stroke width — Snap shutter ring
PiqdTokens.Shape.shutterRoll    // 2.5pt stroke width — Roll shutter outer ring
                                // 1pt stroke width — Roll shutter inner concentric ring
                                // 4pt center dot diameter — Roll shutter end cap dot
```

### 1.6 Haptic Tokens

```swift
PiqdTokens.Haptic.shutterSnap    // UIImpactFeedbackGenerator(.medium) — Snap shutter
PiqdTokens.Haptic.sequenceFrame  // UIImpactFeedbackGenerator(.light) — each of 6 frames
PiqdTokens.Haptic.modeSwitch     // UIImpactFeedbackGenerator(.rigid) — confirmation tap on mode switch sheet
PiqdTokens.Haptic.rollUnlock     // UINotificationFeedbackGenerator(.success) — 9PM unlock
PiqdTokens.Haptic.zoomOptical    // UIImpactFeedbackGenerator(.soft) — at 0.5×/1×/2× snap
PiqdTokens.Haptic.diExpand       // UIImpactFeedbackGenerator(.light) — Island expands
```

---

## 2. Component Library

Every reusable UI element is defined here. Components are composed from tokens only — no local color or size values.

### 2.1 Shutter Button

The most important component in Piqd. It has six states across two modes.

#### Snap Mode — Still / Sequence / Clip (photo/idle)

```
Visual:
  Outer touch target:  72pt × 72pt invisible
  Outer ring:          58pt diameter, 3pt stroke, PiqdTokens.Color.snapChrome
  Inner fill:          50pt diameter, PiqdTokens.Color.snapChrome at 20% opacity
  Center:              empty

State: pressed
  Scale transform:     0.92× (UIViewPropertyAnimator, 80ms, .snap easing)
  Haptic:              PiqdTokens.Haptic.shutterSnap

State: Sequence firing (6-frame window)
  Outer ring color:    PiqdTokens.Color.snapYellow
  Inner fill:          PiqdTokens.Color.snapYellow at 30% opacity
  Ring animates:       brief pulse at each frame (40ms scale to 1.04× then back)
  Haptic per frame:    PiqdTokens.Haptic.sequenceFrame
```

#### Snap Mode — Clip / Dual (video/recording)

```
Visual (idle, video selected):
  Outer ring:          58pt diameter, 3pt stroke, PiqdTokens.Color.recordRed
  Inner shape:         36pt × 36pt rounded square (rx=4pt), PiqdTokens.Color.recordRed
  Indicates:           hold to record

State: recording
  Inner shape:         20pt × 20pt rounded square — shrinks to indicate "tap to stop"
  Outer ring:          pulses slowly (scale 1.0→1.06→1.0, 1200ms loop)
  Duration indicator:  thin arc around outer ring filling clockwise, PiqdTokens.Color.recordRed
```

#### Roll Mode — Still (primary)

```
Visual:
  Outer touch target:  72pt × 72pt invisible
  Outer ring:          58pt diameter, 2.5pt stroke, PiqdTokens.Color.rollChrome
  Inner concentric:    44pt diameter, 1pt stroke, PiqdTokens.Color.rollChrome at 60%
  Center dot:          4pt diameter filled circle, PiqdTokens.Color.rollChrome
  (Film canister end cap aesthetic)

State: pressed
  Scale transform:     0.92× (80ms, .roll easing — slightly slower settle than Snap)
  Haptic:              UIImpactFeedbackGenerator(.heavy) — heavier than Snap, more deliberate

State: disabled (counter = 0)
  Opacity:             40%
  No press response
  No haptic
```

#### Roll Mode — Live Photo

```
Visual:
  Same as Roll Still base
  Addition: small concentric pulse ring at 70pt diameter, 0.5pt stroke,
            PiqdTokens.Color.rollAmber, animates (scale 1.0→1.1, opacity 1→0, 2s loop)
  Indicates: Live Photo mode active
```

### 2.2 Mode Indicator Pill

Persistent at rest. Center bottom of safe area.

```
Container:
  Width:         auto (symbol + PiqdTokens.Spacing.sm padding each side)
  Height:        28pt (fixed — see UX-LAYOUT-12)
  Background:    iOS 26 Liquid Glass material (.ultraThinMaterial)
  Border radius: PiqdTokens.Shape.pillRadius (14pt — produces pill shape)
  Position:      horizontally centered, bottom = safeAreaBottom + 8pt

Snap Mode symbol:
  Aperture open icon: 6-blade aperture, blades fully open
  Size:          18pt × 18pt
  Color:         PiqdTokens.Color.snapYellow
  Stroke:        1pt, filled center void

Roll Mode symbol:
  Aperture stopped-down icon: 6-blade aperture, blades nearly closed
  Size:          18pt × 18pt
  Color:         PiqdTokens.Color.rollAmber
  Stroke:        1pt, smaller center void

Mode switch animation:
  The aperture blades animate between open and stopped-down states
  Duration:      PiqdTokens.Duration.fast (150ms)
  Easing:        PiqdTokens.Easing.snap
  Simultaneously: viewfinder aesthetic transitions on confirmed mode switch

Long-hold affordance:
  On 1.5s hold: progress arc fills clockwise around pill border
  Arc color:     target mode accent color (rollAmber switching to Roll, snapYellow switching to Snap)
  Arc width:     2pt stroke outside pill border
  Arc completes: confirmation sheet slides up
  Arc aborts:    fades out in 150ms if user releases early
```

### 2.3 Film Counter (Roll Mode only)

```
Container:
  Position:      top-right of safe area — safeAreaTop + safeAreaHeight × 0.04 from top,
                 screenWidth - PiqdTokens.Spacing.md from right
  Background:    none — floats over viewfinder
  No border, no pill container

Number:
  Font:          PiqdTokens.TextStyle.counter (OCR-A, adaptive size)
  Color:         PiqdTokens.Color.rollChrome (white)
  Content:       "14" (number only)

Label:
  Font:          PiqdTokens.TextStyle.counterLabel (OCR-A 11pt)
  Color:         PiqdTokens.Color.rollChrome at 70% opacity
  Content:       "left"
  Layout:        number and label on same line, "14 left"

States:
  Default (>5 remaining):   white text
  Warning (≤5 remaining):   PiqdTokens.Color.rollAmber
  Zero (Roll full):          PiqdTokens.Color.rollAmber at 50% opacity, no tap

Counter decrement animation:
  Number ticks down: 120ms scale 1.0→1.15→1.0 (.roll easing)
  Replaced by new number mid-scale at peak (60ms in)
```

### 2.4 Zoom Pill

Layer 1 chrome — appears on single tap of viewfinder, retreats after 3s idle.

```
Container:
  Background:    iOS 26 Liquid Glass (.ultraThinMaterial)
  Border radius: PiqdTokens.Shape.pillRadius
  Height:        32pt
  Padding:       PiqdTokens.Spacing.xs horizontal per segment
  Position:      horizontally centered, Y = safeAreaTop + safeAreaHeight × 0.88

Segments (3):
  "0.5×"  "1×"  "2×"
  Each segment: PiqdTokens.TextStyle.caption weight

Active segment:
  Background:    PiqdTokens.Color.snapYellow (Snap) / PiqdTokens.Color.rollAmber (Roll)
  Text color:    #1A1208 (dark — on yellow/amber background)
  Border radius: PiqdTokens.Shape.pillRadius (produces inner pill within container)

Inactive segment:
  Background:    transparent
  Text color:    PiqdTokens.Color.snapChrome (Snap) / PiqdTokens.Color.rollChrome (Roll)

Appear animation:   220ms fade-in + 8pt upward translate (.system easing)
Dismiss animation:  150ms fade-out (.snap easing)

Front camera:
  Only "1×" segment shown — no 0.5× or 2× (front camera fixed focal length)
  Pill shows single "1×" label, no segment dividers
```

### 2.5 Aspect Ratio Indicator

Layer 1 chrome — appears alongside zoom pill.

```
Container:
  Background:    iOS 26 Liquid Glass (.ultraThinMaterial)
  Border radius: PiqdTokens.Shape.pillRadius
  Height:        32pt
  Position:      same Y as zoom pill,
                 X = zoomPillTrailingEdge + PiqdTokens.Spacing.md

Content:
  Active ratio label: "9:16" or "1:1"
  Font: PiqdTokens.TextStyle.caption
  Color: PiqdTokens.Color.snapChrome / rollChrome

Tap behavior:
  Cycles: 9:16 → 1:1 → 9:16
  Switch animation: 80ms crossfade (instant feel)
  Snap Mode default: 9:16
  Roll Mode default: 4:3 (shows "4:3" label)
  Roll Mode optional: 1:1

Note: Sequence format always 9:16 regardless of selected ratio.
  When Sequence is active format, ratio indicator shows "9:16" and is non-interactive (grayed 50%).
```

### 2.6 Flip Button

Layer 1 chrome — appears on single tap of viewfinder.

```
Container:
  Size:          44pt × 44pt touch target (invisible)
  Visual:        32pt × 32pt circle, iOS 26 Liquid Glass material
  Position:      top-right of safe area
                 X center = screenWidth − PiqdTokens.Spacing.lg
                 Y center = safeAreaTop + safeAreaHeight × 0.04

Icon:
  Flip/rotate camera symbol — standard SF Symbol: camera.rotate or equivalent
  Size:          18pt × 18pt
  Color:         PiqdTokens.Color.snapChrome / rollChrome

Behavior:
  Tap: front/rear switch, 0.4s horizontal 3D flip animation on viewfinder
  Zoom pill resets to 1× on flip (front camera has no 0.5× or 2×)
  Disabled (invisible) when Dual Capture format is active
```

### 2.7 Format Selector

Layer 2 chrome — appears on swipe-up gesture on shutter or long-press on format indicator.

```
Container:
  Background:    iOS 26 Liquid Glass (.thinMaterial)
  Border radius: PiqdTokens.Shape.pillRadius
  Height:        40pt
  Width:         screenWidth × 0.7, horizontally centered
  Position:      Y = shutterCenterY − shutterRadius − PiqdTokens.Spacing.md − 40pt

Snap Mode segments (4):
  [Still]  [Sequence]  [Clip]  [Dual]

Roll Mode segments (2):
  [Still]  [Live]

Active segment:
  Background fill: mode accent color (snapYellow / rollAmber)
  Text: PiqdTokens.TextStyle.caption, #1A1208

Inactive:
  Text: PiqdTokens.Color.snapChrome / rollChrome

Appear animation:   220ms slide up from shutter + fade-in
Dismiss animation:  150ms slide down + fade-out (on selection or 3s idle)

Format switch feedback:
  Shutter button morphs to new format shape (80ms)
  No sound, subtle haptic: UISelectionFeedbackGenerator

Dual sub-mode toggle (NEW — only when Dual format is active):
  Container:    capsule, .black opacity 0.4 background
  Width:        200pt, centered
  Position:     between format selector and shutter (Y = shutterCenterY − 80pt)
  Segments:     [Still]  [Video]
  Persistence:  piqd.dualMediaKind in UserDefaults("piqd")
  Behavior:     hidden during active capture; switching reconfigures the
                multi-cam session (photo outputs ⇄ movie outputs).
  a11y id:      piqd.dual.kind

Dual composite layout (configured in dev settings; promoted to user
Settings in a later release). Three options shared by Still and Video:
  - PIP        — rear full-frame, front inset top-right (~30% width)
  - Top/Bottom — rear top half, front bottom half (BeReal style)
  - Side·by·Side — rear left half, front right half
Note: Top/Bottom and Side·by·Side video composites currently render with
small letterbox bars within each half. Edge-to-edge fill for split-layout
video is deferred (see PRD §5.2.4 Deferred).
```

### 2.8 Unsent Badge

Layer 1 chrome — appears only when drafts tray has items.

```
Visual:
  Background:    iOS 26 Liquid Glass (.ultraThinMaterial)
  Border radius: PiqdTokens.Shape.pillRadius
  Height:        28pt — same as mode indicator pill
  Content:       "3 unsent" — number + "unsent" label
  Font:          PiqdTokens.TextStyle.caption
  Color:         PiqdTokens.Color.snapChrome

Position:
  Same Y as mode indicator pill
  X = modePillLeadingEdge − PiqdTokens.Spacing.md − badgeWidth

Behavior:
  Tap: opens drafts tray as bottom sheet
  Not shown in Roll Mode (Roll has no unsent concept)

Urgency state (items under 1h):
  Badge background: PiqdTokens.Color.recordRed at 60% opacity
  Text: white
```

### 2.9 Sequence Strip Preview

Appears after Sequence assembly completes (shareReady = true).

```
Container:
  Position:      bottom of viewfinder, above home indicator
  Height:        safeAreaHeight × 0.28
  Width:         screenWidth
  Background:    PiqdTokens.Color.rollChrome at 85% opacity (semi-transparent dark)
  Border radius: PiqdTokens.Shape.sheetRadius (top corners only, 20pt)
  Y position:    screenHeight − safeAreaBottom − (safeAreaHeight × 0.28)

Strip display:
  6 frame thumbnails in horizontal row
  Each frame: (containerWidth − 5 × PiqdTokens.Spacing.xs) / 6 wide
  Height: container height − PiqdTokens.Spacing.md (top and bottom padding)
  Border radius: PiqdTokens.Shape.thumbRadius
  The assembled MP4 loops silently across all 6 frames automatically

Action area (right side, 28% of container width):
  Vertical stack:
    send → (PiqdTokens.TextStyle.body, 500 weight, label color)
    save   (PiqdTokens.TextStyle.caption, labelSecondary color)
  Both are text-link style — no borders, no fills

Handle:
  2pt × 28pt handle bar at top-center, PiqdTokens.Color.snapChrome at 40% opacity

Gestures:
  Swipe up: opens circle selector
  Swipe down: dismisses strip, returns to live viewfinder

Auto-dismiss: 8 seconds with no action
Appear animation: 220ms slide up from bottom (.system easing)
Dismiss animation: 150ms slide down
```

### 2.10 Invisible Level Indicator

```
Visual:
  A single horizontal line, full width of viewfinder
  Y position: vertical center of safe area
  Length: screenWidth × 0.4 (40% of screen width, centered)
  Stroke: 1pt, PiqdTokens.Color.levelLine (#FFFFFF at 70%)
  End caps: none — clean line only

Behavior:
  Appears when device tilt > ±3° from horizontal
  Disappears when tilt returns within ±3°
  Fade duration: 150ms

Both modes: active
```

### 2.11 Subject Guidance Text

Snap Mode only.

```
Visual:
  Text: "Step back for the full vibe"
  Font: PiqdTokens.TextStyle.caption
  Color: PiqdTokens.Color.snapChrome
  Background: #000000 at 40% opacity, rounded pill (PiqdTokens.Shape.pillRadius)
  Padding: PiqdTokens.Spacing.xs vertical, PiqdTokens.Spacing.sm horizontal
  Position: horizontally centered, Y = safeAreaTop + safeAreaHeight × 0.15

Behavior:
  Appears when face detected within 15% of any frame edge
  Auto-dismisses after 1.5 seconds
  Does not repeat within 10 seconds for same face position
  Roll Mode: never appears
```

### 2.12 Vibe Hint Glyph

Snap Mode only.

```
Visual:
  A small abstract glyph — three short horizontal lines of decreasing length
  (evokes "signal" or "energy" without being an emoji)
  Size: 16pt × 16pt
  Color: PiqdTokens.Color.snapYellow at 60% opacity
  Position: bottom-left of safe area, above mode indicator zone
             X = PiqdTokens.Spacing.md from left edge
             Y = shutterCenterY − shutterRadius − PiqdTokens.Spacing.lg

State: social vibe detected (high-energy scene)
  Glyph pulses: scale 1.0→1.2→1.0, 600ms loop, 3 iterations then fades
  Opacity: 60% during pulse peak, 0% at rest

State: quiet vibe / neutral:
  Glyph hidden (opacity 0)
```

### 2.13 Circle Selector Sheet

```
Container:
  Type: UISheetPresentationController, .medium detent
  Background: PiqdTokens.Color.surface
  Border radius: PiqdTokens.Shape.sheetRadius (top corners)

Header:
  "Send to" — PiqdTokens.TextStyle.body, 500 weight
  Subtitle: asset type description — "sequence · 3 sec strip"
  Font: PiqdTokens.TextStyle.caption, labelSecondary

Friend list:
  Horizontal scroll of friend avatar pills
  Each pill: avatar + first name
  Avatar: 40pt circle, initials (2 chars), PiqdTokens.Color.surfaceSecondary background,
          labelSecondary text — PiqdTokens.TextStyle.caption
  Selected state: avatar border PiqdTokens.Color.snapYellow, 2pt stroke
  Name: PiqdTokens.TextStyle.micro below avatar

Proximity indicator:
  Friend detected nearby (MultipeerConnectivity): small dot at avatar top-right
  Color: PiqdTokens.Color.snapYellow
  Size: 8pt diameter
  Pulses once on detection

Send action:
  "Send →" button — PiqdTokens.TextStyle.body, 500 weight
  Position: bottom of sheet, full width minus PiqdTokens.Spacing.md each side
  Background: PiqdTokens.Color.snapYellow (Snap) — dark text #1A1208
  Border radius: PiqdTokens.Shape.pillRadius
  Height: 52pt
  Disabled (no friends selected): 40% opacity

Ephemeral policy indicator:
  Below send button: "Disappears after viewed · 24h max"
  Font: PiqdTokens.TextStyle.micro, labelTertiary
  Roll Mode equivalent: "Permanent — no expiry"
```

### 2.14 Drafts Tray Sheet

```
Container:
  Type: UISheetPresentationController, .medium detent
  Background: PiqdTokens.Color.surface

Header:
  "Unsent" — PiqdTokens.TextStyle.body, 500 weight, left-aligned
  Right: item count "3 items" — PiqdTokens.TextStyle.caption, labelSecondary

Asset rows:
  Each row: 72pt height
  Divider: 0.5pt separator between rows

  Row anatomy:
    Left:   thumbnail — 52pt × 52pt, PiqdTokens.Shape.thumbRadius
            Still: static thumbnail
            Sequence: silent looping MP4 (auto-plays)
            Clip/Dual: static thumbnail with play icon overlay (18pt × 18pt)
    Center: asset type label — PiqdTokens.TextStyle.caption, 500 weight
            timer — PiqdTokens.TextStyle.micro, labelSecondary
    Right:  "save" — PiqdTokens.TextStyle.caption, labelSecondary (text link)
            "send →" — PiqdTokens.TextStyle.caption, 500 weight, label (text link)

Timer states:
  >3 hours: hidden (no timer shown)
  1–3 hours: "[Xh Ym] left" — labelSecondary
  <1 hour: "[Xm] left" — PiqdTokens.Color.rollAmber (amber warning)
  <15 min: "[Xm] left" — PiqdTokens.Color.recordRed

  "send →" text color follows timer:
    Default: label color
    <1 hour: PiqdTokens.Color.rollAmber
    <15 min: PiqdTokens.Color.recordRed

Empty state:
  "Nothing waiting to send."
  PiqdTokens.TextStyle.body, labelSecondary, centered
```

---

## 3. Screens — Snap Mode

### 3.1 Snap Viewfinder — Rest State (Layer 0)

This is what the user sees 95% of the time. Maximum simplicity.

```
Full screen: AVCaptureVideoPreviewLayer — 100% width, 100% height
             extends behind Dynamic Island, behind home indicator

Persistent chrome (Layer 0):
  Mode indicator pill:  center bottom, 8pt above home indicator zone
  Shutter button:       horizontally centered, above mode pill
                        (format = Still by default: clean ring, no fill)

Nothing else visible.
No zoom pill. No format selector. No flip button. No badge.
The viewfinder is the entire interface.

Active format shutter appearance:
  Still (default): clean ring, snapChrome, no fill
  Sequence: clean ring, snapChrome, no fill (identical to Still at rest)
  Clip: record ring (red), square inside
  Dual: record ring (red), split diagonal circle
```

### 3.2 Snap Viewfinder — Layer 1 (Single Tap on Viewfinder)

```
Appears (220ms slide up + fade):
  Zoom pill:          horizontally centered, Y = safeAreaTop + safeAreaHeight × 0.88
  Aspect ratio pill:  right of zoom pill, same Y
  Flip button:        top-right safe area
  Unsent badge:       left of mode pill, same Y (only if drafts exist)
  Invisible level:    horizontal center (if device tilted)

Auto-retreat: 3 seconds idle → all Layer 1 chrome fades out (150ms)
Persists while: user is interacting with any Layer 1 element
```

### 3.3 Snap Viewfinder — Layer 2 (Format Selector)

```
Trigger: swipe-up gesture on shutter button OR long-press on shutter

Appears (220ms slide up from shutter):
  Format selector pill: centered, above shutter
  Segments: [Still] [Sequence] [Clip] [Dual]
  Active segment highlighted in snapYellow

On selection:
  Format selector collapses (150ms)
  Shutter button morphs to new format (80ms)
  Format switch haptic fires

Auto-retreat: 3 seconds idle
```

### 3.4 Snap Viewfinder — During Sequence Capture

```
Duration: 3 seconds (6 frames × 333ms)

Chrome changes:
  Shutter ring: fills with snapYellow, pulses per frame (40ms scale burst)
  Sequence frame flash: brief white overlay on viewfinder per frame (40ms)
  Safe Render zone: 9:16 crop guide appears (1pt white at 15% opacity)
  Dynamic Island: State 1 activates (6 dots filling)

During capture:
  Layer 1 chrome retreats (hidden)
  Mode switch gesture disabled
  Zoom gesture disabled
  Format selector disabled

Frame counter: subtle "1 / 6" … "6 / 6" text appears below shutter
  Font: PiqdTokens.TextStyle.micro
  Color: snapChrome at 80%

After 6th frame (assembly begins):
  Shutter ring returns to idle appearance
  Dynamic Island dismisses
  "Assembling…" text appears briefly (only if >1.5s assembly time)
  stripPreviewSheet appears when shareReady = true (220ms slide up)
```

### 3.5 Snap Viewfinder — During Clip Recording

```
Duration: user-defined (5s, 10s, 15s — selected at format pick time)

Chrome changes:
  Shutter button: recording state (inner shape shrinks, outer ring pulses)
  Duration arc: fills clockwise around outer ring, recordRed
  Timer label: "0:07" counting up, PiqdTokens.TextStyle.micro, snapChrome
               Position: above shutter button, centered

Layer 1 chrome: hidden during recording
Mode switch: disabled during recording

On release:
  Recording stops
  Asset available immediately (no assembly wait)
  Circle selector can be invoked (swipe up) or dismissed
```

### 3.6 Snap Viewfinder — Ambient States

```
Invisible level appears:
  Device tilts > ±3°: level line fades in (150ms) across viewfinder center
  Returns to level: line fades out (150ms)

Subject guidance appears:
  Face detected near frame edge: pill text "Step back for the full vibe" fades in
  Auto-dismisses 1.5s. No repeat within 10s.
  Position: upper center of safe area

Vibe hint:
  High-energy scene detected (2fps classifier): yellow glyph pulses bottom-left
  3 pulse cycles (1.8s total) then fades

Backlight correction:
  When active: small EV indicator appears — "+" symbol, PiqdTokens.TextStyle.micro
  Position: adjacent to shutter button, PiqdTokens.Spacing.sm separation
  Only visible when EV compensation is actively applied (>+1.0 EV)
```

### 3.7 Snap — Post-Send Confirmation

```
No navigation. No sheet. Confirmation comes to the user.

Shutter button: brief checkmark animation
  The shutter ring briefly shows a checkmark symbol (150ms)
  Returns to idle state
  Haptic: UINotificationFeedbackGenerator(.success)

If multiple recipients: checkmark appears once for all
If delivery pending (recipient offline): checkmark is replaced by a "→" arrow symbol
  indicating queued, not delivered

The user remains in the viewfinder. Camera stays live.
```

---

## 4. Screens — Roll Mode

### 4.1 Roll Viewfinder — Rest State (Layer 0)

```
Full screen: AVCaptureVideoPreviewLayer with CIFilter chain applied:
  Layer 1 (grain): CIRandomGenerator → CIColorMatrix (desaturate, reduce brightness)
                   Opacity: 6–12% per frame (randomized, drifts)
  Layer 2 (light leak): conditional — appears on session start with ~50% probability
                        CILinearGradient + CIColorMatrix (warm orange)
                        Applied at one of 4 corners (randomized)
                        Opacity: 10–15%
  Layer 3 (film sim): selected preset CIFilter chain
                      .kodakWarm: +warmth, +contrast, +grain density, slight yellow shift
                      .fujiCool: −warmth, flat contrast, fine grain, slight cyan lift
                      .ilfordMono: desaturate to mono, heavy grain, high contrast

Chrome:
  Mode indicator pill:  center bottom (stopped-down aperture, rollAmber)
  Shutter button:       film canister end cap, rollChrome
  Film counter:         top-right safe area, OCR-A font
                        "14 left" — white when >5, amber when ≤5

Nothing else visible. Maximum presence in the experience.
```

### 4.2 Roll Viewfinder — Layer 1 (Single Tap on Viewfinder)

```
Appears:
  Film simulation selector: bottom-left of safe area (edge swipe left/right)
    Three dots indicating current preset, swipeable
    Current preset name appears briefly (1.5s then fades)
    ".kodakWarm" / ".fujiCool" / ".ilfordMono" in OCR-A style, caption size
  Zoom pill: horizontally centered, same Y position as Snap
  Flip button: top-right safe area
  Invisible level: if device tilted

No subject guidance in Layer 1 Roll (intentionally absent)
No vibe hint in Roll Mode
No unsent badge in Roll Mode
No format selector in Layer 1 — Roll formats accessed differently (see 4.3)
```

### 4.3 Roll Viewfinder — Format Selection (Roll)

```
Roll Mode has 2 formats only: Still and Live Photo
Format is selected by edge swipe on the LEFT 20% of viewfinder (not center)
This is the same zone as film simulation change — differentiated by:
  Short swipe (< 80pt): film simulation cycle
  Long swipe (> 80pt) with upward component: format change

On format change:
  Shutter button morphs:
    Still: film canister end cap (base state)
    Live: film canister end cap + concentric pulse ring

  Brief label confirms: "Still" / "Live" — same position as film sim label
```

### 4.4 Roll Viewfinder — Film Counter States

```
Counter full (>5 remaining):
  "14 left" — white OCR-A, standard weight

Counter warning (≤5 remaining):
  "[X] left" — PiqdTokens.Color.rollAmber
  Counter ticks with slightly more pronounced animation (scale 1.0→1.2→1.0)

Counter zero:
  "Roll full" — rollAmber at 50% opacity
  Shutter button dims to 40% opacity
  Shutter does not respond to tap
  Mode indicator still active — user can switch to Snap

9PM approach (within 30 min, counter >0):
  Counter color: rollAmber (matches warning state)
  Subtle ambient pulse: counter breathes (opacity 100%→70%→100%, 4s loop)
  Dynamic Island State 2 activates
```

### 4.5 Roll Viewfinder — Roll Full State

```
Viewfinder remains live (camera feed continues)
Grain and film sim remain active

Overlay message appears (300ms fade-in):
  "Roll's full."
  "See you at 9."

  Font: PiqdTokens.TextStyle.title (DMSans 20pt, 500 weight)
  Color: rollChrome (white)
  Position: vertically centered in safe area
  Background: none — text sits over live viewfinder + grain

  Second line "See you at 9." uses same style but rollAmber color if within 2h of 9PM

Shutter: dimmed, non-responsive
Mode pill: fully active — user can still switch to Snap
Counter shows: "Roll full" label
```

### 4.6 Roll Viewfinder — 9PM Unlock Initiation

```
Trigger: 9PM local time fires

1. Dynamic Island: State 2 (Developing…) transitions in (300ms system spring)

2. Viewfinder: brief "developing" overlay appears
   Visual: the viewfinder grain suddenly increases (opacity doubles, 500ms)
           then slowly fades back (3s) as if the film is being wound out
   Copy: "Developing your Roll…" — PiqdTokens.TextStyle.body, rollChrome
   Position: vertically centered

3. Background processing begins (StoryEngine, iCloud upload)
   No progress bar — the metaphor is "developing", not "uploading"

4. When complete: Dynamic Island updates to "Delivering…"
   then transitions out when APNs fires

5. Viewfinder: returns to normal state (can still shoot if counter > 0)
   The reveal happens in the Film Archive, not the viewfinder
```

---

## 5. Screens — Shared / System

### 5.1 Mode Switch Transition

```
Trigger: long-hold (1.5 seconds) on the mode indicator pill

Phase 1 — Hold feedback (0 → 1.5s):
  Pill border: glows to target mode accent color
  Progress arc: fills clockwise around pill, target mode accent color, 2pt stroke
  Abort: release before 1.5s → arc fades (150ms), no sheet, no switch

Phase 2 — Confirmation sheet (on arc completion):
  Sheet slides up: PiqdTokens.Duration.standard (220ms), .system easing
  Background: PiqdTokens.Color.surface, PiqdTokens.Shape.sheetRadius top corners
  Drag pill: centered at sheet top
  Content:
    Target mode name: "Switch to Roll?" or "Switch to Snap?"
      Font: PiqdTokens.TextStyle.title, label color, centered
    Target mode aperture symbol: 24pt, target mode accent color, centered
    Primary CTA: "Switch"
      Background: target mode accent color (rollAmber or snapYellow)
      Text: #1A1208, PiqdTokens.TextStyle.body, 500 weight, monospace
      Full width minus PiqdTokens.Spacing.md each side, 52pt height
      Border radius: PiqdTokens.Shape.pillRadius
    Secondary dismiss: "Stay in Snap" / "Stay in Roll"
      Style: text-link, PiqdTokens.TextStyle.caption, labelSecondary
  Tap outside sheet: dismisses with no switch (150ms slide down)

Phase 3 — Confirmed transition:
  Haptic: PiqdTokens.Haptic.modeSwitch fires on confirm tap
  Sheet dismisses: 150ms slide down
  Viewfinder aesthetic transitions (150ms, .snap easing):
    Grain: fades in (Snap→Roll) or fades out (Roll→Snap) — crossfade, not slide
    Chrome elements: crossfade (symbol + color on mode pill updates)
    Shutter button: morphs between styles (ring dissolves/resolves, 150ms)
    Color temperature: viewfinder CIFilter color grading crossfades
  Shutter sound changes on transition complete

During transition:
  Mode pill long-hold locked (cannot re-trigger during animation)
  Shutter locked

Disabled states (pill long-hold inactive):
  During active Sequence capture (3-second window)
  During Clip or Dual recording
  During Roll unlock sequence

After transition:
  Layer 0 chrome only — transition completes clean
  Mode persists to next session
```

### 5.2 Inbox Screen

```
Accessed from: gear icon (⚙) in viewfinder Layer 1 → "Inbox" menu option
               OR notification tap deep-link from any screen

Navigation: sheet over viewfinder (viewfinder stays live behind)

Header:
  "inbox" — PiqdTokens.TextStyle.title, label color, left-aligned
  Subtitle: "X waiting" — PiqdTokens.TextStyle.caption, labelSecondary

Item rows (72pt height each):
  Avatar: 40pt circle, sender initials, surfaceSecondary bg
  Name: PiqdTokens.TextStyle.body, 500 weight, label
  Preview: asset type only — "sequence" / "still" / "clip · 10s"
           PiqdTokens.TextStyle.caption, labelSecondary
  Timestamp: "2m ago" — PiqdTokens.TextStyle.micro, labelTertiary
  Unread indicator: 6pt dot, snapYellow, right edge (not a count badge)

Timer appears (right side, replaces timestamp) when:
  <3h remaining: "[Xh Ym] left" — labelSecondary
  <1h: rollAmber color
  <15m: recordRed color

Tap on row: opens asset view (irreversible view trigger)
Swipe down: dismiss sheet, return to viewfinder
```

### 5.3 Asset View (Received Snap)

```
Full screen presentation (no navigation bar, no tab bar)

Header (minimal):
  Back: "← inbox" — PiqdTokens.TextStyle.caption, labelSecondary
  Center: sender first name — PiqdTokens.TextStyle.body, 500 weight
  Right: "viewing now" — PiqdTokens.TextStyle.micro, labelTertiary

Asset area:
  Full screen (behind header)
  Still: static full-screen display
  Sequence: silent looping MP4, full screen, loops automatically
  Clip: plays with audio, full screen, loops once then pauses
  Dual: MP4 composite, full screen

Footer (above home indicator):
  Reaction chips: [haha] [love] [wow] [fire]
    Style: PiqdTokens.Shape.pillRadius pills, 36pt height
    Background: surfaceSecondary
    Font: PiqdTokens.TextStyle.caption
    Selected: snapYellow background, dark text

  Reply field: below chips
    Background: #000000 at 30% opacity, pill shape
    Placeholder: "reply to [name]…" — PiqdTokens.TextStyle.caption, labelTertiary
    Height: 36pt
    Send icon: right side of field, appears when text entered

Screenshot detection:
  If user screenshots: "screenshot detected" banner appears on sender side
  Recipient sees no change (no punitive state)

Viewed trigger: fires immediately on screen appear
View session close: navigate back OR app backgrounds → recipient copy scheduled for deletion
```

### 5.4 Response Thread View (Sender receives reaction)

```
Notification tap deep-links here

Layout: compact card, not a full screen
  Appears as a sheet over the viewfinder

Card anatomy:
  Asset thumbnail (small, 80pt × 80pt, PiqdTokens.Shape.thumbRadius)
  Sender info: "Jiyeon reacted haha" — PiqdTokens.TextStyle.body
  Timestamp: PiqdTokens.TextStyle.micro, labelTertiary

  If text reply: reply text shown below — PiqdTokens.TextStyle.caption

  Reply field (sender can reply back — one level only):
    Same style as asset view reply field
    "Reply to Jiyeon…" placeholder

  Below reply: "Piqd will purge this message when [name] closes it."
    PiqdTokens.TextStyle.micro, labelTertiary

Dismiss: swipe down, returns to viewfinder
```

---

## 6. Film Archive

### 6.1 Archive Entry

```
Accessed: swipe up from viewfinder bottom (both modes)

Sheet: UISheetPresentationController, .large detent (nearly full screen)
Background: PiqdTokens.Color.archiveBg
```

### 6.2 Archive List View

```
Navigation:
  Title: "archive" — PiqdTokens.TextStyle.title, label color, left-aligned
  No back button (no navigation stack — it's a sheet)
  Close: "×" top-right, 44pt touch target

Moment cards (vertical list, no grid):
  Each card: PiqdTokens.Color.archiveCard background, PiqdTokens.Shape.cardRadius
  Card height: adaptive — hero image + metadata row

  Hero image: full card width, 16:9 ratio, rounded top corners
  Metadata row (24pt height, below hero):
    Left: Moment label — "Rainy Walk · Apr 14 · Shibuya"
          PiqdTokens.TextStyle.caption, 500 weight
    Right: friend avatars (received by) — overlapping 20pt circles
           Initials, surfaceSecondary bg
    Far right: timestamp — "Yesterday" / "Apr 14" — PiqdTokens.TextStyle.micro

  Card spacing: PiqdTokens.Spacing.sm between cards
  Card padding: PiqdTokens.Spacing.sm on all sides of hero image

Received Rolls (from friends):
  Same card style
  Attribution label below Moment label: "from Jiyeon" — labelSecondary

Scroll: simple vertical scroll, no pagination, no infinite scroll
        Reverse chronological — newest at top
        No algorithmic reordering ever

Empty state:
  "Your first Roll unlocks at 9. Start shooting."
  PiqdTokens.TextStyle.body, labelSecondary, centered
  Live Roll Mode viewfinder visible behind the text (blurred, 20pt gaussian)
```

### 6.3 Moment View (Inside an unlocked Roll)

```
Navigation: pushed from archive list (standard push transition)
Back: "← archive" — PiqdTokens.TextStyle.caption, labelSecondary

Header:
  Moment label: "Rainy Walk · Apr 14 · Shibuya"
    PiqdTokens.TextStyle.title, 500 weight
  Ambient detail (from AmbientMetadata):
    "Tuesday · Rainy · 17°C · You were listening to [track]"
    PiqdTokens.TextStyle.micro, labelTertiary
    Only fields that have data are shown — no "Unknown" placeholders

Friends who received:
  Horizontal row of avatar pills (initials + first name)
  Opened indicator: filled dot on avatar of friends who opened
  Unopened: empty dot

Asset display:
  Vertical scroll through narrative sequence (StoryEngine order, not capture order)
  Each asset: full width display
  Still: full width, natural aspect ratio
  Live Photo: plays on tap (standard iOS Live Photo behavior)
  Moving Still (v2.0): animates on scroll-into-view

Toggle: "Narrative order / Capture order" — small toggle top-right
  PiqdTokens.TextStyle.micro

Per-asset actions (appear on tap of asset):
  Share (iOS share sheet) — standard SF Symbol
  Save to Photos — standard SF Symbol
  These appear as a compact bar below the asset, fade after 3s

Batch action (bottom of view):
  "Save all to Photos" — text button, PiqdTokens.TextStyle.caption
  Exports all assets in this Moment to iOS Photos library
```

### 6.4 Unlock Reveal Sequence

```
Trigger: user opens Piqd after receiving 9PM APNs notification

Presentation: full screen, replaces viewfinder (not a sheet)
Background: PiqdTokens.Color.rollChrome (#1A1208) — darkroom

Opening state (before reveal begins):
  Center: circular film canister icon, animated (slowly rotating, 3s loop)
  Below: "[Name]'s Roll · [date]" — PiqdTokens.TextStyle.title, rollChrome
  Below: "X photos developing…" — PiqdTokens.TextStyle.caption, rollAmber

Asset reveal sequence:
  Assets appear one by one in StoryEngine narrative order
  Each asset: 400ms film-advance slide from right (roll easing)
  Between assets: 200ms pause (organic — not uniform, ±80ms variance per asset)
  Still photos: appear with grain overlay already baked in
  Live Photos: start animating 500ms after reveal (delayed activation)
  Moving Stills (v2.0): motion begins 800ms after reveal

  Background: shifts from rollChrome to a warm near-dark color
              influenced by the hero asset's dominant palette from ChromaticPalette

Sound design:
  Each asset reveal: soft mechanical film-advance click
  The sound is not identical each time (±3% pitch variation, per UX-IMPERF-04)

Friend opened indicators:
  As friends open the Roll simultaneously, their avatar appears at bottom-right
  Small avatar (24pt) with name slides in from right (150ms)
  Maximum 3 avatars visible simultaneously, then "+N more" label

End of reveal:
  Final asset holds for 1.5s
  Transition to Moment View (standard push, 280ms)
  No fanfare, no celebration — the reveal ends quietly

Reaction to reveal assets:
  Tap any asset during reveal: pause reveal, reaction/reply interface appears
  Resume: "Continue →" text button
```

---

## 7. Onboarding

### 7.1 Screen 1 — Two Modes

```
Full screen, no navigation bar

Background: split vertically
  Left half: Snap Mode viewfinder aesthetic (clean, bright)
  Right half: Roll Mode viewfinder aesthetic (warm, grainy)
  Dividing line: 1pt, white, centered

Text overlay (centered on dividing line):
  "Piqd" — PiqdTokens.TextStyle.displayLarge (28pt, 500 weight), white

Below:
  Left: "Snap" — PiqdTokens.TextStyle.body, snapYellow
  Right: "Roll" — PiqdTokens.TextStyle.body, rollAmber

Bottom:
  "Continue →" — PiqdTokens.TextStyle.body, 500 weight, white
                 Full-width button, snapYellow background, 52pt height
  Below button: "Skip" — PiqdTokens.TextStyle.caption, white at 60% (skips to Screen 4)

Note: This is the only screen where mode names appear as text in the app.
```

### 7.2 Screen 2 — Snap

```
Full screen: live Snap Mode viewfinder (camera active)

Overlay (bottom 40% of safe area):
  Background: #000000 at 50% opacity, top corners rounded (PiqdTokens.Shape.sheetRadius)

  "Tap to capture."
  "Swipe to send."
  PiqdTokens.TextStyle.title, white, left-aligned

  Shutter button visible and tappable during onboarding
  If user taps: captures a still, brief post-capture confirmation
  This teaches by doing, not by describing

  "Next →" text button, right-aligned, snapYellow
```

### 7.3 Screen 3 — Roll

```
Full screen: Roll Mode viewfinder (grain active, film canister shutter visible)

Overlay (same style as Screen 2):
  "Shoot all day."
  "Opens at 9."
  PiqdTokens.TextStyle.title, white, left-aligned

  Film counter visible: "24 left" — OCR-A, white (teaches the counter)

  "Next →" text button, right-aligned, rollAmber
```

### 7.4 Screen 4 — Invite

```
Full screen: solid PiqdTokens.Color.archiveBg (not a viewfinder)

Content centered vertically:
  Large QR code: 200pt × 200pt, centered
  Below: "Invite your first friend"
         PiqdTokens.TextStyle.title, label, centered
  Below: "They scan this to join your circle."
         PiqdTokens.TextStyle.body, labelSecondary, centered

  "Share invite link instead →" — PiqdTokens.TextStyle.caption, snapYellow
                                   opens iOS share sheet with deep link

Bottom:
  "Start shooting →" — full-width button, snapYellow bg, dark text, 52pt height
                       Opens camera in Snap Mode

Permission requests fire contextually (camera permission fires when viewfinder opens,
notification permission fires when user takes first Roll photo)
```

---

## 8. Settings

```
Accessed:
  From viewfinder: gear icon (⚙) appears in Layer 1 top-left safe area alongside existing Layer 1 chrome.
    Tapping gear → small action menu slides up with two options: "Inbox" and "Settings".
    Gear icon obeys Layer 1 auto-retreat (3s idle → fades with all other Layer 1 chrome).
    Gear icon position: top-left safe area, same Y as flip button (cy=87pt), x=44pt from left edge.
    Size: 32pt diameter, same as flip button. Style: ⚙ SF Symbol, labelSecondary weight, surfaceSecondary bg.

  From all non-viewfinder screens (Inbox, Film Archive, Moment View, Asset View, Unlock Reveal):
    Small ⋯ (ellipsis) icon, top-right of screen header, 44pt tap target.
    Tapping ⋯ → action menu with "Settings" option (and "Inbox" where contextually relevant).
    Always visible on non-viewfinder screens — not chrome-layer dependent.
    Color: labelSecondary. No background fill. Consistent position across all screens.

  Note: mode pill long-hold (1.5s) is a completely separate interaction — it triggers mode switch,
  not Settings. These do not conflict: long-hold acts from Layer 0 without tapping first.

Presentation: standard iOS Settings-style UITableViewController
              pushed from viewfinder context

Sections and options:

CAPTURE
  Default Snap format:     [Still / Sequence / Clip / Dual]
  Default Roll format:     [Still / Live Photo]
  Clip max duration:       [5s / 10s / 15s]
  Sequence interval:       333ms (display only — not user-adjustable in v1.0)

ROLL MODE
  Unlock time:             9:00 PM (display only — v1.0, configurable in v1.1)
  Daily shot limit:        24 (display only — not user-adjustable)
  Film simulation:         [kodakWarm / fujiCool / ilfordMono]

SNAP MODE
  Subject guidance:        [On / Off] — toggles UX-PSS-GUIDE-01
  Vibe hint:               [On / Off] — toggles UX-PSS-VIBE-01
  Invisible level:         [On / Off] — toggles UX-PSS-LEVEL-01

CIRCLE
  My friends:              list of trusted friends, tap to remove
  Add friend:              QR / Link options
  My invite QR:            shows QR code for sharing

STORAGE
  Vault storage used:      "[X] MB used by Piqd"
  Clear unsent drafts:     "Clear X items" — with confirmation
  Export Film Archive:     "Save all to Photos" — with confirmation

PRIVACY
  Camera access:           links to iOS Settings
  Notifications:           links to iOS Settings
  Location:                links to iOS Settings

ABOUT
  Version:                 "Piqd 1.0.0"
  Privacy:                 link to privacy statement
  No "Rate us", no "Share app", no social links in Settings
```

---

## 9. Copy Reference

All user-facing strings. Copy is minimal, dry, peer-level. No marketing language.

### 9.1 Viewfinder States

| Context | String |
|---------|--------|
| Roll full | "Roll's full." |
| Roll full — approaching 9PM | "See you at 9." |
| Sequence assembling | "Assembling…" |
| Developing at unlock | "Developing your Roll…" |
| Roll queued (no connectivity) | "Roll queued — will deliver when connected." |
| Subject guidance | "Step back for the full vibe" |

### 9.2 Inbox and Sharing

| Context | String |
|---------|--------|
| Inbox empty | "Nothing waiting." |
| Lock screen notification (Snap) | "[Name] sent you something" |
| Lock screen notification body | "Tap to open before it's gone." |
| Lock screen notification (Roll) | "Your Piqd from today is ready." |
| Roll notification body | "Open it with your circle." |
| Post-send (delivered) | (no text — shutter checkmark animation only) |
| Post-send (queued) | (no text — shutter arrow animation only) |
| Asset expired (sender) | "[Name]'s Snap expired unviewed." |
| Asset purged (recipient) | "Piqd has left the chat." |
| Receipt screenshotted (sender) | "[Name] screenshotted your Snap." |

### 9.3 Dynamic Island

| State | Compact text |
|-------|-------------|
| Sequence firing | (dots only — no text) |
| Roll unlock imminent | "9PM" |
| Roll developing | "Developing…" |
| Snap pending | "→ [Name]" or "→ X pending" |

### 9.4 Film Archive and Reveal

| Context | String |
|---------|--------|
| Archive empty | "Your first Roll unlocks at 9. Start shooting." |
| Reveal opening | "[Name]'s Roll · [Date]" |
| Reveal sub | "X photos developing…" |
| Moment label format | "[Place] · [Date] · [Area]" e.g. "Shibuya · Apr 14" |
| Received Roll attribution | "from [Name]" |
| Received Roll not opened | (soft glow on avatar — no text) |
| Roll archived | (no confirmation — assets appear in archive silently) |

### 9.5 Error States

| Error | String |
|-------|--------|
| Share failed | "Couldn't reach [Name] — we'll try again." |
| iCloud upload failed | "Your Roll is queued for delivery." |
| iCloud upload failed >2h | "Your Roll couldn't deliver — tap to retry." |
| Camera unavailable | "Camera unavailable. Check permissions in Settings." |
| No friends in circle | "Add a friend first." |
| Export to Photos failed | "Couldn't save to Photos. Check permissions in Settings." |

### 9.6 Onboarding

| Screen | Headline | Subhead |
|--------|----------|---------|
| Screen 1 | "Piqd" | (left: "Snap" / right: "Roll") |
| Screen 2 | "Tap to capture." | "Swipe to send." |
| Screen 3 | "Shoot all day." | "Opens at 9." |
| Screen 4 | "Invite your first friend." | "They scan this to join your circle." |

---

## 10. Motion Reference

Complete motion spec. All values from PiqdTokens.Duration and PiqdTokens.Easing.

| Interaction | Duration | Easing | Haptic |
|-------------|----------|--------|--------|
| Mode switch — hold arc | 1500ms | linear | none |
| Mode switch — confirm + transition | 150ms | .snap | .modeSwitch |
| Shutter press (Snap) | 80ms | .snap | .shutterSnap |
| Shutter press (Roll) | 80ms | .roll | UIImpactFeedbackGenerator(.heavy) |
| Sequence frame flash | 40ms | linear | .sequenceFrame |
| Format switch | 80ms | .snap | UISelectionFeedbackGenerator |
| Layer 1 appear | 220ms | .system | none |
| Layer 1 retreat | 150ms | .snap | none |
| Layer 2 appear | 220ms | .system | none |
| Layer 2 retreat | 150ms | .snap | none |
| Mode switch — grain crossfade | 150ms | .snap | none |
| Film counter tick | 120ms | .roll | none |
| Sequence preview appear | 220ms | .system | none |
| Sequence preview dismiss | 150ms | .snap | none |
| Bottom sheet appear | system | system | none |
| Bottom sheet dismiss | system | system | none |
| Zoom level snap | 150ms | .snap | .zoomOptical |
| Zoom continuous (pinch) | real-time | none | .zoomOptical at optical boundaries |
| Flip camera | 400ms | .system | none |
| Roll unlock reveal per asset | 400ms + ±80ms random | .roll | none |
| Roll unlock reveal — sound | per asset | — | film click ±3% pitch |
| Dynamic Island expand | 300ms | system spring | .diExpand |
| Dynamic Island sequence dot | 333ms per dot | linear | none |
| Viewfinder to Archive sheet | 280ms | .system | none |
| Archive to Moment push | 280ms | system push | none |
| Asset view appear | 280ms | system push | none |
| Reduce Motion (all) | crossfade 150ms | linear | haptics preserved |

---

## 11. Dynamic Island Reference

Complete specification for all four Piqd Live Activity states. See UX Requirements v1.1 §Part 3 for rationale.

### State 1 — Sequence Capture

```swift
// ActivityAttributes
struct SequenceCaptureAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var framesFired: Int    // 0–6
        var elapsedSeconds: Double
    }
}

// Compact leading: 6 dot indicators
// Dot filled state = framesFired
// Dot size: 6pt × 6pt, spacing: 4pt
// Color: PiqdTokens.Color.snapYellow (filled), white at 30% (unfilled)

// Compact trailing: elapsed time
// "1.3s" — OCRA font, 11pt, white
// Counts up from 0.0 to 3.0

// Background: PiqdTokens.Color.snapYellow at 40% opacity
// No expanded view defined (sequence is too short for long-press to be useful)

// Duration: exactly 3 seconds. endActivity() fires after 6th frame capture.
```

### State 2 — Roll Unlock Imminent

```swift
// ActivityAttributes
struct RollImminentAttributes: ActivityAttributes {
    let unlockTime: Date       // 9PM local time
    let shotCount: Int         // number of shots in today's Roll
    struct ContentState: Codable, Hashable {
        var minutesRemaining: Int
    }
}

// Compact leading: circular fill indicator
// Circle: 16pt diameter, 1pt stroke, white at 40%
// Fill: rollAmber, arc progresses from 0% (30min before) to 100% (9PM)
// Fill animation: CADisplayLink-driven, imperceptibly slow

// Compact trailing: "9PM"
// Font: DMSans caption, white
// Literal text — no dynamic time display (too small for "8:47 PM")

// Background: rollAmber at 15% opacity — barely visible, atmospheric

// Expanded (long-press):
// "Your Roll unlocks at 9:00 PM"
// "X shots developing"
// No action button

// Updates: every 60 seconds (minutesRemaining decrements)
// Ends: at unlock trigger — replaced by State 3
```

### State 3 — Roll Developing

```swift
// ActivityAttributes
struct RollDevelopingAttributes: ActivityAttributes {
    let shotCount: Int
    struct ContentState: Codable, Hashable {
        var status: DevelopingStatus    // .developing / .delivering / .queued
    }
    enum DevelopingStatus: Codable { case developing, delivering, queued }
}

// Compact leading: animated film-strip icon
// Custom SF Symbol or simple 3-line wave (12pt × 12pt)
// Animates: shimmer / wave motion, 2s loop
// Color: rollAmber

// Compact trailing: status text
// .developing:  "Developing…"
// .delivering:  "Delivering…"
// .queued:      "Queued"
// Font: DMSans micro (11pt), white

// Background: rollAmber at 25% opacity — more visible than State 2

// Expanded (long-press):
// .developing:  "Your Roll is developing — this takes a moment."
// .delivering:  "Delivering to your circle now."
// .queued:      "No connection — will deliver when you're back online."

// Ends: when all recipients notified via APNs — endActivity() fires
//       If queued: stays active until delivery succeeds
```

### State 4 — Snap Pending Delivery

```swift
// ActivityAttributes
struct SnapPendingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var pendingCount: Int
        var firstRecipientName: String   // truncated to 8 chars
    }
}

// Compact leading: outbound arrow icon (SF Symbol: arrow.up.right)
// Size: 12pt × 12pt, snapYellow

// Compact trailing:
// pendingCount == 1: "[Name]" (first 8 chars)
// pendingCount > 1:  "X pending"
// Font: DMSans micro, white

// Background: snapYellow at 20% opacity

// Expanded (long-press):
// Lists up to 3 pending recipients with status
// "Tap to cancel" action per recipient

// Ends: when all pending recipients retrieve. endActivity() fires on last retrieval.
```

---

## 12. Adaptive Layout Validation

Each layout specification must be validated against the smallest (iPhone 15, 390 × 844pt) and largest (iPhone 16 Pro Max / 17 Pro Max, 440 × 956pt) supported screens before the spec is considered final.

### 12.1 Validation Checklist

For each component, confirm on both extreme devices:

- [ ] Shutter button: diameter ≈ 72pt (390pt screen), ≈ 80pt (440pt screen). Reachable by right thumb.
- [ ] Film counter: legible at max(15pt, W × 0.038). Contrast ≥ 4.5:1 against grain overlay.
- [ ] Mode indicator pill: does not overlap shutter button. Sits comfortably above home indicator.
- [ ] Zoom pill: does not overlap shutter button. Fully within safe area width.
- [ ] Format selector: width = screenWidth × 0.7. Does not clip on 390pt screen (273pt — fits 4 segments at ~68pt each).
- [ ] Sequence strip preview: height = safeAreaHeight × 0.28. On iPhone 15: 751 × 0.28 ≈ 210pt. On Pro Max: 860 × 0.28 ≈ 241pt. Both usable.
- [ ] Film Archive cards: hero image 16:9 at full card width. On 390pt: 390pt wide. On 440pt: 440pt wide. Both render hero assets correctly.
- [ ] Dynamic Island: no Piqd chrome within safeAreaTop (59pt or 62pt). Film counter at safeAreaTop + safeAreaHeight × 0.04: on iPhone 15 this is 59 + 30 = 89pt from top — clear of Island. On Pro Max: 62 + 34 = 96pt — clear.
- [ ] Dynamic Island expanded: film counter repositions down by expandedIslandHeight − safeAreaTop. Approximately 84pt − 59pt = 25pt additional offset on standard, 90pt − 62pt = 28pt on Pro.
- [ ] Bottom sheets: max height safeAreaHeight × 0.75. On iPhone 15: 563pt. On Pro Max: 645pt. Both are usable heights.
- [ ] All touch targets: ≥ 44pt × 44pt verified. Shutter ≥ 72pt verified.

### 12.2 Known Layout Constraints

**Format selector on 390pt screen:**
4 segments × ~68pt each = 272pt within a 273pt container (screenWidth × 0.7 = 273pt). This is extremely tight. If segment labels require more space at the specified font size, reduce to 3-letter abbreviations: "STL" / "SEQ" / "CLK" / "DUL" rather than "Still" / "Sequence" / "Clip" / "Dual". Validate on device.

**Film counter OCR-A at minimum size (15pt):**
OCR-A is a condensed typeface — 15pt renders approximately 9pt cap height, which is at the minimum legibility threshold in direct sunlight. If sunlight testing reveals illegibility, increase the formula coefficient from 0.038 to 0.042. Document this change as a v1.1 delta if applied.

**Sequence strip preview on iPhone 15 (210pt height):**
6 frames within 210pt height, with Spacing.md (16pt) padding top and bottom = 178pt usable. Each frame at 178pt tall, (390 − 5 × 8) / 6 = 58pt wide. Frame aspect ratio: 58:178 ≈ 1:3 — very tall and narrow. This is intentional — the contact sheet aesthetic works best with tall narrow frames. Validate the looping MP4 renders correctly in this aspect ratio.

---

*— End of Document — Piqd UI/UX Specification v1.0 · Requirements: piqd_UIUX_Requirements_v1.1.md · April 2026 —*
