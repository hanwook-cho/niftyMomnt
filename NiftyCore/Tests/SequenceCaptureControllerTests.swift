// NiftyCore/Tests/SequenceCaptureControllerTests.swift
// U3 — count + jitter budget.
// U4 — interruption cleanup + no side effects.
// U5 — zoom latch propagation.

import XCTest
@testable import NiftyCore

@MainActor
@available(iOS 17.0, macOS 14.0, *)
final class SequenceCaptureControllerTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seq-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Drain any queued MainActor Tasks so the controller's internal `Task { @MainActor … }`
    /// hops reach their next suspension point before we inspect state.
    private func drain() async {
        try? await Task.sleep(nanoseconds: 30_000_000)  // 30ms
    }

    // MARK: - U3 — count + jitter

    func test_U3_firesExactly6Frames_withJitterUnder20ms() async throws {
        let tmp = try makeTempDir()
        let capturer = RecordingCapturer(tmpDir: tmp)
        let ticker = ManualTicker()
        let clock = ClockBox()
        let controller = SequenceCaptureController(
            capturer: capturer,
            ticker: ticker,
            frameCount: 6,
            intervalMs: 333,
            now: { clock.read() }
        )

        controller.tap(zoom: 1.0)
        await drain()
        // Fire 5 ticks at simulated 333ms ± 10ms jitter.
        for i in 1...5 {
            clock.write(Double(i) * 0.333 + Double(i % 2 == 0 ? 0.005 : -0.005))
            ticker.fire()
            await drain()
        }

        let outcome = await controller.outcome()
        guard case .completed(let urls, let timestamps) = outcome else {
            return XCTFail("expected completed, got \(outcome)")
        }
        XCTAssertEqual(urls.count, 6)
        XCTAssertEqual(timestamps.count, 6)
        XCTAssertEqual(capturer.captured.count, 6)
        XCTAssertEqual(capturer.captured.map(\.index), [0, 1, 2, 3, 4, 5])

        for i in 1..<timestamps.count {
            let delta = timestamps[i] - timestamps[i - 1]
            XCTAssertLessThanOrEqual(abs(delta - 0.333), 0.020,
                                     "gap \(i) = \(delta)s exceeds ±20ms")
        }
    }

    // MARK: - U4 — interruption

    func test_U4_interruptAfterFrame3_deletesPartials_returnsInterrupted() async throws {
        let tmp = try makeTempDir()
        let capturer = RecordingCapturer(tmpDir: tmp)
        let ticker = ManualTicker()
        let controller = SequenceCaptureController(
            capturer: capturer, ticker: ticker, frameCount: 6, intervalMs: 333
        )

        controller.tap(zoom: 1.0)
        await drain()
        ticker.fire(); await drain()   // frame 1
        ticker.fire(); await drain()   // frame 2
        XCTAssertEqual(capturer.captured.count, 3)
        let partialURLs = capturer.captured.map(\.url)
        for url in partialURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        controller.interrupt()
        let outcome = await controller.outcome()
        XCTAssertEqual(outcome, .interrupted)
        XCTAssertTrue(controller.wasInterrupted)

        for url in partialURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                           "partial \(url.lastPathComponent) not deleted")
        }
    }

    func test_U4_acknowledgeInterruption_clearsFlag() async throws {
        let tmp = try makeTempDir()
        let capturer = RecordingCapturer(tmpDir: tmp)
        let ticker = ManualTicker()
        let controller = SequenceCaptureController(
            capturer: capturer, ticker: ticker, frameCount: 6, intervalMs: 333
        )
        controller.tap(zoom: 1.0)
        await drain()
        controller.interrupt()
        _ = await controller.outcome()
        XCTAssertTrue(controller.wasInterrupted)
        controller.acknowledgeInterruption()
        XCTAssertFalse(controller.wasInterrupted)
    }

    // MARK: - U5 — zoom latch

    func test_U5_zoomLatchedAtTap_propagatesToEveryFrame() async throws {
        let tmp = try makeTempDir()
        let capturer = RecordingCapturer(tmpDir: tmp)
        let ticker = ManualTicker()
        let controller = SequenceCaptureController(
            capturer: capturer, ticker: ticker, frameCount: 6, intervalMs: 333
        )

        controller.tap(zoom: 2.5)
        await drain()
        for _ in 1...5 {
            ticker.fire()
            await drain()
        }
        _ = await controller.outcome()
        XCTAssertEqual(capturer.captured.count, 6)
        for frame in capturer.captured {
            XCTAssertEqual(frame.zoom, 2.5, "zoom drifted to \(frame.zoom) on frame \(frame.index)")
        }
    }
}

// MARK: - Test doubles

private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    func read() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
    func write(_ v: TimeInterval) { lock.lock(); value = v; lock.unlock() }
}

@available(iOS 17.0, macOS 14.0, *)
private final class RecordingCapturer: SequenceFrameCapturer, @unchecked Sendable {
    struct Frame { let index: Int; let zoom: Double; let url: URL }
    private(set) var captured: [Frame] = []
    private let tmpDir: URL
    init(tmpDir: URL) { self.tmpDir = tmpDir }
    func captureFrame(zoom: Double, index: Int) async throws -> URL {
        let url = tmpDir.appendingPathComponent("seq-\(index).heic")
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: url)
        captured.append(Frame(index: index, zoom: zoom, url: url))
        return url
    }
}

@available(iOS 17.0, macOS 14.0, *)
private final class ManualTicker: SequenceTicker, @unchecked Sendable {
    // Accessed from MainActor test body only — no locking.
    private var onTick: (@MainActor @Sendable () -> Void)?
    private var remaining: Int = 0
    func schedule(intervalMs: Int, count: Int, onTick: @escaping @MainActor @Sendable () -> Void) {
        self.onTick = onTick
        self.remaining = count
    }
    func cancel() {
        onTick = nil
        remaining = 0
    }
    @MainActor
    func fire() {
        guard remaining > 0, let cb = onTick else { return }
        remaining -= 1
        cb()
    }
}
