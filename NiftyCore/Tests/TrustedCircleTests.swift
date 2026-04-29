// NiftyCore/Tests/TrustedCircleTests.swift
// Piqd v0.6 — TrustedCircle aggregate invariants. PRD §9, SRS §6.4.
// Pure-Swift; no platform deps.

import XCTest
@testable import NiftyCore

final class TrustedCircleTests: XCTestCase {

    // MARK: - Fixtures

    private let ownKey = Data(repeating: 0xAA, count: 32)
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func friend(_ keyByte: UInt8, name: String = "F") -> Friend {
        Friend(
            displayName: name,
            publicKey: Data(repeating: keyByte, count: 32),
            addedAt: now
        )
    }

    private func emptyCircle() -> TrustedCircle {
        TrustedCircle(ownPublicKey: ownKey)
    }

    // MARK: - Empty / single

    func test_emptyCircle_countIsZero_andContainsFalse() {
        let c = emptyCircle()
        XCTAssertEqual(c.count, 0)
        XCTAssertFalse(c.isFull)
        XCTAssertFalse(c.contains(id: UUID()))
        XCTAssertFalse(c.contains(publicKey: Data(repeating: 0x01, count: 32)))
    }

    func test_addOne_count1_containsByIdAndKey() throws {
        var c = emptyCircle()
        let f = friend(0x01)
        try c.add(f)

        XCTAssertEqual(c.count, 1)
        XCTAssertTrue(c.contains(id: f.id))
        XCTAssertTrue(c.contains(publicKey: f.publicKey))
    }

    // MARK: - Capacity (FR-CIRCLE-01)

    func test_fillToMax_succeeds_atTen() throws {
        var c = emptyCircle()
        for i in 0..<10 {
            try c.add(friend(UInt8(i + 1)))
        }
        XCTAssertEqual(c.count, 10)
        XCTAssertTrue(c.isFull)
    }

    func test_addEleventh_throwsFull() throws {
        var c = emptyCircle()
        for i in 0..<10 {
            try c.add(friend(UInt8(i + 1)))
        }
        XCTAssertThrowsError(try c.add(friend(0xFE))) { err in
            XCTAssertEqual(err as? TrustedCircleError, .full)
        }
        XCTAssertEqual(c.count, 10) // not appended on throw
    }

    // MARK: - Duplicate

    func test_addDuplicatePublicKey_throwsDuplicate() throws {
        var c = emptyCircle()
        try c.add(friend(0x01, name: "A"))
        // Different `id` and `displayName`, same public key → still a duplicate.
        XCTAssertThrowsError(try c.add(friend(0x01, name: "B"))) { err in
            XCTAssertEqual(err as? TrustedCircleError, .duplicate)
        }
        XCTAssertEqual(c.count, 1)
    }

    func test_distinctKeysSameDisplayName_bothAdmitted() throws {
        var c = emptyCircle()
        try c.add(friend(0x01, name: "Alex"))
        try c.add(friend(0x02, name: "Alex"))
        XCTAssertEqual(c.count, 2)
    }

    // MARK: - Self-invite

    func test_addOwnPublicKey_throwsSelfInvite() {
        var c = emptyCircle()
        let me = Friend(displayName: "Me", publicKey: ownKey, addedAt: now)
        XCTAssertThrowsError(try c.add(me)) { err in
            XCTAssertEqual(err as? TrustedCircleError, .selfInvite)
        }
        XCTAssertEqual(c.count, 0)
    }

    func test_selfInvitePrecedesDuplicate_andFull() throws {
        // If a candidate is both "self" and would also be a duplicate or push
        // past max, selfInvite wins — the most specific failure surfaces first.
        var c = TrustedCircle(
            ownPublicKey: ownKey,
            friends: [Friend(displayName: "MeAlias", publicKey: ownKey, addedAt: now)]
        )
        // ↑ pre-seeded to set up a duplicate-on-own-key scenario; in real flows
        // the aggregate is constructed by `accept()` which never produces this
        // shape, but the precedence guarantee matters for defensive safety.
        let candidate = Friend(displayName: "X", publicKey: ownKey, addedAt: now)
        XCTAssertThrowsError(try c.add(candidate)) { err in
            XCTAssertEqual(err as? TrustedCircleError, .selfInvite)
        }
    }

    // MARK: - Remove

    func test_remove_existingId_decrementsCount() throws {
        var c = emptyCircle()
        let a = friend(0x01)
        let b = friend(0x02)
        try c.add(a)
        try c.add(b)

        c.remove(id: a.id)
        XCTAssertEqual(c.count, 1)
        XCTAssertFalse(c.contains(id: a.id))
        XCTAssertTrue(c.contains(id: b.id))
    }

    func test_remove_missingId_noOp() throws {
        var c = emptyCircle()
        try c.add(friend(0x01))
        c.remove(id: UUID())
        XCTAssertEqual(c.count, 1)
    }

    func test_removeThenReAddSamePublicKey_succeeds() throws {
        // FR-CIRCLE-05 — removal takes effect immediately; the user can
        // re-invite the same person later.
        var c = emptyCircle()
        let a = friend(0x01, name: "A")
        try c.add(a)
        c.remove(id: a.id)

        let aAgain = Friend(displayName: "A", publicKey: a.publicKey, addedAt: now)
        try c.add(aAgain)
        XCTAssertEqual(c.count, 1)
        XCTAssertTrue(c.contains(publicKey: a.publicKey))
    }

    // MARK: - Order + invariants

    func test_friends_preservesInsertionOrder() throws {
        var c = emptyCircle()
        let a = friend(0x01, name: "A")
        let b = friend(0x02, name: "B")
        let cc = friend(0x03, name: "C")
        try c.add(a)
        try c.add(b)
        try c.add(cc)

        XCTAssertEqual(c.friends.map(\.id), [a.id, b.id, cc.id])
    }

    func test_maxSize_isTen() {
        XCTAssertEqual(TrustedCircle.maxSize, 10)
    }
}
