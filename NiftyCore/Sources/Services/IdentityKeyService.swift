// NiftyCore/Sources/Services/IdentityKeyService.swift
// Piqd v0.6 — Curve25519 identity key service. PRD §9 (FR-CIRCLE-KEY-01..04), SRS §6.3.4.
// Conforms to `InviteSigner` + `InviteVerifier` so it plugs into `InviteTokenCodec`.
// Persistence is delegated to a `KeychainStoreProtocol` seam — concrete
// `SecItem*` impl in NiftyData; in-memory fake in tests.

import Foundation
import CryptoKit

// MARK: - Protocol

public protocol IdentityKeyServiceProtocol: InviteSigner, InviteVerifier, Sendable {
    /// Lazily produce the user's identity key. First call generates + persists
    /// a new Curve25519 keypair; subsequent calls return the cached key.
    func currentKey() async throws -> IdentityKey

    /// Force-rotate the keypair: generates a new private key, overwrites the
    /// keychain entry, returns the new public key. Existing friends would
    /// have to be re-invited (FR-CIRCLE-KEY-04 reinstall semantics).
    func regenerate() async throws -> IdentityKey
}

// MARK: - Errors

public enum IdentityKeyServiceError: Error, Equatable, Sendable {
    /// `sign(_:)` called before `currentKey()` ever loaded a key.
    case notLoaded
    /// Persisted blob doesn't match the expected layout (corrupt or wrong version).
    case malformedKeychainEntry
}

// MARK: - Concrete impl

public final class CryptoKitIdentityKeyService: IdentityKeyServiceProtocol, @unchecked Sendable {

    /// Keychain `account` field. The `service` is set by the concrete
    /// `KeychainStoreProtocol` impl (e.g., `com.piqd.identity`).
    public static let primaryKey = "com.piqd.identity.primary"

    /// Persisted blob layout v1:
    /// `[0]` magic = 0x01 · `[1..8]` createdAt seconds (Int64 BE) · `[9..40]` private raw rep (32B)
    private static let blobVersion: UInt8 = 0x01
    private static let blobSize = 1 + 8 + 32

    private let store: KeychainStoreProtocol
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var cached: (privateKey: Curve25519.Signing.PrivateKey, createdAt: Date)?

    public init(
        store: KeychainStoreProtocol,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    // MARK: IdentityKeyServiceProtocol

    public func currentKey() async throws -> IdentityKey {
        if let c = lockedCached() {
            return IdentityKey(
                publicKey: c.privateKey.publicKey.rawRepresentation,
                createdAt: c.createdAt
            )
        }
        if let blob = store.data(forKey: Self.primaryKey) {
            let parsed = try Self.parse(blob)
            setCached(parsed)
            return IdentityKey(
                publicKey: parsed.privateKey.publicKey.rawRepresentation,
                createdAt: parsed.createdAt
            )
        }
        return try await regenerate()
    }

    public func regenerate() async throws -> IdentityKey {
        let pk = Curve25519.Signing.PrivateKey()
        let createdAt = now()
        let blob = Self.serialize(privateKey: pk, createdAt: createdAt)
        try store.set(blob, forKey: Self.primaryKey)
        setCached((pk, createdAt))
        return IdentityKey(publicKey: pk.publicKey.rawRepresentation, createdAt: createdAt)
    }

    // MARK: InviteSigner

    public func sign(_ payload: Data) throws -> Data {
        guard let pk = lockedCached()?.privateKey else {
            throw IdentityKeyServiceError.notLoaded
        }
        let signature = try pk.signature(for: payload)
        return Data(signature)
    }

    // MARK: InviteVerifier

    public func verify(_ signature: Data, payload: Data, publicKey: Data) -> Bool {
        guard let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return pubKey.isValidSignature(signature, for: payload)
    }

    // MARK: - Cache helpers

    private func lockedCached() -> (privateKey: Curve25519.Signing.PrivateKey, createdAt: Date)? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    private func setCached(_ value: (privateKey: Curve25519.Signing.PrivateKey, createdAt: Date)) {
        lock.lock(); defer { lock.unlock() }
        cached = value
    }

    // MARK: - Blob serialization

    private static func serialize(
        privateKey: Curve25519.Signing.PrivateKey,
        createdAt: Date
    ) -> Data {
        var data = Data()
        data.append(blobVersion)
        let ts = Int64(createdAt.timeIntervalSince1970)
        for i in (0..<8).reversed() {
            data.append(UInt8((ts >> (i * 8)) & 0xFF))
        }
        data.append(privateKey.rawRepresentation)
        return data
    }

    private static func parse(
        _ blob: Data
    ) throws -> (privateKey: Curve25519.Signing.PrivateKey, createdAt: Date) {
        guard blob.count == blobSize, blob[blob.startIndex] == blobVersion else {
            throw IdentityKeyServiceError.malformedKeychainEntry
        }
        let base = blob.startIndex
        var ts: Int64 = 0
        for i in 0..<8 {
            ts = (ts << 8) | Int64(blob[base + 1 + i])
        }
        let raw = blob.subdata(in: (base + 9) ..< (base + 41))
        do {
            let pk = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
            return (pk, Date(timeIntervalSince1970: TimeInterval(ts)))
        } catch {
            throw IdentityKeyServiceError.malformedKeychainEntry
        }
    }
}
