// NiftyData/Sources/Repositories/RollCounterRepository.swift
// Tracks Piqd's per-local-day Roll Mode capture count for the 24-shot daily limit.
// Uses its own SQLite file (`roll_counter.sqlite`) under the Piqd namespace so it neither
// contends with GraphRepository writes nor leaks the concept into shared NiftyCore protocols.
//
// Introduced in Piqd v0.2.

import Foundation
import GRDB
import NiftyCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "RollCounterRepository")

public actor RollCounterRepository {

    private let db: DatabaseQueue
    private let now: NowProvider
    private let dailyLimitProvider: @Sendable () -> Int
    private let calendar: Calendar

    public init(
        config: AppConfig,
        now: NowProvider = SystemNowProvider(),
        dailyLimit: Int = 24,
        calendar: Calendar = .current
    ) {
        self.init(config: config, now: now,
                  dailyLimitProvider: { dailyLimit }, calendar: calendar)
    }

    /// Use this initializer when the daily limit can change at runtime (e.g. dev settings).
    public init(
        config: AppConfig,
        now: NowProvider = SystemNowProvider(),
        dailyLimitProvider: @escaping @Sendable () -> Int,
        calendar: Calendar = .current
    ) {
        self.now = now
        self.dailyLimitProvider = dailyLimitProvider
        self.calendar = calendar
        self.db = RollCounterRepository.openDatabase(namespace: config.namespace)
    }

    private var dailyLimit: Int { dailyLimitProvider() }

    /// Snapshot of the active daily cap. Use this in UI so the gate count and shutter
    /// disable threshold can never disagree with `increment()`.
    public func currentLimit() -> Int { dailyLimit }

    /// Count for *today* in the current calendar (midnight-to-midnight, device timezone).
    public func currentCount() throws -> Int {
        let key = dayKey(for: now.now())
        return try db.read { db in
            try Self.count(db, dayKey: key)
        }
    }

    public func remaining() throws -> Int {
        max(0, dailyLimit - (try currentCount()))
    }

    public func isFull() throws -> Bool {
        try currentCount() >= dailyLimit
    }

    /// Atomically increment today's count. Returns the new count. If the daily limit is
    /// already reached the call throws `RollCounterError.limitReached` without mutating state.
    @discardableResult
    public func increment() throws -> Int {
        let key = dayKey(for: now.now())
        return try db.write { db in
            let current = try Self.count(db, dayKey: key)
            guard current < self.dailyLimit else {
                throw RollCounterError.limitReached
            }
            try db.execute(sql: """
                INSERT INTO roll_counter (day_key, shot_count) VALUES (?, 1)
                ON CONFLICT(day_key) DO UPDATE SET shot_count = shot_count + 1
                """, arguments: [key])
            return current + 1
        }
    }

    /// Test/dev helper — drops all rows.
    public func reset() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM roll_counter")
        }
    }

    // MARK: - Helpers

    private func dayKey(for date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private static func count(_ db: Database, dayKey: String) throws -> Int {
        let value = try Int.fetchOne(db,
            sql: "SELECT shot_count FROM roll_counter WHERE day_key = ?",
            arguments: [dayKey])
        return value ?? 0
    }
}

public enum RollCounterError: Error, Sendable {
    case limitReached
}

// MARK: - Database setup

extension RollCounterRepository {
    private static func openDatabase(namespace: String?) -> DatabaseQueue {
        do {
            let url = databaseURL(namespace: namespace)
            log.debug("RollCounterRepository — opening DB at: \(url.path)")
            var configuration = Configuration()
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            try queue.write { db in
                try createSchema(db)
            }
            return queue
        } catch {
            log.error("RollCounterRepository — file DB failed (\(error)), falling back to IN-MEMORY")
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
        return base.appendingPathComponent("roll_counter.sqlite")
    }

    private static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS roll_counter (
                day_key    TEXT PRIMARY KEY NOT NULL,
                shot_count INTEGER NOT NULL DEFAULT 0
            )
            """)
    }
}
