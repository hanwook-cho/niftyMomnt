// NiftyData/Sources/Platform/KeychainStore.swift
// Piqd v0.6 — concrete `KeychainStoreProtocol` impl over `SecItem*`.
// Used by `IdentityKeyService` (NiftyCore) to persist the user's Curve25519
// private key (FR-CIRCLE-KEY-02). Access class is
// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` per SRS §6.3.4 — the entry
// is unreadable while the device is locked and never syncs to iCloud / other
// devices.
//
// The protocol seam lives in NiftyCore so unit tests can use an in-memory
// fake; this concrete impl gets device-only smoke testing (Keychain calls
// fail on macOS unit-test contexts without a configured keychain access group).

import Foundation
import NiftyCore
import os
import Security

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "KeychainStore")

public struct KeychainStore: KeychainStoreProtocol {

    public enum Error: Swift.Error, Equatable, Sendable {
        case writeFailed(OSStatus)
        case deleteFailed(OSStatus)
    }

    public let service: String

    /// `service` is the Keychain `kSecAttrService` field — defaults to
    /// `com.piqd.identity` to scope Piqd-owned entries away from the host
    /// niftyMomnt app's keychain (the two share a bundle prefix during
    /// development).
    public init(service: String = "com.piqd.identity") {
        self.service = service
    }

    public func data(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    public func set(_ data: Data, forKey key: String) throws {
        // Try update first; if not present, add.
        let updateQuery = baseQuery(forKey: key)
        let attrs: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            log.error("KeychainStore.set update failed: status=\(updateStatus)")
            throw Error.writeFailed(updateStatus)
        }

        var addQuery = baseQuery(forKey: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            log.error("KeychainStore.set add failed: status=\(addStatus)")
            throw Error.writeFailed(addStatus)
        }
    }

    public func delete(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            log.error("KeychainStore.delete failed: status=\(status)")
            throw Error.deleteFailed(status)
        }
    }

    // MARK: - Helpers

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
