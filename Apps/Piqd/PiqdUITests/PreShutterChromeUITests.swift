// Apps/Piqd/PiqdUITests/PreShutterChromeUITests.swift
// Piqd v0.4 — Task 19. Verifies presence + interaction of Layer 1 chrome subsystems:
// zoom pill, aspect-ratio toggle, flip button. Some checks are existence-only on the
// simulator (no real camera): the goal is presence + accessibility wiring, not pixel
// correctness — the device checklist (§6 of the v0.4 plan) covers visual verification.
//
// Note on `isHittable` vs `exists`: SwiftUI Button views stay in the accessibility
// tree even when their parent's opacity is 0, so revealed-state checks use
// `isHittable`. See Layer1ChromeUITests for the same convention.

import XCTest

final class PreShutterChromeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(forceMode: String = "snap") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_MODE"] = "1"
        app.launchEnvironment["PIQD_SEED_EMPTY_VAULT"] = "1"
        app.launchEnvironment["PIQD_DEV_HAPTIC_ENABLED"] = "0"
        app.launchEnvironment["PIQD_RESET_LAST_MODE"] = "1"
        app.launchEnvironment["PIQD_FORCE_LAST_MODE"] = forceMode
        // These tests check post-reveal chrome state; auto-retreat firing mid-test is
        // noise. Set the idle window to 30s so the chrome stays revealed for the
        // duration of any reasonable assertion sequence.
        app.launchEnvironment["PIQD_TEST_LAYER1_IDLE_SECONDS"] = "30"
        app.launch()
        return app
    }

    private func waitForHittable(_ element: XCUIElement, equals expected: Bool, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isHittable == \(expected ? "true" : "false")")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [exp], timeout: timeout) == .completed
    }

    private func revealLayer1(_ app: XCUIApplication) {
        let trigger = app.descendants(matching: .any)["piqd-layer1-tap-test"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 3))
        trigger.tap()
        // Wait for the wide segment (the floor — present on every iPhone) to become
        // hittable, signaling the chrome reveal animation has finished.
        let wide = app.descendants(matching: .any)["piqd.zoomPill.wide"]
        XCTAssertTrue(waitForHittable(wide, equals: true, timeout: 3),
                      "zoom pill segment never became hittable. Tree:\n\(app.debugDescription)")
    }

    // 19.1 — zoom pill `wide` segment is reachable and tappable post-reveal.
    func testZoomPillExistsAndIsTappable() {
        let app = launchApp()
        revealLayer1(app)
        let wide = app.descendants(matching: .any)["piqd.zoomPill.wide"]
        XCTAssertTrue(wide.isHittable)
        wide.tap()
        XCTAssertTrue(wide.exists)
    }

    // 19.2 — ratio pill is interactive in Still and reflects the toggled value.
    func testRatioPillTogglesInStill() {
        let app = launchApp()
        revealLayer1(app)
        let ratio = app.descendants(matching: .any)["piqd.ratioPill"]
        XCTAssertTrue(waitForHittable(ratio, equals: true, timeout: 2))
        let initialValue = ratio.value as? String ?? ""
        ratio.tap()
        Thread.sleep(forTimeInterval: 0.1)
        let toggledValue = ratio.value as? String ?? ""
        XCTAssertNotEqual(initialValue, toggledValue,
                          "ratio pill value should change after tap (was '\(initialValue)')")
    }

    // 19.3 — flip button is tappable post-reveal in Snap.
    func testFlipButtonPresentInSnap() {
        let app = launchApp()
        revealLayer1(app)
        let flip = app.descendants(matching: .any)["piqd.flipButton"]
        XCTAssertTrue(waitForHittable(flip, equals: true, timeout: 2))
    }

    // 19.4 — Snap-only zoom pill: in Roll mode the pill is gone.
    func testZoomPillHiddenInRoll() {
        let app = launchApp(forceMode: "roll")
        // In Roll the trigger early-returns (mode != .snap), so the chrome can never
        // appear. Tap once anyway to confirm zoom pill stays unhittable.
        let trigger = app.descendants(matching: .any)["piqd-layer1-tap-test"]
        if trigger.waitForExistence(timeout: 3) { trigger.tap() }
        Thread.sleep(forTimeInterval: 0.5)
        let wide = app.descendants(matching: .any)["piqd.zoomPill.wide"]
        XCTAssertFalse(wide.isHittable, "zoom pill should not be hittable in Roll")
    }
}
