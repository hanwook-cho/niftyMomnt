// NiftyCore/Tests/IdentityKeyServiceTests.swift
// Piqd v0.6 — `CryptoKitIdentityKeyService` contract tests against in-memory keychain.

import XCTest
@testable import NiftyCore

final class IdentityKeyServiceTests: XCTestCase {

    private func makeService(
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_780_000_000) }
    ) -> (CryptoKitIdentityKeyService, InMemoryKeychainStore) {
        let store = InMemoryKeychainStore()
        let svc = CryptoKitIdentityKeyService(store: store, now: now)
        return (svc, store)
    }

    // MARK: - Lazy generation + persistence

    func test_currentKey_onEmptyStore_generatesAndPersists() async throws {
        let (svc, store) = makeService()
        XCTAssertNil(store.data(forKey: CryptoKitIdentityKeyService.primaryKey))

        let key = try await svc.currentKey()
        XCTAssertEqual(key.publicKey.count, 32) // Curve25519 raw rep
        XCTAssertNotNil(store.data(forKey: CryptoKitIdentityKeyService.primaryKey))
        XCTAssertEqual(store.setCalls, 1)
    }

    func test_currentKey_secondCall_returnsCachedKey_noNewWrite() async throws {
        let (svc, store) = makeService()
        let first = try await svc.currentKey()
        let second = try await svc.currentKey()

        XCTAssertEqual(first.publicKey, second.publicKey)
        XCTAssertEqual(first.createdAt, second.createdAt)
        XCTAssertEqual(store.setCalls, 1, "second call must not re-persist")
    }

    func test_currentKey_warmCache_acrossNewServiceInstance_returnsSameKey() async throws {
        let store = InMemoryKeychainStore()
        let svcA = CryptoKitIdentityKeyService(store: store) {
            Date(timeIntervalSince1970: 1_780_000_000)
        }
        let original = try await svcA.currentKey()

        // Simulate cold relaunch — fresh service, same store.
        let svcB = CryptoKitIdentityKeyService(store: store) {
            Date(timeIntervalSince1970: 9_999_999_999)  // wrong "now" — must NOT be used
        }
        let reloaded = try await svcB.currentKey()

        XCTAssertEqual(reloaded.publicKey, original.publicKey)
        XCTAssertEqual(reloaded.createdAt, original.createdAt)
        XCTAssertEqual(store.setCalls, 1, "warm load must not write")
    }

    // MARK: - Regenerate

    func test_regenerate_producesDifferentKey_andOverwritesStore() async throws {
        let (svc, store) = makeService()
        let first = try await svc.currentKey()
        let rotated = try await svc.regenerate()

        XCTAssertNotEqual(first.publicKey, rotated.publicKey)
        XCTAssertEqual(store.setCalls, 2)

        // Subsequent currentKey() returns the rotated one.
        let after = try await svc.currentKey()
        XCTAssertEqual(after.publicKey, rotated.publicKey)
    }

    // MARK: - Sign / verify round-trip

    func test_signThenVerify_roundTripSucceeds() async throws {
        let (svc, _) = makeService()
        let key = try await svc.currentKey()
        let payload = Data("hello piqd".utf8)

        let signature = try svc.sign(payload)
        XCTAssertEqual(signature.count, 64) // Curve25519.Signing produces 64-byte sigs

        XCTAssertTrue(svc.verify(signature, payload: payload, publicKey: key.publicKey))
    }

    func test_verify_tamperedSignature_fails() async throws {
        let (svc, _) = makeService()
        let key = try await svc.currentKey()
        let payload = Data("hello piqd".utf8)
        var signature = try svc.sign(payload)
        signature[0] ^= 0xFF

        XCTAssertFalse(svc.verify(signature, payload: payload, publicKey: key.publicKey))
    }

    func test_sign_beforeCurrentKey_throwsNotLoaded() {
        let (svc, _) = makeService()
        XCTAssertThrowsError(try svc.sign(Data([0x01, 0x02]))) { err in
            XCTAssertEqual(err as? IdentityKeyServiceError, .notLoaded)
        }
    }

    // MARK: - Bonus: end-to-end with InviteTokenCodec

    func test_codecEndToEnd_signsAndVerifiesAgainstRealCurve25519() async throws {
        let (svc, _) = makeService()
        let key = try await svc.currentKey()

        let token = InviteToken(
            senderID: UUID(),
            displayName: "Alex",
            publicKey: key.publicKey,
            nonce: Data((0..<16).map { _ in UInt8.random(in: 0...255) }),
            createdAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        let codec = InviteTokenCodec()
        let wire = try codec.encode(token, signer: svc)
        let decoded = try codec.decode(wire, verifier: svc)
        XCTAssertEqual(decoded, token)
    }
}
