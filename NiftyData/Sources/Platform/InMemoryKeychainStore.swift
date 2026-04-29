// NiftyData/Sources/Platform/InMemoryKeychainStore.swift
// Piqd v0.6 — in-memory `KeychainStoreProtocol` for unit tests, UI-test seams,
// and dev-mode reset flows. The production `KeychainStore` (SecItem-backed)
// can't be exercised in unit tests reliably because `SecItem*` requires a
// configured keychain access group on the unit-test host.

import Foundation
import NiftyCore

public final class InMemoryKeychainStore: KeychainStoreProtocol, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ data: Data, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    public func delete(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    /// Test-only reset.
    public func clearAll() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}
