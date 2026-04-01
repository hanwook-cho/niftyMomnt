// NiftyData/Sources/Repositories/VaultRepository.swift
// Implements VaultProtocol. FileManager + CoreData backend.

import Combine
import Foundation
import NiftyCore

public actor VaultRepository: VaultProtocol {
    private let config: AppConfig
    nonisolated(unsafe) private let storageSubject = CurrentValueSubject<Int64, Never>(0)

    public init(config: AppConfig) {
        self.config = config
    }

    public nonisolated var storageUsedBytes: AnyPublisher<Int64, Never> {
        storageSubject.eraseToAnyPublisher()
    }

    public func save(_ asset: Asset, data: Data) async throws {
        // TODO: AES-256-GCM encrypt with per-asset DEK, write to sandbox
    }

    public func saveDerivative(_ derivative: DerivativeAsset, data: Data, sourceAssetID: UUID) async throws {
        // TODO: encrypt with same DEK as source, write {uuid}.still.fix.enc
    }

    public func load(_ assetID: UUID) async throws -> (Asset, Data) {
        throw VaultError.notFound
    }

    public func loadPrimary(_ assetID: UUID) async throws -> (Asset, Data) {
        // Returns derivative if one exists, else original
        throw VaultError.notFound
    }

    public func deleteDerivative(for assetID: UUID) async throws {
        // TODO: delete derivative file and DEK reference
    }

    public func delete(_ assetID: UUID) async throws {
        // TODO
    }

    public func query(_ query: VaultQuery) async throws -> [Asset] {
        return []
    }

    public func exportToPhotoLibrary(_ assetID: UUID) async throws {
        // TODO: PHPhotoLibrary.shared().performChanges
    }
}

public enum VaultError: Error {
    case notFound
    case encryptionFailed
    case decryptionFailed
}
