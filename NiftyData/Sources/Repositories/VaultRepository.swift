// NiftyData/Sources/Repositories/VaultRepository.swift
// Implements VaultProtocol. FileManager-based backend for v0.1.
// Assets stored at Documents/assets/{id}.jpg (or .mov for video types).
// Asset metadata stored as JSON sidecar at Documents/assets/{id}.meta.json.
// Encryption (CryptoKit AES-GCM) deferred to v0.7 per interim_version_plan.md.

import Combine
import Foundation
import NiftyCore
import os
import Photos

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "VaultRepository")

public actor VaultRepository: VaultProtocol {
    private let config: AppConfig
    nonisolated(unsafe) private let storageSubject = CurrentValueSubject<Int64, Never>(0)

    public init(config: AppConfig) {
        self.config = config
        do {
            try FileManager.default.createDirectory(at: Self.assetsDirectory, withIntermediateDirectories: true)
            log.debug("VaultRepository init — assets dir: \(Self.assetsDirectory.path)")
        } catch {
            log.error("VaultRepository init — failed to create assets dir: \(error)")
        }
    }

    public nonisolated var storageUsedBytes: AnyPublisher<Int64, Never> {
        storageSubject.eraseToAnyPublisher()
    }

    // MARK: - VaultProtocol

    public func save(_ asset: Asset, data: Data) async throws {
        let fileURL = Self.fileURL(for: asset.id, type: asset.type)
        let metaURL = Self.metaURL(for: asset.id)
        log.debug("save — writing \(data.count)B to \(fileURL.lastPathComponent)")
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("save — JPEG write failed: \(error)")
            throw error
        }
        let record = AssetRecord(from: asset)
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
        let destURL = Self.fileURL(for: asset.id, type: asset.type)
        log.debug("saveVideoFile — moving \(sourceURL.lastPathComponent) → \(destURL.lastPathComponent)")
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
        } catch {
            log.error("saveVideoFile — move failed: \(error)")
            throw error
        }
        let record = AssetRecord(from: asset)
        let encoded = try JSONEncoder().encode(record)
        let metaURL = Self.metaURL(for: asset.id)
        try encoded.write(to: metaURL, options: .atomic)
        storageSubject.send(storageSubject.value + Int64((try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        log.debug("saveVideoFile done — \(destURL.lastPathComponent)")
    }

    public func saveLiveMovieFile(_ asset: Asset, sourceURL: URL) async throws {
        let destURL = Self.liveMovieURL(for: asset.id)
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
        let derivURL = Self.derivativeFileURL(for: sourceAssetID)
        try data.write(to: derivURL, options: .atomic)
    }

    public func load(_ assetID: UUID) async throws -> (Asset, Data) {
        let metaURL = Self.metaURL(for: assetID)
        guard let metaData = try? Data(contentsOf: metaURL),
              let record = try? JSONDecoder().decode(AssetRecord.self, from: metaData) else {
            throw VaultError.notFound
        }
        let asset = record.toAsset()
        let fileURL = Self.fileURL(for: assetID, type: asset.type)
        guard let data = try? Data(contentsOf: fileURL) else {
            throw VaultError.notFound
        }
        return (asset, data)
    }

    public func loadPrimary(_ assetID: UUID) async throws -> (Asset, Data) {
        // Returns derivative bytes if a derivative file exists, else original.
        let derivURL = Self.derivativeFileURL(for: assetID)
        let (asset, originalData) = try await load(assetID)
        if let derivData = try? Data(contentsOf: derivURL) {
            return (asset, derivData)
        }
        return (asset, originalData)
    }

    public func deleteDerivative(for assetID: UUID) async throws {
        let derivURL = Self.derivativeFileURL(for: assetID)
        try? FileManager.default.removeItem(at: derivURL)
    }

    public func delete(_ assetID: UUID) async throws {
        let (asset, _) = try await load(assetID)
        let fileURL = Self.fileURL(for: assetID, type: asset.type)
        let metaURL = Self.metaURL(for: assetID)
        let derivURL = Self.derivativeFileURL(for: assetID)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: metaURL)
        try? FileManager.default.removeItem(at: derivURL)
        // Remove Live Photo companion MOV if present.
        if asset.type == .live {
            try? FileManager.default.removeItem(at: Self.liveMovieURL(for: assetID))
        }
    }

    public func query(_ query: VaultQuery) async throws -> [Asset] {
        let dir = Self.assetsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let metaFiles = files.filter { $0.pathExtension == "json" }
        log.debug("query — scanning \(metaFiles.count) sidecar file(s) in assets dir")

        var results: [Asset] = []
        for url in metaFiles {
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(AssetRecord.self, from: data) else { continue }
            let asset = record.toAsset()
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
        let fileURL = Self.fileURL(for: assetID, type: asset.type)

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
            let movURL = Self.liveMovieURL(for: assetID)
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

        case .clip, .echo, .atmosphere:
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw VaultError.notFound
            }
            try await Self.performPhotoLibraryChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = fileURL.lastPathComponent
                request.addResource(with: .video, fileURL: fileURL, options: options)
            }
        }

        log.debug("exportToPhotoLibrary done — id=\(assetID.uuidString) type=\(asset.type.rawValue)")
    }
}

// MARK: - File layout

private extension VaultRepository {
    static var assetsDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("assets", isDirectory: true)
    }

    static func fileURL(for id: UUID, type: AssetType) -> URL {
        let ext = (type == .still || type == .live || type == .l4c) ? "jpg" : "mov"
        return assetsDirectory.appendingPathComponent("\(id.uuidString).\(ext)")
    }

    static func metaURL(for id: UUID) -> URL {
        assetsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    static func derivativeFileURL(for id: UUID) -> URL {
        assetsDirectory.appendingPathComponent("\(id.uuidString).fix.jpg")
    }

    /// Companion MOV for a Live Photo asset. Stored alongside the JPEG in the assets dir.
    static func liveMovieURL(for id: UUID) -> URL {
        assetsDirectory.appendingPathComponent("\(id.uuidString).mov")
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

    init(from asset: Asset) {
        id = asset.id.uuidString
        type = asset.type.rawValue
        capturedAt = asset.capturedAt.timeIntervalSince1970
        locationLat = asset.location?.latitude
        locationLon = asset.location?.longitude
        vibeTags = asset.vibeTags.map(\.rawValue)
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
            vibeTags: tags
        )
    }
}

// MARK: - AssetTypeSet helper

private extension AssetTypeSet {
    func containsAssetType(_ type: AssetType) -> Bool {
        switch type {
        case .still:      return contains(.still)
        case .live:       return contains(.live)
        case .clip:       return contains(.clip)
        case .echo:       return contains(.echo)
        case .atmosphere: return contains(.atmosphere)
        case .l4c:        return contains(.still)   // L4C composite stored as JPEG; query as .still bucket
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
}
