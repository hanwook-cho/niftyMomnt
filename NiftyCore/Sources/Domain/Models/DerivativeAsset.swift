// NiftyCore/Sources/Domain/Models/DerivativeAsset.swift
// Pure Swift — zero platform imports.

import Foundation

// MARK: - NormalizedRect

/// Coordinate space normalized to 0.0–1.0 relative to the source asset dimensions.
public struct NormalizedRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - DerivativeAsset

/// Represents the result of a Fix operation. The source original is never modified.
public struct DerivativeAsset: Equatable, Sendable {
    public let id: UUID
    public let sourceAssetID: UUID
    public let createdAt: Date
    public var cropRect: NormalizedRect?  // nil = no crop applied
    public var rotationDegrees: Int       // 0, 90, 180, 270 (clockwise)
    public var flipHorizontal: Bool
    public var flipVertical: Bool

    public init(
        id: UUID = UUID(),
        sourceAssetID: UUID,
        createdAt: Date = Date(),
        cropRect: NormalizedRect? = nil,
        rotationDegrees: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
    ) {
        self.id = id
        self.sourceAssetID = sourceAssetID
        self.createdAt = createdAt
        self.cropRect = cropRect
        self.rotationDegrees = rotationDegrees
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }
}
