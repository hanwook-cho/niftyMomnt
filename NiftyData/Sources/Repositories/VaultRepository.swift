// NiftyData/Sources/Repositories/VaultRepository.swift
// Implements VaultProtocol. FileManager-based backend.
// Assets stored at Documents/assets/{id}.jpg (or .mov for video types).
// Asset metadata stored as JSON sidecar at Documents/assets/{id}.json.
// v0.8: Private assets encrypted with AES-GCM. DEK stored in Keychain.
//       Encrypted file: Documents/assets/{id}.enc  (12-byte nonce || ciphertext)
//       Original file deleted after encryption.

import Combine
import CryptoKit
import Foundation
import NiftyCore
import os
import Photos

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "VaultRepository")

public actor VaultRepository: VaultProtocol {
    private let config: AppConfig
    private let assetsDirectory: URL
    /// Piqd v0.2 — Roll captures land in a sibling sub-namespace so v0.8 can enforce
    /// the 9 PM unlock ritual by locking this directory. For non-Piqd variants this
    /// equals `assetsDirectory`.
    private let rollAssetsDirectory: URL
    nonisolated(unsafe) private let storageSubject = CurrentValueSubject<Int64, Never>(0)

    public init(config: AppConfig) {
        self.config = config
        self.assetsDirectory = Self.resolveAssetsDirectory(namespace: config.namespace)
        self.rollAssetsDirectory = Self.resolveRollAssetsDirectory(namespace: config.namespace)
        do {
            try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
            if rollAssetsDirectory != assetsDirectory {
                try FileManager.default.createDirectory(at: rollAssetsDirectory, withIntermediateDirectories: true)
            }
            log.debug("VaultRepository init — assets dir: \(self.assetsDirectory.path)")
        } catch {
            log.error("VaultRepository init — failed to create assets dir: \(error)")
        }
    }

    /// Computes the assets directory for a given app namespace.
    /// - `nil` namespace → legacy niftyMomnt flat layout: `Documents/assets/`
    /// - non-nil namespace → scoped: `Documents/{ns}/assets/`
    private static func resolveAssetsDirectory(namespace: String?) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = namespace.map { docs.appendingPathComponent($0, isDirectory: true) } ?? docs
        return base.appendingPathComponent("assets", isDirectory: true)
    }

    /// Piqd-only: `Documents/{ns}/roll/assets/`. For non-Piqd variants (nil namespace)
    /// this falls back to the main assets directory — Roll is a Piqd concept.
    private static func resolveRollAssetsDirectory(namespace: String?) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let ns = namespace else {
            return docs.appendingPathComponent("assets", isDirectory: true)
        }
        return docs
            .appendingPathComponent(ns, isDirectory: true)
            .appendingPathComponent("roll", isDirectory: true)
            .appendingPathComponent("assets", isDirectory: true)
    }

    public nonisolated var storageUsedBytes: AnyPublisher<Int64, Never> {
        storageSubject.eraseToAnyPublisher()
    }

    // MARK: - VaultProtocol

    public func save(_ asset: Asset, data: Data) async throws {
        try await save(asset, data: data, fileExtension: nil, locked: false)
    }

    /// Piqd v0.2 — save with explicit container extension (e.g. `"heic"`) and Roll-mode
    /// routing. When `locked` is true the bytes go to `Documents/{ns}/roll/assets/` and
    /// the sidecar records the choice so `load`/`delete` can find the file.
    public func save(
        _ asset: Asset,
        data: Data,
        fileExtension: String?,
        locked: Bool
    ) async throws {
        let ext = fileExtension ?? defaultFileExtension(for: asset.type)
        let dir = locked ? rollAssetsDirectory : assetsDirectory
        let fileURL = dir.appendingPathComponent("\(asset.id.uuidString).\(ext)")
        let metaURL = metaURL(for: asset.id)
        log.debug("save — writing \(data.count)B to \(fileURL.lastPathComponent) locked=\(locked)")
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("save — image write failed: \(error)")
            throw error
        }
        var record = AssetRecord(from: asset)
        record.storageExtension = ext
        record.locked = locked ? true : nil
        let encoded = try JSONEncoder().encode(record)
        do {
            try encoded.write(to: metaURL, options: .atomic)
        } catch {
            log.error("save — metadata JSON write failed: \(error)")
            throw error
        }
        storageSubject.send(storageSubject.value + Int64(data.count))
        log.debug("save done — \(fileURL.lastPathComponent) + \(metaURL.lastPathComponent)")
    }

    public func saveVideoFile(_ asset: Asset, sourceURL: URL) async throws {
        let destURL = fileURL(for: asset.id, type: asset.type)
        log.debug("saveVideoFile — moving \(sourceURL.lastPathComponent) → \(destURL.lastPathComponent)")
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
        } catch {
            log.error("saveVideoFile — move failed: \(error)")
            throw error
        }
        let record = AssetRecord(from: asset)
        let encoded = try JSONEncoder().encode(record)
        let metaURL = metaURL(for: asset.id)
        try encoded.write(to: metaURL, options: .atomic)
        storageSubject.send(storageSubject.value + Int64((try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        log.debug("saveVideoFile done — \(destURL.lastPathComponent)")
    }

    public func saveAudioFile(_ asset: Asset, sourceURL: URL) async throws {
        let destURL = fileURL(for: asset.id, type: asset.type)
        log.debug("saveAudioFile — moving \(sourceURL.lastPathComponent) → \(destURL.lastPathComponent)")
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
        } catch {
            log.error("saveAudioFile — move failed: \(error)")
            throw error
        }
        let record = AssetRecord(from: asset)
        let encoded = try JSONEncoder().encode(record)
        let metaURL = metaURL(for: asset.id)
        try encoded.write(to: metaURL, options: .atomic)
        storageSubject.send(storageSubject.value + Int64((try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        log.debug("saveAudioFile done — \(destURL.lastPathComponent)")
    }

    public func saveLiveMovieFile(_ asset: Asset, sourceURL: URL) async throws {
        let destURL = liveMovieURL(for: asset.id)
        log.debug("saveLiveMovieFile — moving \(sourceURL.lastPathComponent) → \(destURL.lastPathComponent)")
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
        } catch {
            log.error("saveLiveMovieFile — move failed: \(error)")
            throw error
        }
        storageSubject.send(storageSubject.value + Int64((try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        log.debug("saveLiveMovieFile done — \(destURL.lastPathComponent)")
    }

    public func saveDerivative(_ derivative: DerivativeAsset, data: Data, sourceAssetID: UUID) async throws {
        // v0.7: AES-GCM encryption with source asset DEK
        let derivURL = derivativeFileURL(for: sourceAssetID)
        try data.write(to: derivURL, options: .atomic)
    }

    public func load(_ assetID: UUID) async throws -> (Asset, Data) {
        let metaURL = metaURL(for: assetID)
        guard let metaData = try? Data(contentsOf: metaURL),
              let record = try? JSONDecoder().decode(AssetRecord.self, from: metaData) else {
            throw VaultError.notFound
        }
        let asset = record.toAsset()

        if record.isPrivate ?? false {
            // Decrypt AES-GCM encrypted file (12-byte nonce prefix).
            let encURL = encryptedFileURL(for: assetID)
            guard let encData = try? Data(contentsOf: encURL) else { throw VaultError.notFound }
            let plainData = try Self.aesGCMDecrypt(encData)
            return (asset, plainData)
        }

        let fileURL = resolvedFileURL(for: assetID, type: asset.type, record: record)
        guard let data = try? Data(contentsOf: fileURL) else {
            throw VaultError.notFound
        }
        return (asset, data)
    }

    public func moveToVault(assetID: UUID) async throws {
        let metaURL = metaURL(for: assetID)
        guard let metaData = try? Data(contentsOf: metaURL),
              var record = try? JSONDecoder().decode(AssetRecord.self, from: metaData) else {
            throw VaultError.notFound
        }
        guard !(record.isPrivate ?? false) else { return } // already private — idempotent

        let asset = record.toAsset()
        let fileURL = fileURL(for: assetID, type: asset.type)
        guard let plainData = try? Data(contentsOf: fileURL) else {
            throw VaultError.notFound
        }

        // Encrypt with AES-GCM — 12-byte random nonce prepended to ciphertext.
        let encData = try Self.aesGCMEncrypt(plainData)
        let encURL = encryptedFileURL(for: assetID)
        do {
            try encData.write(to: encURL, options: .atomic)
        } catch {
            log.error("moveToVault — encrypted write failed: \(error)")
            throw VaultError.encryptionFailed
        }

        // Remove original file (encrypted copy is now the source of truth).
        try? FileManager.default.removeItem(at: fileURL)

        // Update sidecar.
        record.isPrivate = true
        if let encoded = try? JSONEncoder().encode(record) {
            try? encoded.write(to: metaURL, options: .atomic)
        }
        log.debug("moveToVault done — assetID=\(assetID.uuidString)")
    }

    public func loadPrimary(_ assetID: UUID) async throws -> (Asset, Data) {
        // Returns derivative bytes if a derivative file exists, else original.
        let derivURL = derivativeFileURL(for: assetID)
        let (asset, originalData) = try await load(assetID)
        if let derivData = try? Data(contentsOf: derivURL) {
            return (asset, derivData)
        }
        return (asset, originalData)
    }

    public func deleteDerivative(for assetID: UUID) async throws {
        let derivURL = derivativeFileURL(for: assetID)
        try? FileManager.default.removeItem(at: derivURL)
    }

    public func delete(_ assetID: UUID) async throws {
        let metaURL = metaURL(for: assetID)
        let record = (try? Data(contentsOf: metaURL)).flatMap {
            try? JSONDecoder().decode(AssetRecord.self, from: $0)
        }
        let assetType = record.flatMap { AssetType(rawValue: $0.type) } ?? .still
        let fileURL = resolvedFileURL(for: assetID, type: assetType, record: record)
        let derivURL = derivativeFileURL(for: assetID)
        let encURL = encryptedFileURL(for: assetID)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: metaURL)
        try? FileManager.default.removeItem(at: derivURL)
        try? FileManager.default.removeItem(at: encURL)
        if assetType == .live {
            try? FileManager.default.removeItem(at: liveMovieURL(for: assetID))
        }
    }

    public func query(_ query: VaultQuery) async throws -> [Asset] {
        let dir = assetsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let metaFiles = files.filter { $0.pathExtension == "json" }
        log.debug("query — scanning \(metaFiles.count) sidecar file(s) in assets dir")

        var results: [Asset] = []
        for url in metaFiles {
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(AssetRecord.self, from: data) else { continue }
            let asset = record.toAsset()
            // v0.8: showPrivateOnly=true → only private; false (default) → only public
            let isPrivate = record.isPrivate ?? false
            if query.showPrivateOnly && !isPrivate { continue }
            if !query.showPrivateOnly && isPrivate { continue }
            guard query.assetTypes.containsAssetType(asset.type) else { continue }
            if let range = query.dateRange {
                guard range.contains(asset.capturedAt) else { continue }
            }
            results.append(asset)
        }

        results.sort { $0.capturedAt > $1.capturedAt }

        if let offset = query.offset > 0 ? query.offset : nil {
            results = Array(results.dropFirst(offset))
        }
        if let limit = query.limit {
            results = Array(results.prefix(limit))
        }
        return results
    }

    public func exportToPhotoLibrary(_ assetID: UUID) async throws {
        let (asset, _) = try await load(assetID)
        let fileURL = fileURL(for: assetID, type: asset.type)

        try await Self.requestPhotoLibraryAddAccessIfNeeded()

        switch asset.type {
        case .still, .l4c:
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw VaultError.notFound
            }
            try await Self.performPhotoLibraryChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = fileURL.lastPathComponent
                request.addResource(with: .photo, fileURL: fileURL, options: options)
            }

        case .live:
            let movURL = liveMovieURL(for: assetID)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  FileManager.default.fileExists(atPath: movURL.path) else {
                throw VaultError.notFound
            }
            try await Self.performPhotoLibraryChanges {
                let request = PHAssetCreationRequest.forAsset()

                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.originalFilename = fileURL.lastPathComponent
                request.addResource(with: .photo, fileURL: fileURL, options: photoOptions)

                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.originalFilename = movURL.lastPathComponent
                request.addResource(with: .pairedVideo, fileURL: movURL, options: videoOptions)
            }

        case .clip, .atmosphere, .sequence, .dual, .movingStill:
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw VaultError.notFound
            }
            try await Self.performPhotoLibraryChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = fileURL.lastPathComponent
                request.addResource(with: .video, fileURL: fileURL, options: options)
            }
        case .echo:
            throw VaultError.unsupportedPhotoLibraryExport
        }

        log.debug("exportToPhotoLibrary done — id=\(assetID.uuidString) type=\(asset.type.rawValue)")
    }
}

