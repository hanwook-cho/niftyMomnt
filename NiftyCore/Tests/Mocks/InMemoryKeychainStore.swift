// NiftyCore/Tests/Mocks/InMemoryKeychainStore.swift
// Test-only fake for `KeychainStoreProtocol`. Production impl in NiftyData.

import Foundation
@testable import NiftyCore

final class InMemoryKeychainStore: KeychainStoreProtocol, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    var setCalls = 0
    var deleteCalls = 0

    func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func set(_ data: Data, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
        setCalls += 1
    }

    func delete(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
        deleteCalls += 1
    }
}
