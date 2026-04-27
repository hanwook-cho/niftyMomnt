// NiftyData/Tests/DraftPurgeSchedulerTests.swift
// Piqd v0.5 — sweep behavior of `DraftPurgeScheduler`. Uses
// `InMemoryDraftsRepository` + a recording vault mock; no on-disk I/O.

import Foundation
import XCTest
import NiftyCore
@testable import NiftyData

final class DraftPurgeSchedulerTests: XCTestCase {

    // MARK: - Mock vault

    /// Records every `purgeSnapAsset` call. Optionally fails for a configured
    /// asset id so we can exercise the partial-failure path.
    private actor RecordingVault: DraftPurgeVault {
        private(set) var purgedIDs: [UUID] = []
        private var failingIDs: Set<UUID> = []

        func failFor(_ id: UUID) { failingIDs.insert(id) }

        func purgeSnapAsset(id: UUID) async throws {
            purgedIDs.append(id)
            if failingIDs.contains(id) {
                throw VaultError.notFound
            }
        }
    }

    private let anchor = Date(timeIntervalSinceReferenceDate: 0)

    private func still(_ offsetSeconds: TimeInterval = 0, ceiling: Int = 24) -> DraftItem {
        DraftItem(
            assetID: UUID(),
            assetType: .still,
            capturedAt: anchor.addingTimeInterval(offsetSeconds),
            hardCeilingHours: ceiling
        )
    }

    // MARK: - Tests

    func test_sweep_emptyTable_isNoOp() async throws {
        let drafts = InMemoryDraftsRepository()
        let vault = RecordingVault()
        let scheduler = DraftPurgeScheduler(drafts: drafts, vault: vault,
                                            now: MockNowProvider(anchor))

        let result = try await scheduler.sweep()
        XCTAssertEqual(result.purgedAssetIDs, [])
        XCTAssertEqual(result.vaultFailures, [])
        let calls = await vault.purgedIDs
        XCTAssertEqual(calls, [])
    }

    func test_sweep_removesExpiredAndCascadesToVault() async throws {
        let drafts = InMemoryDraftsRepository()
        let stale = still(0, ceiling: 1)
        let alive = still(0, ceiling: 24)
        _ = try await drafts.insert(stale)
        _ = try await drafts.insert(alive)

        let vault = RecordingVault()
        let clock = MockNowProvider(anchor.addingTimeInterval(2 * 3600))
        let scheduler = DraftPurgeScheduler(drafts: drafts, vault: vault, now: clock)

        let result = try await scheduler.sweep()

        XCTAssertEqual(result.purgedAssetIDs, [stale.assetID])
        XCTAssertEqual(result.vaultFailures, [])
        let calls = await vault.purgedIDs
        XCTAssertEqual(calls, [stale.assetID])

        let remaining = try await drafts.all()
        XCTAssertEqual(remaining.map(\.assetID), [alive.assetID])
    }

    func test_sweep_isIdempotent_secondSweepIsEmpty() async throws {
        let drafts = InMemoryDraftsRepository()
        _ = try await drafts.insert(still(0, ceiling: 1))

        let vault = RecordingVault()
        let clock = MockNowProvider(anchor.addingTimeInterval(2 * 3600))
        let scheduler = DraftPurgeScheduler(drafts: drafts, vault: vault, now: clock)

        let first = try await scheduler.sweep()
        let second = try await scheduler.sweep()

        XCTAssertEqual(first.purgedAssetIDs.count, 1)
        XCTAssertEqual(second.purgedAssetIDs.count, 0)
        let calls = await vault.purgedIDs
        XCTAssertEqual(calls.count, 1, "Vault should be touched only once")
    }

    func test_sweep_continuesAfterIndividualVaultFailure() async throws {
        let drafts = InMemoryDraftsRepository()
        let a = still(0, ceiling: 1)
        let b = still(0, ceiling: 1)
        _ = try await drafts.insert(a)
        _ = try await drafts.insert(b)

        let vault = RecordingVault()
        await vault.failFor(a.assetID)

        let clock = MockNowProvider(anchor.addingTimeInterval(2 * 3600))
        let scheduler = DraftPurgeScheduler(drafts: drafts, vault: vault, now: clock)

        let result = try await scheduler.sweep()
        XCTAssertEqual(Set(result.purgedAssetIDs), Set([a.assetID, b.assetID]))
        XCTAssertEqual(result.vaultFailures, [a.assetID])

        // Both vault calls still happened — failure on `a` did not abort the loop.
        let calls = await vault.purgedIDs
        XCTAssertEqual(Set(calls), Set([a.assetID, b.assetID]))
    }

    func test_sweep_explicitNowOverridesInjectedClock() async throws {
        let drafts = InMemoryDraftsRepository()
        let stale = still(0, ceiling: 1)
        _ = try await drafts.insert(stale)

        let vault = RecordingVault()
        // System clock says "anchor" — nothing should be expired at that time.
        let scheduler = DraftPurgeScheduler(drafts: drafts, vault: vault,
                                            now: MockNowProvider(anchor))

        // But the explicit override should expire it.
        let result = try await scheduler.sweep(now: anchor.addingTimeInterval(2 * 3600))
        XCTAssertEqual(result.purgedAssetIDs, [stale.assetID])
    }

    func test_sweep_doesNotPurgeUnexpiredItems() async throws {
        let drafts = InMemoryDraftsRepository()
        let alive = still(0, ceiling: 24)
        _ = try await drafts.insert(alive)

        let vault = RecordingVault()
        let clock = MockNowProvider(anchor.addingTimeInterval(23 * 3600 + 30 * 60))
        let scheduler = DraftPurgeScheduler(drafts: drafts, vault: vault, now: clock)

        let result = try await scheduler.sweep()
        XCTAssertEqual(result.purgedAssetIDs, [])
        let calls = await vault.purgedIDs
        XCTAssertEqual(calls, [])

        let remaining = try await drafts.all()
        XCTAssertEqual(remaining.count, 1)
    }

    func test_sweep_advancingClock_progressivelyPurges() async throws {
        let drafts = InMemoryDraftsRepository()
        let oneHour = still(0, ceiling: 1)
        let twoHour = still(0, ceiling: 2)
        let twentyFour = still(0, ceiling: 24)
        _ = try await drafts.insert(oneHour)
        _ = try await drafts.insert(twoHour)
        _ = try await drafts.insert(twentyFour)

        let vault = RecordingVault()
        let clock = MockNowProvider(anchor)
        let scheduler = DraftPurgeScheduler(drafts: drafts, vault: vault, now: clock)

        // Tick to +1h 30m → purges 1h-ceiling item only.
        clock.set(anchor.addingTimeInterval(1.5 * 3600))
        let r1 = try await scheduler.sweep()
        XCTAssertEqual(r1.purgedAssetIDs, [oneHour.assetID])

        // Tick to +3h → purges 2h-ceiling item.
        clock.set(anchor.addingTimeInterval(3 * 3600))
        let r2 = try await scheduler.sweep()
        XCTAssertEqual(r2.purgedAssetIDs, [twoHour.assetID])

        // Tick to +25h → purges remaining 24h-ceiling item.
        clock.set(anchor.addingTimeInterval(25 * 3600))
        let r3 = try await scheduler.sweep()
        XCTAssertEqual(r3.purgedAssetIDs, [twentyFour.assetID])

        let remaining = try await drafts.all()
        XCTAssertTrue(remaining.isEmpty)
    }
}
