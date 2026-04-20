// NiftyCore/Tests/CaptureFormatTests.swift
// U1 — CaptureFormat exhaustiveness + AssetType bridge identity.

import XCTest
@testable import NiftyCore

final class CaptureFormatTests: XCTestCase {

    func test_allCases_coversFourFormats() {
        XCTAssertEqual(Set(CaptureFormat.allCases),
                       [.still, .sequence, .clip, .dual])
    }

    func test_assetType_isOneToOne() {
        XCTAssertEqual(CaptureFormat.still.assetType,    .still)
        XCTAssertEqual(CaptureFormat.sequence.assetType, .sequence)
        XCTAssertEqual(CaptureFormat.clip.assetType,     .clip)
        XCTAssertEqual(CaptureFormat.dual.assetType,     .dual)
    }

    func test_isVideoRecording_matchesSpec() {
        XCTAssertFalse(CaptureFormat.still.isVideoRecording)
        XCTAssertFalse(CaptureFormat.sequence.isVideoRecording)
        XCTAssertTrue(CaptureFormat.clip.isVideoRecording)
        XCTAssertTrue(CaptureFormat.dual.isVideoRecording)
    }

    func test_rawValues_matchDomainStrings() {
        // Backing rawValues are used by ModeStore UserDefaults persistence.
        XCTAssertEqual(CaptureFormat.still.rawValue,    "still")
        XCTAssertEqual(CaptureFormat.sequence.rawValue, "sequence")
        XCTAssertEqual(CaptureFormat.clip.rawValue,     "clip")
        XCTAssertEqual(CaptureFormat.dual.rawValue,     "dual")
    }
}
