// NiftyCore/Sources/Domain/Protocols/VaultProtocol.swift

import Combine
import Foundation

public protocol VaultProtocol: AnyObject, Sendable {
    func save(_ asset: Asset, data: Data) async throws
    /// Piqd v0.2 — save with explicit container extension (e.g. "heic") and Roll-mode
    /// locked routing. Adopters that do not distinguish (test mocks, niftyMomnt legacy)
    /// may forward to the default `save(_:data:)`.
    func save(_ asset: Asset, data: Data, fileExtension: String?, locked: Bool) async throws
    /// Moves a video file from sourceURL into the vault without loading it into memory.
    func saveVideoFile(_ asset: Asset, sourceURL: URL) async throws
    /// Moves an audio file from sourceURL into the vault without loading it into memory.
    func saveAudioFile(_ asset: Asset, sourceURL: URL) async throws
    /// Moves a Live Photo companion MOV from sourceURL into the vault alongside its JPEG.
    /// The metadata sidecar is NOT re-written — call this after `save(_:data:)` for the JPEG.
    func saveLiveMovieFile(_ asset: Asset, sourceURL: URL) async throws
    func saveDerivative(_ derivative: DerivativeAsset, data: Data, sourceAssetID: UUID) async throws
    func load(_ assetID: UUID) async throws -> (Asset, Data)
    /// Returns derivative if one exists, else returns original.
    func loadPrimary(_ assetID: UUID) async throws -> (Asset, Data)
    func deleteDerivative(for assetID: UUID) async throws
    func delete(_ assetID: UUID) async throws
    func query(_ query: VaultQuery) async throws -> [Asset]
    func exportToPhotoLibrary(_ assetID: UUID) async throws
    var storageUsedBytes: AnyPublisher<Int64, Never> { get }
    // MARK: v0.8
    /// Encrypts the asset file in-place (AES-GCM) and marks the sidecar as private.
    /// After this call the asset's data is only accessible via `load(_:)` / `loadPrimary(_:)`.
    func moveToVault(assetID: UUID) async throws
}

public extension VaultProtocol {
    /// Default forwards to `save(_:data:)` — concrete Piqd adapters override to honor
    /// `fileExtension` and `locked`.
    func save(_ asset: Asset, data: Data, fileExtension: String?, locked: Bool) async throws {
        try await save(asset, data: data)
    }
}
