// NiftyCore/Sources/Domain/UseCases/DualRecorderController.swift
// Piqd v0.3 — drives the Dual format: two synchronized movie outputs (rear + front),
// finalized into a single PIP composite MP4. State machine mirrors ClipRecorderController
// with two key differences:
//   1. `press()` opens two output URLs (rear + front) via `DualMovieRecorder`.
//   2. On stop, the two files are passed to `DualCompositor` which produces a single
//      composite MP4. The outcome carries the composite URL, not the raw inputs.
//
// 15s hard ceiling per SRS. The composition step (AVMutableComposition /
// AVMutableVideoComposition) lives in NiftyData; this controller only speaks to protocols.

import Foundation
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "DualRecorder")

// MARK: - Protocols

public protocol DualMovieRecorder: Sendable {
    /// Begin synchronized recording of both cameras to the two URLs.
    func startRecording(rearURL: URL, frontURL: URL) async throws
    /// Stop both outputs. Returns the captured URLs (may equal the inputs or adapter-chosen
    /// paths) plus the measured raw duration in seconds.
    func stopRecording() async throws -> (rearURL: URL, frontURL: URL, duration: Double)
}

/// PIP compositor. Production: AVMutableComposition-based in NiftyData.
public protocol DualCompositor: Sendable {
    /// Compose the two source movies into one MP4 at `outputURL`. Returns the final URL and
    /// measured composite duration (may differ from raw by the trim / encode tolerance).
    func composite(
        rearURL: URL,
        frontURL: URL,
        outputURL: URL
    ) async throws -> (url: URL, durationSeconds: Double)
}

// MARK: - Outcome

public enum DualRecorderOutcome: Sendable, Equatable {
    /// `url` is the composite MP4 (single file). `autoStopped=true` if the 15s ceiling fired.
    case completed(url: URL, duration: Double, autoStopped: Bool)
    case failed
}

// MARK: - Controller

@MainActor
public final class DualRecorderController {

    public enum State: Sendable, Equatable { case idle, starting, recording, stopping, compositing }

    public let maxDurationSeconds: Double

    private let recorder: any DualMovieRecorder
    private let compositor: any DualCompositor
    private let ceiling: any ClipCeilingTimer
    private let now: @Sendable () -> TimeInterval

    public private(set) var state: State = .idle
    public private(set) var latencyToRecording: TimeInterval?

    private var rearURL: URL?
    private var frontURL: URL?
    private var compositeURL: URL?
    private var pressedAt: TimeInterval?
    private var recordingStartedAt: TimeInterval?
    private var finalOutcome: DualRecorderOutcome?
    private var outcomeContinuation: AsyncStream<DualRecorderOutcome>.Continuation?

    public init(
        recorder: any DualMovieRecorder,
        compositor: any DualCompositor,
        ceiling: any ClipCeilingTimer,
        maxDurationSeconds: Double = 15,
        now: @escaping @Sendable () -> TimeInterval = { CFAbsoluteTimeGetCurrent() }
    ) {
        self.recorder = recorder
        self.compositor = compositor
        self.ceiling = ceiling
        self.maxDurationSeconds = maxDurationSeconds
        self.now = now
    }

    // MARK: - Public API

    public func press(rearURL: URL, frontURL: URL, compositeURL: URL) {
        guard state == .idle else { return }
        state = .starting
        self.rearURL = rearURL
        self.frontURL = frontURL
        self.compositeURL = compositeURL
        self.pressedAt = now()
        self.latencyToRecording = nil
        self.finalOutcome = nil
        log.debug("press → dual start rear=\(rearURL.lastPathComponent) front=\(frontURL.lastPathComponent)")

        Task { @MainActor in
            do {
                try await self.recorder.startRecording(rearURL: rearURL, frontURL: frontURL)
                guard self.state == .starting else { return }
                let t = self.now()
                self.recordingStartedAt = t
                if let p = self.pressedAt { self.latencyToRecording = t - p }
                self.state = .recording
                self.ceiling.schedule(seconds: self.maxDurationSeconds) { [weak self] in
                    self?.handleCeiling()
                }
            } catch {
                log.error("dual startRecording failed: \(error.localizedDescription)")
                self.finish(.failed)
            }
        }
    }

    public func release() {
        guard state == .recording else { return }
        performStop(autoStopped: false)
    }

    public func outcome() async -> DualRecorderOutcome {
        if let existing = finalOutcome { return existing }
        let stream = AsyncStream<DualRecorderOutcome> { cont in
            self.outcomeContinuation = cont
        }
        for await outcome in stream { return outcome }
        return .failed
    }

    public func cancel() {
        guard state != .idle else { return }
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
        log.info("dual ceiling hit at \(self.maxDurationSeconds)s")
        performStop(autoStopped: true)
    }

    private func performStop(autoStopped: Bool) {
        guard state == .recording, let compURL = compositeURL else { return }
        state = .stopping
        ceiling.cancel()
        Task { @MainActor in
            do {
                let (rear, front, rawDuration) = try await self.recorder.stopRecording()
                self.state = .compositing
                let (finalURL, composedDuration) = try await self.compositor.composite(
                    rearURL: rear, frontURL: front, outputURL: compURL
                )
                // Prefer composed duration; fall back to raw, then to max cap.
                let duration = min(
                    composedDuration > 0 ? composedDuration : rawDuration,
                    self.maxDurationSeconds
                )
                self.finish(.completed(url: finalURL, duration: duration, autoStopped: autoStopped))
            } catch {
                log.error("dual stop/composite failed: \(error.localizedDescription)")
                self.finish(.failed)
            }
        }
    }

    private func finish(_ outcome: DualRecorderOutcome) {
        state = .idle
        rearURL = nil
        frontURL = nil
        compositeURL = nil
        pressedAt = nil
        recordingStartedAt = nil
        finalOutcome = outcome
        outcomeContinuation?.yield(outcome)
        outcomeContinuation?.finish()
        outcomeContinuation = nil
    }
}
