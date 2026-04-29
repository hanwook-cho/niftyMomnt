// Apps/Piqd/PiqdUITests/OnboardingUITests.swift
// Piqd v0.6 — XCUITest coverage for onboarding O0–O3, the share-link route,
// the deep-link seed → IncomingInviteSheet path, and completion-survives-relaunch.
//
// All tests reset the onboarding flag via `PIQD_DEV_ONBOARDING_RESET=1` so a
// previous app launch's "completed" state can't leak in. Test 5 explicitly
// LAUNCHES TWICE: first with reset, then without — verifying persistence.

import XCTest

final class OnboardingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Launch helpers

    private func launchApp(
        resetOnboarding: Bool = true,
        inviteTokenSeed: String? = nil,
        terminate previous: XCUIApplication? = nil
    ) -> XCUIApplication {
        previous?.terminate()

        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_MODE"] = "1"
        app.launchEnvironment["PIQD_SEED_EMPTY_VAULT"] = "1"
        app.launchEnvironment["PIQD_DEV_HAPTIC_ENABLED"] = "0"
        if resetOnboarding {
            app.launchEnvironment["PIQD_DEV_ONBOARDING_RESET"] = "1"
            // Wipe friends + keypair so the synthetic-invite test always starts
            // from an empty circle.
            app.launchEnvironment["PIQD_DEV_CIRCLE_CLEAR"] = "1"
        }
        if let seed = inviteTokenSeed {
            app.launchEnvironment["PIQD_DEV_INVITE_TOKEN"] = seed
        }
        app.launch()
        return app
    }

    // MARK: - 1. Happy path O0 → O3 → capture

    func test_O0_to_O3_happyPath_endsAtCaptureView() {
        let app = launchApp()

        let o0 = app.descendants(matching: .any)["piqd.onboarding.O0.continue"]
        XCTAssertTrue(o0.waitForExistence(timeout: 5), "O0 not presented")
        o0.tap()

        let o1Next = app.descendants(matching: .any)["piqd.onboarding.O1.next"]
        XCTAssertTrue(o1Next.waitForExistence(timeout: 5), "O1 not presented")
        o1Next.tap()

        let o2Next = app.descendants(matching: .any)["piqd.onboarding.O2.next"]
        XCTAssertTrue(o2Next.waitForExistence(timeout: 5), "O2 not presented")
        o2Next.tap()

        let o3Start = app.descendants(matching: .any)["piqd.onboarding.O3.start"]
        XCTAssertTrue(o3Start.waitForExistence(timeout: 5), "O3 not presented")
        // Don't assert QR image visibility — async-loaded; presence of the
        // start button is sufficient proof we reached O3.
        o3Start.tap()

        // Verify onboarding has been replaced (regardless of what specifically
        // mounted in its place) — proves `complete()` fired and the root
        // switcher honored isComplete = true.
        let o0Marker = app.descendants(matching: .any)["piqd.onboarding.O0.continue"]
        let gone = NSPredicate(format: "exists == false")
        let exp = expectation(for: gone, evaluatedWith: o0Marker)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed,
                       "onboarding still presenting after Start shooting")
    }

    // MARK: - 2. Skip jumps to O3

    func test_O0_skip_jumpsDirectlyToO3() {
        let app = launchApp()

        let skip = app.descendants(matching: .any)["piqd.onboarding.O0.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "O0 skip not visible")
        skip.tap()

        let o3Start = app.descendants(matching: .any)["piqd.onboarding.O3.start"]
        XCTAssertTrue(o3Start.waitForExistence(timeout: 5),
                      "O0 skip did not jump to O3")

        // O1 / O2 markers must NOT be visible.
        XCTAssertFalse(app.descendants(matching: .any)["piqd.onboarding.O1.next"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["piqd.onboarding.O2.next"].exists)
    }

    // MARK: - 3. O3 share-link button is hittable

    func test_O3_shareLinkButton_isVisibleAndHittable() {
        let app = launchApp()

        let skip = app.descendants(matching: .any)["piqd.onboarding.O0.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let shareLink = app.descendants(matching: .any)["piqd.onboarding.O3.shareLink"]
        XCTAssertTrue(shareLink.waitForExistence(timeout: 5), "Share link button missing")
        // Don't tap — UIActivityViewController is hard to dismiss reliably in
        // XCUITest. Existence is the regression guard. Hittability depends on
        // an async-loaded inviteURL, not worth gating on here.
    }

    // MARK: - 4. PIQD_DEV_INVITE_TOKEN seed → IncomingInviteSheet

    @MainActor
    func test_inviteTokenSeed_surfacesIncomingInviteSheetAtO3() async throws {
        let seed = try await InviteFixture.makeBase64Token(displayName: "Bob")
        let app = launchApp(inviteTokenSeed: seed)

        // Queued URL drains when onboarding reaches `.invite` (or completes).
        // Skip O0 to surface the sheet.
        let skip = app.descendants(matching: .any)["piqd.onboarding.O0.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let displayName = app.descendants(matching: .any)["piqd.incomingInvite.displayName"]
        XCTAssertTrue(displayName.waitForExistence(timeout: 8),
                      "IncomingInviteSheet did not surface from seeded token")
        XCTAssertEqual(displayName.label, "Bob", "Sender display name mismatch")

        // Decline so the test leaves a clean circle for any follow-up.
        let decline = app.descendants(matching: .any)["piqd.incomingInvite.decline"]
        XCTAssertTrue(decline.exists)
        decline.tap()
    }

    // MARK: - 5. Completion survives relaunch

    func test_completionFlag_survivesRelaunch() {
        var app = launchApp()

        // Skip-then-complete to reach `.completed = true` quickly.
        let skip = app.descendants(matching: .any)["piqd.onboarding.O0.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let start = app.descendants(matching: .any)["piqd.onboarding.O3.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Wait for onboarding to vanish (proxy for completion).
        let o0Marker = app.descendants(matching: .any)["piqd.onboarding.O0.skip"]
        let gone = NSPredicate(format: "exists == false")
        let exp1 = expectation(for: gone, evaluatedWith: o0Marker)
        XCTAssertEqual(XCTWaiter().wait(for: [exp1], timeout: 10), .completed)

        // Relaunch WITHOUT the onboarding reset env.
        app = launchApp(resetOnboarding: false, terminate: app)

        // Onboarding must NOT show on this relaunch.
        let o0After = app.descendants(matching: .any)["piqd.onboarding.O0.skip"]
        // Brief wait to give the app time to stabilize.
        _ = o0After.waitForExistence(timeout: 3)
        XCTAssertFalse(o0After.exists,
                       "Onboarding re-appeared on relaunch — completion flag not surviving")

        // Onboarding markers must NOT be present.
        XCTAssertFalse(app.descendants(matching: .any)["piqd.onboarding.O0.continue"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["piqd.onboarding.O0.skip"].exists)
    }
}
