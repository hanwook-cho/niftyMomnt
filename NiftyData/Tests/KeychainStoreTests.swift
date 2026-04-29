// NiftyData/Tests/KeychainStoreTests.swift
// Piqd v0.6 — Keychain seam contract tests against the in-memory impl.
// The concrete `KeychainStore` (SecItem-backed) gets device smoke testing
// outside the CI unit suite because `SecItem*` requires a configured keychain
// access group that simulator / macOS test hosts don't expose by default.

import XCTest
@testable import NiftyData
@testable import NiftyCore

final class KeychainStoreTests: XCTestCase {

    private var store: InMemoryKeychainStore!
    private let key = "com.piqd.test.primary"

    override func setUp() {
        super.setUp()
        store = InMemoryKeychainStore()
    }

    func test_data_forMissingKey_isNil() {
        XCTAssertNil(store.data(forKey: key))
    }

    func test_set_thenData_returnsBytes() throws {
        let bytes = Data([0x01, 0x02, 0x03, 0xFF])
        try store.set(bytes, forKey: key)
        XCTAssertEqual(store.data(forKey: key), bytes)
    }

    func test_set_overwrite_replacesExistingBytes() throws {
        try store.set(Data([0xAA]), forKey: key)
        try store.set(Data([0xBB, 0xCC]), forKey: key)
        XCTAssertEqual(store.data(forKey: key), Data([0xBB, 0xCC]))
    }

    func test_delete_removesEntry() throws {
        try store.set(Data([0x42]), forKey: key)
        try store.delete(forKey: key)
        XCTAssertNil(store.data(forKey: key))
    }

    func test_delete_missingKey_doesNotThrow() {
        XCTAssertNoThrow(try store.delete(forKey: "nonexistent"))
    }

    // MARK: - Bonus: end-to-end with IdentityKeyService against the NiftyData fake

    func test_identityKeyService_persistsAndReloads_acrossNewServiceInstance() async throws {
        let svc1 = CryptoKitIdentityKeyService(store: store) {
            Date(timeIntervalSince1970: 1_780_000_000)
        }
        let original = try await svc1.currentKey()

        let svc2 = CryptoKitIdentityKeyService(store: store) {
            Date(timeIntervalSince1970: 9_999_999_999)
        }
        let reloaded = try await svc2.currentKey()

        XCTAssertEqual(reloaded.publicKey, original.publicKey)
        XCTAssertEqual(reloaded.createdAt, original.createdAt)
    }
}
