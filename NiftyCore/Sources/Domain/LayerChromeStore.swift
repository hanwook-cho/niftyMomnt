// NiftyCore/Sources/Domain/LayerChromeStore.swift
// Piqd v0.4 — pure state machine for the three-layer chrome system. See PRD §5.4.
//
// Lives in NiftyCore so transitions can be unit-tested without SwiftUI/Combine. The
// Apps/Piqd `LayerStore` wraps this in an @Observable view model and drives the idle
// timer via Task.sleep — `shouldRetreat(now:)` is the seam those layers call on each
// tick. UI_TEST_MODE shortens `idleInterval` to keep XCUITest deterministic.

import Foundation

public final class LayerChromeStore: @unchecked Sendable {

    private let lock = NSLock()
    private var _state: LayerChromeState = .rest
    private var _lastInteractionAt: Date?
    private let now: NowProvider
    public let idleInterval: TimeInterval

    public init(now: NowProvider = SystemNowProvider(), idleInterval: TimeInterval = 3.0) {
        self.now = now
        self.idleInterval = idleInterval
    }

    public var state: LayerChromeState { lock.withLock { _state } }
    public var lastInteractionAt: Date? { lock.withLock { _lastInteractionAt } }

    /// Single tap on the viewfinder. Toggles `rest` ↔ `revealed`. Ignored while in
    /// `formatSelector` — Layer 2 swallows viewfinder taps per PRD §5.4.
    public func tap() {
        lock.withLock {
            switch _state {
            case .rest:
                _state = .revealed
                _lastInteractionAt = now.now()
            case .revealed:
                _state = .rest
                _lastInteractionAt = nil
            case .formatSelector:
                break
            }
        }
    }

    /// Any chrome interaction (zoom pill tap, ratio tap, flip, pinch begin) — resets
    /// the 3s idle clock. No state change. No-op outside `revealed`.
    public func interact() {
        lock.withLock {
            guard _state == .revealed else { return }
            _lastInteractionAt = now.now()
        }
    }

    /// Layer 2 (format selector) opens. Pauses idle timing.
    public func enterFormatSelector() {
        lock.withLock {
            _state = .formatSelector
            _lastInteractionAt = nil
        }
    }

    /// Layer 2 collapses. Returns to Layer 1 with a fresh 3s window — matches the
    /// "selector dismiss resets idle" semantic in plan §6.1.5.
    public func exitFormatSelector() {
        lock.withLock {
            _state = .revealed
            _lastInteractionAt = now.now()
        }
    }

    /// Returns true when Layer 1 has been idle for `idleInterval`. App-layer timer
    /// polls this and calls `retreat()` when true. Always false outside `revealed`.
    public func shouldRetreat(at instant: Date) -> Bool {
        lock.withLock {
            guard _state == .revealed, let last = _lastInteractionAt else { return false }
            return instant.timeIntervalSince(last) >= idleInterval
        }
    }

    /// Force-retreat to `rest`. No-op outside `revealed`.
    public func retreat() {
        lock.withLock {
            guard _state == .revealed else { return }
            _state = .rest
            _lastInteractionAt = nil
        }
    }
}
