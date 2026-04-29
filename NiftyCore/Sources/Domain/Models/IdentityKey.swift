// NiftyCore/Sources/Domain/Models/IdentityKey.swift
// Piqd v0.6 — Curve25519 identity public-key value type. SRS §6.3.4, FR-CIRCLE-KEY-01..04.
// Pure Swift — zero platform imports. Concrete signing impl lives in `IdentityKeyService`.

import Foundation

/// A Curve25519 public-identity key paired with the date it was generated. The
/// matching private key never leaves the iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
/// and is not represented in this domain — only the public half travels through
/// invite payloads and is persisted in friends' trusted-circle lists.
public struct IdentityKey: Equatable, Hashable, Sendable {
    /// 32-byte Curve25519 raw representation.
    public let publicKey: Data
    public let createdAt: Date

    public init(publicKey: Data, createdAt: Date) {
        self.publicKey = publicKey
        self.createdAt = createdAt
    }
}
