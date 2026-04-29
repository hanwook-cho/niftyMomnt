// NiftyData/Sources/Repositories/TrustedFriendsRepository.swift
// Piqd v0.6 — GRDB-backed trusted friends list. Own SQLite file
// (`circle.sqlite`) under the Piqd namespace, mirroring the v0.5
// `DraftsRepository` precedent so a corrupt circle DB cannot poison
// `graph.sqlite` or `drafts.sqlite`.
//
// Schema v1:
//   friends(
//     id               TEXT PRIMARY KEY NOT NULL,    -- Friend.id (UUID)
//     display_name     TEXT NOT NULL,
//     public_key       BLOB UNIQUE NOT NULL,         -- 32-byte Curve25519 raw rep
//     added_at         REAL NOT NULL,                -- timeIntervalSinceReferenceDate
//     last_activity_at REAL                          -- nullable; populated v0.7+
//   )

import Foundation
import GRDB
import NiftyCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "TrustedFriendsRepository")

public actor TrustedFriendsRepository: TrustedFriendsRepositoryProtocol {

    private let db: DatabaseQueue

    /// Disk-backed init. Falls back to in-memory if file open fails — same
    /// resilience contract as `DraftsRepository`.
    public init(config: AppConfig) {
        self.db = Self.openDatabase(namespace: config.namespace)
    }

    /// Test-only init bound to an in-memory `DatabaseQueue`.
    public init(inMemory: Bool) {
        precondition(inMemory)
        let q = try! DatabaseQueue()
        try! q.write { try Self.createSchema($0) }
        self.db = q
    }

    public func all() async throws -> [Friend] {
        try await Task.detached(priority: .userInitiated) { [db] in
            try db.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, display_name, public_key, added_at, last_activity_at
                    FROM friends
                    ORDER BY added_at ASC
                    """)
                return rows.compactMap(Self.decode(_:))
            }
        }.value
    }

    public func insert(_ friend: Friend) async throws {
        try await Task.detached(priority: .userInitiated) { [db] in
            try db.write { db in
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM friends") ?? 0
                guard count < TrustedCircle.maxSize else {
                    throw TrustedFriendsRepositoryError.full
                }
                let dup = try Bool.fetchOne(db,
                    sql: "SELECT 1 FROM friends WHERE public_key = ?",
                    arguments: [friend.publicKey]) ?? false
                if dup {
                    throw TrustedFriendsRepositoryError.duplicatePublicKey
                }
                try db.execute(sql: """
                    INSERT INTO friends (id, display_name, public_key, added_at, last_activity_at)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [
                        friend.id.uuidString,
                        friend.displayName,
                        friend.publicKey,
                        friend.addedAt.timeIntervalSinceReferenceDate,
                        friend.lastActivityAt?.timeIntervalSinceReferenceDate
                    ])
            }
        }.value
    }

    public func remove(id: UUID) async throws {
        try await Task.detached(priority: .userInitiated) { [db] in
            try db.write { db in
                try db.execute(sql: "DELETE FROM friends WHERE id = ?",
                               arguments: [id.uuidString])
            }
        }.value
    }

    public func contains(id: UUID) async throws -> Bool {
        try await Task.detached(priority: .userInitiated) { [db] in
            try db.read { db in
                try Bool.fetchOne(db,
                    sql: "SELECT 1 FROM friends WHERE id = ?",
                    arguments: [id.uuidString]) ?? false
            }
        }.value
    }

    public func count() async throws -> Int {
        try await Task.detached(priority: .userInitiated) { [db] in
            try db.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM friends") ?? 0
            }
        }.value
    }

    // MARK: - Decode

    private static func decode(_ row: Row) -> Friend? {
        guard
            let idStr: String       = row["id"],
            let id                  = UUID(uuidString: idStr),
            let displayName: String = row["display_name"],
            let publicKey: Data     = row["public_key"],
            let addedTI: Double     = row["added_at"]
        else { return nil }
        let lastTI: Double? = row["last_activity_at"]
        return Friend(
            id: id,
            displayName: displayName,
            publicKey: publicKey,
            addedAt: Date(timeIntervalSinceReferenceDate: addedTI),
            lastActivityAt: lastTI.map { Date(timeIntervalSinceReferenceDate: $0) }
        )
    }
}

// MARK: - Database setup

extension TrustedFriendsRepository {

    private static func openDatabase(namespace: String?) -> DatabaseQueue {
        do {
            let url = databaseURL(namespace: namespace)
            log.debug("TrustedFriendsRepository — opening DB at: \(url.path)")
            var configuration = Configuration()
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            try queue.write { db in try createSchema(db) }
            return queue
        } catch {
            log.error("TrustedFriendsRepository — file DB failed (\(error)), falling back to IN-MEMORY")
            let queue = try! DatabaseQueue()
            try! queue.write { db in try createSchema(db) }
            return queue
        }
    }

    private static func databaseURL(namespace: String?) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base: URL
        if let ns = namespace {
            base = docs.appendingPathComponent(ns, isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } else {
            base = docs
        }
        return base.appendingPathComponent("circle.sqlite")
    }

    fileprivate static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS friends (
                id               TEXT PRIMARY KEY NOT NULL,
                display_name     TEXT NOT NULL,
                public_key       BLOB UNIQUE NOT NULL,
                added_at         REAL NOT NULL,
                last_activity_at REAL
            )
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_friends_added_at
                ON friends(added_at)
            """)
    }
}
