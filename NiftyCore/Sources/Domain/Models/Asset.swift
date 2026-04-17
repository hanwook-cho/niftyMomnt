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
    case l4c        // niftyMomnt — Life Four Cuts composite strip
    // Piqd additions — SRS §3.1
    case sequence      // 6-frame strip assembled into looping MP4
    case movingStill   // Live Photo with background-warped MP4 (v2.0 Piqd)
    case dual          // simultaneous front+rear composite MP4
}

// MARK: - CaptureMode

public enum CaptureMode: String, CaseIterable, Sendable {
    case still
    case live
    case clip
    case echo
    case atmosphere
    case photoBooth  // Life Four Cuts photo-booth mode
    // Piqd additions
    case snap        // Piqd Snap Mode — reactive/ephemeral
    case roll        // Piqd Roll Mode — delayed 9 PM ritual
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
    public var selectedPresetName: String? // v0.4: user-chosen preset name at capture time
    public var isPrivate: Bool             // v0.8: true when asset is in the private vault

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
        derivative: DerivativeAsset? = nil,
        selectedPresetName: String? = nil,
        isPrivate: Bool = false
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
        self.selectedPresetName = selectedPresetName
        self.isPrivate = isPrivate
    }
}
