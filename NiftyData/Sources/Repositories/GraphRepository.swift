// NiftyData/Sources/Repositories/GraphRepository.swift
// GRDB SQLite. App Group container. WAL mode.
// SRS §7.2: intelligence graph — moments, vibe/acoustic tags, mood map, place history.
// NOTE: SQLCipher AES-256 encryption is deferred until a compatible SPM package is confirmed.
// GRDBSQLCipher was removed from GRDB.swift v7; KeychainBridge is retained for future wiring.

import Foundation
import GRDB
import NiftyCore

public actor GraphRepository: GraphProtocol {
    private let config: AppConfig
    private let db: DatabaseQueue

    public init(config: AppConfig) {
        self.config = config
        self.db = GraphRepository.openDatabase()
    }

    // MARK: - GraphProtocol

    public func saveMoment(_ moment: Moment) async throws {
        // TODO: INSERT/REPLACE INTO moments
    }

    public func updateVibeTag(_ tag: VibeTag, for assetID: UUID) async throws {
        // TODO: INSERT INTO vibe_tags
    }

    public func updateAcousticTag(_ tag: AcousticTag, for assetID: UUID) async throws {
        // TODO: INSERT INTO acoustic_tags
    }

    public func saveNudgeResponse(_ response: NudgeResponse) async throws {
        // TODO: INSERT INTO nudge_responses
    }

    public func saveMoodPoint(_ point: MoodPoint) async throws {
        // TODO: INSERT INTO mood_points
    }

    public func updatePlaceRecord(_ record: PlaceRecord) async throws {
        // TODO: INSERT OR REPLACE INTO place_history
    }

    public func saveDerivativeRecord(_ derivative: DerivativeAsset) async throws {
        // TODO: UPDATE asset_scores SET fix_applied=1, is_derivative=1
    }

    public func deleteDerivativeRecord(for assetID: UUID) async throws {
        // TODO: UPDATE asset_scores SET fix_applied=0 WHERE asset_id=?
    }

    public func fetchMoments(query: GraphQuery) async throws -> [Moment] {
        return []
    }

    public func fetchPlaceHistory(limit: Int) async throws -> [PlaceRecord] {
        return []
    }

    public func fetchMoodMap(range: DateInterval) async throws -> [MoodPoint] {
        return []
    }

    public func exportForCompanion() async throws -> GraphExport {
        GraphExport(moments: [], placeHistory: [], moodMap: [])
    }
}

// MARK: - Database setup

extension GraphRepository {
    /// Opens the encrypted SQLite database in the App Group shared container.
    /// Falls back to an in-memory database if the container is unavailable (e.g., simulator
    /// without entitlements). This prevents launch crashes during development.
    private static func openDatabase() -> DatabaseQueue {
        do {
            let dbURL = databaseURL()
            let config = Configuration()
            // TODO: wire SQLCipher passphrase once GRDBSQLCipher (or equivalent) is available.
            // Retained: let key = try KeychainBridge.graphDatabaseKey(); db.usePassphrase(key)
            let queue = try DatabaseQueue(path: dbURL.path, configuration: config)
            // Enable WAL mode per SRS §7.2
            try queue.write { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
            return queue
        } catch {
            // Development fallback — in-memory DB so the app can launch without entitlements.
            // TODO: in production, surface this error via crash reporting before falling back.
            return try! DatabaseQueue()
        }
    }

    private static func databaseURL() -> URL {
        let appGroup = "group.com.hwcho.niftymomnt"
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) ?? FileManager.default.temporaryDirectory
        return container.appendingPathComponent("graph.sqlite")
    }
}

// MARK: - KeychainBridge

/// Minimal Keychain helper scoped to the graph database key.
/// Generates a random 32-byte key on first launch and stores it in the Keychain.
private enum KeychainBridge {
    static func graphDatabaseKey() throws -> String {
        let service = "com.hwcho.niftymomnt.graphKey"
        let account = "graphDatabaseKey"

        // Return existing key if present
        if let existing = try? keychainLoad(service: service, account: account) {
            return existing
        }

        // Generate and store a new random 32-byte key
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        guard status == errSecSuccess else {
            throw DatabaseError(message: "SecRandomCopyBytes failed: \(status)")
        }
        let key = keyBytes.map { String(format: "%02x", $0) }.joined()
        try keychainStore(service: service, account: account, value: key)
        return key
    }

    private static func keychainLoad(service: String, account: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw DatabaseError(message: "Keychain load failed: \(status)")
        }
        return value
    }

    private static func keychainStore(service: String, account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DatabaseError(message: "Keychain store failed: \(status)")
        }
    }
}
