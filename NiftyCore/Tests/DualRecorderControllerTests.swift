// NiftyCore/Tests/DualRecorderControllerTests.swift
// U10 (NiftyCore portion) — orchestration test:
//   DualRecorderController press/release → single composite URL returned from injected
//   DualCompositor. Track-count and PIP inset assertions are verified by NiftyDataTests
//   and on-device (AVMutableComposition work lives below NiftyCore).

import XCTest
@testable import NiftyCore

@MainActor
@available(iOS 17.0, macOS 14.0, *)
final class DualRecorderControllerTests: XCTestCase {

    private func drain() async {
        try? await Task.sleep(nanoseconds: 30_000_000)
    }

    func test_U10_pressReleaseProducesSingleCompositeURL() async throws {
        let recorder = FakeDualRecorder(reportedDuration: 1.0)
        let compositor = FakeDualCompositor(composedDuration: 1.0)
        let ceiling = ManualCeilingTimer()
        let controller = DualRecorderController(
            recorder: recorder, compositor: compositor, ceiling: ceiling,
            maxDurationSeconds: 15
        )
        let rear = URL(fileURLWithPath: "/tmp/rear-\(UUID().uuidString).mp4")
        let front = URL(fileURLWithPath: "/tmp/front-\(UUID().uuidString).mp4")
        let comp = URL(fileURLWithPath: "/tmp/composite-\(UUID().uuidString).mp4")

        controller.press(rearURL: rear, frontURL: front, compositeURL: comp)
        await drain()
        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.lastRearURL, rear)
        XCTAssertEqual(recorder.lastFrontURL, front)

        controller.release()
        let outcome = await controller.outcome()
        guard case .completed(let url, let duration, let auto) = outcome else {
            return XCTFail("expected completed, got \(outcome)")
        }
        XCTAssertEqual(url, comp, "outcome must carry the single composite URL")
        XCTAssertFalse(auto)
        XCTAssertEqual(duration, 1.0, accuracy: 0.05)
        XCTAssertEqual(compositor.callCount, 1, "compositor must be invoked exactly once")
        XCTAssertEqual(compositor.lastRear, rear)
        XCTAssertEqual(compositor.lastFront, front)
        XCTAssertTrue(ceiling.wasCancelled)
        XCTAssertEqual(controller.state, .idle)
    }

    func test_U10_ceilingAutoStopAt15s() async throws {
        let recorder = FakeDualRecorder(reportedDuration: 15.0)
        let compositor = FakeDualCompositor(composedDuration: 15.0)
        let ceiling = ManualCeilingTimer()
        let controller = DualRecorderController(
            recorder: recorder, compositor: compositor, ceiling: ceiling,
            maxDurationSeconds: 15
        )
        controller.press(
            rearURL: URL(fileURLWithPath: "/tmp/r.mp4"),
            frontURL: URL(fileURLWithPath: "/tmp/f.mp4"),
            compositeURL: URL(fileURLWithPath: "/tmp/c.mp4")
        )
        await drain()
        XCTAssertEqual(ceiling.lastScheduledSeconds, 15.0)
        ceiling.fire()
        let outcome = await controller.outcome()
        guard case .completed(_, _, let auto) = outcome else {
            return XCTFail("expected completed")
        }
        XCTAssertTrue(auto, "ceiling path must set autoStopped=true")
    }

    func test_compositorFailure_yieldsFailedOutcome() async throws {
        let recorder = FakeDualRecorder(reportedDuration: 2.0)
        let compositor = FakeDualCompositor(throwOnComposite: true)
        let ceiling = ManualCeilingTimer()
        let controller = DualRecorderController(
            recorder: recorder, compositor: compositor, ceiling: ceiling
        )
        controller.press(
            rearURL: URL(fileURLWithPath: "/tmp/r.mp4"),
            frontURL: URL(fileURLWithPath: "/tmp/f.mp4"),
            compositeURL: URL(fileURLWithPath: "/tmp/c.mp4")
        )
        await drain()
        controller.release()
        let outcome = await controller.outcome()
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(controller.state, .idle)
    }
}

// MARK: - Doubles

@available(iOS 17.0, macOS 14.0, *)
private final class FakeDualRecorder: DualMovieRecorder, @unchecked Sendable {
    enum StubError: Error { case forced }
    private let reportedDuration: Double
    private(set) var startCount: Int = 0
    private(set) var lastRearURL: URL?
    private(set) var lastFrontURL: URL?
    init(reportedDuration: Double = 0) { self.reportedDuration = reportedDuration }
    func startRecording(rearURL: URL, frontURL: URL) async throws {
        startCount += 1
        lastRearURL = rearURL
        lastFrontURL = frontURL
    }
    func stopRecording() async throws -> (rearURL: URL, frontURL: URL, duration: Double) {
        (lastRearURL ?? URL(fileURLWithPath: "/tmp/unset-r"),
         lastFrontURL ?? URL(fileURLWithPath: "/tmp/unset-f"),
         reportedDuration)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private final class FakeDualCompositor: DualCompositor, @unchecked Sendable {
    enum StubError: Error { case forced }
    private let composedDuration: Double
    private let throwOnComposite: Bool
    private(set) var callCount: Int = 0
    private(set) var lastRear: URL?
    private(set) var lastFront: URL?
    init(composedDuration: Double = 1.0, throwOnComposite: Bool = false) {
        self.composedDuration = composedDuration
        self.throwOnComposite = throwOnComposite
    }
    func composite(rearURL: URL, frontURL: URL, outputURL: URL) async throws -> (url: URL, durationSeconds: Double) {
        callCount += 1
        lastRear = rearURL
        lastFront = frontURL
        if throwOnComposite { throw StubError.forced }
        return (outputURL, composedDuration)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private final class ManualCeilingTimer: ClipCeilingTimer, @unchecked Sendable {
    private var onFire: (@MainActor @Sendable () -> Void)?
    private(set) var lastScheduledSeconds: Double?
    private(set) var wasCancelled: Bool = false
    func schedule(seconds: Double, onFire: @escaping @MainActor @Sendable () -> Void) {
        self.lastScheduledSeconds = seconds
        self.onFire = onFire
        self.wasCancelled = false
    }
    func cancel() {
        onFire = nil
        wasCancelled = true
    }
    @MainActor
    func fire() {
        guard let cb = onFire else { return }
        onFire = nil
        cb()
    }
}
