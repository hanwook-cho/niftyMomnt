// NiftyCore/Tests/DraftEnrollmentPolicyTests.swift

import XCTest
@testable import NiftyCore

final class DraftEnrollmentPolicyTests: XCTestCase {

    func test_snap_enrolls() {
        XCTAssertTrue(DraftEnrollmentPolicy.shouldEnroll(mode: .snap))
    }

    func test_roll_doesNotEnroll() {
        XCTAssertFalse(DraftEnrollmentPolicy.shouldEnroll(mode: .roll))
    }

    func test_legacyNiftyMomntModes_doNotEnroll() {
        // niftyMomnt-only modes never produce Piqd drafts — drafts is a Snap concept.
        let nonSnapModes: [CaptureMode] = [.still, .live, .clip, .echo, .atmosphere, .photoBooth]
        for mode in nonSnapModes {
            XCTAssertFalse(
                DraftEnrollmentPolicy.shouldEnroll(mode: mode),
                "Mode .\(mode.rawValue) should not enroll as a draft"
            )
        }
    }
}
