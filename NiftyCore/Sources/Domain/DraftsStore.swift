// NiftyCore/Sources/Domain/DraftsStore.swift
// Piqd v0.5 — pure state machine for the drafts tray. PRD §5.5, UIUX §2.8 + §2.14.
//
// Lives in NiftyCore so insert / remove / sort / badge-derivation can be unit-tested
// without GRDB or SwiftUI. The Apps/Piqd `DraftsStoreBindings` wraps this in an
// @Observable view model and drives the 1Hz timer used by the tray sheet for live
// timer-label color flips.

import Foundation

public final class DraftsStore: @unchecked Sendable {

    private let lock = NSLock()
    private var _items: [DraftItem] = []
    private let now: NowProvider

    public init(now: NowProvider = SystemNowProvider()) {
        self.now = now
    }

    /// Snapshot of the current item set in insertion order. Use `rows(now:)` for
    /// the tray-display ordering.
    public var items: [DraftItem] {
        lock.withLock { _items }
    }

    /// Insert a draft. Idempotent on `assetID` — re-inserting the same asset is a
    /// no-op (FR-SNAP-DRAFT-01 fires once per capture-completion). Roll-mode
    /// items are rejected outright (FR-SNAP-DRAFT-10).
    @discardableResult
    public func insert(_ item: DraftItem) -> Bool {
        lock.withLock {
            guard item.mode == .snap else { return false }
            guard !_items.contains(where: { $0.assetID == item.assetID }) else { return false }
            _items.append(item)
            return true
        }
    }

    /// Remove by drafts-row id. Returns `true` if a row was removed.
    @discardableResult
    public func remove(id: UUID) -> Bool {
        lock.withLock {
            guard let idx = _items.firstIndex(where: { $0.id == id }) else { return false }
            _items.remove(at: idx)
            return true
        }
    }

    /// Remove by underlying asset id. Returns `true` if a row was removed.
    @discardableResult
    public func removeByAssetID(_ assetID: UUID) -> Bool {
        lock.withLock {
            guard let idx = _items.firstIndex(where: { $0.assetID == assetID }) else { return false }
            _items.remove(at: idx)
            return true
        }
    }

    /// Replace the entire item set (used on app launch when reading the GRDB
    /// table back into memory). Preserves insertion order from the caller.
    public func replaceAll(_ newItems: [DraftItem]) {
        lock.withLock {
            _items = newItems.filter { $0.mode == .snap }
        }
    }

    /// Tray-ordered (oldest-first) live rows paired with their per-row display
    /// state. Expired rows are filtered out — caller is expected to purge them
    /// separately via the scheduler (FR-SNAP-DRAFT-02).
    public func rows(now overrideNow: Date? = nil) -> [(item: DraftItem, state: DraftExpiryState)] {
        let resolvedNow = overrideNow ?? now.now()
        return lock.withLock {
            _items
                .sorted { $0.capturedAt < $1.capturedAt }
                .compactMap { item in
                    let state = DraftExpiryEvaluator.evaluate(
                        capturedAt: item.capturedAt,
                        now: resolvedNow,
                        hardCeilingHours: item.hardCeilingHours
                    )
                    if case .expired = state { return nil }
                    return (item, state)
                }
        }
    }

    /// Badge state for the Layer 1 unsent badge.
    public func badgeState(now overrideNow: Date? = nil) -> DraftBadgeState {
        let resolvedNow = overrideNow ?? now.now()
        return lock.withLock {
            DraftExpiryEvaluator.badgeState(items: _items, now: resolvedNow)
        }
    }

    /// Live count after filtering expired (excludes any items past their ceiling).
    public func liveCount(now overrideNow: Date? = nil) -> Int {
        let resolvedNow = overrideNow ?? now.now()
        return lock.withLock {
            _items.filter { item in
                DraftExpiryEvaluator.evaluate(
                    capturedAt: item.capturedAt,
                    now: resolvedNow,
                    hardCeilingHours: item.hardCeilingHours
                ) != .expired
            }.count
        }
    }
}
