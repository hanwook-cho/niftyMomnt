// NiftyCore/Tests/InviteCoordinatorTests.swift
// Piqd v0.6 — `InviteCoordinator` integration tests against in-memory deps.
// Exercises the cross-cutting flow (identity + codec + friends repo).

import XCTest
@testable import NiftyCore

final class InviteCoordinatorTests: XCTestCase {

    // MARK: - In-memory friends repo (this file lives in NiftyCore tests, so
    // we can't import the NiftyData InMemoryTrustedFriendsRepository — define
    // a minimal local fake conforming to the protocol).

    actor LocalFriendsRepo: TrustedFriendsRepositoryProtocol {
        private var friends: [Friend] = []
        func all() async throws -> [Friend] { friends.sorted { $0.addedAt < $1.addedAt } }
        func insert(_ friend: Friend) async throws {
            guard friends.count < TrustedCircle.maxSize else { throw TrustedFriendsRepositoryError.full }
            if friends.contains(where: { $0.publicKey == friend.publicKey }) {
                throw TrustedFriendsRepositoryError.duplicatePublicKey
            }
            friends.append(friend)
        }
        func remove(id: UUID) async throws { friends.removeAll { $0.id == id } }
        func contains(id: UUID) async throws -> Bool { friends.contains(where: { $0.id == id }) }
        func count() async throws -> Int { friends.count }
    }

    // MARK: - Fixtures

    private let ownerID = UUID(uuidString: "8B23E2F4-1234-5678-9ABC-DEF012345678")!
    private let ownerName = "Alex"
    private let fixedNow = Date(timeIntervalSince1970: 1_780_000_000)
    private let fixedNonce = Data(repeating: 0xAB, count: 16)

    private func makeAlice() -> (InviteCoordinator, CryptoKitIdentityKeyService, LocalFriendsRepo) {
        let now = fixedNow
        let nonce = fixedNonce
        let id = ownerID
        let name = ownerName
        let svc = CryptoKitIdentityKeyService(store: InMemoryKeychainStore()) { now }
        let repo = LocalFriendsRepo()
        let coord = InviteCoordinator(
            identity: svc,
            repo: repo,
            ownerSenderID: { id },
            ownerDisplayName: { name },
            nonceGenerator: { nonce },
            now: { now }
        )
        return (coord, svc, repo)
    }

    private func makeBob() -> (InviteCoordinator, CryptoKitIdentityKeyService, LocalFriendsRepo) {
        let now = fixedNow
        let bobID = UUID()
        let bobNonce = Data(repeating: 0xCD, count: 16)
        let svc = CryptoKitIdentityKeyService(store: InMemoryKeychainStore()) { now }
        let repo = LocalFriendsRepo()
        let coord = InviteCoordinator(
            identity: svc,
            repo: repo,
            ownerSenderID: { bobID },
            ownerDisplayName: { "Bob" },
            nonceGenerator: { bobNonce },
            now: { now }
        )
        return (coord, svc, repo)
    }

    // MARK: - myInviteToken / myInviteURL

    func test_myInviteToken_carriesOwnPublicKeyAndOwnerFields() async throws {
        let (coord, svc, _) = makeAlice()
        let key = try await svc.currentKey()
        let token = try await coord.myInviteToken()

        XCTAssertEqual(token.publicKey, key.publicKey)
        XCTAssertEqual(token.senderID, ownerID)
        XCTAssertEqual(token.displayName, ownerName)
        XCTAssertEqual(token.nonce, fixedNonce)
        XCTAssertEqual(token.createdAt, fixedNow)
    }

    func test_myInviteURL_isPiqdInviteScheme_andRoundTripsThroughCodec() async throws {
        let (coord, svc, _) = makeAlice()
        let url = try await coord.myInviteURL()

        XCTAssertEqual(url.scheme, "piqd")
        XCTAssertEqual(url.host, "invite")
        XCTAssertTrue(url.path.hasPrefix("/"))
        let payload = String(url.path.dropFirst())
        XCTAssertFalse(payload.isEmpty)

        let decoded = try InviteTokenCodec().decode(payload, verifier: svc)
        let original = try await coord.myInviteToken()
        XCTAssertEqual(decoded, original)
    }

    // MARK: - accept happy path (cross-device)

    func test_accept_validBobToken_addsBobToAlicesRepo() async throws {
        let (alice, _, aliceRepo) = makeAlice()
        let (bob, _, _) = makeBob()

        let bobToken = try await bob.myInviteToken()
        let added = try await alice.accept(bobToken)

        XCTAssertEqual(added.publicKey, bobToken.publicKey)
        XCTAssertEqual(added.displayName, "Bob")

        let all = try await aliceRepo.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.publicKey, bobToken.publicKey)
    }

    // MARK: - Self-invite

    func test_accept_ownToken_throwsSelfInvite_andDoesNotPersist() async throws {
        let (alice, _, aliceRepo) = makeAlice()
        let myToken = try await alice.myInviteToken()

        do {
            _ = try await alice.accept(myToken)
            XCTFail("expected selfInvite")
        } catch {
            XCTAssertEqual(error as? InviteCoordinatorError, .selfInvite)
        }

        let count = try await aliceRepo.count()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Duplicate

    func test_accept_sameBobTwice_secondThrowsDuplicate() async throws {
        let (alice, _, aliceRepo) = makeAlice()
        let (bob, _, _) = makeBob()
        let bobToken = try await bob.myInviteToken()

        _ = try await alice.accept(bobToken)
        do {
            _ = try await alice.accept(bobToken)
            XCTFail("expected duplicate")
        } catch {
            XCTAssertEqual(error as? InviteCoordinatorError, .duplicate)
        }
        let count = try await aliceRepo.count()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Full

    func test_accept_pastMax_throwsFull() async throws {
        let (alice, _, aliceRepo) = makeAlice()

        // Seed Alice's repo with 10 unrelated friends.
        for i in 0..<10 {
            let f = Friend(
                displayName: "F\(i)",
                publicKey: Data(repeating: UInt8(i + 1), count: 32),
                addedAt: fixedNow.addingTimeInterval(TimeInterval(i))
            )
            try await aliceRepo.insert(f)
        }

        let (bob, _, _) = makeBob()
        let bobToken = try await bob.myInviteToken()

        do {
            _ = try await alice.accept(bobToken)
            XCTFail("expected full")
        } catch {
            XCTAssertEqual(error as? InviteCoordinatorError, .full)
        }
    }

    // MARK: - acceptURL

    func test_acceptURL_validBobURL_addsFriend() async throws {
        let (alice, _, aliceRepo) = makeAlice()
        let (bob, _, _) = makeBob()
        let url = try await bob.myInviteURL()

        let added = try await alice.acceptURL(url)
        let count = try await aliceRepo.count()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(added.displayName, "Bob")
    }

    func test_acceptURL_wrongScheme_throwsMalformedURL() async throws {
        let (alice, _, _) = makeAlice()
        let url = URL(string: "https://example.com/invite/xxx")!
        do {
            _ = try await alice.acceptURL(url)
            XCTFail("expected malformedURL")
        } catch {
            XCTAssertEqual(error as? InviteCoordinatorError, .malformedURL)
        }
    }

    func test_acceptURL_wrongHost_throwsMalformedURL() async throws {
        let (alice, _, _) = makeAlice()
        let url = URL(string: "piqd://something/xxx")!
        do {
            _ = try await alice.acceptURL(url)
            XCTFail("expected malformedURL")
        } catch {
            XCTAssertEqual(error as? InviteCoordinatorError, .malformedURL)
        }
    }
}
