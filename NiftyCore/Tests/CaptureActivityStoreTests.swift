// NiftyCore/Tests/CaptureActivityStoreTests.swift
// U8 — CaptureActivityStore begin/end balance + state machine.
// DEBUG assertions are disabled in tests to verify no-op recovery behavior.

import XCTest
@testable import NiftyCore

@MainActor
@available(iOS 17.0, macOS 14.0, *)
final class CaptureActivityStoreTests: XCTestCase {

    func test_initialState_isNotCapturing() {
        let s = CaptureActivityStore()
        XCTAssertFalse(s.isCapturing)
        XCTAssertNil(s.reason)
    }

    func test_begin_sets_isCapturing_andReason() {
        let s = CaptureActivityStore()
        s.beginCapture(reason: .sequence)
        XCTAssertTrue(s.isCapturing)
        XCTAssertEqual(s.reason, .sequence)
    }

    func test_end_clearsState() {
        let s = CaptureActivityStore()
        s.beginCapture(reason: .clip)
        s.endCapture()
        XCTAssertFalse(s.isCapturing)
        XCTAssertNil(s.reason)
    }

    func test_beginThenEnd_multipleReasons_cyclesCleanly() {
        let s = CaptureActivityStore()
        for reason in [CaptureActivityReason.sequence, .clip, .dual] {
            s.beginCapture(reason: reason)
            XCTAssertTrue(s.isCapturing)
            XCTAssertEqual(s.reason, reason)
            s.endCapture()
            XCTAssertFalse(s.isCapturing)
        }
    }
}
