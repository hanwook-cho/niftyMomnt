// NiftyCore/Sources/Domain/UseCases/SequenceCaptureController.swift
// Piqd v0.3 — drives the Sequence format: N frames fired at fixed interval, with zoom latched
// at tap-time. All frame disk-writes flow through an injected `SequenceFrameCapturer` so the
// controller is unit-testable without AVFoundation. Interval is driven by an injected
// `SequenceTicker` for the same reason.
//
// Interruption contract (FR-SNAP-SEQ-10): if `interrupt()` is called before all frames land,
// every partial temp URL collected so far is deleted from disk and the outcome is `.interrupted`.
// No vault row is written — that's the caller's responsibility based on the `Outcome`.

import Foundation
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "SequenceCapture")

// MARK: - SequenceFrameCapturer

/// Captures one HEIC frame at the given zoom and returns the temp-file URL.
/// Production: AVCaptureAdapter. Tests: mock returning synthesized files or in-memory stubs.
public protocol SequenceFrameCapturer: Sendable {
    func captureFrame(zoom: Double, index: Int) async throws -> URL
}

// MARK: - SequenceTicker

/// Drives the Sequence firing cadence. Production: `DispatchSourceTimerTicker` wrapping a
/// `DispatchSourceTimer` on a `.userInteractive` serial queue. Tests: `ManualTicker` whose
/// `fire()` is driven from the test body so jitter + interruption can be controlled exactly.
public protocol SequenceTicker: AnyObject, Sendable {
    /// Schedule `onTick` to be invoked on MainActor once every `intervalMs` milliseconds.
    /// The first tick fires after `intervalMs` from schedule time — the tap-moment capture
    /// (index 0) is handled by the controller directly, not the ticker.
    func schedule(intervalMs: Int, count: Int, onTick: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

// MARK: - Outcome

public enum SequenceCaptureOutcome: Sendable, Equatable {
    /// Every frame landed. `urls` has length `frameCount` in capture order.
    /// `timestamps` is the wall-clock delivery time of each frame, used by perf tests to verify
    /// interval jitter ≤ 20 ms (SRS §7).
    case completed(urls: [URL], timestamps: [TimeInterval])
    /// At least one frame was captured before interruption, or interruption hit before the
    /// first frame landed. Any partial URLs have already been deleted from disk by the
    /// controller — the caller should not attempt cleanup.
    case interrupted
}

// MARK: - SequenceCaptureController

@MainActor
public final class SequenceCaptureController {

    // MARK: - Config

    public let frameCount: Int
    public let intervalMs: Int

    // MARK: - Dependencies

    private let capturer: any SequenceFrameCapturer
    private let ticker: any SequenceTicker
    private let now: @Sendable () -> TimeInterval
    private let fileManager: FileManager

    // MARK: - State

    private var capturedURLs: [URL] = []
    private var capturedTimestamps: [TimeInterval] = []
    private var latchedZoom: Double = 1.0
    private var isFiring: Bool = false
    private var finalOutcome: SequenceCaptureOutcome?
    private var outcomeContinuation: AsyncStream<SequenceCaptureOutcome>.Continuation?

    /// Set to `true` by `interrupt()` while a sequence was in flight. Consumed by
    /// `PiqdCaptureView.onAppear` to decide whether to surface the "Sequence didn't finish"
    /// toast (UI18). Reset via `acknowledgeInterruption()`.
    public private(set) var wasInterrupted: Bool = false

    // MARK: - Init

    public init(
        capturer: any SequenceFrameCapturer,
        ticker: any SequenceTicker,
        frameCount: Int = 6,
        intervalMs: Int = 333,
        now: @escaping @Sendable () -> TimeInterval = { CFAbsoluteTimeGetCurrent() },
        fileManager: FileManager = .default
    ) {
        self.capturer = capturer
        self.ticker = ticker
        self.frameCount = frameCount
        self.intervalMs = intervalMs
        self.now = now
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Starts the sequence. Call `outcome()` to await completion. If already firing, this is
    /// a no-op and `outcome()` returns `.interrupted` from the previous session.
    public func tap(zoom: Double) {
        if isFiring {
            log.error("tap() called while already firing — ignoring nested tap")
            return
        }
        isFiring = true
        latchedZoom = zoom
        capturedURLs = []
        capturedTimestamps = []
        finalOutcome = nil
        log.debug("tap zoom=\(zoom) count=\(self.frameCount) intervalMs=\(self.intervalMs)")

        // Fire frame 0 immediately (zero-lag shutter — SRS §5.3).
        Task { @MainActor in
            await self.captureAndAdvance(index: 0)
            guard self.isFiring, self.frameCount > 1 else { return }
            let remaining = self.frameCount - 1
            var fired = 0
            self.ticker.schedule(intervalMs: self.intervalMs, count: remaining) { [weak self] in
                guard let self else { return }
                fired += 1
                let idx = fired
                Task { @MainActor in
                    await self.captureAndAdvance(index: idx)
                    if idx >= remaining { self.finish(interrupted: false) }
                }
            }
        }
    }

    /// Await the outcome of the most recent `tap()`. If `tap()` has not been called, blocks
    /// until it is or the AsyncStream is finished.
    public func outcome() async -> SequenceCaptureOutcome {
        if let existing = finalOutcome { return existing }
        let stream = AsyncStream<SequenceCaptureOutcome> { cont in
            self.outcomeContinuation = cont
        }
        for await outcome in stream {
            return outcome
        }
        return .interrupted
    }

    /// Request interruption. Idempotent.
    public func interrupt() {
        guard isFiring else { return }
        log.info("interrupt() — discarding \(self.capturedURLs.count) partial frame(s)")
        ticker.cancel()
        deletePartialFiles()
        finish(interrupted: true)
    }

    public func acknowledgeInterruption() {
        wasInterrupted = false
    }

    // MARK: - Internals

    private func captureAndAdvance(index: Int) async {
        guard isFiring else { return }
        do {
            let url = try await capturer.captureFrame(zoom: latchedZoom, index: index)
            guard isFiring else {
                try? fileManager.removeItem(at: url)
                return
            }
            capturedURLs.append(url)
            capturedTimestamps.append(now())
            log.debug("frame \(index + 1)/\(self.frameCount) captured → \(url.lastPathComponent)")
        } catch {
            log.error("frame \(index) capture failed: \(error.localizedDescription) — interrupting")
            ticker.cancel()
            deletePartialFiles()
            finish(interrupted: true)
        }
    }

    private func finish(interrupted: Bool) {
        guard isFiring else { return }
        isFiring = false
        let outcome: SequenceCaptureOutcome
        if interrupted {
            wasInterrupted = true
            outcome = .interrupted
            log.info("sequence interrupted — \(self.capturedURLs.count) partial frame(s) discarded")
        } else {
            outcome = .completed(urls: capturedURLs, timestamps: capturedTimestamps)
            log.info("sequence completed — \(self.capturedURLs.count) frames")
        }
        capturedURLs = []
        capturedTimestamps = []
        finalOutcome = outcome
        outcomeContinuation?.yield(outcome)
        outcomeContinuation?.finish()
        outcomeContinuation = nil
    }

    private func deletePartialFiles() {
        for url in capturedURLs {
            try? fileManager.removeItem(at: url)
        }
    }
}
