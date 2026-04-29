// NiftyData/Tests/TrustedFriendsRepositoryTests.swift
// Piqd v0.6 — `TrustedFriendsRepositoryProtocol` contract tests. Runs against
// both the GRDB-backed `TrustedFriendsRepository(inMemory:)` and the
// `InMemoryTrustedFriendsRepository` so divergences surface fast.

import XCTest
@testable import NiftyData
@testable import NiftyCore

final class TrustedFriendsRepositoryTests: XCTestCase {

    // MARK: - Fixtures

    private let baseDate = Date(timeIntervalSince1970: 1_780_000_000)

    private func makeFriend(_ keyByte: UInt8, addedOffset: TimeInterval = 0, name: String = "F") -> Friend {
        Friend(
            displayName: name,
            publicKey: Data(repeating: keyByte, count: 32),
            addedAt: baseDate.addingTimeInterval(addedOffset)
        )
    }

    private func bothImpls() -> [(name: String, repo: TrustedFriendsRepositoryProtocol)] {
        [
            ("InMemory", InMemoryTrustedFriendsRepository()),
            ("GRDB-inMemory", TrustedFriendsRepository(inMemory: true))
        ]
    }

    // MARK: - Empty

    func test_emptyRepo_countZeroAndAllEmpty() async throws {
        for impl in bothImpls() {
            let count = try await impl.repo.count()
            let all = try await impl.repo.all()
            XCTAssertEqual(count, 0, impl.name)
            XCTAssertTrue(all.isEmpty, impl.name)
        }
    }

    // MARK: - Insert + read

    func test_insertOne_countContainsAll_reflect() async throws {
        for impl in bothImpls() {
            let f = makeFriend(0x01, name: "Alex")
            try await impl.repo.insert(f)

            let count = try await impl.repo.count()
            let contains = try await impl.repo.contains(id: f.id)
            let all = try await impl.repo.all()

            XCTAssertEqual(count, 1, impl.name)
            XCTAssertTrue(contains, impl.name)
            XCTAssertEqual(all.count, 1, impl.name)
            XCTAssertEqual(all.first?.id, f.id, impl.name)
            XCTAssertEqual(all.first?.displayName, "Alex", impl.name)
            XCTAssertEqual(all.first?.publicKey, f.publicKey, impl.name)
            XCTAssertNil(all.first?.lastActivityAt, impl.name)
        }
    }

    // MARK: - Sort by addedAt ascending

    func test_all_sortedByAddedAtAscending() async throws {
        for impl in bothImpls() {
            // Insert out of order; expect oldest first.
            let mid    = makeFriend(0x02, addedOffset: 100, name: "B")
            let oldest = makeFriend(0x01, addedOffset: 0,   name: "A")
            let newest = makeFriend(0x03, addedOffset: 200, name: "C")

            try await impl.repo.insert(mid)
            try await impl.repo.insert(oldest)
            try await impl.repo.insert(newest)

            let all = try await impl.repo.all()
            XCTAssertEqual(all.map(\.displayName), ["A", "B", "C"], impl.name)
        }
    }

    // MARK: - Duplicate publicKey

    func test_insertDuplicatePublicKey_throwsDuplicate() async throws {
        for impl in bothImpls() {
            try await impl.repo.insert(makeFriend(0x01, name: "first"))

            let dup = makeFriend(0x01, name: "second")
            do {
                try await impl.repo.insert(dup)
                XCTFail("\(impl.name): expected duplicatePublicKey")
            } catch let err as TrustedFriendsRepositoryError {
                XCTAssertEqual(err, .duplicatePublicKey, impl.name)
            }

            let count = try await impl.repo.count()
            XCTAssertEqual(count, 1, impl.name)
        }
    }

    // MARK: - Max size (defense in depth)

    func test_insert11th_throwsFull() async throws {
        for impl in bothImpls() {
            for i in 0..<10 {
                try await impl.repo.insert(makeFriend(UInt8(i + 1), addedOffset: TimeInterval(i)))
            }
            do {
                try await impl.repo.insert(makeFriend(0xFE, addedOffset: 100))
                XCTFail("\(impl.name): expected .full")
            } catch let err as TrustedFriendsRepositoryError {
                XCTAssertEqual(err, .full, impl.name)
            }

            let count = try await impl.repo.count()
            XCTAssertEqual(count, 10, impl.name)
        }
    }

    // MARK: - Remove

    func test_removeExisting_decrementsCount_andContainsFalse() async throws {
        for impl in bothImpls() {
            let a = makeFriend(0x01, addedOffset: 0)
            let b = makeFriend(0x02, addedOffset: 1)
            try await impl.repo.insert(a)
            try await impl.repo.insert(b)

            try await impl.repo.remove(id: a.id)

            let count = try await impl.repo.count()
            let containsA = try await impl.repo.contains(id: a.id)
            let containsB = try await impl.repo.contains(id: b.id)
            XCTAssertEqual(count, 1, impl.name)
            XCTAssertFalse(containsA, impl.name)
            XCTAssertTrue(containsB, impl.name)
        }
    }

    func test_removeMissingID_isNoOp() async throws {
        for impl in bothImpls() {
            try await impl.repo.insert(makeFriend(0x01))
            try await impl.repo.remove(id: UUID())
            let count = try await impl.repo.count()
            XCTAssertEqual(count, 1, impl.name)
        }
    }

    // MARK: - Round-trip (lastActivityAt + display name w/ unicode)

    func test_roundTrip_preservesAllFields_includingNullLastActivity() async throws {
        for impl in bothImpls() {
            let f = Friend(
                displayName: "Älëx 🌊",
                publicKey: Data(repeating: 0x42, count: 32),
                addedAt: baseDate,
                lastActivityAt: nil
            )
            try await impl.repo.insert(f)
            let all = try await impl.repo.all()
            let reloaded = try XCTUnwrap(all.first, impl.name)

            XCTAssertEqual(reloaded.id, f.id, impl.name)
            XCTAssertEqual(reloaded.displayName, "Älëx 🌊", impl.name)
            XCTAssertEqual(reloaded.publicKey, f.publicKey, impl.name)
            XCTAssertEqual(reloaded.addedAt.timeIntervalSinceReferenceDate,
                           f.addedAt.timeIntervalSinceReferenceDate,
                           accuracy: 0.001,
                           impl.name)
            XCTAssertNil(reloaded.lastActivityAt, impl.name)
        }
    }
}