// MARK: - File layout

private extension VaultRepository {
    func fileURL(for id: UUID, type: AssetType) -> URL {
        let ext = defaultFileExtension(for: type)
        return assetsDirectory.appendingPathComponent("\(id.uuidString).\(ext)")
    }

    func defaultFileExtension(for type: AssetType) -> String {
        switch type {
        case .still, .live, .l4c, .movingStill:
            return "jpg"
        case .clip, .atmosphere, .sequence, .dual:
            return "mov"
        case .echo:
            return "m4a"
        }
    }

    /// Piqd v0.2 — resolves to the correct directory (locked Roll vs main) and extension
    /// based on the sidecar record. Falls back to the legacy computed path when the record
    /// has no `storageExtension` / `locked` info (pre-v0.2 sidecars).
    func resolvedFileURL(for id: UUID, type: AssetType, record: AssetRecord?) -> URL {
        let locked = record?.locked ?? false
        let dir = locked ? rollAssetsDirectory : assetsDirectory
        let ext = record?.storageExtension ?? defaultFileExtension(for: type)
        return dir.appendingPathComponent("\(id.uuidString).\(ext)")
    }

    func metaURL(for id: UUID) -> URL {
        assetsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    func derivativeFileURL(for id: UUID) -> URL {
        assetsDirectory.appendingPathComponent("\(id.uuidString).fix.jpg")
    }

    /// AES-GCM encrypted file: 12-byte nonce || ciphertext (v0.8 private assets).
    func encryptedFileURL(for id: UUID) -> URL {
        assetsDirectory.appendingPathComponent("\(id.uuidString).enc")
    }

    /// Companion MOV for a Live Photo asset. Stored alongside the JPEG in the assets dir.
    func liveMovieURL(for id: UUID) -> URL {
        assetsDirectory.appendingPathComponent("\(id.uuidString).mov")
    }

    // MARK: - AES-GCM encryption helpers (v0.8)

    /// Returns the 256-bit Data Encryption Key, generating and storing it in Keychain on first use.
    /// Keychain item accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never migrates
    /// to a new device and is unavailable before the device is first unlocked after reboot.
    static func vaultDEK() throws -> SymmetricKey {
        let service = "com.hwcho99.niftymomnt.vaultDEK"
        let account = "vaultDataEncryptionKey"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        // First use: generate a fresh 256-bit key.
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw VaultError.encryptionFailed
        }
        return key
    }

