# niftyMomnt — Interim Version Plan
# v0.1 → v1.0 Feature Ladder

_Reference: PRD v1.6 · UI/UX Spec v1.7 · SRS v1.2_
_Last updated: 2026-04-10 · v0.2 + v0.3 signed off; v0.3.5 mode-switching performance resolved; v0.4 implementation complete — pending device verification; v0.5 implementation complete — classification verified on device (music=0.92, singing=0.58 confirmed)_

---

## Legend

| Symbol | Meaning |
|--------|---------|
| ⬜ | Not Started |
| 🔄 | In Progress |
| ✅ | Complete |

---

## Version Summary Table

| Version | Verification Goal | Status |
|---------|-------------------|--------|
| [v0.1](#v01--minimum-viable-capture-to-share) | Full data flow: Still capture → classify → persist → feed → share | ✅ |
| [v0.2](#v02--persistent-metadata--feed-quality) | Real moment metadata: location, time, palette, vibe tags in feed | ✅ |
| [v0.3](#v03--multi-mode-capture) | All 5 asset types captured and stored correctly | ✅ |
| [v0.3.5](#v035--life-four-cuts-photo-booth-mode) | Photo booth flow: 4-shot countdown, strip compose, Featured Frame overlay, share-ready 9:16 image | 🔄 |
| [v0.4](#v04--vibe-preset-system) | Preset selection maps to stored tags; accent theming in feed | 🔄 |
| [v0.5](#v05--sound-stamp--acoustic-pipeline) | SoundStamp captures PCM at shutter; acoustic tags in feed | ✅ |
| [v0.6](#v06--ai-nudge-engine) | Post-capture nudge card fires; response stored in graph | ⬜ |
| [v0.7](#v07--private-vault--face-id) | Assets marked private locked behind Face ID; vault tab functional | ⬜ |
| [v0.8](#v08--story-engine--reel-assembler) | Moment cluster produced; reel assembled with voice overlay | ⬜ |
| [v0.9](#v09--extended-intelligence--dual-camera) | Dual-camera capture; Lab Mode; Journaling Suggestions; AI caption | ⬜ |
| [v1.0](#v10--full-feature-set--app-store-ready) | All MVP features gated, tested, performant; App Store submission ready | ⬜ |

---

## v0.1 — Minimum Viable Capture-to-Share

**Verification goal:** End-to-end data flow verified on device — Still capture → on-device image classify → VaultRepository → GraphRepository → JournalFeed (real data) → UIActivityViewController share.

**AppConfig:** `AppConfig.v0_1` — `assetTypes: .still`, `aiModes: .onDevice`, `features: []`

**Out of scope for v0.1:** Sound Stamp · Dual-Camera · Photo Fix · Chromatic Profiling · Acoustic Analysis · Ambient Metadata · Moment Clustering · Nudge Engine · Vibe Preset System · Private Vault · Story/Reel · Journaling Suggestions API

### Features In Scope

- Still photo capture via `AVCapturePhotoOutput` (back camera, front camera flip)
- Image classification: `VNClassifyImageRequest` → `VibeTag` (Mode-0 on-device only)
- Persist asset file: `VaultRepository` → `Documents/assets/{id}.jpg` + GRDB `asset_files` table
- Persist moment + tags: `GraphRepository` → GRDB (`assets`, `moments`, `moment_assets`)
- JournalFeed loads real `[Moment]` from `GraphManager.fetchMoments()`
- Feed refreshes on `NotificationCenter.niftyMomentCaptured`
- Share: `UIActivityViewController` via `UIViewControllerRepresentable` wired to Share button in `MomentDetailView`

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | Create `Docs/interim_version_plan.md` | `Docs/interim_version_plan.md` | ✅ |
| 2 | Add `AppConfig.v0_1` | `Apps/niftyMomnt/AppConfig+Interim.swift` | ✅ |
| 3 | `VaultRepository`: `Documents/assets/{id}.jpg` + JSON metadata sidecar | `NiftyData/Sources/Repositories/VaultRepository.swift` | ✅ |
| 4 | `GraphRepository`: GRDB schema (`assets`, `moments`, `moment_assets`) + `saveMoment`, `fetchMoments`, `updateVibeTag` | `NiftyData/Sources/Repositories/GraphRepository.swift` | ✅ |
| 5 | `CoreMLIndexingAdapter.classifyImage()`: `VNClassifyImageRequest` + identifier→`VibeTag` mapping | `NiftyData/Sources/Platform/CoreMLIndexingAdapter.swift` | ✅ |
| 6 | `IndexingEngine.classifyImmediate(id:imageData:)` — detached background task | `NiftyCore/Sources/Engines/IndexingEngine.swift` | ✅ |
| 7 | `GraphManager.fetchMoments(query:) async throws -> [Moment]` | `NiftyCore/Sources/Managers/GraphManager.swift` | ✅ |
| 8 | `CaptureMomentUseCase.captureAsset()`: full pipeline + `graph: GraphManager` init param | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift` | ✅ |
| 9 | `niftyMomntApp.swift`: pass `graph: graphManager` to `CaptureMomentUseCase` | `Apps/niftyMomnt/niftyMomntApp.swift` | ✅ |
| 10 | `JournalFeedView`: `.onAppear` load + `.onReceive` refresh + `ActivityViewController` share sheet | `Apps/niftyMomnt/niftyMomnt/UI/Journal/JournalFeedView.swift` | ✅ |
| 11 | `CaptureHubView`: thumbnail wired to last captured photo; Vision runs on detached task | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ✅ |
| 12 | **Post-v0.1 fix:** Corrected `PRODUCT_BUNDLE_IDENTIFIER` from `group.com.hwcho99.niftyMomnt` → `com.hwcho99.niftyMomnt` (removed erroneous `group.` prefix); removed App Group entitlement (deferred to v0.9+); updated all `com.hwcho.` strings to `com.hwcho99.` across Swift, plist, and entitlement files | `project.pbxproj`, `*.entitlements`, `Info.plist`, all Swift files | ✅ |

### Verification Checklist

> Run on a real device. Record Pass / Fail / Note per row. All rows must pass before starting v0.2.

#### 1 — Capture

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 1.1 | Launch app | Camera preview visible in Zone B, no crash | |
| 1.2 | Tap shutter button | Post-capture overlay appears (~100ms), vibe chip options shown | |
| 1.3 | Wait ~1–2s after tap | Thumbnail left of shutter updates to the captured photo (no blank, no "▶ LIVE") | |
| 1.4 | Tap shutter 3 more times | Overlay fires each time; thumbnail updates to latest shot each time | |

#### 2 — Persist (Vault)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 2.1 | After each capture, check Xcode console | No `[CaptureHub] captureAsset failed:` lines | |
| 2.2 | _(optional)_ Xcode Device File Browser → `Documents/assets/` | One `.jpg` + one `.json` sidecar per capture | |

#### 3 — Classify (VibeTags)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 3.1 | Capture a bright outdoor / golden-hour scene | Moment in feed shows vibe chips (e.g. `.golden`, `.serene`) — non-empty | |
| 3.2 | Capture a dark or indoor scene | Vibe chips reflect `.moody`, `.cozy`, or `.raw` | |
| 3.3 | Capture an ambiguous subject | Acceptable if chips are empty — moment still saved | |

#### 4 — Film Feed

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 4.1 | Swipe up to open Film | At least one moment card visible — not permanently empty | |
| 4.2 | Swipe down → capture → tap shutter → swipe up | New moment card appears at top of feed on re-open | |
| 4.3 | ⚠️ Kill and relaunch app → open Film | Previously captured moments still present (GRDB persisted, not in-memory) | ✅ Pass (see note) |
| 4.4 | Capture while Film is already open (journal visible) | Feed refreshes in-place without closing journal | |

> **4.3 persistence note.** Originally passed under the malformed `group.com.hwcho99.niftyMomnt` bundle ID. After correcting the bundle ID to `com.hwcho99.niftyMomnt` (removing the erroneous `group.` prefix and removing the App Group entitlement), the app sandbox path changed and previously captured data became unreachable — causing an apparent regression to in-memory fallback. **Resolution: delete and reinstall the app from the device** (long-press → Remove App → reinstall via Xcode). After a clean install, GRDB opens at the correct path under the new sandbox and persistence is confirmed working. No code changes required — `GraphRepository.databaseURL()` uses `Documents/` which is correct per Architecture Decision G (App Group deferred to v0.9+).

#### 5 — Share

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 5.1 | Tap a moment card | `MomentDetailView` sheet opens | ✅ Pass |
| 5.2 | Tap Share button (top-right lavender icon) | System `UIActivityViewController` sheet appears | ✅ Pass |
| 5.3 | Tap Share button in bottom sheet | Same share sheet appears | ✅ Pass |
| 5.4 | Share to Notes or save to Photos | Completes without crash | ✅ Pass |

#### 6 — Edge Cases

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 6.1 | Double-tap viewfinder to flip camera → capture | Thumbnail shows front-camera shot; moment appears in feed | ✅ Pass |
| 6.2 | Rapid-tap shutter 5× | No crash; each capture processes; thumbnail shows last shot | ✅ Pass |

### v0.1 Sign-off

| Item | Status |
|------|--------|
| All verification rows passing | ✅ |
| 4.3 persistence confirmed (GRDB file DB, not in-memory) | ✅ |
| No `[CaptureHub]` or `[FilmFeed]` errors in console | ✅ |
| **v0.1 complete — ready for v0.2** | ✅ |

---

## v0.2 — Persistent Metadata & Feed Quality

**Verification goal:** Captured moments display real location chip, capture time, chromatic palette accent, and accurate vibe tags in `MomentCardView` — no placeholder data.

**AppConfig:** `AppConfig.v0_2` — adds `AssetTypeSet.still`, ambient harvesting on, palette extraction on

**Out of scope:** Sound Stamp · Multi-mode capture · Presets · Nudge · Vault · Story

### Features In Scope

- `MapKitGeocoderAdapter`: reverse-geocode GPS coordinate → `PlaceRecord` (city, neighborhood)
- `WeatherKitAdapter`: fetch weather condition + temperature at capture time
- `CoreMLIndexingAdapter.extractPalette()`: dominant color → `ChromaticPalette`
- `IndexingEngine`: add palette extraction step after classification
- `GraphRepository`: `updatePlaceRecord()`, `saveMoodPoint()` implementations
- `MomentCardView`: real location chip, real vibe tag chips, palette-derived accent color
- `FilmFeedView`: geo-tagged timeline grouping (THIS WEEK / LAST WEEK / MONTH using real dates)

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `MapKitGeocoderAdapter`: `CLGeocoder` → `PlaceRecord`; conforms to `GeocoderProtocol` | `NiftyData/Sources/Platform/MapKitGeocoderAdapter.swift` | 🔄 |
| 2 | `OpenMeteoWeatherAdapter`: Open-Meteo free API → temperature + condition (replaces WeatherKit — paid tier not available) | `NiftyData/Sources/Platform/WeatherKitAdapter.swift` | 🔄 |
| 3 | `CoreMLIndexingAdapter.extractPalette()`: `CIAreaAverage` 5-region dominant color | `NiftyData/Sources/Platform/CoreMLIndexingAdapter.swift` | 🔄 |
| 4 | `IndexingEngine`: add `extractPaletteImmediate` + `harvestAmbientImmediate` for inline capture path | `NiftyCore/Sources/Engines/IndexingEngine.swift` | 🔄 |
| 5 | `GraphRepository`: implement `updatePlaceRecord()`, `saveMoodPoint()`; add ambient+palette columns | `NiftyData/Sources/Repositories/GraphRepository.swift` | 🔄 |
| 6 | `CaptureMomentUseCase`: add geocoder param; run palette + ambient + geocode concurrently in pipeline | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift` | 🔄 |
| 7 | `MomentCardView`: `placeLabel` reads real location from `moment.label`; `dateSubtitle` shows real sun position | `Apps/niftyMomnt/niftyMomnt/UI/Journal/MomentCardView.swift` | 🔄 |
| 8 | `MomentDetailView`: delete button (trash) in actions row → `confirmationDialog` → delete vault files + graph record + notify feed | `Apps/niftyMomnt/niftyMomnt/UI/Journal/JournalFeedView.swift` | 🔄 |

### Verification Checklist

> Run on a real device with Location Services enabled. Record Pass / Fail / Note per row. All rows must pass before starting v0.3.

#### 1 — Location (Geocoder)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 1.1 | Launch app → open CaptureHub (camera view) → system location permission prompt appears automatically | Tap "Allow While Using App". If previously denied: **Settings → Privacy & Security → Location Services → niftyMomnt → While Using** | |
| 1.2 | Capture a photo outdoors or in a recognisable area. Check Xcode console for `[MapKitGeocoder]` lines — confirm `reverseGeocode` was called and a name was resolved | `MomentCardView` title row shows a real neighbourhood / city name (e.g. "Hongdae · AMALFI"); console shows `reverseGeocode — resolved '...'` | |
| 1.3 | Capture in an area with no GPS signal (indoors, airplane mode) | Card still saves and shows a date-based fallback label — no crash | |
| 1.4 | Kill and relaunch app → open Film | Location name persists in feed (stored in `moments.label` in GRDB) | |

#### 2 — Weather (Open-Meteo)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 2.1 | Capture a photo with network available | `MomentCardView` date subtitle shows a weather emoji + temperature (e.g. "☀️ 22°") | |
| 2.2 | Capture in airplane mode | No crash; weather fields are blank in subtitle — moment still saves | |
| 2.3 | Capture 2 photos within 30 min from the same area | Console shows `cache hit` for the second weather fetch (no duplicate network call) | |
| 2.4 | Kill and relaunch → open Film | Weather emoji + temperature visible on previously captured cards (persisted in `ambient_weather` / `ambient_temp_c` columns) | |

#### 3 — Sun Position

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 3.1 | Capture during daytime (7–17h) | `MomentCardView` date subtitle includes a sun position label (e.g. "morning", "midday", "afternoon") | |
| 3.2 | Capture around sunrise / sunset window | Label shows "sunrise" or "sunset" accordingly | |
| 3.3 | Kill and relaunch → open Film | Sun position label persists on card (`ambient_sun_pos` column) | |

#### 4 — Chromatic Palette

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 4.1 | Capture a brightly coloured scene (golden hour, neon, greenery) | Xcode console logs `extractPalette done — N color(s) extracted` with N ≥ 1 | |
| 4.2 | Kill and relaunch → open Film | Moment card loads without crash; palette is non-nil (confirmed via console or debugger) | |
| 4.3 | Capture a near-black or near-white scene | Palette extraction completes without crash; 0–1 color(s) returned is acceptable | |

#### 5 — Place History (GraphRepository)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 5.1 | Capture 3+ photos in the same neighbourhood | `place_history` table contains a row for that place (verify via Xcode Device File Browser → `Documents/graph.sqlite`) | |
| 5.2 | Capture again at the same place after relaunching | `visit_count` for that place increments (upsert ON CONFLICT working) | |

#### 6 — Delete Photo

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 6.1 | Tap a moment card → `MomentDetailView` opens | Trash button visible at right end of actions row (red-tinted) | |
| 6.2 | Tap trash → confirmation dialog appears | Dialog shows "Delete this photo?" with destructive "Delete Photo" + "Cancel" | |
| 6.3 | Tap "Cancel" | Sheet stays open; moment unchanged | |
| 6.4 | Tap trash → "Delete Photo" | Sheet dismisses; moment card is removed from feed | |
| 6.5 | Kill and relaunch → open Film | Deleted moment does not reappear (removed from GRDB + vault files deleted) | |
| 6.6 | Verify `Documents/assets/` via Xcode Device File Browser | No orphaned `.jpg` or `.json` sidecar for the deleted moment | |

#### 7 — Regression (v0.1 pipeline still intact)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 7.1 | Capture a photo | Post-capture overlay still appears; thumbnail updates in Zone D | |
| 7.2 | Open Film | New moment card appears with vibe tags | |
| 7.3 | Tap Share in `MomentDetailView` | `UIActivityViewController` sheet appears | |

### v0.2 Sign-off

| Item | Status |
|------|--------|
| All verification rows passing | ✅ |
| Location name shown on card (or graceful fallback confirmed) | ✅ |
| Weather + sun position persisted and visible after relaunch | ✅ |
| Deleted moment fully removed from GRDB + vault | ✅ |
| **v0.2 complete — ready for v0.3** | ✅ |

---

## v0.3 — Multi-Mode Capture

**Verification goal:** All 5 asset types (Still, Live, Clip, Echo, Atmosphere) can be captured, stored, and displayed in the feed with correct type labels and thumbnails.

**AppConfig:** `AppConfig.v0_3` — `assetTypes: .all`

### Features In Scope

- `AVCaptureAdapter`: Live Photo via `AVCapturePhotoOutput` with `livePhotoMovieFileURL`
- `AVCaptureAdapter`: Clip via video recording path; Echo via audio-only AAC / M4A path
- `AVCaptureAdapter`: Atmosphere placeholder path pending replacement with still + audio loop flow
- `CaptureMode` navigation in `CaptureHubView` — mode rail scroll, preset bar visibility per mode
- `VaultRepository`: store `.mov`/`.mp4` alongside JPEG; `asset_files` type column
- `MomentCardView`: video thumbnail, Live badge, type-appropriate overlay

### Implementation Notes

- Live Photo in v0.3: captures a still JPEG with `.live` type — shows LIVE badge in feed. Live motion companion file (`.mov`) deferred to v0.4+.
- Clip currently uses `AVCaptureMovieFileOutput` for `.mov` recording.
- Echo now uses an audio-only `.m4a` capture path and should be verified as an audio asset, not a video asset.
- Atmosphere has been pivoted to a **Still + Looping Audio (JPEG + M4A)** hybrid. High-res capture is triggered at the stop of an audio recording session.
- `saveVideoFile(_:sourceURL:)` moves the `.mov` file rather than loading it into memory.
- Video classification (vibe tags from video frame) deferred to v0.5.

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `CaptureEngineProtocol`: add `startRecording(mode:)` + `stopRecording() -> Asset` | `NiftyCore/Sources/Domain/Protocols/CaptureEngineProtocol.swift` | ✅ |
| 2 | `VaultProtocol` + `VaultManager` + `VaultRepository`: add `saveVideoFile(_:sourceURL:)` | `NiftyCore/…/VaultProtocol.swift`, `VaultManager.swift`, `VaultRepository.swift` | ✅ |
| 3 | `AVCaptureAdapter`: `AVCaptureMovieFileOutput` + audio input + `MovieDelegate` + `startRecording` + `stopRecording` + `switchMode` output-class reconfigure | `NiftyData/Sources/Platform/AVCaptureAdapter.swift` | ✅ |
| 4 | `CaptureMomentUseCase`: `switchMode`, `startVideoRecording`, `stopVideoRecording` pipeline | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift` | ✅ |
| 5 | `CaptureHubView`: `cycleMode` wired to `switchMode`; Clip tap → start/stop + auto-stop at ceiling; Echo/Atmosphere tap → start/stop | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ✅ |
| 6 | `MomentCardView`: asset type badge (LIVE/CLIP/ECHO/ATMOS) + `AVAssetImageGenerator` video thumbnail | `Apps/niftyMomnt/niftyMomnt/UI/Journal/MomentCardView.swift` | ✅ |

### Verification Checklist

> Run on a real device. Record Pass / Fail / Note per row. All rows must pass before starting v0.4.

#### 1 — Still (regression)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 1.1 | Launch → capture a still photo | Overlay appears, thumbnail updates, moment in feed — v0.2 pipeline intact | |
| 1.2 | Open Film → tap card | Detail view shows location, weather, vibe tags | |

#### 2 — Live Mode

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 2.1 | Swipe mode rail to LIVE **or** tap Live Photo pill (Zone A right ①) | "LIVE" ghost label flashes; mode anchor dot updates; Live Photo pill shows active (brighter) state | |
| 2.2 | Tap shutter in LIVE mode | Post-capture overlay appears; Xcode console shows `captureAsset — live MOV at temp: present`; moment appears in feed with LIVE badge | |
| 2.3 | Kill and relaunch → open Film | LIVE moment present with LIVE badge; Xcode Device File Browser → `Documents/assets/` shows both `{id}.jpg` and `{id}.mov` | |
| 2.4 | Tap LIVE card → Detail View | `PHLivePhotoView` plays the 3 s motion loop (not a static image); tapping the view replays it | |
| 2.5 | Delete LIVE moment from Detail View | Both `{id}.jpg` and `{id}.mov` removed from `Documents/assets/` (no orphan files) | |
| 2.6 | Tap Live Photo pill again while in LIVE mode | Switches back to STILL; ghost label "S T I L L" flashes; pill returns to dim state | |

> **Device note.** If the device does not support Live Photo capture (simulator or unsupported hardware), the console logs `live MOV at temp: MISSING` / `saved as JPEG-only Live`. The LIVE badge and card still appear correctly with a static JPEG; Detail View shows the still frame. This is acceptable fallback behaviour and does not block sign-off on a supported device.

#### 3 — Clip Mode

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 3.1 | Swipe to CLIP mode | Ghost label "CLIP" flashes | |
| 3.2 | Tap More while in CLIP mode | Capture Controls deck shows `Video Format` (`VGA`, `HD`, `4K`) and `Clip Length` (`5s`, `10s`, `15s`, `30s`) — no still/live-only rows shown | |
| 3.3 | Select `5s` Clip Length → tap shutter once | Recording starts immediately; `isRecording` true; REC overlay visible; countdown timer visible on shutter; clip progress ring fills | |
| 3.4 | Do not tap again and wait past the 5s ceiling | Recording auto-stops at ~5s; preset bar expands again; no freeze/crash | |
| 3.5 | Select `10s` Clip Length → tap shutter once → tap again after ~3s | Recording stops early on second tap; moment appears in feed with CLIP badge and a video thumbnail (first frame) | |
| 3.6 | Open the captured CLIP in Film / Detail | Hero media loads without crash; clip is recognisable as video content rather than a blank or still-only failure state | |
| 3.7 | Record one CLIP while holding phone in portrait | Saved clip plays back in portrait orientation (social-ready vertical output) | |
| 3.8 | Record one CLIP while holding phone in landscape | Saved clip plays back in landscape orientation | |
| 3.9 | In CLIP mode, switch Video Format across `VGA`, `HD`, `4K` and start a short recording each time | Recording starts successfully for each selection; if a preset is unsupported on the device, safe fallback is used and capture still succeeds | |
| 3.10 | Kill and relaunch | CLIP moment persists; `.mov` file present in `Documents/assets/` | |

> **Clip note.** `Video Format` is currently a recording preset selector, not a freeform aspect-ratio picker: `VGA` = `640×480` (4:3), `HD` = `1920×1080` (16:9), `4K` = `3840×2160` (16:9). User-held device orientation at record start should determine whether playback is portrait or landscape. For v0.3 stabilization, CLIP currently uses tap-to-start / tap-to-stop instead of hold-to-record; Slide to Lock remains deferred.

#### 4 — Echo Mode

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 4.1 | Swipe to ECHO mode | Ghost label "ECHO" flashes | |
| 4.2 | Tap More while in ECHO mode | Capture Controls deck shows `Echo Limit` only; no Clip / Still / Live rows shown | |
| 4.3 | Tap shutter to start, tap again to stop (~3s) | Recording starts and stops; REC overlay remains visible while recording; moment appears in feed with ECHO badge | |
| 4.4 | Open the captured ECHO in Film / Detail | Detail shows an audio-only Echo player card, not a video player or broken image state | |
| 4.5 | Tap Share on the Echo detail | Standard share sheet opens with the `.m4a` file prepared successfully | |
| 4.6 | In Echo detail, inspect bottom actions | `Fix this shot` and `Export to Photo Library` are not shown for Echo | |
| 4.7 | Kill and relaunch | ECHO moment persists; audio file exists as `.m4a` in `Documents/assets/` | |

#### 5 — Atmosphere Mode

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 5.1 | Swipe to ATMOS mode | Ghost label "ATMOS" flashes | |
| 5.2 | Tap shutter to START | Recording starts; REC overlay visible; status reads "ATMOS" | |
| 5.3 | Tap shutter to STOP | White flash indicates high-res capture; audio recording stops; thumbnail updates to the high-res frame | |
| 5.4 | Check Xcode Device File Browser → `Documents/assets/` | Verify two files exist for the asset ID: `{id}.jpg` and `{id}.m4a` | |
| 5.5 | Open ATMOS moment in Detail View | High-res static image is displayed; background audio begins playing automatically | |
| 5.6 | Observe audio for > 10s | Audio loops seamlessly from the end back to the start | |
| 5.7 | Kill and relaunch | ATMOS moment persists in feed with ATMOS badge and high-res thumbnail | |

> **Echo note.** Echo is treated as an audio-only asset for capture, persistence, and share.
> **Atmosphere note.** Atmosphere capture leverages the high-resolution photo output while maintaining a background audio recording session.

#### 6 — Mode Switching (session reconfigure)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 6.1 | Swipe from STILL → CLIP → STILL | No crash; camera preview remains live throughout | |
| 6.2 | In CLIP mode, check Xcode console | Log shows `switchMode — output class change, reconfiguring session` when crossing photo↔video boundary | |

#### 7 — Regression (v0.2 metadata)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 7.1 | Capture a still | Location, weather, sun position still appear on card | |
| 7.2 | Share from MomentDetailView | `UIActivityViewController` still works | |

### v0.3 Sign-off

| Item | Status |
|------|--------|
| Mode switching (photo↔video class change) verified on device | ✅ |
| All 5 asset types captured and stored | ✅ |
| Type badge visible on each card type | ✅ |
| Video thumbnail loads for clip/echo/atmosphere | ✅ |
| All verification rows passing | ✅ |
| **v0.3 complete — ready for v0.3.5** | ✅ |

---

## v0.3.5 — Life Four Cuts (Photo Booth Mode)

> **Status: 🔄 In Progress — BOOTH flow is implemented inside CaptureHub, but preview-to-capture framing still needs refinement**

> **Design reference:** See `Docs/l4c_template_design_spec.md` for the current template-first L4C UX direction. That note is the working design reference for keeping BOOTH inside the standard CaptureHub shell while moving styling/template expression into the review phase.

> **Current engineering note:** The BOOTH sequence, review sheet, border selection, and slot-shape selection are all working. The main remaining gap is that the live preview guide and the final booth crop still do not match closely enough for user-trustworthy framing.

**Verification goal:** User can trigger a 4-shot photo-booth countdown from Capture Hub, preview the assembled vertical strip with a Featured Frame overlay, customise the border colour, and export a single share-ready 9:16 JPEG to the system share sheet or directly to Camera Roll.

**AppConfig:** `AppConfig.v0_3_5` — same as v0.3 + `features: .l4c`

**Out of scope for v0.3.5:** Downloadable frame packs (server CDN) · AI-generated captions on strip · Private-vault L4C · Video booths (4 short clips instead of 4 stills)

---

### 1. New Domain Types

#### 1.1 `AssetType.l4c`

Add `case l4c` to the existing `AssetType` enum. An L4C asset is a single composite JPEG that represents the assembled strip. The 4 source stills are stored separately as ordinary `.still` assets and linked via a new `L4CRecord`.

```
AssetType.l4c   →  Documents/assets/{id}.jpg   (the composite strip)
                    Documents/assets/{id}.json  (sidecar: sourceAssetIDs[4], frameID, borderColor)
AssetType.still ×4  →  Documents/assets/{stillID}.jpg  (source frames, no change)
```

**Why this model?** Keeps vault and graph generic. The composite is the sharable artefact. Source stills are independently viewable in the feed as a separate Moment (or can be hidden — see §4.1).

#### 1.2 `CaptureMode.photoBooth`

Add `case photoBooth` to `CaptureMode`. The mode rail swipe cycles through it like any other mode. Ghost label: `"B O O T H"`.

#### 1.3 `L4CRecord` (NiftyCore domain model)

```swift
public struct L4CRecord: Identifiable, Sendable {
    public let id: UUID                     // = composite asset ID
    public let sourceAssetIDs: [UUID]       // exactly 4, in capture order
    public let frameID: String              // bundle name of the Featured Frame PNG, or "none"
    public let borderColor: L4CBorderColor  // .white | .black | .pastelPink | .skyBlue | .custom(hex:)
    public let capturedAt: Date
    public let location: GPSCoordinate?
    public let label: String                // place name or date fallback (same as Moment.label)
}

public enum L4CBorderColor: String, CaseIterable, Sendable {
    case white, black, pastelPink, skyBlue
}
```

#### 1.4 `FeaturedFrame` (NiftyCore domain model)

```swift
public struct FeaturedFrame: Identifiable, Sendable {
    public let id: String           // matches PNG asset name in app bundle
    public let displayName: String  // e.g. "Spring Blossom"
    public let previewColorHex: String  // used in carousel before PNG loads
    // PNG has alpha=0 in the 4 photo slots; artwork fills the rest
}
```

---

### 2. Capture Flow (Photo Booth)

```
User taps BOOTH mode in mode rail
    ↓
CaptureHub shell remains intact (same Zone A / Zone C / Zone D structure as other modes)
    ↓
[4-slot booth strip overlay appears on top of the live preview]
    ↓
User taps shutter / START state in BOOTH mode
    ↓
Shot 1: "3... 2... 1... ✦"  →  flash overlay  →  capture still
Shot 2: "3... 2... 1... ✦"  →  flash overlay  →  capture still
Shot 3: "3... 2... 1... ✦"  →  flash overlay  →  capture still
Shot 4: "3... 2... 1... ✦"  →  flash overlay  →  capture still
    ↓
[Strip Review Sheet — bottom sheet over CaptureHub, shows assembled strip]
    ↓
User picks border colour / Featured Frame in the review sheet or More deck
    ↓
"Save & Share" → composites final strip → VaultRepository → share sheet
```

**Countdown UX detail:**
- Each "3... 2... 1..." is animated with large bold numbers (≥80pt, white, centred).
- At "✦": full-screen white flash (`opacity: 1 → 0` in 0.25s) signals capture.
- Brief "freeze frame" thumbnail (0.4s) shows the captured shot before the next countdown.
- Between shots 1→2, 2→3, 3→4: 0.6s gap (to let the user reset pose).
- Countdown speed setting: fixed at 1s/count in v0.3.5; configurable in a later version.
- The strip overlay remains visible during the whole capture sequence; captured slots fill in place so progress is obvious without leaving the standard camera surface.

---

### 3. Compositing Pipeline (`L4CCompositor`)

A new `L4CCompositor` struct in `NiftyCore` (pure Swift, no platform imports — uses a `CompositingAdapterProtocol` for the actual CoreImage work).

```
Input:  [Data × 4]  +  FeaturedFrame  +  L4CBorderColor  +  L4CStampConfig
Output: Data  (JPEG, 9:16 aspect, target ≥ 1080×1920px)
```

#### 3.1 Strip layout geometry

```
Total canvas:  1080 × 1920  (9:16, standard IG story)

Border thickness:  ~28pt all sides, ~20pt between frames
                   Adjusts automatically so 4 equal-height photo slots fill the interior.

Photo slot height: (1920 − 2×28 − 3×20) / 4  ≈  444px each
Photo slot width:  1080 − 2×28              = 1024px

Bottom stamp zone: 64px  (below last slot, within border)
    → App logo (centred, white, ~40px tall)  +  date/location in smaller text below
```

#### 3.2 Featured Frame compositing (PNG window)

The Featured Frame PNG (`1080 × 1920`, RGBA) has:
- **alpha = 0** in the 4 photo-slot rectangles (photo shows through)
- **alpha = 1** in the artwork region (floral graphics, brand logo, holiday decorations, etc.)

Compositing order (back → front):
1. Solid border colour fill (full canvas)
2. The 4 cropped/scaled source photos placed at slot positions
3. Bottom stamp (app wordmark + date label rendered to bitmap)
4. Featured Frame PNG composited on top (`kCGBlendModeNormal`)

For "no frame" (plain border), steps 1–3 only.

#### 3.3 `CompositingAdapterProtocol` (NiftyData)

```swift
public protocol CompositingAdapterProtocol: AnyObject, Sendable {
    func compositeStrip(
        photos: [Data],           // exactly 4 JPEGs
        borderColor: L4CBorderColor,
        frameAssetName: String?,  // bundle PNG name, nil = no frame
        stamp: L4CStampConfig
    ) async throws -> Data        // JPEG output
}
```

Implemented by `CoreImageCompositingAdapter` in `NiftyData` using `CIFilter`, `CGContext`, and `CoreText` for the stamp label. No UIKit dependency (so it can run in a background actor).

#### 3.4 `L4CStampConfig`

```swift
public struct L4CStampConfig: Sendable {
    public let dateText: String       // e.g. "Apr 7 · 2026"
    public let locationText: String   // place name or empty
    public let showAppLogo: Bool      // default true
}
```

---

### 4. Persistence

#### 4.1 `GraphRepository` additions

New table: `l4c_records`

```sql
CREATE TABLE l4c_records (
    id              TEXT PRIMARY KEY,
    source_ids      TEXT NOT NULL,   -- JSON array of 4 UUIDs
    frame_id        TEXT NOT NULL,   -- "none" or bundle asset name
    border_color    TEXT NOT NULL,
    captured_at     REAL NOT NULL,
    location_lat    REAL,
    location_lon    REAL,
    label           TEXT NOT NULL
);
```

**Feed integration:** L4C assets appear in `FilmFeedView` as a special card (`L4CMomentCardView`) using the composite JPEG as hero image and a "✦ BOOTH" badge. They live alongside regular Moment cards in the same chronological timeline. Source stills (`AssetType.still`) captured during the booth session are **not** shown as separate cards (linked and hidden via `source_ids`).

#### 4.2 Delete behaviour

Deleting an L4C card: removes the composite asset + sidecar from vault, removes the `l4c_records` row, and removes the 4 linked source stills + their vault files. (Cascade all the way through.)

---

### 5. UI Components

#### 5.1 `BoothCaptureOverlay` (new Zone B overlay inside `CaptureHub`)

Entered when user swipes to BOOTH mode. The app keeps the normal `CaptureHub` shell rather than replacing it with a dedicated full-screen booth screen.

**Zones (same CaptureHub shell, mode-specific overlays only):**

| Zone | Content |
|---|---|
| Zone A | Same top bar as other modes: Flash / Timer / Flip / More |
| Zone B | `CameraPreviewView` + centred 4-slot booth strip guide (warm white frame, translucent fill) |
| Zone B — overlay | Countdown label in active slot; white flash + freeze feedback after each capture |
| Zone C | Same mode anchor / preset area footprint; booth-specific controls may collapse or simplify |
| Zone D | Standard shutter row; in BOOTH idle state the shutter shows `START` treatment, then runs the 4-shot sequence automatically |

**Booth strip overlay:**
- Uses the 4-slot vertical frame as a composition guide over the live preview.
- One slot is active at a time (slightly brighter border / accent glow).
- Captured shots freeze into completed slots as the sequence progresses.
- Remaining slots stay dark / translucent until captured.

**More deck in BOOTH mode:**
- `Featured Frame`
- `Border Colour`
- Future-safe for `Countdown Speed` and `Save Source Shots`

#### 5.2 `StripReviewSheet` (new bottom sheet)

After all 4 captures:
- Bottom review sheet rises over the same CaptureHub shell.
- Displays the composited strip (initially with the selected frame, no stamp).
- **Border colour picker:** 4 circular swatches at the bottom (white / black / pastel pink / sky blue). Tapping one re-composites and updates preview live (async, shows a spinner).
- **Featured Frame picker:** same choices as the BOOTH More deck; can be changed again at review time.
- **"Save & Share" button:** Composites the final JPEG (with stamp) → writes to vault → presents `UIActivityViewController`. Also offers a separate "Save to Photos" quick-action chip.
- **"Retake" button:** Dismisses sheet, returns to booth flow, discards this set.

#### 5.3 `L4CMomentCardView` (new card variant in `FilmFeedView`)

Same outer shell as `MomentCardView` but:
- Hero: the composite strip image (object-fit cover, letterboxed if needed).
- Badge: `"✦ BOOTH"` amber pill (replaces shot-count badge).
- Subtitle: `"4 cuts · {location} · {date}"`.
- No thumbnail strip (single composite image, no grid needed).

---

### 6. Featured Frame Assets (v0.3.5 bundle)

3 frames bundled in `Assets.xcassets` for launch. No server required.

| ID | Name | Theme |
|---|---|---|
| `frame_minimalist_black` | Minimalist Black | Thick black border, small "nifty" wordmark in bottom-left |
| `frame_spring_blossom` | Spring Blossom | Pastel pink bg, hand-drawn floral corners, soft serif font stamp |
| `frame_retro_neon` | Retro Neon | Dark bg, neon grid lines, pixel art logo at bottom |

Each frame is a **1080 × 1920 PNG** with premultiplied alpha. The slot cutouts must match the compositor's slot geometry exactly (see §3.1).

> **Design note for artist:** The 4 transparent slots are at:
> `x=28, y=28+(i×(444+20)), w=1024, h=444` for i in 0…3.
> Export as PNG-32 with premultiplied alpha. Keep total file size ≤ 400 KB (compress artwork regions).

---

### 10. Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `AssetType.l4c`, `CaptureMode.photoBooth` enum additions | `NiftyCore/…/Asset.swift` | ✅ |
| 2 | `L4CRecord`, `FeaturedFrame`, `L4CBorderColor`, `L4CStampConfig` | `NiftyCore/…/L4CRecord.swift` | ✅ |
| 3 | `CompositingAdapterProtocol` | `NiftyCore/…/CompositingAdapterProtocol.swift` | ✅ |
| 4 | `FeatureSet.l4c`, `AppConfig.v0_3_5` | `AppConfig.swift`, `AppConfig+Interim.swift` | ✅ |
| 5 | `CoreImageCompositingAdapter` — CGContext strip, slot geometry, frame overlay, stamp | `NiftyData/…/CoreImageCompositingAdapter.swift` | ✅ |
| 6 | `LifeFourCutsUseCase` — `captureOneShot`, `buildAndSave`, `recomposite` | `NiftyCore/…/LifeFourCutsUseCase.swift` | ✅ |
| 7 | `GraphProtocol` + `GraphManager` + `GraphRepository` — `l4c_records` table, save/fetch/delete | graph files | ✅ |
| 8 | `AppContainer` — `lifeFourCutsUseCase` property | `AppContainer.swift` | ✅ |
| 9 | `BoothCaptureOverlay` — countdown loop, flash, freeze, 4-slot strip overlay, active-slot progress state | `UI/CaptureHub/BoothCaptureView.swift` | ✅ |
| 10 | `StripPreviewSheet` — recomposite on border change, Save & Share, Save to Photos | `UI/CaptureHub/StripPreviewSheet.swift` | ✅ |
| 11 | `L4CMomentCardView` + `L4CDetailView` — feed card, share, delete | `UI/Journal/L4CMomentCardView.swift` | ✅ |
| 12 | `FilmFeedView` — `FeedItem` union, `groupedFeedItems`, L4C fetch, L4C sheet | `JournalFeedView.swift` | ✅ |
| 13 | `CaptureHubView` — BOOTH branch, `availableModes`, display helpers | `CaptureHubView.swift` | ✅ |
| 14 | `niftyMomntApp` — wire compositor + `LifeFourCutsUseCase`, config `v0_3_5` | `niftyMomntApp.swift` | ✅ |
| 15 | Frame PNG art assets (3 frames) | `Assets.xcassets/` | ⬜ design deliverable |

### 7. Open Questions for Sign-off

Before implementation begins, please confirm your intent on these:

| # | Question | Default assumed |
|---|---|---|
| Q1 | Should source stills (the 4 individual shots) appear separately in the feed, or only the composite strip card? | Hidden (only composite shown) |
| Q2 | Should the 4-shot countdown delay be user-configurable (1s / 2s / 3s per count), or fixed at 1s for now? | Fixed 1s |
| Q3 | Should users be able to retake individual shots (e.g., tap "Retake shot 3") or must they retake all 4? | Retake all 4 only |
| Q4 | Should the stamp logo be the full app wordmark "niftyMomnt" or a symbol-only logo? | Full wordmark text |
| Q5 | Should `FeaturedFrameOverlay` on the live preview be dismissable (to see the clean viewfinder)? | Always visible while frame selected; hidden for "None" |
| Q6 | Version slot: insert as v0.3.5 between v0.3 and v0.4 (as above), or defer to a later slot? | v0.3.5 as above |

---

### 8. Architecture Impact Summary

| Layer | New/Changed | Note |
|---|---|---|
| `NiftyCore/Domain/Models/Asset.swift` | `AssetType.l4c` added | One-line enum addition |
| `NiftyCore/Domain/Models/Asset.swift` | `CaptureMode.photoBooth` added | One-line enum addition |
| `NiftyCore/Domain/Models/` | `L4CRecord.swift` new | Pure Swift |
| `NiftyCore/Domain/Models/` | `FeaturedFrame.swift` new | Pure Swift |
| `NiftyCore/Domain/Protocols/` | `CompositingAdapterProtocol.swift` new | Pure Swift |
| `NiftyCore/Domain/UseCases/` | `LifeFourCutsUseCase.swift` new | Orchestrates booth capture + composite + persist |
| `NiftyData/Sources/Platform/` | `CoreImageCompositingAdapter.swift` new | CoreImage compositor |
| `NiftyData/Sources/Repositories/GraphRepository.swift` | `l4c_records` table, save/fetch/delete | GRDB migration |
| `NiftyData/Sources/Repositories/VaultRepository.swift` | No change (L4C composite stored as regular JPEG) | |
| `Apps/.../UI/CaptureHub/` | `BoothCaptureView.swift` new | CaptureHub-integrated booth overlay flow |
| `Apps/.../UI/Journal/` | `L4CMomentCardView.swift` new | Feed card variant |
| `Apps/.../UI/Journal/JournalFeedView.swift` | Render `L4CMomentCardView` when `assetType == .l4c` | Small change |
| `Apps/.../Assets.xcassets/` | 3 Featured Frame PNGs | Design deliverable |
| `AppConfig+Interim.swift` | `AppConfig.v0_3_5` | New config |
| `niftyMomntApp.swift` | Wire `CoreImageCompositingAdapter` + `LifeFourCutsUseCase` | Composition root |

---

### 9. Verification Checklist (draft — finalise after sign-off)

#### 1 — Booth Capture Flow

| # | Step | Expected result |
|---|------|-----------------|
| 1.1 | Swipe mode rail to BOOTH | "BOOTH" ghost label, Frame Carousel and Start button visible |
| 1.2 | Select "Spring Blossom" frame | Low-opacity frame overlay appears on live preview |
| 1.3 | Tap shutter / `START` in BOOTH mode | Countdown 3…2…1 appears in the active slot; white flash at capture; strip overlay fills after each shot |
| 1.4 | After shot 4 | Strip Preview Sheet slides up showing assembled composite |

#### 2 — Strip Preview & Customisation

| # | Step | Expected result |
|---|------|-----------------|
| 2.1 | Tap border colour swatch (e.g., pastel pink) | Strip updates live (async, spinner while compositing) |
| 2.2 | Tap "Save & Share" | `UIActivityViewController` presented with the composite JPEG |
| 2.3 | Tap "Retake" | Sheet dismisses; booth flow restarts |

#### 3 — Feed & Persistence

| # | Step | Expected result |
|---|------|-----------------|
| 3.1 | Save a strip; open Film | L4C card appears with "✦ BOOTH" badge and composite as hero |
| 3.2 | Kill and relaunch | L4C card persists |
| 3.3 | Tap card → MomentDetailView | Composite image shown full-size; standard share button works |
| 3.4 | Delete from MomentDetailView | Card removed from feed; composite + 4 source files deleted from vault |

#### 4 — Regression

| # | Step | Expected result |
|---|------|-----------------|
| 4.1 | Capture a regular still after a booth session | v0.3 pipeline intact |
| 4.2 | Open Film | Still moment card and L4C card coexist in timeline |

### v0.3.5 Sign-off

| Item | Status |
|------|--------|
| Q1–Q6 open questions answered | ⬜ |
| Frame PNG art assets delivered | ⬜ |
| All verification rows passing | ⬜ |
| **v0.3.5 complete — ready for v0.4** | ⬜ |

---

## v0.4 — Vibe Preset System

**Verification goal:** Selecting a preset in Capture Hub stores the name on the asset; `MomentCardView` accent reflects the stored preset; Roll Mode shot counter reads real daily count from GRDB; 5 preset packs fully wired end-to-end.

**AppConfig:** `AppConfig.v0_4` — same as v0.3 + `features: .rollMode`. Switch `niftyMomntApp.swift` from `v0_3_5` → `v0_4`.

**Note:** Atmosphere Asset capture support is deferred past v0.4. v0.3 §5 Atmosphere checklist will be covered in a dedicated verification pass before v0.5.

### Pre-existing scaffold (no changes needed)

| Item | Location | Notes |
|------|----------|-------|
| `VibePresetUI.defaults` — 5 named packs + accent colors | `DesignSystem.swift` | ✅ |
| Preset bar renders, swipe-cycle, long-press picker | `CaptureHubView.swift` | ✅ UI only |
| `derivedPresetAccent(for:)` + `derivedPresetName(for:)` | `JournalFeedView.swift` | ✅ reads AI vibes; needs fallback to stored preset |
| `MomentCardView.presetAccent` displayed as left border + chip fill | `MomentCardView.swift` | ✅ |
| `filmStripCounter` view in Zone A | `CaptureHubView.swift` | ✅ UI only; `rollShotsRemaining` was hardcoded `@State = 17` → wired to GRDB in task 4c (max = 36) |
| `AppConfig.v0_4` defined | `AppConfig+Interim.swift` | ✅ |
| `FeatureSet.rollMode` defined | `AppConfig.swift` | ✅ |
| `CaptureEngine.applyPreset(_:)` stub | `CaptureEngine.swift` + `AVCaptureAdapter.swift` | ✅ (passthrough, not needed for v0.4) |

### Features In Scope

- Store selected preset name on the `Asset` and `Moment` at capture time
- Feed accent color reads stored preset name first; falls back to AI-classified vibe tags
- Roll Mode counter reads real daily count from GRDB; enforces 36-shot soft cap

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1a | Add `selectedPresetName: String?` to `Asset` and `Moment` domain models | `NiftyCore/Sources/Domain/Models/Asset.swift`, `Moment.swift` | ✅ |
| 1b | Add `func updatePreset(_ name: String, for assetID: UUID) async throws` + `fetchTodayMomentCount` to `GraphProtocol` | `NiftyCore/Sources/Domain/Protocols/GraphProtocol.swift` | ✅ |
| 1c | Implement `GraphRepository.updatePreset()` — `UPDATE assets SET preset_name = ? WHERE id = ?`; add `preset_name TEXT` column via `ALTER TABLE` migration; update `fetchMoments` to SELECT + populate `preset_name` on `Asset` and `Moment` | `NiftyData/Sources/Repositories/GraphRepository.swift` | ✅ |
| 1d | Add `GraphManager.updatePreset()` and `fetchTodayMomentCount()` pass-throughs | `NiftyCore/Sources/Managers/GraphManager.swift` | ✅ |
| 2a | `CaptureMomentUseCase.captureAsset(preset: String?)` and `stopVideoRecording(config:preset:)` — add optional param; set `asset.selectedPresetName`; after `graph.saveMoment`, call `graph.updatePreset` when non-nil | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift` | ✅ |
| 2b | `CaptureHubView`: pass `activePreset.name` into `captureAsset(preset:)` (still) and `stopVideoRecording(config:preset:)` (clip/echo/atmosphere). Note: booth uses `lifeFourCutsUseCase.captureOneShot()` — preset not applicable | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ✅ |
| 3a | `JournalFeedView.derivedPresetAccent(for:)` — check `moment.selectedPresetName` first → map via `VibePresetUI.defaults`; fall back to AI vibe mapping | `Apps/niftyMomnt/niftyMomnt/UI/Journal/JournalFeedView.swift` | ✅ |
| 3b | `JournalFeedView.derivedPresetName(for:)` — same priority: stored name → AI vibe fallback | `Apps/niftyMomnt/niftyMomnt/UI/Journal/JournalFeedView.swift` | ✅ |
| 4a | Add `GraphRepository.fetchTodayMomentCount()` — SQL `COUNT(*)` WHERE `start_time >= startOfDay` | `NiftyData/Sources/Repositories/GraphRepository.swift` | ✅ |
| 4b | `GraphManager.fetchTodayMomentCount()` pass-through; `GraphProtocol` requirement | `NiftyCore/Sources/Managers/GraphManager.swift`, `GraphProtocol.swift` | ✅ |
| 4c | `CaptureHubView`: `rollModeMax = 36`; `.task` calls `refreshRollCounter()` → `fetchTodayMomentCount()`; decrement on each successful still and video capture; film-strip formula scaled to 36-shot range | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ✅ |
| 5 | Switch `niftyMomntApp.swift` config from `AppConfig.v0_3_5` → `AppConfig.v0_4` | `Apps/niftyMomnt/niftyMomnt/niftyMomntApp.swift` | ✅ |

> **DB migration note (task 1c):** GRDB allows `ALTER TABLE assets ADD COLUMN preset_name TEXT` when run inside `prepareDatabase` (outside a transaction). Use `try db.execute(sql: "ALTER TABLE assets ADD COLUMN preset_name TEXT")` guarded by checking if the column already exists via `try db.tableExists("assets") && !db.columns(in: "assets").contains { $0.name == "preset_name" }`.

> **Roll Mode cap note (task 4c):** The 36-shot cap is a soft limit (UI shows 0, shutter is not disabled). This matches the PRD "film roll" metaphor. No enforcement at the use case layer for v0.4.

### Verification Checklist

> Run on a real device with `AppConfig.v0_4`. Record Pass / Fail / Note per row. All rows must pass before starting v0.5.

#### 1 — Config & Boot

| # | Step | Expected | Result |
|---|------|----------|--------|
| 1.1 | Build and launch with `AppConfig.v0_4` | No crash; camera preview visible; Roll Mode counter visible in Zone A | |
| 1.2 | Open Settings | Roll Mode toggle visible under Capture section | |

#### 2 — Preset Bar UI

| # | Step | Expected | Result |
|---|------|----------|--------|
| 2.1 | Observe Zone C preset bar on launch | AMALFI shown as default (amber accent, name label) | |
| 2.2 | Swipe left/right on preset bar | Preset cycles through FILM ROLL → AMALFI → TOKYO NEON → NORDIC → DISPOSABLE; accent color updates in Zone C, Zone D shutter ring, and Zone A border | |
| 2.3 | Long-press preset bar | Full preset picker sheet rises; 5 named presets visible | |
| 2.4 | Tap a preset in the picker | Picker dismisses; selected preset active in Zone C | |

#### 3 — Preset Stored at Capture

| # | Step | Expected | Result |
|---|------|----------|--------|
| 3.1 | Select TOKYO NEON preset → capture a Still | Card appears in feed with lavender (`#C4B5FD`) left accent border | |
| 3.2 | Select NORDIC preset → capture a Still | Card appears in feed with blue-grey (`#8EB4D4`) left accent border | |
| 3.3 | Select DISPOSABLE preset → capture a Still | Card appears in feed with red-coral (`#FF6B6B`) left accent border | |
| 3.4 | Kill and relaunch app → open Film | Preset accent colors persist on previously captured cards (stored in `preset_name` column, not in-memory) | |
| 3.5 | Capture with preset X → verify Xcode console | No `updatePreset failed:` errors; `preset_name` column row visible in GRDB file (optional: Device File Browser) | |

#### 4 — Preset Accent in Feed (fallback)

The accent color appears in two places on each card: the **3pt vertical strip** on the left edge of the hero photo, and the **round play button** at the bottom-right. The **preset name** appears as readable text in the card title, formatted `"PRESET · Location"` (e.g. `"AMALFI · Apr 9"`).

| # | Step | Expected | Result |
|---|------|----------|--------|
| 4.1 | *(Upgrade path only — skip on fresh installs)* If you have moments captured before v0.4 (i.e. rows where `preset_name IS NULL` in the DB), open Film | No crash; card title still shows a preset name derived from AI vibes — not blank or "null". To force this on a fresh device: pull app container via Xcode Device Manager → edit `Documents/graph.sqlite` → `UPDATE assets SET preset_name = NULL` → push back → relaunch | |
| 4.2 | Select FILM ROLL in the preset bar → capture a Still → open Film | Card title prefix reads **"FILM ROLL"**; left strip and play button are warm tan (compare to the FILM ROLL dot colour in the preset bar — same swatch) | |

#### 5 — Roll Mode Counter

| # | Step | Expected | Result |
|---|------|----------|--------|
| 5.1 | Launch app; note today's prior capture count from feed | Zone A shows `36 - priorCount left` (e.g. 3 captures → "33 left") | |
| 5.2 | Capture 3 more photos | Counter decrements by 1 each time; film-strip tiles fill from left | |
| 5.3 | Kill and relaunch | Counter resets to the correct remaining value (reads today's GRDB count on launch) | |
| 5.4 | Advance device clock past midnight (or test on a day with 0 captures) | Counter shows "36 left" | |
| 5.5 | Reach 0 remaining | Counter shows "0 left" in amber; shutter still tappable (soft limit) | |

#### 6 — Edge Cases

| # | Step | Expected | Result |
|---|------|----------|--------|
| 6.1 | Capture Echo with TOKYO NEON selected | Echo card shows lavender accent (stored preset, not AI vibe) | |
| 6.2 | Capture Clip with NORDIC selected | Clip card shows blue-grey accent | |
| 6.3 | Rapid preset switch → immediate capture | Correct (latest) preset stored on asset — no stale preset from previous selection | |
| 6.4 | Delete a moment from MomentDetailView | Roll Mode counter does NOT decrement (deletes do not subtract from today's capture count) | |

### v0.4 Sign-off

| Item | Status |
|------|--------|
| All verification rows passing | ⬜ |
| Preset name visible in GRDB `assets.preset_name` for newly captured moments | ⬜ |
| Feed accent reads stored preset, not only AI vibes | ⬜ |
| Roll counter initializes from real daily GRDB count on launch | ⬜ |
| **v0.4 complete — ready for v0.5** | ⬜ |

---

## v0.5 — Sound Stamp & Acoustic Pipeline

**Verification goal:** In Still mode, ambient PCM audio is captured around the shutter moment; `SNAudioFileAnalyzer` classifies it against a 19-label allowlist mapped from Apple's AudioSet classifier; acoustic tags (wind / rain / thunder / fire / beach / river / water / speech / crowd / laughter / music / singing / bird / dog / insect / car / train / airplane / alarm) appear in `MomentDetailView`; tags survive kill-and-relaunch. A temp CAF file is used during classification only and deleted before classify() returns — no permanent audio file written to disk.

**Status: ✅ Implementation complete and verified on device — 2026-04-10**

**AppConfig:** `AppConfig.v0_5` — same as v0.4 + `features: [.rollMode, .soundStamp]`. Already defined in `AppConfig+Interim.swift`. Switch `niftyMomntApp.swift` config from `v0_4` → `v0_5`.

### Pre-existing scaffold (no changes needed)

| Item | Location | Notes |
|------|----------|-------|
| `SoundStampPipelineProtocol` — `activatePreRoll`, `deactivatePreRoll`, `analyzeAndTag`, `isActive` | `NiftyCore/…/SoundStampPipelineProtocol.swift` | ✅ full protocol |
| `AcousticTag`, `AcousticTagType`, `AcousticSource` | `NiftyCore/…/SupportingTypes.swift` | ✅ |
| `Asset.acousticTags: [AcousticTag]` | `NiftyCore/…/Asset.swift` | ✅ |
| `IndexingProtocol.analyzePCMBuffer()` | `NiftyCore/…/IndexingProtocol.swift` | ✅ |
| `GraphProtocol.updateAcousticTag()` | `NiftyCore/…/GraphProtocol.swift` | ✅ |
| `CaptureEngine` — full soundStamp feature-flag wiring: `activatePreRoll` on Still entry, fire-and-forget `analyzeAndTag` after shutter, `deactivatePreRoll` on mode switch / stop | `NiftyCore/…/CaptureEngine.swift` | ✅ |
| `AppConfig.v0_5` defined | `AppConfig+Interim.swift` | ✅ |
| `FeatureSet.soundStamp` | `AppConfig.swift` | ✅ |
| `MockSoundStampPipeline` | `NiftyCore/Tests/Mocks/` | ✅ |
| `SoundStampAdapter` actor (stubs) | `NiftyData/…/SoundStampAdapter.swift` | 🔲 implement |
| `CoreMLIndexingAdapter.analyzePCMBuffer()` (stub) | `NiftyData/…/CoreMLIndexingAdapter.swift` | 🔲 implement |
| `GraphRepository.updateAcousticTag()` (stub, no table) | `NiftyData/…/GraphRepository.swift` | 🔲 implement |
| `SoundStampAdapter(config:)` instantiated + wired to `CaptureEngine` | `niftyMomntApp.swift` | ✅ wired — needs `graph:` param added |

### Features In Scope

- `SoundStampAdapter`: `AVAudioEngine` input tap → 44.1kHz PCM ring buffer (0.5s pre-roll); 1.0s post-shutter capture; combined buffer passed to `CoreMLIndexingAdapter.analyzePCMBuffer()`; results persisted to graph; buffer discarded immediately — **never written to disk**
- `CoreMLIndexingAdapter.analyzePCMBuffer()`: `SNAudioStreamAnalyzer` on in-memory `AVAudioPCMBuffer` → map `SNClassificationResult` → `[AcousticTag]` (confidence threshold ≥ 0.35)
- `GraphRepository`: create `acoustic_tags` table; implement `updateAcousticTag()`; load tags in `fetchMoments()`
- `MomentDetailView`: acoustic tag chip row (amber pill chips, sound wave icon prefix), shown only when `acousticTags` non-empty
- `CaptureHubView`: mic activity indicator in Zone A (small amber waveform icon, visible when pre-roll is active in Still mode)
- `SettingsView`: Sound Stamp toggle gated on `config.features.contains(.soundStamp)`

### Architecture Notes

**V — `SoundStampAdapter` owns graph persistence**
`CaptureEngine` does `_ = try? await soundStampPipeline.analyzeAndTag(assetID:)` — the return value is dropped. Persistence (calling `graph.updateAcousticTag`) must happen inside `SoundStampAdapter.analyzeAndTag`. Add `graph: any GraphProtocol` to `SoundStampAdapter.init`; update composition root accordingly.

**W — `AVAudioSession` category for Sound Stamp**
Use `.playAndRecord` with `[.mixWithOthers, .allowBluetooth]`. This avoids interrupting `AVCaptureSession`'s photo-output class (same principle as Architecture Decision Q for Echo). Do **not** use `.record` alone — it conflicts with the active `AVCaptureSession` audio input and causes silent failures. Note: `.measurement` is macOS-only and does not compile on iOS.

**X — `SNAudioFileAnalyzer` for batch PCM classification (revised from original plan)**
`SNAudioStreamAnalyzer` is designed for real-time streaming. Its internal windowing engine expects audio arriving at real-time cadence; feeding a pre-recorded buffer in a tight loop causes it to silently produce 0 classification windows (`requestDidComplete` fires immediately with 0 results). The correct batch API is `SNAudioFileAnalyzer`: write samples to a temp CAF (Int16 PCM — Float32 non-interleaved is silently unreadable), open with `SNAudioFileAnalyzer(url:)`, and call `analyze(completionHandler:)`. Use a `DispatchSemaphore` to block the `Task.detached` thread until the completion fires — no RunLoop required.

**X2 — Ring buffer must be ≥3s for SNClassifySoundRequest**
`SNClassifySoundRequest` default `windowDuration = 3.0s`, `overlapFactor = 0.5`. At least one full 3s window must be present in the audio file or `SNAudioFileAnalyzer` produces 0 windows. The original 1.5s ring (0.5s pre-roll + 1.0s post-shutter) was too short. `ringDuration` was increased to `4.5s` (~3.5s pre-roll + 1.0s post-shutter), giving 1–2 classification windows. Memory cost: 4.5s × 48000Hz × 4 bytes ≈ 864KB max.

**X3 — AVAudioFile must close before SNAudioFileAnalyzer opens**
Write `AVAudioFile` inside a `do { }` scope so it deinits (flushes and closes the fd) before `SNAudioFileAnalyzer` opens the same URL. If the file handle is still open, the analyzer reads an empty or incomplete file and produces 0 windows.

**Y — DB migration: `acoustic_tags` table**
Run `CREATE TABLE IF NOT EXISTS acoustic_tags (asset_id TEXT NOT NULL, tag TEXT NOT NULL, source TEXT NOT NULL, confidence REAL NOT NULL, PRIMARY KEY (asset_id, tag))` via `Configuration.prepareDatabase` (outside a transaction, matching the WAL pattern from Architecture Decision F).

**Z — `fetchMoments` acoustic tag hydration**
After loading assets from GRDB, run a second query: `SELECT * FROM acoustic_tags WHERE asset_id IN (...)` and populate `Asset.acousticTags` on each asset. Avoid N+1 by using a single `IN` clause.

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1a | Add `graph: any GraphProtocol` param to `SoundStampAdapter.init`; store as `private let graph` | `NiftyData/Sources/Platform/SoundStampAdapter.swift` | ✅ |
| 1b | `SoundStampAdapter.activatePreRoll()`: does NOT call `AVAudioSession.setCategory/setActive` (AVCaptureSession owns the shared session); installs `inputNode` tap, copies samples to `[Float]` (PCMChunk) on tap thread; 4.5s ring buffer; `engine.prepare()` + `engine.start()` | `NiftyData/Sources/Platform/SoundStampAdapter.swift` | ✅ |
| 1c | `SoundStampAdapter.deactivatePreRoll()`: remove tap; `engine.pause()` (NOT stop — stop calls `setActive(false)` breaking AVCaptureSession with -17281); clear ring; `isActiveSubject.send(false)` | `NiftyData/Sources/Platform/SoundStampAdapter.swift` | ✅ |
| 1d | `SoundStampAdapter.analyzeAndTag(assetID:)`: sleep 1.0s post-shutter; snapshot ring; flatten to `[Float]`; `Task.detached` → `classify()`; persist tags; post `niftyAcousticTagsUpdated` | `NiftyData/Sources/Platform/SoundStampAdapter.swift` | ✅ |
| 2 | `CoreMLIndexingAdapter.analyzePCMBuffer()`: reuses `SoundStampAdapter.mapAudioSetIdentifier`; same SNAudioFileAnalyzer pattern | `NiftyData/Sources/Platform/CoreMLIndexingAdapter.swift` | ✅ |
| 3a | `GraphRepository` DB migration: `acoustic_tags` table with `PRIMARY KEY (asset_id, tag)` | `NiftyData/Sources/Repositories/GraphRepository.swift` | ✅ |
| 3b | `GraphRepository.updateAcousticTag(_:for:)`: `INSERT OR REPLACE` with `MAX(confidence)` | `NiftyData/Sources/Repositories/GraphRepository.swift` | ✅ |
| 3c | `GraphRepository.fetchMoments()`: batch `acoustic_tags WHERE asset_id IN (...)` hydration | `NiftyData/Sources/Repositories/GraphRepository.swift` | ✅ |
| 4 | `niftyMomntApp.swift`: `SoundStampAdapter(config:graph:graphRepo)`; `AppConfig.v0_5`; `AppConfig+Interim` v0_4–v0_9 all carry `.l4c` (was missing, broke BOOTH mode) | `Apps/niftyMomnt/niftyMomnt/niftyMomntApp.swift` | ✅ |
| 5 | `MomentDetailView`: `@State acousticTags`; `loadAcousticTags()` via `graphManager.fetchAcousticTags(for:)`; `.onReceive(.niftyAcousticTagsUpdated)` for post-capture refresh; amber waveform chip row | `Apps/niftyMomnt/niftyMomnt/UI/Journal/JournalFeedView.swift` | ✅ |
| 6 | `CaptureHubView`: unified AppStorage key `"nifty.soundStampEnabled"`; amber waveform+LIVE indicator in Zone A; `.onChange` → `applySoundStampToggle` | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ✅ |
| 7 | `SettingsView`: Sound Stamp toggle — `config.features.contains(.soundStamp)` gate | `Apps/niftyMomnt/niftyMomnt/UI/` | ✅ |

> **AudioSet allowlist mapping (task 2):** `SNClassificationResult.identifier` strings to `AcousticTagType` — implement as a `static let` dictionary in `CoreMLIndexingAdapter`:
>
> | `AcousticTagType` case | AudioSet identifiers to match (prefix or exact) |
> |------------------------|--------------------------------------------------|
> | `.wind` | `"wind"`, `"wind_noise"` |
> | `.rain` | `"rain"`, `"rain_on_surface"` |
> | `.thunder` | `"thunder"`, `"thunderstorm"` |
> | `.beach` | `"beach"`, `"surf"`, `"ocean"`, `"waves"` |
> | `.river` | `"stream"`, `"river"`, `"babbling_brook"`, `"creek"` |
> | `.water` | `"water"`, `"waterfall"`, `"dripping"` (generic fallback) |
> | `.fire` | `"fire"`, `"crackling_fire"` |
> | `.speech` | `"speech"`, `"male_speech"`, `"female_speech"`, `"child_speech"` |
> | `.crowd` | `"crowd"`, `"chatter"`, `"hubbub"` |
> | `.laughter` | `"laughter"` |
> | `.music` | `"music"`, `"musical_instrument"` |
> | `.singing` | `"singing"`, `"choir"`, `"vocal_music"` |
> | `.bird` | `"bird"`, `"bird_song"`, `"bird_vocalization"`, `"chirping_birds"` |
> | `.dog` | `"dog"`, `"bark"`, `"bow-wow"` |
> | `.insect` | `"insect"`, `"cricket"`, `"bee_wasp"` |
> | `.car` | `"car"`, `"vehicle"`, `"engine"`, `"traffic_noise"` |
> | `.train` | `"train"`, `"railroad_car"`, `"rail_transport"` |
> | `.airplane` | `"airplane"`, `"aircraft"`, `"jet_engine"` |
> | `.alarm` | `"alarm"`, `"siren"`, `"smoke_detector"` |
>
> Use a prefix match (`identifier.hasPrefix(...)`) to handle classifier version differences across iOS versions. When multiple identifiers map to the same case, take the highest confidence score.

> **Privacy note (tasks 1b–1d):** The PCM ring buffer is an in-memory `[PCMChunk]` (`[Float]`-backed). It is cleared in `deactivatePreRoll` and immediately after `analyzeAndTag` snapshots it. A single temp `.caf` is written to `NSTemporaryDirectory()` during classification only and deleted via `defer` before `classify()` returns. It never touches `Documents/assets/`. Verify in Instruments (File Activity) that no `.caf` file persists after Sound Stamp capture.

> **`AppContainer` note (task 6):** Expose `soundStampAdapter.isActive` as a published property or pass through via a dedicated `@Published var isSoundStampActive: Bool`. `SoundStampAdapter.isActive` is an `AnyPublisher<Bool, Never>` — subscribe in `AppContainer.init` and forward to a `@Published` var so `CaptureHubView` can bind without importing `NiftyData`.

### Verification Checklist

> Run on a real device with `AppConfig.v0_5`. Record Pass / Fail / Note per row. All rows must pass before starting v0.6.

#### 1 — Config & Boot

| # | Step | Expected | Result |
|---|------|----------|--------|
| 1.1 | Build and launch with `AppConfig.v0_5` | No crash; camera preview visible; no mic indicator visible on boot (camera starts in Still mode but pre-roll not yet active) | |
| 1.2 | Open Settings | Sound Stamp toggle visible and ON | |

#### 2 — Pre-Roll Activation

| # | Step | Expected | Result |
|---|------|----------|--------|
| 2.1 | With Sound Stamp ON, ensure Still mode is active | Amber waveform icon appears in Zone A within ~200ms | |
| 2.2 | Swipe to Clip mode | Waveform icon disappears | |
| 2.3 | Swipe back to Still | Waveform icon reappears | |
| 2.4 | Disable Sound Stamp in Settings → return to CaptureHub | Waveform icon not shown; no mic activation | |

#### 3 — Acoustic Tag Capture

| # | Step | Expected | Result |
|---|------|----------|--------|
| 3.1 | Capture a Still in a **quiet indoor** environment | Card in feed; open MomentDetailView → acoustic chip row is **empty** (no tags above threshold — quiet is implied by absence) | |
| 3.2 | Capture a Still with **music playing nearby** | Acoustic chip shows `music` | |
| 3.3 | Capture a Still **outdoors with wind** | Acoustic chip shows `wind` | |
| 3.4 | Capture a Still in a **crowded public space** | Acoustic chip shows `crowd` and/or `speech` | |
| 3.5 | Capture a Still **near a road with traffic** | Acoustic chip shows `car` | |
| 3.6 | Capture a Still **outside with birds audible** | Acoustic chip shows `bird` | |
| 3.7 | Capture a Still **during rain** | Acoustic chip shows `rain` | |
| 3.8 | Capture a Still **at the beach** (waves audible) | Acoustic chip shows `beach` | |
| 3.9 | Capture a Still **by a river or creek** | Acoustic chip shows `river` | |
| 3.10 | Capture in a very ambiguous acoustic environment | Acceptable if acoustic chip row is hidden (no tags above threshold) — card still saves normally | |

#### 4 — Persistence

| # | Step | Expected | Result |
|---|------|----------|--------|
| 4.1 | After tagging a moment, kill and relaunch | Acoustic chips still present on the card in MomentDetailView | |
| 4.2 | _(Optional)_ Inspect GRDB file via Xcode Device Manager → `Documents/graph.sqlite` → `acoustic_tags` table | Rows present with correct `asset_id`, `tag`, `source = "soundStamp"`, `confidence` values | |

#### 5 — Privacy & No-File Guarantee

| # | Step | Expected | Result |
|---|------|----------|--------|
| 5.1 | Profile a Sound Stamp capture in Instruments → File Activity | No `.m4a` / `.caf` / `.wav` / `.pcm` file created in `Documents/assets/` or temp directories during Still capture | |
| 5.2 | Check Xcode console after capture | No `[SoundStamp] writing` or `AVAudioFile` log lines | |

#### 6 — Regression

| # | Step | Expected | Result |
|---|------|----------|--------|
| 6.1 | Capture a Live Photo | No acoustic chip on card; Live Photo playback unaffected | |
| 6.2 | Capture an Echo | Echo recording unaffected; no conflict with SoundStamp pre-roll (Echo disables pre-roll on mode switch) | |
| 6.3 | Capture a Clip | No acoustic chip; video recording unaffected | |
| 6.4 | Capture a Booth strip (L4C) | No acoustic chip; strip composite unaffected | |
| 6.5 | Roll Mode counter | Increments normally for Still captures with Sound Stamp active | |

### v0.5 Sign-off

| Item | Status |
|------|--------|
| All verification rows passing | 🔄 (3.2 music/singing confirmed; 3.1 / 3.3–3.10 / 4–6 pending) |
| Temp CAF deleted before classify() returns; no permanent audio file on disk | ✅ (verified by design — defer + NSTemporaryDirectory) |
| Acoustic tags visible in `acoustic_tags` GRDB table | 🔄 pending 4.2 |
| Tags survive kill-and-relaunch | 🔄 pending 4.1 |
| No regression in Live / Echo / Clip / Booth modes | 🔄 pending 6.1–6.5 |
| **v0.5 complete — ready for v0.6** | 🔄 |

#### Key implementation lessons recorded (2026-04-10)

| Finding | Resolution |
|---------|------------|
| `SNAudioStreamAnalyzer` produces 0 windows with pre-recorded buffers | Use `SNAudioFileAnalyzer` (batch API) instead |
| `SNClassifySoundRequest` windowDuration = 3.0s requires ≥3s of audio | Increased `ringDuration` from 1.5s → 4.5s |
| `AVAudioFile` must close before `SNAudioFileAnalyzer` opens the same URL | Wrap write in `do { }` scope to force deinit/flush |
| `SNAudioFileAnalyzer.analyze()` (sync) delivers callbacks via RunLoop — 0 results on `Task.detached` thread | Use `analyze(completionHandler:)` + `DispatchSemaphore` |
| `AVAudioEngine.stop()` calls `AVAudioSession.setActive(false)` — breaks `AVCaptureSession` (-17281) | Use `engine.pause()` in `deactivatePreRoll` |
| `AVAudioSession.Category.measurement` is macOS-only | Do not call `setCategory` at all; `AVCaptureSession` owns the session |
| Float32 non-interleaved CAF silently unreadable by `SNAudioFileAnalyzer` | Write as Int16 PCM CAF (`kAudioFormatLinearPCM`, 16-bit) |
| AppStorage key mismatch between SettingsView and CaptureHubView | Unified to `"nifty.soundStampEnabled"` |
| `AppConfig.v0_4–v0_9` missing `.l4c` broke BOOTH mode | Added `.l4c` to all configs from v0_4 onward |

---

## v0.6 — AI Nudge Engine

**Verification goal:** Post-capture nudge card appears after vibe tag window closes; user response persists in graph; nudge reads stored vibe tags (not live classification).

**AppConfig:** adds `features: .nudgeEngine`

### Features In Scope

- `NudgeEngine`: read `VibeTag[]` from graph → generate reflection prompt (on-device, template-based at this stage)
- Post-capture overlay sequencing: vibe tag prompt fires first → tags written → nudge card after window closes (per PRD §3.9 / §8)
- `NudgeResponse` persistence in `GraphRepository.saveNudgeResponse()`
- `CaptureHubView`: nudge card sheet presentation after overlay dismisses

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `NudgeEngine.generateNudge(for:)` — template-based from vibe tags | `NiftyCore/Sources/Engines/NudgeEngine.swift` | ⬜ |
| 2 | `GraphRepository.saveNudgeResponse()` | `NiftyData/Sources/Repositories/GraphRepository.swift` | ⬜ |
| 3 | `CaptureMomentUseCase`: fire nudge after classification | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift` | ⬜ |
| 4 | `CaptureHubView`: nudge card sheet, dismiss → write response | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ⬜ |

---

## v0.7 — Private Vault & Face ID

**Verification goal:** Assets marked private are encrypted and hidden behind Face ID; Vault tab shows only authenticated assets; lock/unlock state persists across app launches.

**AppConfig:** adds `features: .trustedSharing`

### Features In Scope

- `VaultRepository`: encrypted file storage (`CryptoKit` AES-GCM) for assets flagged `.private`
- `LocalAuthentication`: Face ID / Touch ID gate in `VaultView`
- `VaultManager.lockVault()` / `unlockVault()` state machine
- `VaultView`: locked shell → Face ID prompt → unlocked asset grid (per current UI scaffold)
- `MomentDetailView`: "Move to Vault" action

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `VaultRepository`: `CryptoKit` encryption for `.private` assets | `NiftyData/Sources/Repositories/VaultRepository.swift` | ⬜ |
| 2 | `VaultManager`: lock/unlock state + `LAContext` auth | `NiftyCore/Sources/Managers/VaultManager.swift` | ⬜ |
| 3 | `VaultView`: Face ID gate → unlocked grid | `Apps/niftyMomnt/niftyMomnt/UI/` | ⬜ |
| 4 | `MomentDetailView`: "Move to Vault" action | `Apps/niftyMomnt/niftyMomnt/UI/Journal/` | ⬜ |

---

## v0.8 — Story Engine & Reel Assembler

**Verification goal:** `IndexingEngine.clusterMoments()` groups assets into `[Moment]` automatically; `AssembleReelUseCase` produces a playable `.mov` reel with voice overlay.

**AppConfig:** adds `features: .journalSuggest` (voice prose), `aiModes: .enhancedAI` optional

### Features In Scope

- `IndexingEngine.clusterMoments()`: time + location proximity clustering
- `StoryEngine`: narrative arc selection (3 templates)
- `VoiceProseEngine`: Poet / Foodie / Minimalist caption generation
- `AssembleReelUseCase`: `AVMutableComposition` — photo sequence + audio overlay + captions
- Reel playback in `MomentDetailView`

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `IndexingEngine.clusterMoments()`: time+location proximity | `NiftyCore/Sources/Engines/IndexingEngine.swift` | ⬜ |
| 2 | `StoryEngine`: 3 narrative arc templates | `NiftyCore/Sources/Engines/StoryEngine.swift` | ⬜ |
| 3 | `VoiceProseEngine`: prose style variants | `NiftyCore/Sources/Engines/VoiceProseEngine.swift` | ⬜ |
| 4 | `AssembleReelUseCase`: `AVMutableComposition` reel | `NiftyCore/Sources/Domain/UseCases/AssembleReelUseCase.swift` | ⬜ |
| 5 | `MomentDetailView`: reel playback | `Apps/niftyMomnt/niftyMomnt/UI/Journal/` | ⬜ |

---

## v0.9 — Extended Intelligence & Dual-Camera

**Verification goal:** Dual-camera capture works on supported devices; Lab Mode (Mode-2) sends encrypted visual data to cloud VLM; Journaling Suggestions API surfaces relevant moments; AI caption generated from ambient metadata.

**AppConfig:** `aiModes: .full` (adds `.enhancedAI`, `.lab`), adds dual-camera feature flag

### Features In Scope

- `AVCaptureAdapter`: dual-camera session (`AVCaptureMultiCamSession`) on iPhone 15+
- `LabClient` / `LabNetworkAdapter`: encrypted visual payload → cloud VLM response (Mode-2)
- `JournalSuggestionsAdapter`: `JournalingSuggestions` framework → surface recent moments
- AI caption generator: ambient metadata + vibe tags → `EnhancedAIClient` text completion
- `SettingsView`: Dual Camera toggle gated on device capability
- Roll Mode: daily cap enforcement via `GraphManager` count

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `AVCaptureAdapter`: `AVCaptureMultiCamSession` dual-camera | `NiftyData/Sources/Platform/AVCaptureAdapter.swift` | ⬜ |
| 2 | `LabNetworkAdapter`: encrypted payload + VLM response parse | `NiftyData/Sources/Network/LabNetworkAdapter.swift` | ⬜ |
| 3 | `JournalSuggestionsAdapter`: `JournalingSuggestions` framework integration | `NiftyData/Sources/Platform/JournalSuggestionsAdapter.swift` | ⬜ |
| 4 | AI caption generator: ambient + vibe → text | `NiftyCore/Sources/Engines/VoiceProseEngine.swift` | ⬜ |
| 5 | `SettingsView`: Dual Camera toggle capability check | `Apps/niftyMomnt/niftyMomnt/UI/` | ⬜ |

---

## v1.0 — Full Feature Set & App Store Ready

**Verification goal:** All PRD v1.6 MVP features implemented, gated, and verified on device. `AppConfig.full` and `AppConfig.lite` both boot cleanly. Performance targets met. App Store submission ready.

### Features In Scope

- Live Activities + Lock Screen quick-capture actions (`ActivityKit`)
- Home Screen widget (3 types via `WidgetKit`)
- Self-timer (3s / 10s) in `CaptureHubView` Zone A
- Onboarding: gesture tutorial (interactive), personalized daily capture prompt (opt-in)
- niftyMomntLite variant: `AppConfig.lite` validated (`assetTypes: .basic`, `aiModes: .onDevice`)
- Accessibility: Dynamic Type, VoiceOver labels, `reduceMotion` all passing
- Performance: cold launch < 1.5s; capture-to-preview < 300ms; classification < 500ms on A16+
- App Store: Privacy Nutrition Labels, App Tracking Transparency, export compliance

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `ActivityKit`: Live Activity for active capture session | `Apps/niftyMomnt/` | ⬜ |
| 2 | `WidgetKit`: 3 widget types (last moment, streak, daily prompt) | `Apps/Widgets/` | ⬜ |
| 3 | Self-timer: 3s/10s countdown in Zone A | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ⬜ |
| 4 | Onboarding flow: gesture tutorial + daily prompt opt-in | `Apps/niftyMomnt/niftyMomnt/UI/` | ⬜ |
| 5 | `AppConfig.lite` E2E smoke test | `Apps/niftyMomntLite/` | ⬜ |
| 6 | Accessibility audit: Dynamic Type, VoiceOver, reduceMotion | All UI files | ⬜ |
| 7 | Performance profiling: launch, capture, classification | Instruments | ⬜ |
| 8 | Privacy manifest + App Store metadata | `Apps/niftyMomnt/` | ⬜ |

---

_Companion documents: PRD v1.6 · UI/UX Spec v1.7 · SRS v1.2 · Architecture ADR v1.1_
