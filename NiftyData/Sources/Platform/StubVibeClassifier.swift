// NiftyData/Sources/Platform/StubVibeClassifier.swift
// Piqd v0.4 — placeholder VibeClassifying that always reports `.quiet`.
// Real CoreML scene classifier is deferred — see piqd_interim_v0.4_plan.md §7.
//
// Wiring: injected via PiqdAppContainer. UI subscribes to `signals` to drive the
// vibe hint glyph. With this stub the glyph stays hidden in v0.4.

import Foundation
import NiftyCore

public final class StubVibeClassifier: VibeClassifying, @unchecked Sendable {

    private let lock = NSLock()
    private var current: VibeSignal = .quiet
    private var continuations: [UUID: AsyncStream<VibeSignal>.Continuation] = [:]
    private var started = false

    public init() {}

    public func start() {
        lock.withLock {
            guard !started else { return }
            started = true
        }
        // Emit the current signal once so subscribers attached before start() observe it.
        publish(current)
    }

    public func stop() {
        lock.withLock { started = false }
    }

    public func currentSignal() -> VibeSignal {
        lock.withLock { current }
    }

    public var signals: AsyncStream<VibeSignal> {
        AsyncStream { continuation in
            let id = UUID()
            self.lock.withLock { self.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations.removeValue(forKey: id) }
            }
            // Replay current signal to new subscribers.
            continuation.yield(self.currentSignal())
        }
    }

    /// Test/dev hook — substitute a different signal at runtime. UI tests can drive this
    /// to verify the vibe hint glyph pulse without standing up a real classifier.
    public func emit(_ signal: VibeSignal) {
        lock.withLock { current = signal }
        publish(signal)
    }

    private func publish(_ signal: VibeSignal) {
        let conts = lock.withLock { Array(continuations.values) }
        for c in conts { c.yield(signal) }
    }
}
