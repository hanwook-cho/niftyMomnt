// NiftyData/Sources/Platform/MotionMonitor.swift
// Piqd v0.4 — wraps `CMMotionManager.deviceMotion` and republishes a stream of
// `MotionSample` (rollDegrees) for the invisible-level UI. Two update rates per the v0.4
// plan §3 / UIUX §2.10:
//   • Idle (default): 30 Hz
//   • During recording (Clip / Dual): 5 Hz — the level line stays visible if it was
//     already showing, but motion subscription downshifts to save power.
//
// Lives in NiftyData because CoreMotion is an iOS-only platform dependency. Snapshot
// the model in NiftyCore (`MotionSample`) so tests and UI can speak in domain terms.
//
// Test seam: `emit(_:)` lets unit tests push samples directly without standing up a
// CMMotionManager (which doesn't deliver updates in XCTest hosts). Same shape as
// `StubVibeClassifier.emit(_:)`.

import Foundation
import NiftyCore
import os

#if canImport(CoreMotion)
import CoreMotion
#endif

private let motionLog = Logger(subsystem: "com.hwcho99.niftymomnt", category: "MotionMonitor")

public final class MotionMonitor: @unchecked Sendable {

    public enum UpdateRate: Sendable {
        case idle      // 30 Hz
        case recording // 5 Hz

        var intervalSeconds: TimeInterval {
            switch self {
            case .idle:      return 1.0 / 30.0
            case .recording: return 1.0 / 5.0
            }
        }
    }

    // MARK: - State

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<MotionSample>.Continuation] = [:]
    private var started = false
    private var rate: UpdateRate = .idle

    /// Most recent emitted sample. Replayed to new subscribers.
    private var latest: MotionSample?

    // MARK: - Platform

    #if canImport(CoreMotion)
    private let manager: CMMotionManager
    private let queue: OperationQueue
    #endif

    public init() {
        #if canImport(CoreMotion)
        self.manager = CMMotionManager()
        self.queue = OperationQueue()
        self.queue.qualityOfService = .userInteractive
        self.queue.name = "com.hwcho99.niftymomnt.motionMonitorQ"
        self.queue.maxConcurrentOperationCount = 1
        #endif
    }

    // MARK: - Lifecycle

    /// Begin device-motion updates at the current rate. Idempotent.
    public func start() {
        let shouldStart: Bool = lock.withLock {
            guard !started else { return false }
            started = true
            return true
        }
        guard shouldStart else { return }
        beginUpdates()
    }

    public func stop() {
        let wasStarted: Bool = lock.withLock {
            guard started else { return false }
            started = false
            return true
        }
        guard wasStarted else { return }
        #if canImport(CoreMotion)
        manager.stopDeviceMotionUpdates()
        #endif
    }

    // MARK: - Rate control

    public func setRecording(_ isRecording: Bool) {
        let newRate: UpdateRate = isRecording ? .recording : .idle
        let needsRestart: Bool = lock.withLock {
            guard newRate != rate else { return false }
            rate = newRate
            return started
        }
        guard needsRestart else { return }
        #if canImport(CoreMotion)
        manager.stopDeviceMotionUpdates()
        beginUpdates()
        #endif
    }

    public func currentRate() -> UpdateRate { lock.withLock { rate } }
    public func isRunning() -> Bool { lock.withLock { started } }

    // MARK: - Stream

    public var samples: AsyncStream<MotionSample> {
        AsyncStream { continuation in
            let id = UUID()
            self.lock.withLock { self.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations.removeValue(forKey: id) }
            }
            // Replay latest sample to new subscriber so the level can hydrate immediately.
            if let s = self.lock.withLock({ self.latest }) {
                continuation.yield(s)
            }
        }
    }

    public func currentSample() -> MotionSample? { lock.withLock { latest } }

    // MARK: - Test seam

    /// Push a sample to all subscribers without going through CMMotionManager. UI tests and
    /// XCTest exercises drive level-line behavior through this.
    public func emit(_ sample: MotionSample) {
        publish(sample)
    }

    // MARK: - Private

    private func beginUpdates() {
        #if canImport(CoreMotion)
        guard manager.isDeviceMotionAvailable else {
            motionLog.warning("CMMotionManager reports deviceMotion unavailable — skipping start")
            return
        }
        manager.deviceMotionUpdateInterval = currentRate().intervalSeconds
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                motionLog.error("deviceMotion error: \(String(describing: error))")
                return
            }
            guard let motion else { return }
            // Portrait-held phone — left/right tilt is rotation around the long axis.
            // `gravity.x` is the lateral component; atan2 gives the angle from upright.
            let radians = atan2(motion.gravity.x, -motion.gravity.y)
            let degrees = radians * 180.0 / .pi
            self.publish(MotionSample(rollDegrees: degrees, timestamp: Date()))
        }
        #endif
    }

    private func publish(_ sample: MotionSample) {
        let conts: [AsyncStream<MotionSample>.Continuation] = lock.withLock {
            self.latest = sample
            return Array(self.continuations.values)
        }
        for c in conts { c.yield(sample) }
    }
}
