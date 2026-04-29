// Apps/Piqd/PiqdUITests/InviteFixture.swift
// Piqd v0.6 — generates a real signed synthetic invite token for XCUITest.
// Used by `OnboardingUITests` (`PIQD_DEV_INVITE_TOKEN` seed) and
// `CircleSettingsUITests`. Avoids hard-coding a static fixture string —
// the keypair is generated fresh per test so signature verification
// behavior matches production.

import Foundation
import NiftyCore

/// Minimal `KeychainStoreProtocol` impl scoped to the test bundle so we don't
/// need to drag NiftyData into PiqdUITests for one mock.
final class TestFakeKeychain: KeychainStoreProtocol, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func data(forKey key: String) -> Data? { store[key] }
    func set(_ data: Data, forKey key: String) throws { store[key] = data }
    func delete(forKey key: String) throws { store.removeValue(forKey: key) }
}

enum InviteFixture {

    /// Builds a base64-URL invite payload (the same wire format the app
    /// produces) signed by a freshly-generated synthetic identity.
    /// Returns the value to pass via `PIQD_DEV_INVITE_TOKEN`.
    static func makeBase64Token(displayName: String = "Bob") async throws -> String {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let identity = CryptoKitIdentityKeyService(store: TestFakeKeychain()) { now }
        let key = try await identity.currentKey()

        let token = InviteToken(
            senderID: UUID(),
            displayName: displayName,
            publicKey: key.publicKey,
            nonce: Data((0..<16).map { _ in UInt8.random(in: 0...255) }),
            createdAt: now
        )
        return try InviteTokenCodec().encode(token, signer: identity)
    }
}
