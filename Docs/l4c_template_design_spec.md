# Life Four Cuts — Template-First UX Design Spec

_Drafted: 2026-04-08_

---

## 0. Current Implementation Status

As of `2026-04-08`, BOOTH has a working first-pass implementation inside `CaptureHub`, but it is not yet at the desired product quality.

### What is implemented

- `BOOTH` lives inside the same `CaptureHub` shell as other capture modes
- tap `START` runs an automatic 4-shot sequence
- each shot uses a `3 → 2 → 1` countdown, white flash, and slot-by-slot progression
- `More` exposes BOOTH controls for:
  - `Photo Shape`
  - `Template`
  - `Border Colour`
- `StripPreviewSheet` appears after shot 4
- live re-compositing works in the preview sheet when border or template changes
- final strip export path is wired through `LifeFourCutsUseCase` and `CoreImageCompositingAdapter`
- BOOTH now supports two slot-shape options:
  - `4:3`
  - `3:4`

### What has been attempted recently

- the BOOTH capture overlay was moved away from the old standalone booth screen and into `CaptureHub`
- the strip compositor was updated to use dynamic slot geometry based on `Photo Shape`
- the final strip renderer was changed from a flipped Core Graphics path to `UIGraphicsImageRenderer` to address upside-down strip output
- booth stills are now normalized upright before compositing, rather than force-rotated

### Current known gaps

1. **Preview guide and final crop still do not match perfectly**
- the active camera preview now has a more visible guide area, but it is still not a true WYSIWYG framing contract
- the captured booth photo can still differ from what the user thought the slot crop would be
- this is expected for now because the live camera preview and the saved still are still coming from different framing assumptions

2. **BOOTH needs a stronger preview-first framing model**
- the user wants the active slot to be the real guide for what will be taken
- for `4:3`, the preview should clearly show a wide landscape capture window
- for `3:4`, the preview should clearly show a tall portrait capture window
- the current overlay is better than before, but still not product-final

3. **Cropping rules need to be made explicit**
- booth stills are currently normalized and cropped in the app layer
- however, the exact crop contract between:
  - live camera preview
  - captured JPEG
  - final strip compositing
  still needs one unified rule

4. **Template system is still MVP-level**
- `Template` currently behaves more like a frame/border choice than a full layout system
- true template families, user-uploaded templates, and downloadable template packs are future work

### Current product conclusion

The BOOTH flow is now good enough to prove the overall interaction pattern:

1. BOOTH should stay in `CaptureHub`
2. BOOTH should use a review sheet after shot 4
3. BOOTH should support slot shape selection
4. BOOTH should evolve toward a template-first system

But the **preview-to-capture matching problem is still unresolved** and should be treated as the next quality milestone.

### Immediate next engineering milestone

The next BOOTH implementation milestone should focus on one thing:

- make the active preview guide and the final slot crop obey the same geometry

That means:

1. define a single source of truth for BOOTH slot geometry
2. use that geometry for the live guide
3. use that same geometry when normalizing/cropping captured stills
4. use that same geometry again in the final strip compositor

Until that is complete, BOOTH should be considered **functionally present but visually not yet trustworthy for framing**.

---

## 1. Product Position

Life Four Cuts (L4C) should not be treated only as a booth-strip feature.

It should be designed as:

- a 4-shot capture mode
- plus a template-based social composition system

User mental model:

1. capture 4 quick shots
2. choose a style/template
3. export a share-ready result

---

## 2. Core UX Principle

Split the experience into two phases:

### A. Capture Phase

- simple
- camera-first
- same `CaptureHub` shell as other asset types

### B. Review + Style Phase

- expressive
- template-driven
- social/share-first

This keeps capture clear and styling fun.

---

## 3. High-Level Flow

1. User swipes to `BOOTH`
2. The normal `CaptureHub` stays visible
3. Zone B shows a simple 4-slot booth overlay
4. User taps `START`
5. 4-shot sequence runs automatically
6. After shot 4, `StripReviewSheet` rises
7. User changes template / border / style
8. User `Retake`, `Share`, or `Export to Photo Library`

---

## 4. Capture Phase UI

Use the normal `CaptureHub` frame.

### Zone A

Keep the same top bar as all modes:

- `Flash`
- `Timer`
- `Flip Camera`
- `More`

### Zone B

Keep the full live preview and place a simple 4-slot booth guide on top.

Guide characteristics:

- centered vertically
- warm off-white frame
- translucent fill
- subtle shadow

Slot behavior:

