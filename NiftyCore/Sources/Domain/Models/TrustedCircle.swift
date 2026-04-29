// NiftyCore/Sources/Domain/Models/TrustedCircle.swift
// Piqd v0.6 — trusted friends domain aggregate. PRD §9 (FR-CIRCLE-01..08), SRS §6.4.
// Pure Swift — zero platform imports. Persistence lives in
// `TrustedFriendsRepository` (NiftyData); this is the in-memory invariant layer.

import Foundation

// MARK: - Friend

/// A trusted-circle member. Public key travels in invite payloads and is the
/// stable identity dimension; `id` is a local UUID so two devices rendering the
/// same friend independently don't need a coordinated identifier.
public struct Friend: Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let publicKey: Data
    public let addedAt: Date
    /// Last send/receive timestamp. v0.6 always nil — populated starting v0.7.
    public let lastActivityAt: Date?

    public init(
        id: UUID = UUID(),
        displayName: String,
        publicKey: Data,
        addedAt: Date,
        lastActivityAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.publicKey = publicKey
        self.addedAt = addedAt
        self.lastActivityAt = lastActivityAt
    }
}

// MARK: - Errors

public enum TrustedCircleError: Error, Equatable, Sendable {
    /// Circle already at `TrustedCircle.maxSize`. FR-CIRCLE-01.
    case full
    /// A friend with the same public key already exists in the circle.
    case duplicate
    /// Attempted to add own public key. FR-CIRCLE-06 (no self-invite).
    case selfInvite
}

// MARK: - TrustedCircle

/// Pure aggregate enforcing v0.6 circle invariants:
/// - max 10 friends (FR-CIRCLE-01)
/// - public-key uniqueness (a single friend cannot be added twice)
/// - cannot add own public key
///
/// Insertion order is preserved (`friends` is an Array, not a Set) so UI can
/// render in `addedAt` order without an explicit sort. `remove(id:)` is a
/// no-op on missing IDs — the repo layer handles row-not-found semantics.
public struct TrustedCircle: Equatable, Sendable {

    public static let maxSize = 10

    public let ownPublicKey: Data
    public private(set) var friends: [Friend]

    public init(ownPublicKey: Data, friends: [Friend] = []) {
        self.ownPublicKey = ownPublicKey
        self.friends = friends
    }

    public var count: Int { friends.count }
    public var isFull: Bool { friends.count >= TrustedCircle.maxSize }

    public func contains(id: UUID) -> Bool {
        friends.contains(where: { $0.id == id })
    }

    public func contains(publicKey: Data) -> Bool {
        friends.contains(where: { $0.publicKey == publicKey })
    }

    /// Add a friend. Validates self-invite, duplicate, and capacity in that
    /// order — self-invite is the most specific failure and surfaces first
    /// even when the candidate would also be a duplicate or push past max.
    public mutating func add(_ friend: Friend) throws {
        if friend.publicKey == ownPublicKey {
            throw TrustedCircleError.selfInvite
        }
        if contains(publicKey: friend.publicKey) {
            throw TrustedCircleError.duplicate
        }
        if isFull {
            throw TrustedCircleError.full
        }
        friends.append(friend)
    }

    public mutating func remove(id: UUID) {
        friends.removeAll { $0.id == id }
    }
}
