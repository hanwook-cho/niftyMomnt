// NiftyCore/Sources/Domain/Models/L4CRecord.swift
// Life Four Cuts — domain models. Pure Swift, zero platform imports.

import Foundation

// MARK: - L4CRecord

/// A completed photo-booth session: 4 source stills + one composite strip asset.
public struct L4CRecord: Identifiable, Equatable, Sendable {
    public let id: UUID               // = composite asset ID (stored as AssetType.l4c)
    public let sourceAssetIDs: [UUID] // exactly 4, capture order
    public let frameID: String        // bundle PNG asset name, or "none"
    public let borderColor: L4CBorderColor
    public let capturedAt: Date
    public let location: GPSCoordinate?
    public let label: String          // place name or date fallback

    public init(
        id: UUID = UUID(),
        sourceAssetIDs: [UUID],
        frameID: String,
        borderColor: L4CBorderColor,
        capturedAt: Date,
        location: GPSCoordinate? = nil,
        label: String
    ) {
        precondition(sourceAssetIDs.count == 4, "L4CRecord requires exactly 4 source asset IDs")
        self.id = id
        self.sourceAssetIDs = sourceAssetIDs
        self.frameID = frameID
        self.borderColor = borderColor
        self.capturedAt = capturedAt
        self.location = location
        self.label = label
    }
}

// MARK: - L4CBorderColor

public enum L4CBorderColor: String, CaseIterable, Sendable {
    case white
    case black
    case pastelPink
    case skyBlue
}

// MARK: - L4CStampConfig

public struct L4CStampConfig: Sendable {
    public let dateText: String       // e.g. "Apr 7 · 2026"
    public let locationText: String   // place name, or empty
    public let showAppLogo: Bool

    public init(dateText: String, locationText: String, showAppLogo: Bool = true) {
        self.dateText = dateText
        self.locationText = locationText
        self.showAppLogo = showAppLogo
    }
}

// MARK: - FeaturedFrame

/// A PNG "window" frame that composites on top of the 4-photo strip.
/// The PNG has alpha=0 in the 4 photo slots and artwork everywhere else.
public struct FeaturedFrame: Identifiable, Equatable, Sendable {
    public let id: String            // matches PNG asset name in app bundle
    public let displayName: String   // shown in the carousel
    public let previewColorHex: String // carousel cell background before PNG loads

    public init(id: String, displayName: String, previewColorHex: String) {
        self.id = id
        self.displayName = displayName
        self.previewColorHex = previewColorHex
    }
}

// MARK: - Built-in frames

public extension FeaturedFrame {
    static let none = FeaturedFrame(id: "none", displayName: "None", previewColorHex: "#FFFFFF")
    static let minimalistBlack = FeaturedFrame(id: "frame_minimalist_black", displayName: "Minimalist", previewColorHex: "#111111")
    static let springBlossom   = FeaturedFrame(id: "frame_spring_blossom",   displayName: "Blossom",    previewColorHex: "#FFD6E0")
    static let retroNeon       = FeaturedFrame(id: "frame_retro_neon",        displayName: "Retro Neon", previewColorHex: "#0D0D1A")

    static let allCases: [FeaturedFrame] = [.none, .minimalistBlack, .springBlossom, .retroNeon]
}
