// Tests/CaptureEngineTests.swift

import XCTest
@testable import NiftyCore

final class CaptureEngineTests: XCTestCase {
    func test_availableModes_lite_excludesEchoAndAtmosphere() async throws {
        let engine = await CaptureEngine(
            config: .lite,
            captureAdapter: MockCaptureAdapter(),
            soundStampPipeline: MockSoundStampPipeline()
        )
        let modes = await engine.availableModes()
        XCTAssertFalse(modes.contains(.echo))
        XCTAssertFalse(modes.contains(.atmosphere))
        XCTAssertTrue(modes.contains(.still))
    }

    func test_soundStamp_notActivated_whenFeatureFlagOff() async throws {
        let mockPipeline = MockSoundStampPipeline()
        let engine = await CaptureEngine(
            config: .lite,  // .lite has no .soundStamp flag
            captureAdapter: MockCaptureAdapter(),
            soundStampPipeline: mockPipeline
        )
        try await engine.startSession(mode: .still, config: .lite)
        let activated = await mockPipeline.preRollActivated
        XCTAssertFalse(activated)
    }
}