    /// Encrypts `plainData` with AES-GCM. Returns `nonce (12 bytes) || ciphertext+tag`.
    static func aesGCMEncrypt(_ plainData: Data) throws -> Data {
        let key = try vaultDEK()
        let nonce = try AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plainData, using: key, nonce: nonce)
        // sealed.combined = nonce(12) + ciphertext + tag(16)
        guard let combined = sealed.combined else { throw VaultError.encryptionFailed }
        return combined
    }

    /// Decrypts data produced by `aesGCMEncrypt` (`nonce || ciphertext+tag`).
    static func aesGCMDecrypt(_ encData: Data) throws -> Data {
        let key = try vaultDEK()
        let sealedBox = try AES.GCM.SealedBox(combined: encData)
        do {
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw VaultError.decryptionFailed
        }
    }

    static func requestPhotoLibraryAddAccessIfNeeded() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized || newStatus == .limited else {
                throw VaultError.photoLibraryAccessDenied
            }
        case .denied, .restricted:
            throw VaultError.photoLibraryAccessDenied
        @unknown default:
            throw VaultError.photoLibraryAccessDenied
        }
    }

    static func performPhotoLibraryChanges(_ changes: @escaping @Sendable () -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: VaultError.photoLibraryExportFailed)
                }
            }
        }
    }
}

