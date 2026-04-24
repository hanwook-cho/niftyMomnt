// NiftyData/Sources/Platform/DispatchSourceTimerTicker.swift
// Piqd v0.3 — production `SequenceTicker` conformance backed by a DispatchSourceTimer on a
// .userInteractive serial queue. Tests use `ManualTicker` in NiftyCoreTests instead.
//
// Contract (mirrors SequenceTicker doc):
//   • First tick fires `intervalMs` after `schedule(...)` is called.
//   • `count` total ticks are delivered before the timer auto-cancels.
//   • `onTick` is dispatched to MainActor.
//   • `cancel()` is idempotent and safe to call from any thread.

import Foundation
import NiftyCore

public final class DispatchSourceTimerTicker: SequenceTicker, @unchecked Sendable {

    private let queue = DispatchQueue(
        label: "com.hwcho99.niftymomnt.sequenceTicker",
        qos: .userInteractive
    )
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    public init() {}

    public func schedule(
        intervalMs: Int,
        count: Int,
        onTick: @escaping @MainActor @Sendable () -> Void
    ) {
        cancel()
        guard count > 0, intervalMs > 0 else { return }

        let t = DispatchSource.makeTimerSource(queue: queue)
        let interval: DispatchTimeInterval = .milliseconds(intervalMs)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(5))

        var remaining = count
        t.setEventHandler { [weak self] in
            Task { @MainActor in onTick() }
            remaining -= 1
            if remaining <= 0 {
                self?.cancel()
            }
        }

        lock.withLock { self.timer = t }
        t.resume()
    }

    public func cancel() {
        let existing: DispatchSourceTimer? = lock.withLock {
            let t = self.timer
            self.timer = nil
            return t
        }
        existing?.cancel()
    }

    deinit { cancel() }
}
