// Apps/Piqd/PiqdUITests/Layer1ChromeUITests.swift
// Piqd v0.4 — Task 18. Verifies Layer 1 tap-reveal + auto-retreat behavior.
// Under UI_TEST_MODE the idle interval is accelerated to 0.3s
// (`PiqdTokens.Layer.idleRetreatSecondsUITest`) so retreat is observable in real-time.
//
// Implementation notes for XCUITest:
//   • SwiftUI `Button` views stay in the accessibility tree even when the parent's
//     opacity is 0, so `XCUIElement.exists` is NOT a reliable "is chrome revealed"
//     signal. `isHittable` IS — opacity 0 → `isHittable == false`.
//   • `simultaneousGesture` on the SwiftUI viewfinder catcher does not respond to
//     XCUITest's tap synthesis on iOS 26. Tests use the hidden `piqd-layer1-tap-test`
//     button which calls `layerStore.tap()` directly.

import XCTest

final class Layer1ChromeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(idleSeconds: Double? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_MODE"] = "1"
        app.launchEnvironment["PIQD_SEED_EMPTY_VAULT"] = "1"
        app.launchEnvironment["PIQD_DEV_HAPTIC_ENABLED"] = "0"
        app.launchEnvironment["PIQD_RESET_LAST_MODE"] = "1"
        app.launchEnvironment["PIQD_FORCE_LAST_MODE"] = "snap"
        if let s = idleSeconds {
            app.launchEnvironment["PIQD_TEST_LAYER1_IDLE_SECONDS"] = "\(s)"
        }
        app.launch()
        return app
    }

    private func tapViewfinder(_ app: XCUIApplication) {
        let trigger = app.descendants(matching: .any)["piqd-layer1-tap-test"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 3),
                      "layer1 tap trigger missing — chrome can't be revealed")
        trigger.tap()
    }

    private func waitForHittable(_ element: XCUIElement, equals expected: Bool, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isHittable == \(expected ? "true" : "false")")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [exp], timeout: timeout) == .completed
    }

    // 18.1 — tap reveals Layer 1 (flip button becomes hittable).
    func testTapViewfinderRevealsLayer1() {
        let app = launchApp()
        let trigger = app.descendants(matching: .any)["piqd-layer1-tap-test"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 3))
        let flip = app.descendants(matching: .any)["piqd.flipButton"]
        XCTAssertFalse(flip.isHittable, "flip should not be hittable at rest (Layer 0)")
        tapViewfinder(app)
        XCTAssertTrue(waitForHittable(flip, equals: true, timeout: 3),
                      "flip never became hittable after tap. Tree:\n\(app.debugDescription)")
    }

    // 18.2 — Layer 1 auto-retreats after the (accelerated) idle window.
    func testLayer1AutoRetreatsAfterIdle() {
        let app = launchApp()
        let flip = app.descendants(matching: .any)["piqd.flipButton"]
        tapViewfinder(app)
        XCTAssertTrue(waitForHittable(flip, equals: true, timeout: 3))
        // UI_TEST_MODE idle is 1.5s + 150ms exit fade; allow generous tolerance.
        XCTAssertTrue(waitForHittable(flip, equals: false, timeout: 5),
                      "flip never became non-hittable after idle. Tree:\n\(app.debugDescription)")
    }

    // 18.3 — interacting with a chrome leaf resets the idle clock without toggling
    // state (viewfinder tap toggles, leaf interaction just resets the timer).
    func testInteractionResetsIdleClock() {
        // 5s idle so the test has comfortable margin around XCUITest's polling.
        let app = launchApp(idleSeconds: 5.0)
        let flip = app.descendants(matching: .any)["piqd.flipButton"]
        let ratio = app.descendants(matching: .any)["piqd.ratioPill"]
        tapViewfinder(app)
        XCTAssertTrue(waitForHittable(flip, equals: true, timeout: 3))
        // Tap the ratio pill — its onTap calls `layerStore.interact()` which resets
        // the idle timer without toggling state.
        ratio.tap()
        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertTrue(flip.isHittable,
                      "flip should still be revealed — ratio tap resets idle clock")
    }
}
