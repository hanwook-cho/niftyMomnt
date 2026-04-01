// NiftyCore/Sources/Domain/UseCases/FixAssetUseCase.swift
// Nonisolated — coordinates between VaultManager and GraphManager actors.

import Foundation

public final class FixAssetUseCase: Sendable {
    private let fixRepo: any FixRepositoryProtocol
    private let vault: VaultManager
    private let graph: GraphManager

    public init(fixRepo: any FixRepositoryProtocol, vault: VaultManager, graph: GraphManager) {
        self.fixRepo = fixRepo
        self.vault = vault
        self.graph = graph
    }

    public func applyFix(
        to assetID: UUID,
        cropRect: NormalizedRect?,
        rotationDegrees: Int,
        flipH: Bool,
        flipV: Bool
    ) async throws -> DerivativeAsset {
        let derivative = try await fixRepo.applyFix(
            to: assetID,
            cropRect: cropRect,
            rotationDegrees: rotationDegrees,
            flipH: flipH,
            flipV: flipV
        )
        try await graph.saveDerivativeRecord(derivative)
        return derivative
    }

    public func revertFix(for assetID: UUID) async throws {
        try await fixRepo.revertFix(for: assetID)
        try await graph.deleteDerivativeRecord(for: assetID)
    }
}
