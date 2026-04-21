// NiftyCore/Tests/ClipRecorderControllerTests.swift
// U9 — ClipRecorderController:
//   (a) start emits .recording within 50ms on a fake adapter,
//   (b) ceiling auto-stop fires at clipMaxDurationSeconds,
//   (c) release before ceiling produces correct duration.

import XCTest
@testable import NiftyCore

@MainActor
@available(iOS 17.0, macOS 14.0, *)
final class ClipRecorderControllerTests: XCTestCase {

    private func drain() async {
        try? await Task.sleep(nanoseconds: 30_000_000)
    }

    // MARK: - U9a — start latency < 50ms on fake adapter

    func test_U9a_startLatencyUnder50ms_onFakeAdapter() async throws {
        let recorder = FakeMovieRecorder()
        let ceiling = ManualCeilingTimer()
        let controller = ClipRecorderController(
            recorder: recorder,
            ceiling: ceiling,
            maxDurationSeconds: 10
        )

        let url = URL(fileURLWithPath: "/tmp/clip-\(UUID().uuidString).mp4")
        controller.press(outputURL: url)
        await drain()

        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.lastOutputURL, url)
        XCTAssertNotNil(controller.latencyToRecording)
        XCTAssertLessThan(controller.latencyToRecording ?? .infinity, 0.050,
                          "start latency \(controller.latencyToRecording ?? 0)s exceeded 50ms budget")
    }

    // MARK: - U9b — ceiling auto-stop

    func test_U9b_ceilingAutoStopFiresAndReportsAutoStopped() async throws {
        let recorder = FakeMovieRecorder(reportedDuration: 10.0)
        let ceiling = ManualCeilingTimer()
        let controller = ClipRecorderController(
            recorder: recorder, ceiling: ceiling, maxDurationSeconds: 10
        )
        let url = URL(fileURLWithPath: "/tmp/clip-\(UUID().uuidString).mp4")
        controller.press(outputURL: url)
        await drain()
        XCTAssertEqual(ceiling.lastScheduledSeconds, 10.0)

        ceiling.fire()
        let outcome = await controller.outcome()
        guard case .completed(let outURL, let duration, let auto) = outcome else {
            return XCTFail("expected completed, got \(outcome)")
        }
        XCTAssertEqual(outURL, url)
        XCTAssertTrue(auto, "expected autoStopped=true on ceiling path")
        XCTAssertLessThanOrEqual(duration, 10.0 + 0.001)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: - U9c — release before ceiling

    func test_U9c_releaseBeforeCeiling_reportsMeasuredDuration_notAutoStopped() async throws {
        let recorder = FakeMovieRecorder(reportedDuration: 2.0)
        let ceiling = ManualCeilingTimer()
        let clock = ClockBox()
        let controller = ClipRecorderController(
            recorder: recorder, ceiling: ceiling, maxDurationSeconds: 10,
            now: { clock.read() }
        )
        let url = URL(fileURLWithPath: "/tmp/clip-\(UUID().uuidString).mp4")
        clock.write(100.0)
        controller.press(outputURL: url)
        await drain()
        clock.write(102.0)  // simulate 2s elapsed
        controller.release()
        let outcome = await controller.outcome()
        guard case .completed(_, let duration, let auto) = outcome else {
            return XCTFail("expected completed, got \(outcome)")
        }
        XCTAssertFalse(auto)
        XCTAssertEqual(duration, 2.0, accuracy: 0.05)
        XCTAssertTrue(ceiling.wasCancelled, "ceiling must be cancelled on release")
    }

    // MARK: - Error path

    func test_startRecordingThrow_yieldsFailedOutcome() async throws {
        let recorder = FakeMovieRecorder(throwOnStart: true)
        let ceiling = ManualCeilingTimer()
        let controller = ClipRecorderController(
            recorder: recorder, ceiling: ceiling, maxDurationSeconds: 10
        )
        controller.press(outputURL: URL(fileURLWithPath: "/tmp/x.mp4"))
        let outcome = await controller.outcome()
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(controller.state, .idle)
    }
}

// MARK: - Doubles

private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    func read() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
    func write(_ v: TimeInterval) { lock.lock(); value = v; lock.unlock() }
}

@available(iOS 17.0, macOS 14.0, *)
private final class FakeMovieRecorder: ClipMovieRecorder, @unchecked Sendable {
    enum StubError: Error { case forced }
    private let throwOnStart: Bool
    private let reportedDuration: Double
    private(set) var startCount: Int = 0
    private(set) var stopCount: Int = 0
    private(set) var lastOutputURL: URL?
    init(throwOnStart: Bool = false, reportedDuration: Double = 0) {
        self.throwOnStart = throwOnStart
        self.reportedDuration = reportedDuration
    }
    func startRecording(to outputURL: URL) async throws {
        startCount += 1
        lastOutputURL = outputURL
        if throwOnStart { throw StubError.forced }
    }
    func stopRecording() async throws -> Double {
        stopCount += 1
        return reportedDuration
    }
}

@available(iOS 17.0, macOS 14.0, *)
private final class ManualCeilingTimer: ClipCeilingTimer, @unchecked Sendable {
    // MainActor-accessed from test body; no locking.
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
