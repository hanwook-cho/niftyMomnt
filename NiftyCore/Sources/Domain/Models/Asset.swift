// NiftyCore/Sources/Domain/Models/Asset.swift
// Pure Swift — zero platform imports.

import Foundation

// MARK: - AssetType

public enum AssetType: String, CaseIterable, Sendable {
    case still
    case live
    case clip
    case echo
    case atmosphere
    case l4c        // Life Four Cuts composite strip
}

// MARK: - CaptureMode

public enum CaptureMode: String, CaseIterable, Sendable {
    case still
    case live
    case clip
    case echo
    case atmosphere
    case photoBooth  // Life Four Cuts photo-booth mode
}

// MARK: - GPSCoordinate

public struct GPSCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Asset

public struct Asset: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let type: AssetType
    public let capturedAt: Date
    public let location: GPSCoordinate?
    public var vibeTags: [VibeTag]
    public var acousticTags: [AcousticTag]
    public var palette: ChromaticPalette?
    public var ambient: AmbientMetadata
    public var transcript: String?        // Echo only
    public var score: AssetScore?         // Set by StoryEngine
    public var duration: TimeInterval?    // Clip / Echo / Atmosphere
    public var derivative: DerivativeAsset? // Set by Fix — nil if no fix applied

    public init(
        id: UUID = UUID(),
        type: AssetType,
        capturedAt: Date,
        location: GPSCoordinate? = nil,
        vibeTags: [VibeTag] = [],
        acousticTags: [AcousticTag] = [],
        palette: ChromaticPalette? = nil,
        ambient: AmbientMetadata = AmbientMetadata(),
        transcript: String? = nil,
        score: AssetScore? = nil,
        duration: TimeInterval? = nil,
        derivative: DerivativeAsset? = nil
    ) {
        self.id = id
        self.type = type
        self.capturedAt = capturedAt
        self.location = location
        self.vibeTags = vibeTags
        self.acousticTags = acousticTags
        self.palette = palette
        self.ambient = ambient
        self.transcript = transcript
        self.score = score
        self.duration = duration
        self.derivative = derivative
    }
}
