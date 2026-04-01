// NiftyData/Sources/Platform/CoreImageFixAdapter.swift
// Core Image / Metal for crop/rotate/flip. Never imports UIKit.

import CoreImage
import Foundation
import Metal
import NiftyCore

public final class CoreImageFixAdapter: FixRepositoryProtocol, Sendable {
    private let vault: any VaultProtocol

    public init(config: AppConfig, vault: any VaultProtocol) {
        self.vault = vault
    }

    public func applyFix(
        to assetID: UUID,
        cropRect: NormalizedRect?,
        rotationDegrees: Int,
        flipH: Bool,
        flipV: Bool
    ) async throws -> DerivativeAsset {
        // TODO: load original from vault
        // TODO: CIImage transform: crop, rotate, flip
        // TODO: render via Metal, write encrypted derivative
        let derivative = DerivativeAsset(
            sourceAssetID: assetID,
            cropRect: cropRect,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipH,
            flipVertical: flipV
        )
        return derivative
    }

    public func revertFix(for assetID: UUID) async throws {
        try await vault.deleteDerivative(for: assetID)
    }

    public func derivative(for assetID: UUID) async throws -> DerivativeAsset? {
        return nil
    }
}
