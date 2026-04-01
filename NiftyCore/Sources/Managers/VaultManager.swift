// NiftyCore/Sources/Managers/VaultManager.swift
// actor — serialises all vault reads and writes.

import Foundation

public actor VaultManager {
    private let vault: any VaultProtocol

    public init(vault: any VaultProtocol) {
        self.vault = vault
    }

    public func save(_ asset: Asset, data: Data) async throws {
        try await vault.save(asset, data: data)
    }

    public func saveDerivative(_ derivative: DerivativeAsset, data: Data, sourceAssetID: UUID) async throws {
        try await vault.saveDerivative(derivative, data: data, sourceAssetID: sourceAssetID)
    }

    public func loadPrimary(_ assetID: UUID) async throws -> (Asset, Data) {
        try await vault.loadPrimary(assetID)
    }

    public func deleteDerivative(for assetID: UUID) async throws {
        try await vault.deleteDerivative(for: assetID)
    }

    public func delete(_ assetID: UUID) async throws {
        try await vault.delete(assetID)
    }

    public func query(_ query: VaultQuery) async throws -> [Asset] {
        try await vault.query(query)
    }

    public func exportToPhotoLibrary(assetID: UUID) async throws {
        try await vault.exportToPhotoLibrary(assetID)
    }
}
