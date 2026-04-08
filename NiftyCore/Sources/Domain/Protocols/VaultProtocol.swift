// NiftyCore/Sources/Domain/Protocols/VaultProtocol.swift

import Combine
import Foundation

public protocol VaultProtocol: AnyObject, Sendable {
    func save(_ asset: Asset, data: Data) async throws
    /// Moves a video file from sourceURL into the vault without loading it into memory.
    func saveVideoFile(_ asset: Asset, sourceURL: URL) async throws
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
}
