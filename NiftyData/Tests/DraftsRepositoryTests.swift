// NiftyData/Tests/DraftsRepositoryTests.swift
// Piqd v0.5 — exercises both DraftsRepositoryProtocol implementations against
// the same protocol-level expectations.

import XCTest
import NiftyCore
@testable import NiftyData

final class DraftsRepositoryTests: XCTestCase {

    // MARK: - Helpers

    private let anchor = Date(timeIntervalSinceReferenceDate: 0)

    private func still(_ offsetSeconds: TimeInterval = 0, ceiling: Int = 24) -> DraftItem {
        DraftItem(
            assetID: UUID(),
            assetType: .still,
            capturedAt: anchor.addingTimeInterval(offsetSeconds),
            hardCeilingHours: ceiling
        )
    }

    private func makeImpls() -> [(name: String, repo: any DraftsRepositoryProtocol)] {
        [
            ("InMemory", InMemoryDraftsRepository()),
            ("GRDB",     DraftsRepository(inMemory: true)),
        ]
    }

    // MARK: - Insert + all

    func test_insert_persistsRow() async throws {
        for (name, repo) in makeImpls() {
            let item = still()
            let inserted = try await repo.insert(item)
            XCTAssertTrue(inserted, "[\(name)]")
            let all = try await repo.all()
            XCTAssertEqual(all.count, 1, "[\(name)]")
            XCTAssertEqual(all.first?.assetID, item.assetID, "[\(name)]")
        }
    }

    func test_insert_idempotentOnAssetID() async throws {
        for (name, repo) in makeImpls() {
            let item = still()
            _ = try await repo.insert(item)
            let second = try await repo.insert(item)
            XCTAssertFalse(second, "[\(name)]")
            let all = try await repo.all()
            XCTAssertEqual(all.count, 1, "[\(name)]")
        }
    }

    func test_insert_rejectsRollMode() async throws {
        for (name, repo) in makeImpls() {
            let rollItem = DraftItem(
                assetID: UUID(), assetType: .still, capturedAt: anchor, mode: .roll
            )
            let inserted = try await repo.insert(rollItem)
            XCTAssertFalse(inserted, "[\(name)]")
            let all = try await repo.all()
            XCTAssertTrue(all.isEmpty, "[\(name)]")
        }
    }

    // MARK: - Order

    func test_all_returnsCapturedAtAscending() async throws {
        for (name, repo) in makeImpls() {
            let older = still(0)
            let newer = still(60)
            _ = try await repo.insert(newer) // out of order on purpose
            _ = try await repo.insert(older)
            let all = try await repo.all()
            XCTAssertEqual(all.map(\.assetID), [older.assetID, newer.assetID], "[\(name)]")
        }
    }

    // MARK: - purgeExpired

    func test_purgeExpired_removesPastCeiling() async throws {
        for (name, repo) in makeImpls() {
            let stale = still(0, ceiling: 1)            // expires at anchor+1h
            let alive = still(0, ceiling: 24)
            _ = try await repo.insert(stale)
            _ = try await repo.insert(alive)
            let purgedIDs = try await repo.purgeExpired(now: anchor.addingTimeInterval(2 * 3600))
            XCTAssertEqual(purgedIDs, [stale.assetID], "[\(name)]")
            let remaining = try await repo.all()
            XCTAssertEqual(remaining.map(\.assetID), [alive.assetID], "[\(name)]")
        }
    }

    func test_purgeExpired_isIdempotent() async throws {
        for (name, repo) in makeImpls() {
            let stale = still(0, ceiling: 1)
            _ = try await repo.insert(stale)
            let now = anchor.addingTimeInterval(2 * 3600)
            let first = try await repo.purgeExpired(now: now)
            let second = try await repo.purgeExpired(now: now)
            XCTAssertEqual(first.count, 1, "[\(name)]")
            XCTAssertEqual(second.count, 0, "[\(name)]")
        }
    }

    func test_purgeExpired_emptyTableReturnsEmpty() async throws {
        for (name, repo) in makeImpls() {
            let purged = try await repo.purgeExpired(now: anchor.addingTimeInterval(48 * 3600))
            XCTAssertTrue(purged.isEmpty, "[\(name)]")
        }
    }

    func test_purgeExpired_respectsExactCeilingBoundary() async throws {
        for (name, repo) in makeImpls() {
            // Item with 1h ceiling captured at anchor → expires AT anchor+1h.
            // FR-SNAP-DRAFT-02 + DraftExpiryEvaluator both treat `<=` ceiling as expired.
            let item = still(0, ceiling: 1)
            _ = try await repo.insert(item)
            let purged = try await repo.purgeExpired(now: anchor.addingTimeInterval(3600))
            XCTAssertEqual(purged, [item.assetID], "[\(name)]")
        }
    }

    // MARK: - remove

    func test_remove_byAssetID() async throws {
        for (name, repo) in makeImpls() {
            let item = still()
            _ = try await repo.insert(item)
            try await repo.remove(assetID: item.assetID)
            let all = try await repo.all()
            XCTAssertTrue(all.isEmpty, "[\(name)]")
        }
    }

    func test_remove_unknownAssetID_isNoOp() async throws {
        for (name, repo) in makeImpls() {
            try await repo.remove(assetID: UUID())
            let all = try await repo.all()
            XCTAssertTrue(all.isEmpty, "[\(name)]")
        }
    }
}
