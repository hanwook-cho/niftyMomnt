// NiftyData/Sources/Repositories/DraftsRepository.swift
// Piqd v0.5 — GRDB-backed drafts table. Own SQLite file (`drafts.sqlite`) under the
// Piqd namespace, mirroring the `RollCounterRepository` pattern so a corrupt drafts
// DB cannot poison `graph.sqlite`.
//
// Schema:
//   drafts(
//     id              TEXT PRIMARY KEY NOT NULL,    -- DraftItem.id  (UUID)
//     asset_id        TEXT UNIQUE NOT NULL,         -- DraftItem.assetID
//     asset_type      TEXT NOT NULL,                -- AssetType raw value
//     captured_at     REAL NOT NULL,                -- timeIntervalSinceReferenceDate
//     ceiling_hours   INTEGER NOT NULL DEFAULT 24,
//     mode            TEXT NOT NULL DEFAULT 'snap'  -- CaptureMode raw value
//   )

import Foundation
import GRDB
import NiftyCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "DraftsRepository")

public actor DraftsRepository: DraftsRepositoryProtocol {

    private let db: DatabaseQueue

    /// Disk-backed init. Falls back to in-memory if file open fails (parity with
    /// `RollCounterRepository`).
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

    @discardableResult
    public func insert(_ item: DraftItem) async throws -> Bool {
        guard item.mode == .snap else { return false }
        return try await Task.detached(priority: .userInitiated) { [db] in
            try db.write { db in
                let exists = try Bool.fetchOne(db,
                    sql: "SELECT 1 FROM drafts WHERE asset_id = ?",
                    arguments: [item.assetID.uuidString]) ?? false
                if exists { return false }
                try db.execute(sql: """
                    INSERT INTO drafts (id, asset_id, asset_type, captured_at, ceiling_hours, mode)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        item.id.uuidString,
                        item.assetID.uuidString,
                        item.assetType.rawValue,
                        item.capturedAt.timeIntervalSinceReferenceDate,
                        item.hardCeilingHours,
                        item.mode.rawValue,
                    ])
                return true
            }
        }.value
    }

    public func all() async throws -> [DraftItem] {
        try await Task.detached(priority: .userInitiated) { [db] in
            try db.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, asset_id, asset_type, captured_at, ceiling_hours, mode
                    FROM drafts
                    ORDER BY captured_at ASC
                    """)
                return rows.compactMap(Self.decode(_:))
            }
        }.value
    }

    @discardableResult
    public func purgeExpired(now: Date) async throws -> [UUID] {
        let cutoff = now.timeIntervalSinceReferenceDate
        return try await Task.detached(priority: .userInitiated) { [db] in
            try db.write { db in
                let expiredIDs = try String.fetchAll(db, sql: """
                    SELECT asset_id FROM drafts
                    WHERE (captured_at + ceiling_hours * 3600.0) <= ?
                    """, arguments: [cutoff])
                guard !expiredIDs.isEmpty else { return [] }
                try db.execute(sql: """
                    DELETE FROM drafts
                    WHERE (captured_at + ceiling_hours * 3600.0) <= ?
                    """, arguments: [cutoff])
                return expiredIDs.compactMap { UUID(uuidString: $0) }
            }
        }.value
    }

    public func remove(assetID: UUID) async throws {
        try await Task.detached(priority: .userInitiated) { [db] in
            try db.write { db in
                try db.execute(sql: "DELETE FROM drafts WHERE asset_id = ?",
                               arguments: [assetID.uuidString])
            }
        }.value
    }

    // MARK: - Decode

    private static func decode(_ row: Row) -> DraftItem? {
        guard
            let idStr: String       = row["id"],
            let id                  = UUID(uuidString: idStr),
            let assetIDStr: String  = row["asset_id"],
            let assetID             = UUID(uuidString: assetIDStr),
            let typeStr: String     = row["asset_type"],
            let assetType           = AssetType(rawValue: typeStr),
            let capturedTI: Double  = row["captured_at"],
            let ceiling: Int        = row["ceiling_hours"],
            let modeStr: String     = row["mode"],
            let mode                = CaptureMode(rawValue: modeStr)
        else { return nil }
        return DraftItem(
            id: id,
            assetID: assetID,
            assetType: assetType,
            capturedAt: Date(timeIntervalSinceReferenceDate: capturedTI),
            hardCeilingHours: ceiling,
            mode: mode
        )
    }
}

// MARK: - Database setup

extension DraftsRepository {

    private static func openDatabase(namespace: String?) -> DatabaseQueue {
        do {
            let url = databaseURL(namespace: namespace)
            log.debug("DraftsRepository — opening DB at: \(url.path)")
            var configuration = Configuration()
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            try queue.write { db in try createSchema(db) }
            return queue
        } catch {
            log.error("DraftsRepository — file DB failed (\(error)), falling back to IN-MEMORY")
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
        return base.appendingPathComponent("drafts.sqlite")
    }

    fileprivate static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS drafts (
                id            TEXT PRIMARY KEY NOT NULL,
                asset_id      TEXT UNIQUE NOT NULL,
                asset_type    TEXT NOT NULL,
                captured_at   REAL NOT NULL,
                ceiling_hours INTEGER NOT NULL DEFAULT 24,
                mode          TEXT NOT NULL DEFAULT 'snap'
            )
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_drafts_captured_at
                ON drafts(captured_at)
            """)
    }
}
