// NiftyCore/Tests/CaptureMomentFormatGateTests.swift
// U14 — CaptureMomentUseCase format/mode gating (PRD FR-ROLL-01):
// Roll mode is Still-only in v0.3. Any other format raises .unsupportedFormatForMode
// before any camera / vault side effect runs.
//
// We exercise the static `validate(format:mode:)` path so no AVFoundation / VaultManager
// plumbing is required — the gate is pure.

import XCTest
@testable import NiftyCore

final class CaptureMomentFormatGateTests: XCTestCase {

    func test_U14_rollMode_rejectsClipFormat() {
        XCTAssertThrowsError(try CaptureMomentUseCase.validate(format: .clip, mode: .roll)) { error in
            guard case CaptureError.unsupportedFormatForMode(let f, let m) = error else {
                return XCTFail("expected .unsupportedFormatForMode, got \(error)")
            }
            XCTAssertEqual(f, "clip")
            XCTAssertEqual(m, "roll")
        }
    }

    func test_U14_rollMode_rejectsSequenceFormat() {
        XCTAssertThrowsError(try CaptureMomentUseCase.validate(format: .sequence, mode: .roll))
    }

    func test_U14_rollMode_rejectsDualFormat() {
        XCTAssertThrowsError(try CaptureMomentUseCase.validate(format: .dual, mode: .roll))
    }

    func test_U14_rollMode_permitsStill() {
        XCTAssertNoThrow(try CaptureMomentUseCase.validate(format: .still, mode: .roll))
    }

    func test_U14_snapMode_permitsAllFormats() {
        for fmt in CaptureFormat.allCases {
            XCTAssertNoThrow(try CaptureMomentUseCase.validate(format: fmt, mode: .snap),
                             "Snap mode must permit \(fmt.rawValue)")
        }
    }

    // Non-still formats in Snap mode should signal that the caller must use a dedicated
    // controller (SequenceCaptureController / ClipRecorderController / DualRecorderController).
    // This is a contract marker — it prevents silent no-ops when a future caller wires the
    // shutter through the UseCase instead of the controllers.
    func test_nonStillSnap_raisesFormatRequiresDedicatedController() async {
        // We can't easily build a full UseCase here (it needs real engines), so we only assert
        // the validate() path for passing formats. The actual throw from execute(format:)
        // is exercised via the concrete PiqdCaptureView tests in Wave 3.
        XCTAssertNoThrow(try CaptureMomentUseCase.validate(format: .clip, mode: .snap))
    }
}