// MARK: - AssetRecord (Codable sidecar)

private struct AssetRecord: Codable {
    let id: String
    let type: String
    let capturedAt: Double
    let locationLat: Double?
    let locationLon: Double?
    let vibeTags: [String]
    let transcript: String?
    let duration: Double?
    // v0.8: false = public, true = encrypted in vault. Absent in pre-v0.8 sidecars → defaults false.
    var isPrivate: Bool?
    // Piqd v0.2: container extension on disk (e.g. "heic", "jpg"). Absent → derive from type.
    var storageExtension: String?
    // Piqd v0.2: true when bytes live in the Roll sub-namespace. Absent → false (main vault).
    var locked: Bool?

    init(from asset: Asset) {
        id = asset.id.uuidString
        type = asset.type.rawValue
        capturedAt = asset.capturedAt.timeIntervalSince1970
        locationLat = asset.location?.latitude
        locationLon = asset.location?.longitude
        vibeTags = asset.vibeTags.map(\.rawValue)
        transcript = asset.transcript
        duration = asset.duration
        isPrivate = asset.isPrivate ? true : nil  // omit false (saves space; decodes as nil → false)
        storageExtension = nil
        locked = nil
    }

    func toAsset() -> Asset {
        let location: GPSCoordinate? = locationLat.flatMap { lat in
            locationLon.map { lon in GPSCoordinate(latitude: lat, longitude: lon) }
        }
        let tags = vibeTags.compactMap { VibeTag(rawValue: $0) }
        return Asset(
            id: UUID(uuidString: id) ?? UUID(),
            type: AssetType(rawValue: type) ?? .still,
            capturedAt: Date(timeIntervalSince1970: capturedAt),
            location: location,
            vibeTags: tags,
            transcript: transcript,
            duration: duration,
            isPrivate: isPrivate ?? false
        )
    }
}

// MARK: - AssetTypeSet helper

private extension AssetTypeSet {
    func containsAssetType(_ type: AssetType) -> Bool {
        switch type {
        case .still:       return contains(.still)
        case .live:        return contains(.live)
        case .clip:        return contains(.clip)
        case .echo:        return contains(.echo)
        case .atmosphere:  return contains(.atmosphere)
        case .l4c:         return contains(.still)        // L4C composite stored as JPEG; query as .still bucket
        case .sequence:    return contains(.sequence)     // Piqd
        case .movingStill: return contains(.movingStill)  // Piqd
        case .dual:        return contains(.dual)         // Piqd
        }
    }
}

// MARK: - VaultError

public enum VaultError: Error, Equatable {
    case notFound
    case encryptionFailed
    case decryptionFailed
    case photoLibraryAccessDenied
    case photoLibraryExportFailed
    case unsupportedPhotoLibraryExport
}
