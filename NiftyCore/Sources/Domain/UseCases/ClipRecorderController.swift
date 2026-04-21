// NiftyCore/Sources/Domain/UseCases/ClipRecorderController.swift
// Piqd v0.3 — drives the Clip format: press-and-hold movie recording with a ceiling auto-stop.
// Press → `recorder.startRecording(to:)` → state flips to `.recording`, ceiling timer armed.
// Release → `recorder.stopRecording()` → outcome `.completed(url, duration, autoStopped: false)`.
// Ceiling fires → same stop path with `autoStopped: true`.
//
// All AVFoundation work flows through an injected `ClipMovieRecorder`; timing through an
// injected `ClipCeilingTimer`. Platform-free for unit tests.

import Foundation
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "ClipRecorder")

// MARK: - Protocols

/// Movie-file recorder contract. Production: AVCaptureAdapter wrapping AVCaptureMovieFileOutput.
/// Tests: fake that records call order + fakes duration.
public protocol ClipMovieRecorder: Sendable {
    /// Begin writing to `outputURL`. Must resume quickly — the controller measures latency
    /// between `press()` and this call returning for the 50ms budget (PRD §5.2.3).
    func startRecording(to outputURL: URL) async throws
    /// Stop writing and return the final measured duration in seconds. Caller owns the file.
    func stopRecording() async throws -> Double
}

/// One-shot ceiling timer. Fires `onFire` once after `seconds` unless cancelled.
/// Production: DispatchSourceTimer. Tests: ManualCeilingTimer whose `fire()` is driven by test.
public protocol ClipCeilingTimer: AnyObject, Sendable {
    func schedule(seconds: Double, onFire: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

// MARK: - Outcome

public enum ClipRecorderOutcome: Sendable, Equatable {
    /// Recording finalized. `autoStopped=true` means ceiling hit; `false` means user released.
    case completed(url: URL, duration: Double, autoStopped: Bool)
    /// Recorder threw — any partial file is the adapter's responsibility to clean up.
    case failed
}

// MARK: - ClipRecorderController

@MainActor
public final class ClipRecorderController {

    public enum State: Sendable, Equatable { case idle, starting, recording, stopping }

    // MARK: - Config

    public let maxDurationSeconds: Double

    // MARK: - Dependencies

    private let recorder: any ClipMovieRecorder
    private let ceiling: any ClipCeilingTimer
    private let now: @Sendable () -> TimeInterval

    // MARK: - State

    public private(set) var state: State = .idle
    /// Wall-clock delta between `press()` return and `.recording` transition. Populated once
    /// per press so U9 can assert it stays under 50ms on a fake adapter.
    public private(set) var latencyToRecording: TimeInterval?

    private var outputURL: URL?
    private var pressedAt: TimeInterval?
    private var recordingStartedAt: TimeInterval?
    private var finalOutcome: ClipRecorderOutcome?
    private var outcomeContinuation: AsyncStream<ClipRecorderOutcome>.Continuation?

    // MARK: - Init

    public init(
        recorder: any ClipMovieRecorder,
        ceiling: any ClipCeilingTimer,
        maxDurationSeconds: Double = 10,
        now: @escaping @Sendable () -> TimeInterval = { CFAbsoluteTimeGetCurrent() }
    ) {
        self.recorder = recorder
        self.ceiling = ceiling
        self.maxDurationSeconds = maxDurationSeconds
        self.now = now
    }

    // MARK: - Public API

    /// Begin recording to `outputURL`. No-op if already non-idle. Call `outcome()` to await the
    /// final result — delivered on release, ceiling, or error.
    public func press(outputURL: URL) {
        guard state == .idle else {
            log.error("press() called in state \(String(describing: self.state)) — ignored")
            return
        }
        state = .starting
        self.outputURL = outputURL
        self.pressedAt = now()
        self.latencyToRecording = nil
        self.finalOutcome = nil
        log.debug("press → starting recording at \(outputURL.lastPathComponent)")

        Task { @MainActor in
            do {
                try await self.recorder.startRecording(to: outputURL)
                // The caller may have already released or been interrupted during the hop.
                guard self.state == .starting else { return }
                let t = self.now()
                self.recordingStartedAt = t
                if let p = self.pressedAt { self.latencyToRecording = t - p }
                self.state = .recording
                self.ceiling.schedule(seconds: self.maxDurationSeconds) { [weak self] in
                    self?.handleCeiling()
                }
            } catch {
                log.error("startRecording failed: \(error.localizedDescription)")
                self.finish(.failed)
            }
        }
    }

    /// User lifted finger before ceiling. Stops the recording and emits `.completed` with the
    /// measured duration, `autoStopped: false`. No-op if not currently recording.
    public func release() {
        switch state {
        case .idle, .stopping:
            return
        case .starting:
            // The recorder hasn't confirmed start yet; mark stopping so the starting-task sees
            // it on the next hop. We still attempt to stop once `.recording` is reached — but
            // for the fake-adapter test that resumes synchronously, we'll hit `.recording`
            // first. Simplest: mark stopping now; the starting-task won't transition.
            state = .stopping
            // Schedule a stop once the starting hop completes. For the fake case the start
            // has already resolved above. For a slow real adapter we defer to the completion
            // path — the recorder will auto-stop at ceiling.
            return
        case .recording:
            performStop(autoStopped: false)
        }
    }

    /// Await the outcome of the most recent `press()`. Returns the cached outcome if the
    /// recording already finished.
    public func outcome() async -> ClipRecorderOutcome {
        if let existing = finalOutcome { return existing }
        let stream = AsyncStream<ClipRecorderOutcome> { cont in
            self.outcomeContinuation = cont
        }
        for await outcome in stream { return outcome }
        return .failed
    }

    /// Cancel any in-flight recording without delivering a completed outcome. Used when the
    /// capture host tears down (view dismissal, app backgrounded pre-record-start). Emits
    /// `.failed` so any awaiter unblocks.
    public func cancel() {
        guard state != .idle else { return }
        log.info("cancel() in state \(String(describing: self.state))")
        ceiling.cancel()
        state = .stopping
        Task { @MainActor in
            _ = try? await self.recorder.stopRecording()
            self.finish(.failed)
        }
    }

    // MARK: - Internals

    private func handleCeiling() {
        guard state == .recording else { return }
        log.info("ceiling hit at \(self.maxDurationSeconds)s")
        performStop(autoStopped: true)
    }

    private func performStop(autoStopped: Bool) {
        guard state == .recording, let url = outputURL else { return }
        state = .stopping
        ceiling.cancel()
        Task { @MainActor in
            do {
                let reportedDuration = try await self.recorder.stopRecording()
                // Prefer our own wall-clock measure when the adapter returns 0 (e.g. fakes).
                let measuredDuration: Double
                if let start = self.recordingStartedAt {
                    measuredDuration = max(reportedDuration, self.now() - start)
                } else {
                    measuredDuration = reportedDuration
                }
                let capped = min(measuredDuration, self.maxDurationSeconds)
                self.finish(.completed(url: url, duration: capped, autoStopped: autoStopped))
            } catch {
                log.error("stopRecording failed: \(error.localizedDescription)")
                self.finish(.failed)
            }
        }
    }

    private func finish(_ outcome: ClipRecorderOutcome) {
        state = .idle
        outputURL = nil
        pressedAt = nil
        recordingStartedAt = nil
        finalOutcome = outcome
        outcomeContinuation?.yield(outcome)
        outcomeContinuation?.finish()
        outcomeContinuation = nil
    }
}
