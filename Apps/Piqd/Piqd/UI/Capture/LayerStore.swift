// Apps/Piqd/Piqd/UI/Capture/LayerStore.swift
// Piqd v0.4 — @Observable wrapper around NiftyCore's LayerChromeStore. Owns the idle
// ticker that calls `shouldRetreat(at:)` and triggers `retreat()`. Pure state-machine
// logic (transitions, idle math) lives in `LayerChromeStore` and is unit-tested there.

import Foundation
import NiftyCore
import Observation

@MainActor
@Observable
final class LayerStore {

    /// Mirrors `LayerChromeStore.state`. Updated synchronously after each mutation so
    /// SwiftUI `withAnimation` blocks observe the change in the same render pass.
    private(set) var state: LayerChromeState

    private let core: LayerChromeStore
    private var idleTask: Task<Void, Never>?

    init(idleInterval: TimeInterval = PiqdTokens.Layer.idleRetreatSeconds,
         now: NowProvider = SystemNowProvider()) {
        self.core = LayerChromeStore(now: now, idleInterval: idleInterval)
        self.state = core.state
    }

    func tap() {
        core.tap()
        sync()
        scheduleIdleCheck()
    }

    func interact() {
        core.interact()
        scheduleIdleCheck()
    }

    func enterFormatSelector() {
        core.enterFormatSelector()
        idleTask?.cancel()
        idleTask = nil
        sync()
    }

    func exitFormatSelector() {
        core.exitFormatSelector()
        sync()
        scheduleIdleCheck()
    }

    private func sync() {
        let next = core.state
        if next != state { state = next }
    }

    /// Polls `shouldRetreat` after `idleInterval`. Cancels and reschedules on each
    /// interaction so a tap mid-window extends the visible duration to a fresh 3s.
    private func scheduleIdleCheck() {
        idleTask?.cancel()
        guard core.state == .revealed else { return }
        let interval = core.idleInterval
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                if self.core.shouldRetreat(at: Date()) {
                    self.core.retreat()
                    self.sync()
                }
            }
        }
    }
}
