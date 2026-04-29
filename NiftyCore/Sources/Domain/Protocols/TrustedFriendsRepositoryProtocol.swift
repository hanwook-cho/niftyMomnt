// NiftyCore/Sources/Domain/Protocols/TrustedFriendsRepositoryProtocol.swift
// Piqd v0.6 — persistence seam for the trusted friends list. PRD §9, SRS §6.4.
//
// The concrete GRDB-backed adapter lives in NiftyData (`circle.sqlite`).
// `InMemoryTrustedFriendsRepository` (also NiftyData) is the test/dev seam.
//
// The repo enforces SQL-level uniqueness on `public_key` and a defense-in-depth
// max-size check at `TrustedCircle.maxSize`. Higher-level invariants
// (self-invite, ordering precedence) live in the `TrustedCircle` aggregate
// and `InviteCoordinator`.

import Foundation

public enum TrustedFriendsRepositoryError: Error, Equatable, Sendable {
    /// Insert would push past `TrustedCircle.maxSize` (10).
    case full
    /// A friend with the same public key already exists.
    case duplicatePublicKey
}

public protocol TrustedFriendsRepositoryProtocol: AnyObject, Sendable {
    /// All persisted friends ordered by `addedAt` ascending (oldest first).
    func all() async throws -> [Friend]

    /// Insert a new friend. Throws `.full` at max size or `.duplicatePublicKey`
    /// if the public key is already present. Idempotent it is NOT — callers
    /// (`InviteCoordinator`) decide what to do with `.duplicatePublicKey`.
    func insert(_ friend: Friend) async throws

    /// Remove by `Friend.id`. Idempotent — no-op on missing rows.
    func remove(id: UUID) async throws

    /// Whether a friend with the given id exists.
    func contains(id: UUID) async throws -> Bool

    /// Current row count.
    func count() async throws -> Int
}
