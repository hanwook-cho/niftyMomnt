# Journal Debugging Record

Date: 2026-04-08

## Summary

This note records investigation and stabilization work for journal-related issues in `MomentDetailView` and adjacent feed/detail behavior.

Affected file:

- `Apps/niftyMomnt/niftyMomnt/UI/Journal/JournalFeedView.swift`

## Issue 1: Live Photo Continuation Crash

### Reported Error

Observed runtime failure:

```text
_Concurrency/CheckedContinuation.swift:172: Fatal error:
SWIFT TASK CONTINUATION MISUSE: loadHeroImage() tried to resume its continuation more than once, returning ()!
```

Crash site:

- `loadHeroImage()`
- `cont.resume()`

### Initial Symptoms

The logs showed:

- a Live Photo capture and save completed successfully
- the feed loaded normally
- `loadHeroImage` started once for the selected moment
- `PHLivePhoto.request(...)` produced two callbacks
- both callbacks returned a non-nil `photo`
- the continuation was resumed twice, causing a fatal runtime error

Representative sequence:

```text
loadHeroImage[...] start
loadHeroImage[...] callback #1 ... hasResumed=false
loadHeroImage[...] resuming continuation on callback #1
loadHeroImage[...] callback #2 ... hasResumed=true
loadHeroImage[...] resuming continuation on callback #2
Fatal error: SWIFT TASK CONTINUATION MISUSE
```

### Root Cause

`loadHeroImage()` wrapped `PHLivePhoto.request(...)` with `withCheckedContinuation`.

That was unsafe because:

- `withCheckedContinuation` requires exactly one `resume()`
- `PHLivePhoto.request(...)` can invoke its result handler multiple times
- the callback in this case was invoked twice for the same request

The debug logs showed the Photos info dictionary contained:

```text
PHLivePhotoInfoIsDegradedKey=1
```

This confirmed the Photos framework was delivering multiple results for a single request, which is valid framework behavior and not a SwiftUI task duplication issue.

### Unrelated Log Noise

The following startup logs were investigated and determined to be unrelated to the crash:

```text
duplicate column name: ambient_weather
duplicate column name: ambient_temp_c
duplicate column name: ambient_sun_pos
duplicate column name: palette_json
```

These come from `GraphRepository` schema migration logic that attempts `ALTER TABLE ... ADD COLUMN` and intentionally ignores the error when the column already exists.

### Debugging Work Added

Temporary diagnostic logging was added to `loadHeroImage()` to capture:

- a per-request UUID
- `momentID`
- `assetID`
- asset type
- cancellation state
- callback invocation count
- whether the callback was stale
- whether the returned photo was nil
- Photos `info` dictionary contents

This allowed confirmation that:

- there was one `loadHeroImage()` task start
- there were multiple `PHLivePhoto.request(...)` callbacks
- the continuation misuse was caused by the callback contract, not by multiple SwiftUI `.task` launches

### Stabilization Change

The implementation was changed to remove `withCheckedContinuation` from the Live Photo load path.

New behavior:

- the JPEG hero image is loaded and applied immediately
- `PHLivePhoto.request(...)` is called directly without suspending the async function
- `livePhoto` is updated from the callback when a photo arrives
- a `heroLoadRequestID` state value prevents stale callbacks from older requests from overwriting current UI state

Why this is more stable:

- no continuation means no risk of double-resume crash
- the UI already reacts to `@State` updates, so awaiting the callback was not required
- the request token protects against overlap if the detail view reloads while a prior request is still in flight

### Current Status

Status after change:

- continuation-based crash path removed
- debug logging remains in place for verification
- one repro/build pass is still recommended to confirm behavior on device

### Suggested Follow-up

After confirming the fix is stable, consider:

1. trimming the temporary debug logs down to a smaller permanent set
2. optionally filtering degraded callbacks if the final Photos behavior needs to be more controlled
3. reducing schema migration log noise in `GraphRepository` so startup logs are easier to read

## Issue 2: MomentDetailView Layout Shift During Live Photo Playback

