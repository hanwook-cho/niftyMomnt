// NiftyData/Sources/Repositories/InMemoryTrustedFriendsRepository.swift
// Piqd v0.6 — zero-IO test/dev seam for `TrustedFriendsRepositoryProtocol`.
// Mirrors `InMemoryDraftsRepository`: enforces the same invariants as the
// GRDB-backed impl so contract tests can run against either.

import Foundation
import NiftyCore

public actor InMemoryTrustedFriendsRepository: TrustedFriendsRepositoryProtocol {

    private var friends: [Friend] = []

    public init() {}

    public func all() async throws -> [Friend] {
        friends.sorted(by: { $0.addedAt < $1.addedAt })
    }

    public func insert(_ friend: Friend) async throws {
        guard friends.count < TrustedCircle.maxSize else {
            throw TrustedFriendsRepositoryError.full
        }
        if friends.contains(where: { $0.publicKey == friend.publicKey }) {
            throw TrustedFriendsRepositoryError.duplicatePublicKey
        }
        friends.append(friend)
    }

    public func remove(id: UUID) async throws {
        friends.removeAll { $0.id == id }
    }

    public func contains(id: UUID) async throws -> Bool {
        friends.contains(where: { $0.id == id })
    }

    public func count() async throws -> Int {
        friends.count
    }

    /// Test-only reset.
    public func clearAll() async {
        friends.removeAll()
    }
}
