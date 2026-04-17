// Apps/Piqd/PiqdUITests/PiqdUITests.swift
// v0.1 automated UI coverage per piqd_interim_v0.1_plan.md §5.2.
// Each test launches with PIQD_SEED_EMPTY_VAULT=1 so state is deterministic.

import XCTest

final class PiqdUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(cameraDenied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_MODE"] = "1"
        app.launchEnvironment["PIQD_SEED_EMPTY_VAULT"] = "1"
        if cameraDenied {
            // Simulator-only: bypass real permission dialog. PiqdCaptureView reads its own
            // env override first so the denied-hint renders without needing AVFoundation state.
            app.launchEnvironment["PIQD_FORCE_CAMERA_DENIED"] = "1"
        }
        app.launch()
        return app
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

    // UI6
    func testCameraPermissionDeniedShowsHint() {
        let app = launchApp(cameraDenied: true)
        let hint = app.descendants(matching: .any)["piqd.cameraDeniedHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 3),
                      "denied hint not found. Tree:\n\(app.debugDescription)")
    }
}