### Reported Symptom

After the Live Photo playback fix, `MomentDetailView` no longer crashed, but the layout shifted horizontally once the Live Photo started playing.

Observed behavior:

- action buttons moved off-screen or became partially hidden
- icons and controls changed horizontal position during playback
- the actions row around line 633 in `JournalFeedView.swift` was visibly affected

### Root Cause

The static hero image path and the Live Photo path were not contributing layout size in exactly the same way.

Likely contributing factor:

- `PHLivePhotoView` inside `UIViewRepresentable` sized differently from SwiftUI `Image`
- when the Live Photo view became active, it could influence parent width/layout
- that width change propagated into the detail layout and squeezed the bottom action row

### Stabilization Change

The hero media container and bottom sheet were pinned to the available width in `JournalFeedView.swift`.

Changes made:

- applied `frame(maxWidth: .infinity, maxHeight: .infinity)` to the Live Photo hero view
- applied the same full-frame constraint to the static image hero view
- applied the same full-frame constraint to the gradient fallback
- applied `frame(maxWidth: .infinity)` to the glass bottom sheet

Why this helped:

- the hero area now fills the offered space instead of contributing an unexpected intrinsic width
- static image and Live Photo paths behave more consistently
- the actions row remains anchored within the device width during playback

### Current Status

Status after change:

- Live Photo playback works
- the continuation crash is resolved
- the horizontal layout shift no longer reproduces in the reported flow

### Suggested Follow-up

If layout motion appears again in a different device class, consider:

1. wrapping the hero area in a geometry-driven container with an explicit width
2. constraining the `UIViewRepresentable` even more tightly at the UIKit layer
3. trimming temporary debug logging after a few clean verification passes

## Issue 3: Export Journal Assets to Apple Photos for Compatibility Testing

### Goal

Enable export from `MomentDetailView` to the iPhone Photo Library so still and Live assets can be verified against Apple Photos behavior directly on device.

### Previous State

The `Share` affordance in `JournalFeedView.swift` did not export media.

Previous behavior:

- the top-right share button presented a generic `UIActivityViewController`
- the sheet only shared `moment.label`
- no still image or Live Photo resource was saved to the Apple Photo Library
- compatibility with Apple Photos could not be verified from the app

### Work Completed

Photo Library export was implemented across the vault and detail-view layers.

Repository/export layer:

- implemented `exportToPhotoLibrary(_:)` in `VaultRepository`
- added Photo Library add-only authorization handling
- added a shared async bridge for `PHPhotoLibrary.performChanges`
- exported still assets as `.photo`
- exported Live assets as `.photo` plus `.pairedVideo`
- preserved the original vault JPEG and companion MOV when constructing the Live Photo export

Detail-view behavior:

- replaced the placeholder text-only share flow in `MomentDetailView`
- wired the top-right button to export the currently displayed asset
- updated the bottom action button from generic share to `Save to Photos`
- added in-progress UI state during export
- added success/error alerts for user feedback

### Why This Matters

This allows real on-device verification of:

- whether a still image appears correctly in Apple Photos
- whether a saved Live asset is recognized by Apple Photos as a Live Photo
- whether the vault-preserved JPEG and MOV remain compatible outside the app

### Current Status

Status after change:

- still-photo export path implemented
- Live Photo export path implemented
- add-only Photo Library permission path implemented
- ready for iPhone verification in Apple Photos

### UX Adjustment

After implementation, the export action label was refined to reduce confusion with the app's secure vault storage model.

Updated UX decision:

- keep `Share` as the primary top-right action in `MomentDetailView`
- use the standard system share sheet for outward sharing behavior
- keep Photo Library copy as a separate bottom-row utility action
- rename that bottom action to `Export to Photo Library`

Why this was changed:

- `Save to Photos` could be misread as "save into niftyMomnt's protected vault"
- the app's long-term roadmap treats `Share` as a core user-facing feature
- separating `Share` from `Export to Photo Library` matches common iOS app patterns more closely

Current split:

