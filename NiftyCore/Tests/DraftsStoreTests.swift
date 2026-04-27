// NiftyCore/Tests/DraftsStoreTests.swift
// Piqd v0.5 — pure DraftsStore state-machine behavior. PRD §5.5.

import XCTest
@testable import NiftyCore

final class DraftsStoreTests: XCTestCase {

    private var clock: MockNowProvider!
    private var store: DraftsStore!

    override func setUp() {
        super.setUp()
        clock = MockNowProvider(Date(timeIntervalSinceReferenceDate: 0))
        store = DraftsStore(now: clock)
    }

    private func still(at offset: TimeInterval = 0) -> DraftItem {
        DraftItem(assetID: UUID(), assetType: .still, capturedAt: clock.now().addingTimeInterval(offset))
    }

    // MARK: - Insert

    func test_insert_appendsItem() {
        XCTAssertTrue(store.insert(still()))
        XCTAssertEqual(store.items.count, 1)
    }

    func test_insert_isIdempotentOnAssetID() {
        let item = still()
        XCTAssertTrue(store.insert(item))
        XCTAssertFalse(store.insert(item))
        XCTAssertEqual(store.items.count, 1)
    }

    func test_insert_rejectsRollMode() {
        let rollItem = DraftItem(
            assetID: UUID(), assetType: .still, capturedAt: clock.now(), mode: .roll
        )
        XCTAssertFalse(store.insert(rollItem))
        XCTAssertEqual(store.items.count, 0)
    }

    // MARK: - Remove

    func test_remove_byID() {
        let item = still()
        store.insert(item)
        XCTAssertTrue(store.remove(id: item.id))
        XCTAssertEqual(store.items.count, 0)
    }

    func test_remove_returnsFalseForUnknownID() {
        XCTAssertFalse(store.remove(id: UUID()))
    }

    func test_removeByAssetID() {
        let item = still()
        store.insert(item)
        XCTAssertTrue(store.removeByAssetID(item.assetID))
        XCTAssertEqual(store.items.count, 0)
    }

    // MARK: - Replace

    func test_replaceAll_filtersRollItems() {
        let snap = still()
        let roll = DraftItem(assetID: UUID(), assetType: .still, capturedAt: clock.now(), mode: .roll)
        store.replaceAll([snap, roll])
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.mode, .snap)
    }

    // MARK: - rows() ordering + filtering

    func test_rows_sortedOldestFirst() {
        let newer = still(at: 100)
        let older = still(at: 0)
        store.insert(newer)
        store.insert(older)
        let rows = store.rows()
        XCTAssertEqual(rows.map { $0.item.id }, [older.id, newer.id])
    }

    func test_rows_excludesExpired() {
        let stale = still(at: -25 * 3600)   // captured 25h before "now" → expired
        let alive = still(at: 0)
        store.insert(stale)
        store.insert(alive)
        let rows = store.rows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.item.id, alive.id)
    }

    func test_rows_carriesPerRowState() {
        let urgent = still(at: -(23 * 3600 + 30 * 60)) // 30min remaining
        store.insert(urgent)
        let rows = store.rows()
        guard case .amber = rows.first?.state else {
            return XCTFail("Expected .amber for 30min-remaining item, got \(String(describing: rows.first?.state))")
        }
    }

    // MARK: - badgeState

    func test_badgeState_emptyIsHidden() {
        XCTAssertEqual(store.badgeState(), .hidden)
    }

    func test_badgeState_freshIsNormal() {
        store.insert(still())
        store.insert(still(at: 60))
        XCTAssertEqual(store.badgeState(), .normal(count: 2))
    }

    func test_badgeState_anyUnderOneHour_promotesToUrgent() {
        store.insert(still())                                    // fresh
        store.insert(still(at: -(23 * 3600 + 30 * 60)))          // 30min remaining
        XCTAssertEqual(store.badgeState(), .urgent(count: 2))
    }

    func test_badgeState_excludesExpiredFromCount() {
        store.insert(still())                       // fresh
        store.insert(still(at: -25 * 3600))         // expired
        XCTAssertEqual(store.badgeState(), .normal(count: 1))
    }

    // MARK: - liveCount

    func test_liveCount_excludesExpired() {
        store.insert(still())
        store.insert(still(at: -25 * 3600))
        XCTAssertEqual(store.liveCount(), 1)
    }

    // MARK: - Clock injection

    func test_clockAdvance_changesBadgeUrgency() {
        store.insert(still())
        XCTAssertEqual(store.badgeState(), .normal(count: 1))
        clock.advance(by: 23 * 3600 + 30 * 60) // jump to 30min-remaining
        XCTAssertEqual(store.badgeState(), .urgent(count: 1))
    }

    func test_clockAdvance_pastCeiling_evictsFromBadge() {
        store.insert(still())
        clock.advance(by: 25 * 3600) // past ceiling
        XCTAssertEqual(store.badgeState(), .hidden)
        XCTAssertEqual(store.liveCount(), 0)
    }
}
