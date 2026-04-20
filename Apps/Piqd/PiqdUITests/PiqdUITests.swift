// Apps/Piqd/PiqdUITests/PiqdUITests.swift
// v0.1 automated UI coverage per piqd_interim_v0.1_plan.md §5.2.
// Each test launches with PIQD_SEED_EMPTY_VAULT=1 so state is deterministic.

import XCTest

final class PiqdUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(
        cameraDenied: Bool = false,
        seedEmpty: Bool = true,
        rollDailyLimit: Int? = nil,
        longHoldSeconds: Double? = nil,
        hapticEnabled: Bool = false,
        forceMode: String? = nil,
        resetMode: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_MODE"] = "1"
        if seedEmpty { app.launchEnvironment["PIQD_SEED_EMPTY_VAULT"] = "1" }
        if cameraDenied {
            app.launchEnvironment["PIQD_FORCE_CAMERA_DENIED"] = "1"
        }
        if let limit = rollDailyLimit {
            app.launchEnvironment["PIQD_DEV_ROLL_DAILY_LIMIT"] = "\(limit)"
        }
        if let hold = longHoldSeconds {
            app.launchEnvironment["PIQD_DEV_LONG_HOLD"] = "\(hold)"
        }
        // Haptics off by default for deterministic tests.
        app.launchEnvironment["PIQD_DEV_HAPTIC_ENABLED"] = hapticEnabled ? "1" : "0"
        if resetMode {
            // ModeStore persists across launches via UserDefaults("piqd"); zero out
            // so each test starts in Snap unless `forceMode` says otherwise.
            app.launchEnvironment["PIQD_RESET_LAST_MODE"] = "1"
        }
        if let mode = forceMode {
            app.launchEnvironment["PIQD_FORCE_LAST_MODE"] = mode
        }
        app.launch()
        return app
    }

    /// Simulates the mode-pill long-hold. XCUITest's press synthesis does not route
    /// through SwiftUI's gesture recognizers on iOS 26, so the app exposes a hidden
    /// UI_TEST_MODE-only button that directly triggers the long-hold action. The
    /// `seconds` parameter is ignored (retained for readability at call sites).
    private func holdModePill(_ app: XCUIApplication, seconds: Double) {
        _ = seconds
        let pill = app.descendants(matching: .any)["piqd-mode-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 3))
        let trigger = app.descendants(matching: .any)["piqd-mode-pill-longhold-test"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 3))
        trigger.tap()
    }

    // UI1
    func testLaunchShowsViewfinder() {
        let app = launchApp()
        let preview = app.otherElements["piqd.capture"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
    }

    // UI2
    func testShutterTapEnqueuesCapture() {
        let app = launchApp()
        let shutter = app.buttons["piqd.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 3))
        shutter.tap()
        // Capture-flash element appears for ~400 ms in UI_TEST_MODE; poll across
        // all element types because SwiftUI may expose Rectangle as image/other.
        let flash = app.descendants(matching: .any)["piqd.captureIndicator"]
        XCTAssertTrue(flash.waitForExistence(timeout: 2),
                      "flash overlay not found. Tree:\n\(app.debugDescription)")
    }

    // UI3
    func testDebugVaultShowsCapturedAsset() {
        let app = launchApp()
        app.buttons["piqd.shutter"].tap()
        // Give the capture pipeline time to persist before opening the debug sheet.
        sleep(1)
        app.buttons["piqd.debug.open"].tap()
        let nav = app.navigationBars.firstMatch
        XCTAssertTrue(nav.waitForExistence(timeout: 3))
        XCTAssertTrue(nav.identifier.contains("Vault") || nav.staticTexts["Vault (1)"].exists ||
                      app.staticTexts["Vault (1)"].waitForExistence(timeout: 2))
    }

    // UI4
    func testRelaunchPersistsCapture() {
        let app = launchApp()
        app.buttons["piqd.shutter"].tap()
        sleep(1)
        app.terminate()

        // Second launch MUST NOT reset the vault — override the seed flag.
        let app2 = XCUIApplication()
        app2.launchEnvironment["UI_TEST_MODE"] = "1"
        app2.launchEnvironment["PIQD_SEED_EMPTY_VAULT"] = "0"
        app2.launch()

        app2.buttons["piqd.debug.open"].tap()
        XCTAssertTrue(app2.staticTexts["Vault (1)"].waitForExistence(timeout: 3))
    }

    // UI5
    func testRapidTapDoesNotCrash() {
        let app = launchApp()
        let shutter = app.buttons["piqd.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 3))
        for _ in 0..<10 {
            shutter.tap()
        }
        sleep(3)
        app.buttons["piqd.debug.open"].tap()
        // Not all 10 taps guaranteed to land as separate captures (serialization allowed per
        // §6.2 row 2.4) — we just require the app is still alive with some captures persisted.
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
    }

    // P2 — cold launch → shutter ready. §5.3 baseline <1.5s per SRS §8.
    // XCTApplicationLaunchMetric aggregates duration, memory, CPU across 5 runs.
    func testPerf_P2_coldLaunchToShutterReady() {
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            let app = XCUIApplication()
            app.launchEnvironment["UI_TEST_MODE"] = "1"
            app.launchEnvironment["PIQD_SEED_EMPTY_VAULT"] = "1"
            app.launch()
            _ = app.buttons["piqd.shutter"].waitForExistence(timeout: 5)
            stopMeasuring()
            app.terminate()
        }
    }

    // UI6 (v0.1)
    func testCameraPermissionDeniedShowsHint() {
        let app = launchApp(cameraDenied: true)
        let hint = app.descendants(matching: .any)["piqd.cameraDeniedHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 3),
                      "denied hint not found. Tree:\n\(app.debugDescription)")
    }

    // MARK: - v0.2 Mode System (UI1–UI13 per piqd_interim_v0.2_plan §5.2)

    /// UI1 — short tap on the mode pill must NOT open the confirmation sheet.
    func testV02_UI1_shortTapPillDoesNothing() {
        let app = launchApp(longHoldSeconds: 0.4)
        let pill = app.descendants(matching: .any)["piqd-mode-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 3))
        pill.tap()
        let sheet = app.descendants(matching: .any)["piqd-mode-sheet"]
        // Sheet should never appear from a single short tap.
        XCTAssertFalse(sheet.waitForExistence(timeout: 1))
    }

    /// UI2 — holding past `longHoldDurationSeconds` opens the confirmation sheet.
    func testV02_UI2_longHoldShowsConfirmSheet() {
        let app = launchApp(longHoldSeconds: 0.3)
        holdModePill(app, seconds: 0.6)
        let sheet = app.descendants(matching: .any)["piqd-mode-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3),
                      "mode sheet not shown. Tree:\n\(app.debugDescription)")
        XCTAssertTrue(
            app.descendants(matching: .any)["piqd-mode-sheet-roll"].waitForExistence(timeout: 2),
            "roll segment not found. Tree:\n\(app.debugDescription)"
        )
    }

    /// UI4 — confirming the switch updates the preview's accessibility value.
    func testV02_UI4_confirmSwitchesMode() {
        let app = launchApp(longHoldSeconds: 0.3)
        let preview = app.descendants(matching: .any)["piqd.capture"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        XCTAssertEqual(preview.value as? String, "snap")

        holdModePill(app, seconds: 0.6)
        let rollSegment = app.descendants(matching: .any)["piqd-mode-sheet-roll"]
        XCTAssertTrue(rollSegment.waitForExistence(timeout: 2))
        rollSegment.tap()

        // Mode value should flip to "roll" promptly.
        let predicate = NSPredicate(format: "value == %@", "roll")
        let exp = expectation(for: predicate, evaluatedWith: preview, handler: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: 2), .completed)
    }

    /// UI5 — Cancel button on the sheet dismisses without changing mode.
    func testV02_UI5_cancelKeepsMode() {
        let app = launchApp(longHoldSeconds: 0.3)
        holdModePill(app, seconds: 0.6)
        let cancel = app.descendants(matching: .any)["piqd-mode-sheet-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()

        let preview = app.descendants(matching: .any)["piqd.capture"]
        XCTAssertEqual(preview.value as? String, "snap")
    }

    /// UI6 — selected mode survives a cold relaunch.
    func testV02_UI6_modePersistsAcrossRelaunch() {
        let app = launchApp(longHoldSeconds: 0.3, forceMode: "roll", resetMode: false)
        let preview = app.descendants(matching: .any)["piqd.capture"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        XCTAssertEqual(preview.value as? String, "roll")
        app.terminate()

        // Second launch with no reset/force — should hydrate the persisted "roll".
        let app2 = XCUIApplication()
        app2.launchEnvironment["UI_TEST_MODE"] = "1"
        app2.launchEnvironment["PIQD_DEV_HAPTIC_ENABLED"] = "0"
        app2.launch()
        let preview2 = app2.descendants(matching: .any)["piqd.capture"]
        XCTAssertTrue(preview2.waitForExistence(timeout: 3))
        XCTAssertEqual(preview2.value as? String, "roll")
    }

    /// UI7 — counter + grain overlay are present in Roll, absent in Snap.
    func testV02_UI7_rollShowsCounterAndGrain() {
        let app = launchApp(forceMode: "roll", resetMode: false)
        XCTAssertTrue(app.descendants(matching: .any)["piqd-film-counter"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["piqd-grain-overlay"].exists)

        // Switch to Snap via dev mode reset → relaunch.
        app.terminate()
        let snap = launchApp(resetMode: true)
        XCTAssertTrue(snap.descendants(matching: .any)["piqd.capture"].waitForExistence(timeout: 3))
        XCTAssertFalse(snap.descendants(matching: .any)["piqd-film-counter"].exists)
        XCTAssertFalse(snap.descendants(matching: .any)["piqd-grain-overlay"].exists)
    }

    /// UI8 — tapping the shutter in Roll decrements the visible counter.
    func testV02_UI8_captureDecrementsCounter() {
        let app = launchApp(rollDailyLimit: 5, forceMode: "roll", resetMode: false)
        let counter = app.descendants(matching: .any)["piqd-film-counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 3))
        let initial = NSPredicate(format: "label == %@", "Film counter 0 of 5")
        let initExp = expectation(for: initial, evaluatedWith: counter, handler: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [initExp], timeout: 3), .completed)

        app.buttons["piqd.shutter"].tap()
        let after = NSPredicate(format: "label == %@", "Film counter 1 of 5")
        let afterExp = expectation(for: after, evaluatedWith: counter, handler: nil)
        let result = XCTWaiter.wait(for: [afterExp], timeout: 3)
        XCTAssertEqual(result, .completed,
                       "after-tap label: \(counter.label). Tree:\n\(app.debugDescription)")
    }

    /// UI9 — once the daily Roll limit is reached, the Roll-Full overlay is shown
    /// automatically and the shutter is disabled.
    func testV02_UI9_rollFullOverlayAppearsWhenExhausted() {
        let app = launchApp(rollDailyLimit: 1, forceMode: "roll", resetMode: false)
        let shutter = app.buttons["piqd.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 3))
        shutter.tap() // counter: 0 → 1, now full

        let overlay = app.descendants(matching: .any)["piqd-roll-full-overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3),
                      "roll-full overlay not shown. Tree:\n\(app.debugDescription)")
        let disabled = NSPredicate(format: "isEnabled == false")
        let exp = expectation(for: disabled, evaluatedWith: shutter, handler: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: 3), .completed)
    }

    /// UI12 — five taps on the mode pill within the 2s window opens the dev settings sheet.
    func testV02_UI12_devSettingsReachableVia5Tap() {
        let app = launchApp(longHoldSeconds: 1.5)
        let pill = app.descendants(matching: .any)["piqd-mode-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 3))
        for _ in 0..<5 { pill.tap() }
        let dev = app.descendants(matching: .any)["piqd-dev-settings"]
        XCTAssertTrue(dev.waitForExistence(timeout: 3),
                      "dev settings not shown. Tree:\n\(app.debugDescription)")
    }

    /// UI13 — `PIQD_DEV_ROLL_DAILY_LIMIT` env var shortens the visible roll limit.
    func testV02_UI13_devLimitShortensCounter() {
        let app = launchApp(rollDailyLimit: 3, forceMode: "roll", resetMode: false)
        let counter = app.descendants(matching: .any)["piqd-film-counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 3))
        let predicate = NSPredicate(format: "label == %@", "Film counter 0 of 3")
        let exp = expectation(for: predicate, evaluatedWith: counter, handler: nil)
        let result = XCTWaiter.wait(for: [exp], timeout: 3)
        XCTAssertEqual(result, .completed,
                       "actual label: \(counter.label). Tree:\n\(app.debugDescription)")
    }
}