- `Share` = outward sharing through the standard share sheet
- `Export to Photo Library` = copy asset into Apple Photos for compatibility testing or personal library use

### Suggested Test Pass

Recommended manual validation:

1. export a still asset from `MomentDetailView` and confirm it appears normally in Apple Photos
2. export a Live asset from `MomentDetailView` and confirm it appears as a Live Photo in Apple Photos
3. open the exported Live Photo in Apple Photos and test playback/press interaction
4. verify that repeated exports do not fail after the initial permission prompt

## Issue 4: CaptureHub Freeze While App Becomes Inactive

### Reported Symptom

The app appeared to freeze when it became inactive after switching to another app on iPhone.

Observed debugger/runtime signals:

```text
Thread 34: EXC_BREAKPOINT
Queue: _dispatch_assert_queue_fail
<<<< FigXPCUtilities >>>> signalled err=-17281
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 "
LocationProvider — didFailWithError: Error Domain=kCLErrorDomain Code=1
```

### Root Cause

`CaptureHubView` started the camera preview on appear, but only stopped it on disappear.

That meant:

- the capture UI could remain mounted while the app moved to `.inactive` or `.background`
- `AVCaptureSession` could still be running during app deactivation
- location updates could still be active during the same transition
- iOS then interrupted camera ownership from the outside, producing `Fig*` logs and unstable teardown behavior

This created a risky lifecycle gap between:

- view lifecycle
- app scene lifecycle
- camera session lifecycle

### Stabilization Change

The preview lifecycle was updated to follow app `scenePhase`, not just view appearance.

Changes made:

- added `scenePhase` handling in `CaptureHubView`
- stop preview when scene moves to `.inactive` or `.background`
- restart preview when scene returns to `.active`
- added `isPreviewRunning` guard state to avoid duplicate start/stop calls
- updated `onDisappear` to use the same preview-stop helper
- updated `AVCaptureAdapter.stopSession()` to stop `LocationProvider` updates before session teardown

### Why This Helps

- camera preview is now explicitly stopped before iOS forcibly interrupts capture access
- location updates no longer remain active during inactive/background transitions
- camera session lifecycle is aligned more closely with app lifecycle
- reduces the chance of queue assertions and background freeze behavior during app switching

### Current Status

Status after change:

- preview is lifecycle-managed on app active/inactive transitions
- location updates stop with the capture session
- ready for device verification with app switching and foreground resume testing

### Suggested Test Pass

Recommended manual validation:

1. open `CaptureHubView`
2. switch to another app or send the app to the Home screen
3. return to niftyMomnt
4. confirm the app is responsive
5. confirm camera preview restarts correctly
6. confirm no black preview and no capture freeze after returning

### Follow-up Stabilization

After the initial lifecycle fix, another crash/regression path was observed around session reconfiguration and preview restart.

Observed behavior:

- breakpoint/crash around `AVCaptureAdapter.configureSession`
- restart attempts could fail with `startPreview failed: sessionFailed`
- preview could remain unavailable after export/background-style transitions

Refined root cause:

- iterating `session.inputs` / `session.outputs` during session rebuild was unsafe after interruption/stop
- some AVFoundation-backed session objects could be invalidated during teardown
- a first fix replaced direct iteration with retained references, but preview restart then failed because retained objects were cleared without always being removed from the underlying `AVCaptureSession`

Additional changes made:

- added retained `videoDeviceInput` tracking in `AVCaptureAdapter`
- updated `configureSession()` to remove retained input/output references directly instead of iterating session collections
- updated `switchCamera()` to swap camera input using the retained `videoDeviceInput`
- updated `stopSession()` to remove retained inputs/outputs from the session before nil-ing references

Why this matters:

- avoids AVFoundation crashes tied to invalidated session collections
- preserves safe teardown behavior after export/interruption/app inactive transitions
- allows preview to restart cleanly after the session has been stopped

Current status after follow-up:

- export flow no longer reproduces the earlier restart failure in the latest user test
- preview resumes again after the prior regression fix
- next validation target is repeated app inactive/background transitions
