// Apps/Piqd/PiqdUITests/Layer1LayoutAuditUITests.swift
// Piqd v0.5 Task 18 — Layer 1 chrome layout audit. Drives the app into the
// "everything visible" state and captures a baseline screenshot for human
// review of overlaps. Future versions can diff against the attachment to
// catch the badge-on-mode-pill class of regression that v0.5 introduced and
// then fixed.
//
// Coverage:
//   • Mode pill (HUD-rendered above Layer1ChromeView)
//   • Zoom pill (Layer 1 — bottom-center)
//   • Aspect ratio pill (Layer 1 — bottom-center, beside zoom)
//   • Flip button (Layer 1 — top-right)
//   • Drafts badge (Layer 1 — bottom-left; urgent tint via fake-now)
//   • Shutter button (Layer 0 — bottom-center)
//
// Deferred to a future seam:
//   • Invisible level (needs MotionMonitor.emit() XCUITest hook)
//   • Vibe glyph .social state (needs StubVibeClassifier.emit() hook)
//   • Subject guidance pill (needs SubjectGuidanceDetector.emit() hook)
// All three are listed in v0.5 plan §7 as "covered by device checklist".

import XCTest

final class Layer1LayoutAuditUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchAppFullReveal() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_MODE"] = "1"
        app.launchEnvironment["PIQD_SEED_EMPTY_VAULT"] = "1"
        app.launchEnvironment["PIQD_DEV_HAPTIC_ENABLED"] = "0"
        app.launchEnvironment["PIQD_RESET_LAST_MODE"] = "1"
        app.launchEnvironment["PIQD_FORCE_LAST_MODE"] = "snap"
        app.launchEnvironment["PIQD_TEST_LAYER1_IDLE_SECONDS"] = "60" // hold reveal for the audit
        // Push drafts into urgent state (23h 45m elapsed → 15m left → red tint).
        app.launchEnvironment["PIQD_DEV_FAKE_NOW_OFFSET"] = "85500"
        app.launch()
        return app
    }

    /// Drives the app into the full Layer 1 reveal and attaches a screenshot.
    /// The test passes as long as every expected element is hittable — overlap
    /// review is a human pass on the captured attachment.
    func test_layer1_fullReveal_audit() {
        let app = launchAppFullReveal()

        // Seed three drafts so the badge reads "3 unsent" (urgent).
        let fakeCapture = app.descendants(matching: .any)["piqd-drafts-fake-capture"]
        XCTAssertTrue(fakeCapture.waitForExistence(timeout: 3),
                      "drafts fake-capture trigger missing")
        for _ in 0..<3 { fakeCapture.tap() }

        // Reveal Layer 1.
        let revealTrigger = app.descendants(matching: .any)["piqd-layer1-tap-test"]
        XCTAssertTrue(revealTrigger.waitForExistence(timeout: 3))
        revealTrigger.tap()

        // Assert each element is hittable (i.e., visible inside Layer 1 chrome).
        let badge = app.descendants(matching: .any)["piqd.draftsBadge"]
        let zoom = app.descendants(matching: .any)["piqd.zoomPill.wide"]
        let ratio = app.descendants(matching: .any)["piqd.ratioPill"]
        let flip = app.descendants(matching: .any)["piqd.flipButton"]

        XCTAssertTrue(badge.waitForExistence(timeout: 3))
        XCTAssertTrue(badge.isHittable, "Drafts badge should be hittable in full reveal")
        XCTAssertEqual(badge.value as? String, "3 unsent")

        XCTAssertTrue(zoom.exists, "Zoom pill (.wide segment) should exist in full reveal")
        XCTAssertTrue(ratio.exists, "Ratio pill should exist in full reveal")
        XCTAssertTrue(flip.exists, "Flip button should exist in full reveal")

        // Capture the audit screenshot as an attachment for human review.
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Layer1-FullReveal-iPhone17Pro"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Frame-overlap sanity check between leaf-keyed elements that share
        // screen real estate. Mode pill is HUD-rendered (no leaf id), so this
        // catches collisions between Layer 1 chrome elements only.
        XCTAssertNoOverlap(badge.frame, zoom.frame, "drafts badge ↔ zoom pill")
        XCTAssertNoOverlap(badge.frame, ratio.frame, "drafts badge ↔ ratio pill")
        XCTAssertNoOverlap(badge.frame, flip.frame, "drafts badge ↔ flip button")
        XCTAssertNoOverlap(zoom.frame, flip.frame, "zoom pill ↔ flip button")
        XCTAssertNoOverlap(ratio.frame, flip.frame, "ratio pill ↔ flip button")
    }

    private func XCTAssertNoOverlap(
        _ a: CGRect,
        _ b: CGRect,
        _ label: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertFalse(a.intersects(b),
                       "Layout overlap detected: \(label) — \(a) ∩ \(b)",
                       file: file, line: line)
    }
}