- one slot is active at a time
- active slot has a brighter border and subtle accent glow
- captured slots fill with the frozen shot
- remaining slots stay dimmed/empty

### Zone C

Keep the same mode-anchor area as other modes.

- BOOTH should feel like another capture mode, not a separate screen
- preset bar footprint should remain stable even if Booth uses fewer controls

### Zone D

Keep the same shutter row.

Idle state:

- shutter shows `START`
- optional micro-label: `4 CUTS`

Active state:

- countdown and shot progress appear
- no separate dedicated booth screen

---

## 5. Capture Sequence Behavior

Sequence per shot:

1. user taps `START`
2. `3 → 2 → 1` countdown
3. white flash
4. still capture
5. captured shot freezes into the current slot
6. next slot becomes active

Timing targets:

- countdown: 1 second per numeral
- flash fade: ~0.25s
- freeze feedback: ~0.4s
- gap between shots: ~0.6s

This repeats 4 times automatically.

---

## 6. Review + Style Phase UI

After shot 4:

- a bottom review sheet rises over `CaptureHub`
- the live preview remains underneath, dimmed
- the sheet shows the composited output preview

The review sheet should feel like styling a printed object, not editing raw capture.

MVP controls:

- `Template`
- `Border Colour`
- `Retake`
- `Share`
- `Export to Photo Library`

Later controls:

- sticker density
- background theme
- custom text
- favorite template
- save as default

---

## 7. Template System

User-facing term:

- `Template`

Internal term:

- `FrameTemplate`

A template can define:

- layout geometry
- border/background
- overlay artwork
- stamp/text zones
- optional sticker/decor style

This is broader and more future-proof than the term "Featured Frame".

---

## 8. Why Templates, Not Just Frames

Reference examples show several different output types:

- classic booth strip
- editorial card layout
- playful sticker-heavy collage

These are not just borders. They include:

- page/background style
- slot arrangement
- decorative overlays
- typography
- stamp placement
- sticker language

So L4C should be modeled as a template system, not only a frame overlay feature.

---

## 9. MVP Template Families

Start with 3 bundled template families:

### A. Classic Strip

- clean vertical booth strip
- closest to traditional life-four-cuts

### B. Soft Editorial

- calmer, lifestyle/card aesthetic
- inspired by soft travel/editorial examples

### C. Sticker Pop

- colorful scrapbook / K-pop / Y2K feel
- more playful and youth-oriented

This gives meaningful variety without overbuilding the first release.

---

## 10. Design Rule: Capture Simple, Review Expressive

This is the most important rule.

### During Capture

- show only the simple booth guide
- avoid heavy stickers or full poster styling
- keep posing and framing easy

### During Review

- apply the selected template
- show the expressive final composition
- let users browse style options

This matches how real booth products feel:

- shooting is functional
- the result is the fun collectible object

---

## 11. BOOTH More Deck

Use the same `More` entry point as other capture modes.

MVP Booth controls:

- `Template`
- `Border Colour`
- `Timer`

Possible later controls:

- `Countdown Speed`
- `Save Source Shots`
- `Default Template`

Keep the controls light during capture.

---

## 12. Review Sheet Structure

Recommended structure:

### Header

- title: `Your Strip`
- `Retake`

### Main preview

- large composited output preview
- should feel like a printed strip/card lying on a subtle stage

### Styling controls

- template picker
- border colour picker

### Final actions

- `Share`
- `Export to Photo Library`

---

## 13. Data Model Direction

Suggested internal model:

```swift
struct FrameTemplate: Identifiable, Sendable {
    let id: String
    let displayName: String
    let category: TemplateCategory
    let sourceType: TemplateSourceType
    let previewAssetName: String
    let layoutSpec: TemplateLayoutSpec
    let overlayAssetName: String?
    let defaultColors: [String]
    let supportsCustomBorder: Bool
    let supportsStickers: Bool
}

enum TemplateSourceType: String, Sendable {
    case bundled
    case downloaded
    case userUploaded
}
```

This keeps the system ready for future expansion.

---

## 14. Template Source Roadmap

### v0.3.5 MVP

- bundled templates only

### Later

- downloaded template packs
- user-uploaded templates
- "My Templates"
- "Template Store"

This supports the future plan for:

- server-delivered frames
- downloadable packs
- personal uploaded frames/templates

---

## 15. Architecture Direction

Separate these concerns:

### A. Capture Layout

- simple 4-slot booth guide
- stable across all templates

### B. Template Asset

- bundled
- downloaded
- user-uploaded

