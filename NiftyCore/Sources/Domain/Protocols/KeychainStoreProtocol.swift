// NiftyCore/Sources/Domain/Protocols/KeychainStoreProtocol.swift
// Piqd v0.6 — Keychain seam consumed by `IdentityKeyService` (Task 4).
// Concrete `SecItem*`-backed impl lives in NiftyData (Task 5). The protocol
// sits in NiftyCore so the service can depend on it without a back-edge.

import Foundation

public protocol KeychainStoreProtocol: Sendable {
    /// Read the data for `key`, or nil if no entry exists.
    func data(forKey key: String) -> Data?
    /// Insert or overwrite `data` at `key`. Throws on Keychain failure.
    func set(_ data: Data, forKey key: String) throws
    /// Remove the entry at `key`. Idempotent — succeeds on missing entry.
    func delete(forKey key: String) throws
}
