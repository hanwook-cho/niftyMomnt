// Apps/Piqd/Piqd/UI/Capture/ModeStore.swift
// Single source of truth for Piqd's active capture mode (snap vs roll). App-layer because
// mode selection is a Piqd-only UX concept — niftyMomnt has no equivalent. Persists selection
// across launches via UserDefaults under the "piqd" suite. Also tracks the 5-tap sequence
// on the mode pill that reveals the hidden dev-settings screen.
//
// v0.2 scope: snap + roll only. Future Piqd versions (v0.3+) may expand modes; this store
// is kept intentionally narrow so the call sites don't grow past what's in use.

import Foundation
import NiftyCore
import Observation

@MainActor
@Observable
public final class ModeStore {

    // MARK: - State

    public private(set) var mode: CaptureMode

    // Dev-menu tap sequence state — not persisted.
    private var tapCount: Int = 0
    private var lastTapAt: Date?
    private static let tapWindow: TimeInterval = 2.0
    private static let tapsToReveal = 5

    // Tripped when the 5-tap pattern completes. Consumer sets back to false after presenting.
    public var devMenuRequested: Bool = false

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let now: NowProvider

    private static let modeKey = "piqd.captureMode"

    // MARK: - Init

    public init(
        defaults: UserDefaults = UserDefaults(suiteName: "piqd") ?? .standard,
        now: NowProvider = SystemNowProvider(),
        defaultMode: CaptureMode = .snap
    ) {
        self.defaults = defaults
        self.now = now
        if let raw = defaults.string(forKey: Self.modeKey),
           let saved = CaptureMode(rawValue: raw),
           saved == .snap || saved == .roll {
            self.mode = saved
        } else {
            self.mode = defaultMode
        }
    }

    // MARK: - Mode switching

    public func set(_ newMode: CaptureMode) {
        guard newMode == .snap || newMode == .roll else { return }
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Self.modeKey)
    }

    // MARK: - Dev-menu tap gesture

    /// Register a tap on the mode pill. Five taps within `tapWindow` seconds set
    /// `devMenuRequested = true`. Consumer is expected to read and reset.
    public func registerPillTap() {
        let t = now.now()
        if let last = lastTapAt, t.timeIntervalSince(last) <= Self.tapWindow {
            tapCount += 1
        } else {
            tapCount = 1
        }
        lastTapAt = t
        if tapCount >= Self.tapsToReveal {
            tapCount = 0
            lastTapAt = nil
            devMenuRequested = true
        }
    }
}
