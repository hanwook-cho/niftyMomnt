// Apps/Piqd/Piqd/UI/Capture/DraftsStoreBindings.swift
// Piqd v0.5 — @Observable bridge between the pure NiftyCore `DraftsStore` and
// SwiftUI. Owns the 1Hz timer that drives live timer-label color flips while
// the drafts tray sheet is presented, plus the GRDB hydration handshake.
//
// Lifecycle:
//   • `hydrate()` runs once on app launch (PiqdApp `.task`) — pulls all rows
//     from the GRDB repo into the in-memory store.
//   • `enroll(asset:)` is the post-capture call — forwards to the repo + store
//     in the same Task so the badge updates within one render frame.
//   • `startTicker()` / `stopTicker()` bracket the sheet presentation. Outside
//     the sheet the timer is off; the badge re-evaluates on scenePhase
//     transitions and on `enroll()`.

import Foundation
import NiftyCore
import Observation

@MainActor
@Observable
public final class DraftsStoreBindings {

    public let store: DraftsStore
    private let repo: any DraftsRepositoryProtocol
    /// Test-only offset provider (Debug builds; always 0 in Release per
    /// `DevSettingsStore.effectiveFakeNowOffset`). Lets XCUITest seed
    /// `PIQD_DEV_FAKE_NOW_OFFSET=82800` and observe amber timer labels
    /// without waiting 23 hours.
    private let nowOffsetProvider: @MainActor () -> TimeInterval

    /// Drives SwiftUI re-evaluation of timer-derived state. Updated by the
    /// 1Hz ticker while visible, by `enroll`/`remove` on every mutation, and
    /// by `refreshNow()` on scenePhase transitions.
    public private(set) var now: Date = Date()

    private var tickerTask: Task<Void, Never>?

    public init(
        repo: any DraftsRepositoryProtocol,
        store: DraftsStore = DraftsStore(),
        nowOffsetProvider: @MainActor @escaping () -> TimeInterval = { 0 }
    ) {
        self.repo = repo
        self.store = store
        self.nowOffsetProvider = nowOffsetProvider
    }

    // MARK: - Hydration + mutation

    public func hydrate() async {
        let items = (try? await repo.all()) ?? []
        store.replaceAll(items)
        refreshNow()
    }

    public func enroll(asset: Asset) async {
        let item = DraftItem(
            assetID: asset.id,
            assetType: asset.type,
            capturedAt: asset.capturedAt
        )
        _ = try? await repo.insert(item)
        store.insert(item)
        refreshNow()
    }

    public func remove(assetID: UUID) async {
        try? await repo.remove(assetID: assetID)
        store.removeByAssetID(assetID)
        refreshNow()
    }

    /// Re-pull from the repo. Call after `DraftPurgeScheduler.sweep(...)` so
    /// the in-memory store reflects post-purge state.
    public func refreshFromRepo() async {
        let items = (try? await repo.all()) ?? []
        store.replaceAll(items)
        refreshNow()
    }

    // MARK: - Derived state

    public var badgeState: DraftBadgeState {
        store.badgeState(now: now)
    }

    public var rows: [(item: DraftItem, state: DraftExpiryState)] {
        store.rows(now: now)
    }

    public var liveCount: Int {
        store.liveCount(now: now)
    }

    // MARK: - 1Hz ticker (sheet-presented only)

    public func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await MainActor.run { self.refreshNow() }
            }
        }
    }

    public func stopTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    /// Bumps `now` so SwiftUI views observing this object re-evaluate. Safe to
    /// call from any actor-routed mutation site. Applies the dev fake-now
    /// offset in Debug builds.
    public func refreshNow() {
        now = Date().addingTimeInterval(nowOffsetProvider())
    }
}