### C. Composition Renderer

- takes 4 shots + template + style options
- produces final output

This makes future uploads/downloads much easier than tying the capture UI directly to one visual frame.

---

## 16. v0.3.5 MVP Scope Recommendation

Build in this order:

1. simple BOOTH overlay inside `CaptureHub`
2. 4-shot sequence state machine
3. bottom review sheet
4. 2–3 bundled templates
5. share/export flow
6. later: downloaded and uploaded templates

---

## 17. Design Goal

Capture should feel:

- fast
- understandable
- camera-native

Review should feel:

- playful
- collectible
- social-ready

That balance is what will make L4C both usable and distinctive.

---

## 18. Immediate Next Step — BOOTH Overlay State Machine

The most practical immediate build step is:

- implement the BOOTH overlay inside `CaptureHub`
- wire the 4-shot state machine
- do not start with templates, downloads, or advanced styling

This creates the foundation for everything else.

### 18.1 States

Recommended MVP state model:

```swift
enum BoothCaptureState: Equatable {
    case idle
    case countingDown(slotIndex: Int, count: Int)   // 3, 2, 1
    case flashing(slotIndex: Int)
    case freeze(slotIndex: Int)                     // captured image shown in slot
    case advancing(nextSlotIndex: Int)
    case completed                                  // all 4 captured
}
```

Supporting view data:

```swift
struct BoothSessionState {
    var state: BoothCaptureState = .idle
    var capturedImages: [UIImage?] = [nil, nil, nil, nil]
    var activeSlotIndex: Int = 0
    var selectedTemplateID: String = "classic_strip"
    var selectedBorderColor: String = "white"
}
```

### 18.2 UI By State

#### `idle`

- same `CaptureHub` shell visible
- booth 4-slot guide visible
- slot 0 highlighted
- shutter shows `START`
- `More` exposes BOOTH controls

#### `countingDown(slotIndex, count)`

- active slot highlighted more strongly
- large countdown numeral shown in the active slot
- already-captured slots remain filled
- remaining slots remain dim
- top bar still visible

#### `flashing(slotIndex)`

- white flash overlay fades quickly
- should feel like a camera event, not a full-screen transition

#### `freeze(slotIndex)`

- just-captured image freezes into the active slot
- freeze duration ~0.4s

#### `advancing(nextSlotIndex)`

- next slot becomes active
- no jarring transition
- previous slots remain filled

#### `completed`

- all 4 slots filled
- review sheet presented
- CaptureHub remains underneath

### 18.3 Sequence Timing

Per slot:

1. `count = 3`
2. wait 1.0s
3. `count = 2`
4. wait 1.0s
5. `count = 1`
6. wait 1.0s
7. `flashing`
8. capture still
9. `freeze`
10. wait 0.4s
11. if slot < 3:
    - `advancing(nextSlotIndex)`
    - wait 0.6s
    - begin next countdown
12. else:
    - `completed`

### 18.4 Minimal UI Components To Build First

Build only these first:

1. `BoothStripOverlayView`
- renders 4-slot vertical frame
- shows active slot
- shows captured slot images

2. `BoothCountdownView`
- renders countdown numeral in active slot

3. `BoothFlashOverlay`
- fast white flash

4. `BoothSessionController`
- owns the state machine and timing

Do not build first:

- downloaded templates
- user uploads
- sticker systems
- advanced review styling

### 18.5 Implementation Order

#### Step 1

Render `BOOTH` mode using the normal `CaptureHub` shell with a placeholder 4-slot overlay.

Success condition:

- swiping to BOOTH shows the booth guide immediately

#### Step 2

Add `idle -> countingDown` transition when tapping `START`.

Success condition:

- countdown appears in slot 1

#### Step 3

Wire one real still capture into the active slot.

Success condition:

- first slot fills with captured image

#### Step 4

Loop the sequence through all 4 slots.

Success condition:

- all 4 slots fill in order with no sheet yet

#### Step 5

Present a placeholder review sheet after slot 4 completes.

Success condition:

- the user sees a clear end state and can retake

#### Step 6

Replace placeholder review content with the first real `Classic Strip` composite.

### 18.6 Definition Of Done For This Step

This immediate task is complete when:

- BOOTH mode uses the same CaptureHub shell as other modes
- the 4-slot overlay appears reliably
- tapping `START` runs the 4-shot countdown/capture sequence
- each captured shot fills the correct slot
- a review sheet appears after shot 4

At that point, the template system can be layered on top safely.
