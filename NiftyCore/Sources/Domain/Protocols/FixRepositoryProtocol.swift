// NiftyCore/Sources/Domain/Protocols/FixRepositoryProtocol.swift

import Foundation

public protocol FixRepositoryProtocol: AnyObject, Sendable {
    /// Apply geometry corrections and write derivative to vault. Returns the new DerivativeAsset.
    func applyFix(
        to assetID: UUID,
        cropRect: NormalizedRect?,
        rotationDegrees: Int,
        flipH: Bool,
        flipV: Bool
    ) async throws -> DerivativeAsset

    /// Remove derivative and restore original as primary.
    func revertFix(for assetID: UUID) async throws

    /// Returns the current derivative for an asset, if one exists.
    func derivative(for assetID: UUID) async throws -> DerivativeAsset?
}
