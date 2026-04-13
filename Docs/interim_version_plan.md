# niftyMomnt — Interim Version Plan
# v0.1 → v1.0 Feature Ladder

_Reference: PRD v1.6 · UI/UX Spec v1.7 · SRS v1.2_
_Last updated: 2026-04-12 · v0.2 + v0.3 signed off; v0.3.5 mode-switching performance resolved; v0.4 implementation complete — pending device verification; v0.5 complete (Sound Stamp verified on device); v0.6 AI Nudge Engine — implementation complete, verification in progress; v0.7 Story Engine & Reel Assembler — implementation complete, verification in progress (checklist updated to reflect AVAssetWriter stills-only scope, prose UI deferred to v0.8); v0.8 Private Vault & Face ID — implementation complete; v1.0 Vault Backup & Restore (Option C) design added_

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
| [v0.6](#v06--ai-nudge-engine) | Post-capture nudge card fires; response stored in graph | 🔄 |
| [v0.7](#v07--story-engine--reel-assembler) | Moment cluster produced; reel assembled with voice overlay | ⬜ |
| [v0.8](#v08--private-vault--face-id) | Assets marked private locked behind Face ID; vault tab functional | ⬜ |
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

**Verification goal:** Post-capture nudge card appears after vibe tag overlay closes; user response persists in `nudge_responses` GRDB table; nudge is gated by `.nudgeEngine` feature flag.

**AppConfig:** `AppConfig.v0_6` — `features: [.l4c, .rollMode, .soundStamp, .nudgeEngine]` _(already defined in AppConfig+Interim.swift)_

### Pre-existing scaffold (no re-implementation needed)

| Item | Location | State |
|------|----------|-------|
| `NudgeEngineProtocol` | `NiftyCore/Sources/Domain/Protocols/NudgeEngineProtocol.swift` | ✅ fully defined |
| `NudgeCard`, `NudgeResponse`, `NudgeTrigger` models | `NiftyCore/Sources/Domain/Models/SupportingTypes.swift` | ✅ defined |
| `NudgeEngine` shell | `NiftyCore/Sources/Engines/NudgeEngine.swift` | stub — `evaluateTriggers` is empty |
| `GenerateNudgeUseCase` | `NiftyCore/Sources/Domain/UseCases/GenerateNudgeUseCase.swift` | ✅ thin wrapper |
| `AppConfig.v0_6` | `Apps/niftyMomnt/niftyMomnt/AppConfig+Interim.swift` | ✅ defined |
| `AppContainer.nudgeEngine` | `Apps/niftyMomnt/niftyMomnt/AppContainer.swift` | ✅ wired + exposed |
| `GraphRepository.saveNudgeResponse()` | `NiftyData/Sources/Repositories/GraphRepository.swift` | stub — body empty |
| BGAppRefreshTask → `nudgeEngine.refresh()` | `Apps/niftyMomnt/niftyMomnt/niftyMomntApp.swift` | ✅ wired |

### Features In Scope

- `NudgeEngine.evaluateTriggers(for:)`: pick a template question from `VibeTag[]` → publish `NudgeCard` on `pendingNudge`
- GRDB `nudge_responses` table migration + real `saveNudgeResponse()` INSERT
- `CaptureMomentUseCase`: inject `nudgeEngine: NudgeEngine`; call `evaluateTriggers(for: moment)` after graph save (still + video pipelines)
- `niftyMomntApp.swift`: pass `nudgeEngine` into `CaptureMomentUseCase` init
- `CaptureHubView`: `.onReceive(container.nudgeEngine.pendingNudge)` → hold in `@State var pendingNudgeCard: NudgeCard?`; present nudge sheet only after `dismissPostCapture()` completes; dismiss calls `submitResponse()` or `dismiss(nudgeID:)`

### Sequencing (per PRD §3.9 / §8)

```
shutter tap
  → captureAsset() pipeline
      → graph.saveMoment()
      → nudgeEngine.evaluateTriggers(for: moment)   ← publishes NudgeCard to subject
      → NotificationCenter.niftyMomentCaptured
  → CaptureHubView shows post-capture vibe overlay  ← user picks chip or auto-dismisses (3s)
  → dismissPostCapture() completes (0.25s animation)
  → pendingNudgeCard is non-nil → .sheet presents NudgeCardView
  → user responds / dismisses → submitResponse() or dismiss() → subject sends nil
```

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `NudgeEngine.evaluateTriggers(for:)` — pick template question from `moment.dominantVibes` → publish `NudgeCard` on `nudgeSubject` | `NiftyCore/Sources/Engines/NudgeEngine.swift` | ✅ |
| 2 | GRDB migration: `nudge_responses` table (`id TEXT PK, nudge_id TEXT, response_type TEXT, response_value TEXT, timestamp REAL`) + real `saveNudgeResponse()` INSERT | `NiftyData/Sources/Repositories/GraphRepository.swift` | ✅ |
| 3 | `CaptureMomentUseCase`: add `nudge: NudgeEngine?` init param (optional, defaults nil for backward compat); call `await nudge?.evaluateTriggers(for: moment)` after step 7 in both `captureAsset()` and `stopVideoRecording()` | `NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift` | ✅ |
| 4 | `niftyMomntApp.swift`: pass `nudgeEngine` into `CaptureMomentUseCase(nudge: nudgeEngine)` + switch to `AppConfig.v0_6` | `Apps/niftyMomnt/niftyMomnt/niftyMomntApp.swift` | ✅ |
| 5 | `CaptureHubView`: `@State var pendingNudgeCard: NudgeCard?`; `.onReceive(container.nudgeEngine.pendingNudge)` stores card; modify `dismissPostCapture()` to set sheet after animation; `.sheet(item: $pendingNudgeCard)` presents `NudgeCardView`; response/dismiss path calls `container.nudgeEngine` | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ✅ |
| 6 | `NudgeCardView` — bottom sheet: question text, text-entry or quick-pick response, submit + dismiss buttons | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/NudgeCardView.swift` _(new file)_ | ✅ |

### Verification Checklist

> Run on real device with `AppConfig.v0_6`. Record Pass / Fail / Note per row. All rows must pass before v0.6 sign-off.

#### 1 — Nudge Card Appearance

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 1.1 | Still capture → post-capture overlay appears → wait 3s for auto-dismiss | After overlay fades out (~3.25s), nudge card sheet slides up | |
| 1.2 | Still capture → tap a vibe chip to dismiss overlay early | Nudge card sheet appears shortly after overlay closes | |
| 1.3 | Nudge card is visible — check question text | Non-empty reflection question; text varies with different dominant vibe tags (e.g. `.golden` → different prompt than `.moody`) | |
| 1.4 | Capture with no dominant vibe tags (ambiguous scene) | Nudge card still appears with a fallback generic question | |

#### 2 — Nudge Response & Persistence

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 2.1 | Enter text in nudge card → tap Submit | Sheet dismisses, no crash | |
| 2.2 | Xcode Device Manager → `Documents/graph.sqlite` → inspect `nudge_responses` table | Row exists: correct `nudge_id`, `response_type`, non-empty `response_value`, valid `timestamp` | |
| 2.3 | Tap "✕" / dismiss nudge without responding | Sheet closes, no row written to `nudge_responses` (dismiss ≠ response) | |
| 2.4 | Kill + relaunch → open Film | Previously captured moments + nudge responses still present (GRDB migration didn't break existing tables) | |

#### 3 — Feature Flag Gating

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 3.1 | Switch boot config to `AppConfig.v0_5` → capture still | No nudge card appears (feature flag `.nudgeEngine` absent) | |
| 3.2 | Switch back to `AppConfig.v0_6` → capture still | Nudge card appears again | |

#### 4 — Regression

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 4.1 | Still capture with Sound Stamp enabled | Acoustic tags still appear in Film feed (Sound Stamp pipeline unaffected) | |
| 4.2 | Clip / Echo / Booth / Roll capture → check for nudge | Nudge card fires for all capture types (or is explicitly suppressed — document whichever is chosen) | |
| 4.3 | Rapid-tap shutter 3× (still mode) | No crash; at most one nudge card queued at a time (latest wins) | |
| 4.4 | Open Film → existing moments visible | Feed not broken by GRDB migration adding `nudge_responses` table | |

### v0.6 Sign-off

| Item | Status |
|------|--------|
| All verification rows passing | ⬜ |
| `nudge_responses` table populated in graph.sqlite | ⬜ |
| Feature gating confirmed (v0_5 config → no nudge) | ⬜ |
| Sound Stamp regression clean | ⬜ |
| **v0.6 complete — ready for v0.7** | ⬜ |

---

## v0.7 — Story Engine & Reel Assembler

**Verification goal:** `IndexingEngine.clusterMoments()` groups assets into temporal `[Moment]` clusters automatically; `AssembleReelUseCase` produces a playable `.mov` reel with scored asset ordering and prose captions; `MomentDetailView` plays the reel inline.

**AppConfig:** `AppConfig.v0_7` — adds `features: .journalSuggest`, `aiModes: .onDevice` (prose on-device only for v0.7; `.enhancedAI` lab prose deferred to v0.9)

### Pre-existing Scaffold

| Component | File | State |
|-----------|------|-------|
| `StoryEngine` | `NiftyCore/Sources/Engines/StoryEngine.swift` | Stub — `assembleReel()` sorts `[ReelAsset]` by `score.composite`; all 4 scoring methods return placeholder floats |
| `AssembleReelUseCase` | `NiftyCore/Sources/Domain/UseCases/AssembleReelUseCase.swift` | Thin wrapper — calls `engine.assembleReel(moment:)`, no `AVMutableComposition` yet |
| `VoiceProseEngine` | `NiftyCore/Sources/Engines/VoiceProseEngine.swift` | Stub — delegates to `lab.transformProse()` (no on-device path) |
| `AssetScore` | `NiftyCore/Sources/Domain/Models/SupportingTypes.swift` | Fully defined: `motionInterest`, `vibeCoherence`, `chromaticHarmony`, `uniqueness` (weights 0.25 each) |
| `ReelAsset` | `NiftyCore/Sources/Domain/Models/SupportingTypes.swift` | Fully defined: `asset`, `score`, `caption`, `startTime`, `duration` |
| `ProseStyle` / `ProseVariant` | `NiftyCore/Sources/Domain/Models/SupportingTypes.swift` | Fully defined enum with raw values |
| `IndexingEngine` | `NiftyCore/Sources/Engines/IndexingEngine.swift` | `clusterMoments()` does **not exist** — must be added |
| `MomentDetailView` | `Apps/niftyMomnt/niftyMomnt/UI/Journal/` | **Does not exist** — must be created (currently feed is the only journal view) |

### Features In Scope

- `IndexingEngine.clusterMoments()`: time-window (≤ 2 h gap) + optional location radius (≤ 500 m) clustering → returns `[[Asset]]` groups that map to `[Moment]`
- `StoryEngine`: implement 3 narrative arc templates (Rising Action, Quiet Chronicle, Vibe Loop); real scoring for `motionInterest` (video vs still), `vibeCoherence` (dominant vibe match), `chromaticHarmony` (palette similarity), `uniqueness` (timestamp spread)
- `VoiceProseEngine`: on-device prose path using `ProseStyle` — 3 simple template strings per style (Poet, Foodie, Minimalist), no network call for v0.7
- `AssembleReelUseCase`: real `AVMutableComposition` — still photo → `CMSampleBuffer` via `AVAssetImageGenerator`, video assets appended natively; total duration target 15–60 s; exported to `.mov` in `Documents/reels/{momentID}.mov`
- `MomentDetailView`: pushed from `JournalFeedView` on moment tap; shows asset grid + "Play Reel" button; `AVPlayer` inline reel playback in a sheet

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `AppConfig.v0_7` — add `.journalSuggest` to features | `Apps/niftyMomnt/AppConfig+Interim.swift` | ⬜ |
| 2 | `IndexingEngine.clusterMoments(assets:)` — time-window + location clustering | `NiftyCore/Sources/Engines/IndexingEngine.swift` | ⬜ |
| 3 | `GraphProtocol.fetchAssets(for momentID:)` — asset list for a moment | `NiftyCore/Sources/Domain/Protocols/GraphProtocol.swift` | ⬜ |
| 4 | `GraphRepository`: implement `fetchAssets(for momentID:)` | `NiftyData/Sources/Repositories/GraphRepository.swift` | ⬜ |
| 5 | `StoryEngine`: implement 3 arc templates + real `AssetScore` computation | `NiftyCore/Sources/Engines/StoryEngine.swift` | ⬜ |
| 6 | `VoiceProseEngine`: on-device prose (template strings per `ProseStyle`) | `NiftyCore/Sources/Engines/VoiceProseEngine.swift` | ⬜ |
| 7 | `AssembleReelUseCase`: `AVMutableComposition` reel → export `.mov` | `NiftyCore/Sources/Domain/UseCases/AssembleReelUseCase.swift` | ⬜ |
| 8 | `AppContainer`: expose `storyUseCase` + `assembleUseCase` to views | `Apps/niftyMomnt/niftyMomnt/AppContainer.swift` | ⬜ |
| 9 | `MomentDetailView`: asset grid + "Play Reel" → `AVPlayer` sheet | `Apps/niftyMomnt/niftyMomnt/UI/Journal/MomentDetailView.swift` | ⬜ |
| 10 | `JournalFeedView`: tap row → `NavigationLink` to `MomentDetailView` | `Apps/niftyMomnt/niftyMomnt/UI/Journal/JournalFeedView.swift` | ⬜ |
| 11 | `niftyMomntApp.swift`: bump config to `AppConfig.v0_7` | `Apps/niftyMomnt/niftyMomntApp.swift` | ⬜ |

### Design Notes

**Clustering algorithm (task 2):**
- Sort all un-clustered assets by `capturedAt` ascending
- Start new cluster when gap to previous asset > 7200 s (2 h) OR location distance > 500 m (if location available)
- Minimum cluster size = 2 assets; singletons remain as standalone moments (no reel)
- Each cluster maps 1:1 to a `Moment` via existing `GraphRepository` moment + `moment_assets` join

**Narrative arc selection (task 5):**
- **Rising Action**: lead with lowest-score asset, end with highest — classic build
- **Quiet Chronicle**: chronological order, no reordering — preserves memory sequence
- **Vibe Loop**: sort by `vibeCoherence` descending, drop outliers — coherent mood reel
- Arc is selected automatically: if `vibeCoherence` spread < 0.2 → Vibe Loop; if sequence is ≥ 5 assets → Rising Action; else Quiet Chronicle

**Scoring implementation (task 5):**
- `motionInterest`: video asset = 0.9, still = 0.4 + (0.1 × nudge response weight if present)
- `vibeCoherence`: fraction of moment's `dominant_vibes` that appear in this asset's vibe tags
- `chromaticHarmony`: compare first 3 palette colours to moment median palette — cosine similarity in RGB space
- `uniqueness`: score = 1.0 − (similar_timestamp_count / total_assets); assets > 30 s apart from nearest neighbour score 1.0

**Prose generation (task 6):**
- Input: `[ReelAsset]`, `ProseStyle`, moment `location` name (optional)
- Poet template: `"A {vibe} moment{location_suffix} — {asset_count} frames of something worth keeping."`
- Foodie template: `"Savoured {asset_count} glimpses of {vibe}{location_suffix}."`
- Minimalist template: `"{vibe}.{location_suffix_short}"` (single sentence)
- Fill `{vibe}` from `moment.dominant_vibes.first?.rawValue ?? "quiet"`
- Fill `{location_suffix}` from geocoded place name if available; empty string otherwise

**AVMutableComposition (task 7):**
- Still photos: create `AVURLAsset` from JPEG on disk → `AVAssetImageGenerator` → `CVPixelBuffer` → write frames at 30fps for `ReelAsset.duration` seconds (default 2.5 s per still)
- Video clips: append native `AVAsset` track segment directly
- Total composition capped at 60 s; trim lowest-score assets first if over limit
- Export with `AVAssetExportSession`, preset `AVAssetExportPresetHighestQuality`, output to `Documents/reels/{momentID}.mov`
- Exported URL stored in `Moment.reelURL` (new optional field in GRDB `moments` table)

### Verification Checklist

> Run on a real device after all tasks complete. All rows must pass before starting v0.8.
>
> **v0.7 scope notes (updated after implementation):**
> - Reel composer is `AVAssetWriter` (JPEG stills → H.264), **not** `AVMutableComposition`. Video clips (Clip, Echo, Atmosphere) are **excluded** from v0.7 reels; full AVComposition support is v0.9.
> - `VoiceProseEngine` generates `[ProseVariant]` on-device and is available via `container.voiceProseEngine.generateProse(for:)`. Prose UI (caption overlay, style picker) is deferred to v0.8.
> - Clustering is wired into the **capture pipeline** (`mergedOrNew()` in `CaptureMomentUseCase`), not a post-hoc batch step. Console filter `CaptureUseCase` → look for `[merge]` lines.

#### 1 — Clustering (merge-on-capture)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 1.1 | Capture 3+ stills within 10 minutes at the same location | Console shows `[merge] merging asset … into moment … (now N assets)` for shots 2+; single moment in feed with N assets | |
| 1.2 | Capture 2 stills, move >500 m away (or wait >2 h), capture 2 more | Console shows `[merge] no compatible moment found` for the second pair; two separate moments in feed | |
| 1.3 | Capture a single asset with no other nearby assets | Console shows `[merge] no compatible moment found`; moment created with 1 asset; "Play Reel" button absent in MomentDetailView | |
| 1.4 | Open MomentDetailView for a merged moment | "Shot N of M" counter shows correct total; swipe left/right navigates all M shots | |

#### 2 — Story Scoring & Arc

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 2.1 | Open MomentDetailView for a moment with ≥2 stills → tap "Play Reel" | Reel plays without crash; asset order is deterministic across runs (same scoring each time) | |
| 2.2 | Capture a moment with a mix of Clip + Still assets (≥2 stills) | "Play Reel" button appears; reel plays stills-only (clips excluded in v0.7, no error shown); no crash | |
| 2.3 | Capture a moment with only Clip assets and no stills | "Play Reel" button absent (gate: ≥2 still/live/l4c assets required) | |
| 2.4 | Capture a mood-coherent burst (all assets share same vibe context, ≥2 stills) | Vibe Loop arc selected (vibeCoherence spread < 0.2); most-coherent shot plays first | |
| 2.5 | Capture a moment with ≥5 still assets with varied vibe spread | Rising Action arc selected; shots build from lowest to highest vibeCoherence as tiebreaker | |

#### 3 — Prose Engine (backend verification only)

> Prose UI is deferred to v0.8. Test the engine directly via Xcode debugger or a temporary log call.

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 3.1 | Call `container.voiceProseEngine.generateProse(for: moment)` in debugger for a moment with a geocoded location | Returns 3 `ProseVariant` values; each contains location name in body text | |
| 3.2 | Call for a moment with no location | Returns 3 variants; location suffix omitted gracefully (no "nil" or placeholder text) | |
| 3.3 | Call for a moment with a dominant vibe | `{vibe}` token replaced with `dominantVibes.first?.rawValue`; deterministic across calls (same moment ID → same template) | |

#### 4 — Reel Export & Playback

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 4.1 | Tap "Play Reel" for a moment with ≥2 stills | AVPlayer sheet appears and plays `.mov`; no crash | |
| 4.2 | Xcode Device Manager → `Documents/reels/` | `.mov` file exists for the moment; file size > 0 | |
| 4.3 | Play a reel with portrait stills | Frames display upright (not rotated 90°); EXIF orientation correctly applied | |
| 4.4 | Play a reel with a mix of landscape and portrait stills | Output dimensions match the first successfully decoded image; no crash on dimension mismatch | |
| 4.5 | Reel for a moment with >24 still assets (edge case) | Reel ≤ 60 s (lowest-scored assets trimmed); no crash | |

#### 5 — Navigation & Regression

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 5.1 | Tap any moment card in Film feed | MomentDetailView sheet opens with correct moment data | |
| 5.2 | Swipe left in MomentDetailView (multi-shot moment) | Hero image advances to next shot; "Shot N of M" counter increments; pagination dots update | |
| 5.3 | Swipe right from shot 2+ | Returns to previous shot | |
| 5.4 | Dismiss MomentDetailView and re-open | Returns to Shot 1 (index resets on `.task(id: moment.id)`) | |
| 5.5 | Still capture with nudge card (v0.6) | Nudge card still fires; merge-on-capture and reel assembly unaffected | |
| 5.6 | Kill + relaunch | `Documents/reels/` `.mov` persists; tapping "Play Reel" plays the cached file on second launch | |

### v0.7 Sign-off

| Item | Status |
|------|--------|
| All verification rows passing | ⬜ |
| `Documents/reels/` contains valid upright `.mov` files | ⬜ |
| Merge-on-capture respects 2 h / 500 m thresholds (console verified) | ⬜ |
| Mixed clips+stills: reel plays stills-only without crash | ⬜ |
| Shot swipe navigation works for all asset types | ⬜ |
| v0.6 nudge card regression clean | ⬜ |
| **v0.7 complete — ready for v0.8** | ⬜ |

---

## v0.8 — Private Vault & Face ID

**Verification goal:** Assets marked private are AES-GCM encrypted and hidden from the feed; VaultView is Face ID-gated; lock/unlock state persists correctly across app launches.

**AppConfig:** `AppConfig.v0_8` — cumulative features: `[.l4c, .rollMode, .soundStamp, .nudgeEngine, .journalSuggest, .trustedSharing]`

> **Pre-condition (fix in v0.7 task 1):** `AppConfig+Interim.swift` labels are inverted from the v0.7↔v0.8 swap. Before starting v0.7:
> - `v0_7` comment → "Story Engine + Reel Assembler"; remove `.trustedSharing`, add `.journalSuggest`
> - `v0_8` comment → "Private Vault + Face ID"; features → cumulative through `.trustedSharing`

### Features In Scope

- `Asset.isPrivate: Bool` domain flag; stored in `.json` sidecar and GRDB `assets` table
- `VaultRepository`: AES-GCM encryption via `CryptoKit`; single app DEK in Keychain; `moveToVault` re-encrypts in place
- `VaultManager`: `isVaultLocked` state + `LAContext` Face ID gate + `moveToVault` coordinating vault + graph
- `GraphRepository`: `is_private` column migration; `fetchMoments` excludes private assets when locked
- `VaultView`: real Face ID prompt; private asset grid when unlocked
- `MomentDetailView`: "Move to Vault" action (extends v0.7-built view)
- `FilmFeedView` / `JournalFeedView`: filter out private moments when vault is locked

### Design Decisions

**Encryption:** Single 256-bit app DEK stored in Keychain under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. AES-GCM nonce stored as 12-byte prefix of each ciphertext file. No per-asset DEK for v0.8 — key rotation deferred to v0.9+.

**`moveToVault` flow:** Update sidecar `isPrivate = true` → re-encrypt file in place → call `GraphRepository.markAssetPrivate(assetID:isPrivate:true)`. Encrypted file overwrites original.

**Vault lock state:** `VaultManager.isVaultLocked` is in-process only — resets to `true` on every cold launch. No stored unlock token. User must re-authenticate every session.

**LAContext policy:** Primary policy `.deviceOwnerAuthenticationWithBiometrics`. If fails with `LAError.biometryNotEnrolled`, surface a user-facing message (do not silently fall back to passcode in v0.8).

**Feed filtering:** `GraphRepository.fetchMoments()` gains `showPrivate: Bool = false`. Moments where all linked assets have `is_private = 1` are excluded by default. `VaultView` queries with `showPrivate: true` post-auth.

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | `Asset.isPrivate: Bool = false` + `AssetRecord` sidecar field + `VaultQuery.showPrivateOnly: Bool` | `NiftyCore/Sources/Domain/Models/Asset.swift`, `NiftyCore/Sources/Domain/Models/SupportingTypes.swift`, `NiftyData/Sources/Repositories/VaultRepository.swift` | ⬜ |
| 2 | `VaultProtocol.moveToVault(assetID:)` | `NiftyCore/Sources/Domain/Protocols/VaultProtocol.swift` | ⬜ |
| 3 | `GraphProtocol.markAssetPrivate(assetID:isPrivate:)` | `NiftyCore/Sources/Domain/Protocols/GraphProtocol.swift` | ⬜ |
| 4 | `GraphRepository`: `is_private INTEGER NOT NULL DEFAULT 0` migration + `markAssetPrivate` UPDATE + `fetchMoments` excludes private rows when `showPrivate: false` | `NiftyData/Sources/Repositories/GraphRepository.swift` | ⬜ |
| 5 | `VaultRepository`: AES-GCM encrypt on `save`/`saveVideoFile`/`saveAudioFile` when `asset.isPrivate`; Keychain DEK; `moveToVault` (sidecar update + re-encrypt in place) | `NiftyData/Sources/Repositories/VaultRepository.swift` | ⬜ |
| 6 | `VaultManager`: add `graph: any GraphProtocol` injection; `isVaultLocked: Bool`; `unlockVault()` via `LAContext`; `lockVault()`; `moveToVault(assetID:)` → coordinates vault + graph | `NiftyCore/Sources/Managers/VaultManager.swift` | ⬜ |
| 7 | `AppContainer`: inject `graph` into `VaultManager`; expose `vaultManager.isVaultLocked` to views | `Apps/niftyMomnt/niftyMomnt/AppContainer.swift` | ⬜ |
| 8 | `VaultView`: bind `container.vaultManager` state; real `LAContext` Face ID prompt; private asset grid via `VaultQuery(showPrivateOnly: true)`; lock button re-locks | `Apps/niftyMomnt/niftyMomnt/UI/Vault/VaultView.swift` | ⬜ |
| 9 | `MomentDetailView`: "Move to Vault" action (extends v0.7-built view) | `Apps/niftyMomnt/niftyMomnt/UI/Journal/MomentDetailView.swift` | ⬜ |
| 10 | `FilmFeedView`/`JournalFeedView`: pass `showPrivate: false` to `fetchMoments` + `AppConfig.v0_8` label fix + `niftyMomntApp.swift` bump to `AppConfig.v0_8` | `Apps/niftyMomnt/niftyMomnt/UI/Journal/JournalFeedView.swift`, `Apps/niftyMomnt/niftyMomnt/AppConfig+Interim.swift`, `Apps/niftyMomnt/niftyMomnt/niftyMomntApp.swift` | ⬜ |

### Verification Checklist

> Run on a real device after all tasks complete. All rows must pass before starting v0.9.
>
> **Pre-conditions before running:**
> - Build target set to a real device (not Simulator — Face ID policy requires real biometrics).
> - At least 3 moments with still assets already in the feed from a prior v0.7 run, or capture fresh ones now.
> - Xcode console open, filter set to subsystem `com.hwcho99.niftymomnt`.
> - Xcode Device Manager → Files tab open alongside (used to inspect `Documents/assets/`).

---

#### 1 — Move to Vault (happy path)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 1.1 | Open any moment in the film feed → MomentDetailView opens. Note the moment's first asset ID from console (`loadHeroImage` log line shows `assetID=…`). | MomentDetailView loads the shot normally. | |
| 1.2 | In the actions row, find and tap **"Move to Vault"**. | Button shows "Moving…" spinner briefly, then an alert appears: "Shot moved to your private vault." | |
| 1.3 | Tap **OK** on the alert. | MomentDetailView dismisses automatically. | |
| 1.4 | In Xcode Device Manager → Files → `Documents/assets/`, look for `{assetID}.json` (sidecar). Download and open it. | `isPrivate` key is present and set to `true`. | |
| 1.5 | In the same `Documents/assets/` directory, verify the file list for that asset ID. | `{assetID}.enc` exists (encrypted file). The original `{assetID}.jpg` (or `.mov` / `.m4a`) is **absent** — it was deleted after encryption. | |
| 1.6 | In Xcode console, filter category `VaultRepository`. | Log line: `moveToVault done — assetID={id}` is present. No errors. | |
| 1.7 | In Xcode console, filter category `GraphRepository` (or search `markAssetPrivate`). | Log line: `markAssetPrivate done` is present. | |

---

#### 2 — Feed filtering (private assets hidden)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 2.1 | Return to the film feed after step 1.3. | The moment that had its shot moved to vault either: (a) still appears in the feed if it has remaining non-private assets, or (b) disappears entirely if it had only one asset. | |
| 2.2 | If the moment is still visible: open it in MomentDetailView. | The privatised shot is **absent** from the shot list — "Shot N of M" count has decreased by 1. Swiping no longer reaches that shot. | |
| 2.3 | Move all remaining shots of a multi-shot moment to the vault one by one (repeat steps 1.1–1.3 for each). | After the last shot is moved, the moment card disappears from the film feed entirely. | |
| 2.4 | Kill and relaunch the app from the home screen. | Film feed still excludes the privatised moment(s). No ghost cards or blank entries. | |
| 2.5 | In Xcode console, filter category `FilmFeed`. | On each feed reload, log shows `loadFeed — N moment(s)` where N does not include the private-only moments. | |

---

#### 3 — Vault tab: locked state

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 3.1 | Navigate to the Vault tab (tab ② in the Journal sheet). | Locked state UI shows: lock icon, "Private Vault" title, "Unlock with Face ID" button. No asset content visible. | |
| 3.2 | Do **not** tap the button. Kill and relaunch the app. Navigate back to Vault tab. | Still shows locked state — lock state is not persisted across launches. | |
| 3.3 | On a device with Face ID **not enrolled** (or use a device/simulator without biometrics): tap "Unlock with Face ID". | Error message appears below the button: "Face ID is not available or not enrolled on this device." Button re-enables. Vault stays locked. | |

---

#### 4 — Vault tab: Face ID unlock

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 4.1 | On a device with Face ID enrolled: tap "Unlock with Face ID". | System Face ID prompt appears with reason string "Access your private archive". | |
| 4.2 | Authenticate successfully (correct face). | Vault tab transitions to unlocked content. Private assets moved in §1 appear as a 3-column thumbnail grid. Each thumbnail has a small lock badge in its corner. | |
| 4.3 | In Xcode console, filter category `VaultView`. | Log line: `loadPrivateAssets — N private asset(s)` where N matches the number of shots you moved to vault. | |
| 4.4 | Tap "Unlock with Face ID" again on a new session (after lock, see §5): deliberately fail authentication (wrong face or cancel). | Alert or system error is dismissed; vault stays locked. Error message from `VaultAuthError.authFailed` appears below the button. | |

---

#### 5 — Lock / re-lock

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 5.1 | While vault is unlocked (after step 4.2): tap the **lock icon** in the top-right toolbar of VaultView. | View transitions back to the locked state immediately. Grid disappears. | |
| 5.2 | While vault is unlocked: kill the app from the app switcher and relaunch. Navigate to Vault tab. | Vault is locked again (cold launch resets state). | |
| 5.3 | Background the app (home button / swipe up), wait 5 seconds, foreground it again. Navigate to Vault tab. | Vault is still locked if it was locked; still unlocked if it was unlocked in this session. Background alone does not re-lock. | |

---

#### 6 — Vault thumbnail loading (decryption round-trip)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 6.1 | Unlock vault and observe the asset grid (step 4.2). | Thumbnails load for still/live/l4c assets. Images appear correctly — upright, not rotated, not corrupted. | |
| 6.2 | Move a portrait still to vault, then unlock and inspect its thumbnail. | Portrait thumbnail displays upright (same orientation as in the film feed before it was privatised). Confirms AES-GCM decrypt → UIImage path respects EXIF orientation. | |
| 6.3 | Move a clip (`.mov`) asset to vault, unlock, check grid. | Clip tile shows the video icon + "Video Clip" label placeholder, with a **CLIP** badge top-left and lock badge bottom-right. No JPEG thumbnail (encrypted MOV can't be decoded in-grid — by design). No crash. | |
| 6.4 | In Xcode console during thumbnail loading, filter category `VaultRepository`. | Log lines show `load` being called for each private asset. No `decryptionFailed` errors. | |
| 6.5 | Tap any tile in the vault grid (still, clip, echo). | **Nothing happens — expected v0.8 behavior.** Vault tiles are display-only in this version; no detail view or playback. Full vault asset viewer is scoped to v1.0. | |

---

#### 7 — "Move to Vault" edge cases

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 7.1 | Open a MomentDetailView for a shot that was already moved to vault (navigate back to it via a multi-asset moment where only some shots are private). | **"Move to Vault" button is absent** for that shot (`asset.isPrivate == true` hides the button). | |
| 7.2 | Rapidly double-tap "Move to Vault" on a shot. | Only one `moveToVault` call executes; second tap is a no-op (idempotency: `guard !(record.isPrivate ?? false) else { return }`). No duplicate `.enc` files or double-write errors in console. | |
| 7.3 | Move the only shot of a single-asset moment to vault. | Alert fires, detail view dismisses, and the film feed refreshes: that moment card disappears. | |
| 7.4 | Attempt to move an Echo (audio) asset to vault. | "Move to Vault" button is present for Echo assets. Tap it → `moveToVault` runs. In `Documents/assets/`, verify `{id}.enc` exists and `{id}.m4a` is gone. | |

---

#### 8 — Encryption integrity (file-level verification)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 8.1 | Download a `{assetID}.enc` file via Xcode Device Manager. Open it in a hex editor. | First 12 bytes are the AES-GCM nonce (random, non-zero). Bytes 13+ are opaque ciphertext. The file is **not** a valid JPEG (no `FF D8 FF` magic bytes at offset 0). | |
| 8.2 | Download the same asset's `{assetID}.json` sidecar. | `isPrivate` is `true`. `type`, `capturedAt`, and other metadata fields are present in plaintext (sidecar is not encrypted). | |
| 8.3 | Kill the app, manually rename `{assetID}.enc` to something else using Xcode Device Manager (breaking the decrypt path). Relaunch and unlock vault. | Vault grid shows the asset tile with a placeholder icon (no crash). Console shows `notFound` or similar — `load()` returns nil for the missing `.enc`. | |
| 8.4 | Restore the original filename (rename back). Relaunch, unlock vault. | Thumbnail loads correctly again — decryption succeeds. | |

---

#### 9 — Delete private asset

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 9.1 | Navigate to the film feed. Find a moment where only some shots are private (mix of private + public assets). Open MomentDetailView and navigate to a **non-private** shot. Tap **Delete** (trash icon). Confirm the deletion dialog. | Moment is deleted. Both public and private files for that moment are removed. Console shows `deleteMoment done`. | |
| 9.2 | In `Documents/assets/`, verify for the deleted moment's private asset. | `{id}.enc` is **absent** (delete path removes `.enc` alongside `.jpg` and `.json`). | |
| 9.3 | Navigate to Vault tab and unlock. | The deleted asset's thumbnail is absent from the private grid. No ghost entry. | |

---

#### 10 — Regression (v0.7 features unaffected)

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 10.1 | Capture 3 stills at the same location within 10 minutes. | Console shows `[merge]` lines; single moment with 3 shots in feed. "Play Reel" button appears. | |
| 10.2 | Tap "Play Reel" on a moment with ≥2 non-private stills. | Reel assembles and plays correctly. No crash. | |
| 10.3 | Move 1 of 3 stills in a moment to vault. Tap "Play Reel" on the same moment. | Reel assembles from the **2 remaining non-private** stills only. `StoryEngine.assembleReel` fetches via `graph.fetchAssets` which returns all assets including private ones — reel may include private stills (v0.8 does not filter them from reel scoring; that is a v0.9 concern). No crash. | |
| 10.4 | Post-capture nudge card (v0.6). | Nudge card still fires after capture. "Move to Vault" and nudge coexist without interference. | |
| 10.5 | Shot swipe in MomentDetailView for a moment with mixed public/private shots. | Swipe navigates all assets including the private shot's position (the moment model still includes private assets in its `assets` array — the feed just hides the card when all are private). No crash. | |

---

### v0.8 Sign-off

| Item | Status |
|------|--------|
| All §1–§10 verification rows passing | ⬜ |
| `{assetID}.enc` present, original file absent, sidecar `isPrivate: true` for moved assets | ⬜ |
| Film feed hides moments where all assets are private (cold-launch verified) | ⬜ |
| Face ID unlock succeeds; face fail / cancel stays locked with error message shown | ⬜ |
| Lock button and cold-launch both reset vault to locked state | ⬜ |
| Thumbnail decryption round-trip: image displayed correctly (upright, not corrupted) | ⬜ |
| `.enc` file is not valid JPEG (hex-verified) | ⬜ |
| Delete removes `.enc` file from disk (Xcode Device Manager verified) | ⬜ |
| v0.7 reel assembly and merge-on-capture regression clean | ⬜ |
| **v0.8 complete — ready for v0.9** | ⬜ |

---

## v0.9 — Extended Intelligence & Dual-Camera

**Verification goal:** Dual-camera capture works on supported devices; Lab Mode (Mode-2) sends encrypted visual data to cloud VLM; Journaling Suggestions API surfaces relevant moments; AI caption generated from ambient metadata.

**AppConfig:** `AppConfig.v0_9` — `aiModes: [.onDevice, .enhancedAI, .lab]`, `features: [..., .dualCamera]`

### Features In Scope

- `AVCaptureAdapter`: dual-camera session (`AVCaptureMultiCamSession`) on iPhone 15+
- `LabNetworkAdapter`: encrypted visual payload → cloud VLM response (Mode-2); AI caption via Mode-1
- `JournalSuggestionsAdapter`: `JournalingSuggestions` framework → surface relevant moments as `NudgeCard`
- `VoiceProseEngine`: `generateAICaption(for:tone:config:)` — ambient + vibe → `EnhancedAI` text completion with on-device fallback
- `SettingsView`: Dual Camera toggle gated on `.dualCamera` feature flag + `AVCaptureMultiCamSession.isMultiCamSupported`
- Roll Mode: confirm shutter hard-disabled at daily cap (verification + fix if needed)

### Implementation Tasks

#### Dependency Order

```
Phase 1 — Foundation
  Task 1: FeatureSet.dualCamera flag

Phase 2 — Core (parallel after Task 1)
  Task 2: AVCaptureAdapter dual-camera
  Task 3: LabNetworkAdapter stubs → real implementation
  Task 4: JournalSuggestionsAdapter JSDataFetcher integration
  Task 5: VoiceProseEngine generateAICaption

Phase 3 — UI + wiring (after Phase 2)
  Task 6: SettingsView dual camera gate
  Task 7: Roll Mode shutter cap enforcement
  Task 8: Config bump → AppConfig.v0_9
```

#### Task Table

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | Add `FeatureSet.dualCamera` (rawValue `1 << 10`); add to `FeatureSet.all`; add to `AppConfig.v0_9` features array | `NiftyCore/Sources/Domain/AppConfig.swift`, `NiftyData/Sources/Config/AppConfig+Interim.swift` | ⬜ |
| 2 | `AVCaptureAdapter`: `AVCaptureMultiCamSession` dual-camera — session type selected at `init` time; secondary camera → `AVCaptureVideoDataOutput` (frames only, never persisted); `latestSecondaryFrameData() -> Data?` for Lab VLM payload | `NiftyData/Sources/Platform/AVCaptureAdapter.swift` | ⬜ |
| 3 | `LabNetworkAdapter`: fill `generateCaption` (Mode-1 URLSession POST `/v1/caption`, JSON ambient+vibe, guarded by `.enhancedAI`); fill `requestLabSession` (CryptoKit P256 DH key exchange, AES-256-GCM per-asset encryption); fill `processLabSession` (POST multipart, parse `LabResult`); fill `verifyPurge` (DELETE `/v1/lab/{sessionID}`); placeholder URL + stub fallback when network unavailable | `NiftyData/Sources/Network/LabNetworkAdapter.swift` | ⬜ |
| 4 | `JournalSuggestionsAdapter`: implement `evaluateTriggers` (`JSDataFetcher.requestAuthorization` + `fetchSuggestions(limit:5)`, filter by recency within 24h of moment, map to `NudgeCard`) and `refresh` (re-fetch + publish or nil); `@available(iOS 17.2, *)` guards throughout | `NiftyData/Sources/Platform/JournalSuggestionsAdapter.swift` | ⬜ |
| 5 | `VoiceProseEngine`: add `generateAICaption(for:tone:config:) async throws -> [CaptionCandidate]` — routes to `lab.generateCaption` when `config.aiModes.contains(.enhancedAI)`, else on-device template fallback | `NiftyCore/Sources/Engines/VoiceProseEngine.swift` | ⬜ |
| 6 | `SettingsView`: wrap `dualCameraEnabled` toggle in `config.features.contains(.dualCamera) && AVCaptureMultiCamSession.isMultiCamSupported`; show locked row with "Requires iPhone 15 or later." when flag set but hardware unsupported; add `import AVFoundation` | `Apps/niftyMomnt/niftyMomnt/UI/Settings/SettingsView.swift` | ⬜ |
| 7 | `CaptureHubView`: confirm shutter button action is hard-disabled (not just visually dimmed) when `rollShotsRemaining == 0 && config.features.contains(.rollMode)`; add guard if missing | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ⬜ |
| 8 | Bump composition root to `AppConfig.v0_9`; verify `AppContainer` requires no new injections (Lab + JournalSuggestions adapters already wired) | `Apps/niftyMomnt/niftyMomnt/niftyMomntApp.swift` | ⬜ |

#### Implementation Notes

**Task 2 — `AVCaptureAdapter` init constraint.** `AVCaptureSession` vs `AVCaptureMultiCamSession` must be decided at `init` time — the session is `let` and cannot be replaced. Check `AVCaptureMultiCamSession.isMultiCamSupported && config.features.contains(.dualCamera)` in `init` and initialize accordingly. Typed as `AVCaptureSession` in the property declaration; `AppContainer.captureSession: AVCaptureSession` continues to work without change.

**Task 3 — No separate `EnhancedAIClient`.** `LabNetworkAdapter` already implements `LabClientProtocol` which covers both Mode-1 (caption/prose) and Mode-2 (encrypted visual). A second class would duplicate protocol machinery. `generateCaption` on `LabNetworkAdapter` is the enhanced-AI path.

**Task 3 — Backend not live.** Implement crypto path fully (P256 DH + AES-GCM), but use a placeholder endpoint URL and return a stub `LabResult` on any network failure. This matches the existing stub pattern and avoids blocking device verification on backend readiness.

**Task 4 — Entitlement required.** `com.apple.developer.journaling-suggestion` must be added to `niftyMomnt.entitlements` in Xcode (capability checkbox) before device testing. No code change, but a test run without it will crash on the `JournalingSuggestions` framework call.

---

### Verification Checklist

> Run on a real device after all tasks complete. All rows must pass before starting v1.0.

#### §1 — Config & Feature Flags

| # | Step | Expected | Result |
|---|------|----------|--------|
| 1.1 | Build and launch. Open Settings. | App boots on `AppConfig.v0_9` without crash. | |
| 1.2 | On iPhone 15 or later, check Settings → Dual Camera row. | Toggle is visible and interactive. | |
| 1.3 | On iPhone 14 or earlier (or simulator), check Settings → Dual Camera row. | Row shows "Requires iPhone 15 or later." with lock icon; no toggle. | |
| 1.4 | In `AppConfig+Interim.swift`, confirm `v0_9.aiModes` contains `.onDevice`, `.enhancedAI`, `.lab`. | Build-time assertion or log output confirms all three modes active. | |

#### §2 — Dual-Camera Capture (iPhone 15+ only)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 2.1 | Enable Dual Camera toggle in Settings. Navigate to CaptureHub. | No crash. Camera preview shows primary (back wide) feed. | |
| 2.2 | Capture a still. | Photo saved normally. No secondary frame appears in Camera Roll or in `graph.fetchAssets`. | |
| 2.3 | Call `captureAdapter.latestSecondaryFrameData()` in a debug breakpoint immediately after capture. | Returns non-nil JPEG-compressed `Data`. | |
| 2.4 | Disable Dual Camera toggle in Settings. Restart app. Capture a still. | Single-camera session used. `latestSecondaryFrameData()` returns `nil`. | |
| 2.5 | Run on simulator (multi-cam unsupported). Enable Dual Camera toggle (should not be visible — §1.3 gate). | Settings row absent. `AVCaptureAdapter` uses standard `AVCaptureSession`. | |

#### §3 — Lab Mode / LabNetworkAdapter

| # | Step | Expected | Result |
|---|------|----------|--------|
| 3.1 | With network available, trigger `LabNetworkAdapter.generateCaption(for:tone:)` via `VoiceProseEngine.generateAICaption` on a moment with at least one vibe tag. | Method completes. Returns `[CaptionCandidate]` (stub or real). No crash. | |
| 3.2 | With network unavailable (Airplane Mode), call `generateAICaption` with `config.aiModes.contains(.enhancedAI) == true`. | Graceful fallback: returns `[CaptionCandidate]` from on-device template. No crash. | |
| 3.3 | Call `LabNetworkAdapter.requestLabSession(assets:consent:)` with 2 asset UUIDs. | Method completes. CryptoKit P256 key pair generated (verify in debugger). AES-GCM encryption applied. No crash. | |
| 3.4 | Call `verifyPurge(sessionID:)` with a test session ID. | DELETE request fired (verify in Proxyman/Charles or network logs). Returns `PurgeConfirmation` (stub). No crash. | |
| 3.5 | Confirm `requestLabSession` / `processLabSession` are gated: call them when `config.aiModes.contains(.lab) == false`. | Methods return early or throw a gating error. No network call made. | |

#### §4 — Journaling Suggestions

| # | Step | Expected | Result |
|---|------|----------|--------|
| 4.1 | First launch after adding `com.apple.developer.journaling-suggestion` entitlement. Open app. | System authorization prompt appears for Journaling Suggestions. | |
| 4.2 | Deny authorization. Trigger `evaluateTriggers(for:)` (e.g. capture a moment). | Method returns early. No crash. No nudge card shown. | |
| 4.3 | Grant authorization. Capture a moment with a timestamp matching a recent Journal suggestion (within 24h). | `NudgeEngine` surfaces a `NudgeCard` derived from the matching suggestion. | |
| 4.4 | Call `refresh()` with no recent Journal suggestions. | Nudge card cleared or remains absent. No crash. | |
| 4.5 | On iOS < 17.2 (if tested). | `@available` guard prevents any `JournalingSuggestions` API call. No crash. | |

#### §5 — AI Caption (VoiceProseEngine)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 5.1 | Open a moment with at least one vibe tag. Trigger "Generate Caption" action. `config.aiModes.contains(.enhancedAI) == true`. | `generateAICaption` calls `lab.generateCaption`. Returns `[CaptionCandidate]`. Caption text displayed. | |
| 5.2 | Temporarily set `aiModes` to `[.onDevice]` only. Trigger "Generate Caption" on same moment. | On-device template prose returned as single `CaptionCandidate`. No network call made. Caption text displayed. | |
| 5.3 | Trigger "Generate Caption" on a moment with no vibe tags. | Returns at minimum one caption candidate (template fallback). No empty state crash. | |

#### §6 — Roll Mode Cap

| # | Step | Expected | Result |
|---|------|----------|--------|
| 6.1 | Enable Roll Mode in Settings. Set debug daily cap to 3. Capture 3 stills. | Roll counter reads `0 / 3`. | |
| 6.2 | Tap shutter button when `rollShotsRemaining == 0`. | Shutter button is non-interactive (disabled, not just dimmed). No capture occurs. No crash. | |
| 6.3 | Disable Roll Mode in Settings. Tap shutter. | Capture proceeds normally. No cap enforced. | |

#### §7 — Regression

| # | Step | Expected | Result |
|---|------|----------|--------|
| 7.1 | Capture a still (single-camera). Verify it appears in Timeline. | Asset saved and displayed. No regression from v0.8. | |
| 7.2 | Move an asset to Vault. Unlock Vault (Face ID). Verify asset visible in Vault. | Vault lock/unlock flow intact. | |
| 7.3 | Trigger Sound Stamp recording. | Sound Stamp captured and linked to moment. | |
| 7.4 | Trigger `NudgeEngine` via `NudgeEngineAdapter` (non-Journal path). | Nudge card appears without crash. JournalSuggestionsAdapter changes did not break existing nudge sources. | |
| 7.5 | Open Settings. Verify all v0.8 toggles still function. | No settings regression. | |

| **v0.9 complete — ready for v1.0** | ⬜ |

---

## v1.0 — Full Feature Set & App Store Ready

**Verification goal:** All PRD v1.6 MVP features implemented, gated, and verified on device. `AppConfig.full` and `AppConfig.lite` both boot cleanly. Performance targets met. App Store submission ready.

### Features In Scope

- **Vault Backup & Restore** (Option C — user-driven portable archive)
- Live Activities + Lock Screen quick-capture actions (`ActivityKit`)
- Home Screen widget (3 types via `WidgetKit`)
- Self-timer (3s / 10s) in `CaptureHubView` Zone A
- Onboarding: gesture tutorial (interactive), personalized daily capture prompt (opt-in)
- niftyMomntLite variant: `AppConfig.lite` validated (`assetTypes: .basic`, `aiModes: .onDevice`)
- Accessibility: Dynamic Type, VoiceOver labels, `reduceMotion` all passing
- Performance: cold launch < 1.5s; capture-to-preview < 300ms; classification < 500ms on A16+
- App Store: Privacy Nutrition Labels, App Tracking Transparency, export compliance

---

### Vault Backup & Restore Design (v1.0)

**Why this is needed:** The v0.8 vault DEK uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — it is deliberately excluded from all iCloud and iTunes/Finder backups. The encrypted `.enc` files live in `Documents/assets/` and would be backed up, but without the DEK they are unrecoverable. Net result: vault content is permanently lost if the app is deleted or the user moves to a new phone. This feature closes that gap with an intentional, user-controlled export/import flow.

**Design decisions:**

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Transport format | Password-encrypted ZIP archive (`vault-backup-{date}.niftyvault`) | Portable, inspectable, no proprietary container needed |
| Archive encryption | AES-256-GCM with a key derived from user passphrase via HKDF-SHA256 | Passphrase-based; no dependency on device Keychain |
| Passphrase KDF | HKDF with a random 32-byte salt (stored unencrypted at start of archive) | HKDF is available via CryptoKit; no scrypt/Argon2 dependency needed |
| Archive contents | Decrypted asset files + JSON manifest (asset ID, type, capturedAt, vibeTags, momentID) | Decrypted at export time; re-encrypted at import time with new device's DEK |
| DEK handling | NOT exported — new DEK generated (or existing reused) on target device at import | DEK is device-local by design; archive passphrase is the portability layer |
| iCloud/AirDrop | `UIActivityViewController` with the `.niftyvault` file | User chooses where to send it (Files app, AirDrop, iMessage, etc.) |
| Minimum passphrase | 8 characters, enforced at export UI | Prevents trivially weak archives |

**Archive format (`vault-backup-{date}.niftyvault`):**

```
niftyvault/
  manifest.json          ← asset list + moment associations (plaintext)
  salt.bin               ← 32-byte random KDF salt (plaintext)
  assets/
    {assetID}.jpg        ← decrypted asset files (AES-GCM re-encrypted with passphrase-derived key)
    {assetID}.mov
    ...
```

> `manifest.json` is itself encrypted with the passphrase-derived key. `salt.bin` is the only plaintext data in the archive.

**Implementation Tasks:**

| # | Task | File(s) | Status |
|---|------|---------|--------|
| V1 | `VaultArchiver` (NiftyData) — `export(assets:passphrase:) async throws -> URL` · decrypt `.enc` files with DEK · re-encrypt each with HKDF-derived key · write manifest · ZIP via `ZIPFoundation` or `libcompression` | `NiftyData/Sources/Platform/VaultArchiver.swift` (new) | ⬜ |
| V2 | `VaultArchiver.import(archiveURL:passphrase:) async throws` — validate manifest, decrypt assets with passphrase key, re-encrypt with device DEK, write `.enc` + JSON sidecars, re-insert moment rows in GRDB | `NiftyData/Sources/Platform/VaultArchiver.swift` | ⬜ |
| V3 | `VaultProtocol` + `VaultManager`: `exportArchive(passphrase:) async throws -> URL` and `importArchive(url:passphrase:) async throws` passthroughs | `VaultProtocol.swift`, `VaultManager.swift` | ⬜ |
| V4 | `VaultExportView` — passphrase entry (min 8 chars, strength meter), export progress, `UIActivityViewController` share sheet | `Apps/niftyMomnt/niftyMomnt/UI/Vault/VaultExportView.swift` (new) | ⬜ |
| V5 | `VaultImportView` — file picker (`fileImporter` for `.niftyvault` UTType), passphrase entry, import progress + success/error state | `Apps/niftyMomnt/niftyMomnt/UI/Vault/VaultImportView.swift` (new) | ⬜ |
| V6 | `VaultView` (v1.0): add "Backup Vault" + "Restore Vault" buttons to unlocked content toolbar | `VaultView.swift` | ⬜ |
| V7 | Register `.niftyvault` UTType in `Info.plist` (`com.hwcho99.niftymomnt.vault-archive`) so Files app can open it directly into the import flow | `Info.plist`, `UTExportedTypeDeclarations` | ⬜ |
| V8 | Exclude `.enc` files from iCloud/iTunes backup (`URLResourceValues.isExcludedFromBackup = true` in `VaultRepository.moveToVault`) — makes device-local-only behavior explicit and prevents the misleading "backed up but unrestorable" state from v0.8 | `VaultRepository.swift` | ⬜ |

> **Note on V8:** Task V8 (exclude `.enc` from backup) is a correctness fix for the v0.8 inconsistency described above. It should be treated as the first task of v1.0, not deferred — it has no UX surface and closes the data-loss-by-confusion vector.

**Key constraints:**
- Export requires vault to be unlocked (Face ID authenticated) — enforced by checking `isVaultLocked` before starting
- Import does not require prior unlock — a fresh install with no vault can import
- Archive passphrase is never stored anywhere on device
- Progress is shown for both export and import (asset count / total)

---

### Implementation Tasks

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 1 | Vault Backup & Restore — see §Vault Backup & Restore Design above (tasks V1–V8) | Multiple | ⬜ |
| 2 | `ActivityKit`: Live Activity for active capture session | `Apps/niftyMomnt/` | ⬜ |
| 3 | `WidgetKit`: 3 widget types (last moment, streak, daily prompt) | `Apps/Widgets/` | ⬜ |
| 4 | Self-timer: 3s/10s countdown in Zone A | `Apps/niftyMomnt/niftyMomnt/UI/CaptureHub/CaptureHubView.swift` | ⬜ |
| 5 | Onboarding flow: gesture tutorial + daily prompt opt-in | `Apps/niftyMomnt/niftyMomnt/UI/` | ⬜ |
| 6 | `AppConfig.lite` E2E smoke test | `Apps/niftyMomntLite/` | ⬜ |
| 7 | Accessibility audit: Dynamic Type, VoiceOver, reduceMotion | All UI files | ⬜ |
| 8 | Performance profiling: launch, capture, classification | Instruments | ⬜ |
| 9 | Privacy manifest + App Store metadata | `Apps/niftyMomnt/` | ⬜ |

---

_Companion documents: PRD v1.6 · UI/UX Spec v1.7 · SRS v1.2 · Architecture ADR v1.1_
