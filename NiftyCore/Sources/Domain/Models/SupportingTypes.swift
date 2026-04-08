// NiftyCore/Sources/Domain/Models/SupportingTypes.swift
// Pure Swift — zero platform imports.

import Foundation

// MARK: - VibeTag

public enum VibeTag: String, CaseIterable, Sendable {
    case golden, moody, serene, electric, nostalgic, raw, dreamy, cozy
}

// MARK: - VibePreset

public struct VibePreset: Equatable, Sendable {
    public let name: String
    public let accentColorHex: String
    public init(name: String, accentColorHex: String) {
        self.name = name
        self.accentColorHex = accentColorHex
    }
}

// MARK: - AcousticTagType

public enum AcousticTagType: String, CaseIterable, Sendable {
    case windy, crowded, music, quiet, serene, rain, ocean, water
}

// MARK: - AcousticSource

public enum AcousticSource: String, Sendable {
    case soundStamp, echo, clip, atmosphere
}

// MARK: - AcousticTag

public struct AcousticTag: Equatable, Sendable {
    public let tag: AcousticTagType
    public let source: AcousticSource
    public let confidence: Float  // 0.0–1.0

    public init(tag: AcousticTagType, source: AcousticSource, confidence: Float) {
        self.tag = tag
        self.source = source
        self.confidence = confidence
    }
}

// MARK: - ChromaticPalette

public struct ChromaticPalette: Equatable, Sendable {
    /// Up to 5 HSL colors
    public let colors: [HSLColor]
    public init(colors: [HSLColor]) { self.colors = colors }
}

public struct HSLColor: Equatable, Sendable {
    public let hue: Double        // 0–360
    public let saturation: Double // 0–1
    public let lightness: Double  // 0–1
    public init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }
}

// MARK: - AmbientMetadata

public struct AmbientMetadata: Equatable, Sendable {
    public var weather: WeatherCondition?
    public var temperatureC: Double?
    public var elevationM: Double?
    public var sunPosition: SunPosition?
    public var nowPlayingTrack: String?
    public var nowPlayingArtist: String?
    public init() {}
}

public enum WeatherCondition: String, Sendable {
    case clear, cloudy, rain, snow, fog, thunder
}

public enum SunPosition: String, Sendable {
    case sunrise, morning, midday, afternoon, sunset, night
}

// MARK: - AssetScore

public struct AssetScore: Equatable, Sendable {
    public let motionInterest: Double    // weight 0.30
    public let vibeCoherence: Double    // weight 0.30
    public let chromaticHarmony: Double // weight 0.20
    public let uniqueness: Double       // weight 0.20

    public var composite: Double {
        (motionInterest + vibeCoherence + chromaticHarmony + uniqueness) / 4
    }

    public init(motionInterest: Double, vibeCoherence: Double, chromaticHarmony: Double, uniqueness: Double) {
        self.motionInterest = motionInterest
        self.vibeCoherence = vibeCoherence
        self.chromaticHarmony = chromaticHarmony
        self.uniqueness = uniqueness
    }
}

// MARK: - Intelligence Graph Models

public struct PlaceRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let placeName: String
    public let coordinate: GPSCoordinate
    public var visitCount: Int
    public var totalDwellMins: Int
    public var firstVisit: Date
    public var lastVisit: Date
    public var dominantVibes: [VibeTag]

    public init(id: UUID = UUID(), placeName: String, coordinate: GPSCoordinate,
                visitCount: Int, totalDwellMins: Int, firstVisit: Date, lastVisit: Date,
                dominantVibes: [VibeTag] = []) {
        self.id = id
        self.placeName = placeName
        self.coordinate = coordinate
        self.visitCount = visitCount
        self.totalDwellMins = totalDwellMins
        self.firstVisit = firstVisit
        self.lastVisit = lastVisit
        self.dominantVibes = dominantVibes
    }
}

public enum MoodTag: String, CaseIterable, Sendable {
    case joyful, calm, melancholy, energetic, reflective, anxious, content
}

public struct EmotionColor: Equatable, Sendable {
    public let hex: String
    public let emotion: MoodTag
    public init(hex: String, emotion: MoodTag) { self.hex = hex; self.emotion = emotion }
}

public struct MoodPoint: Equatable, Sendable {
    public let momentID: UUID
    public let coordinate: GPSCoordinate
    public let dominantMood: MoodTag
    public let palette: [EmotionColor]
    public init(momentID: UUID, coordinate: GPSCoordinate, dominantMood: MoodTag, palette: [EmotionColor]) {
        self.momentID = momentID
        self.coordinate = coordinate
        self.dominantMood = dominantMood
        self.palette = palette
    }
}

// MARK: - Nudge Models

public struct NudgeCard: Identifiable, Sendable {
    public let id: UUID
    public let question: String
    public let momentID: UUID
    public init(id: UUID = UUID(), question: String, momentID: UUID) {
        self.id = id
        self.question = question
        self.momentID = momentID
    }
}

public struct NudgeResponse: Sendable {
    public let nudgeID: UUID
    public let responseType: String
    public let responseValue: String
    public let timestamp: Date
    public init(nudgeID: UUID, responseType: String, responseValue: String, timestamp: Date = Date()) {
        self.nudgeID = nudgeID
        self.responseType = responseType
        self.responseValue = responseValue
        self.timestamp = timestamp
    }
}

public struct NudgeTrigger: Sendable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

// MARK: - Lab Models

public struct LabSession: Sendable {
    public let id: UUID
    public let assetIDs: [UUID]
    public init(id: UUID = UUID(), assetIDs: [UUID]) { self.id = id; self.assetIDs = assetIDs }
}

public struct LabConsent: Sendable {
    public let accepted: Bool
    public let timestamp: Date
    public init(accepted: Bool, timestamp: Date = Date()) { self.accepted = accepted; self.timestamp = timestamp }
}

public struct LabResult: Sendable {
    public let sessionID: UUID
    public let captions: [CaptionCandidate]
    public init(sessionID: UUID, captions: [CaptionCandidate]) { self.sessionID = sessionID; self.captions = captions }
}

public struct PurgeConfirmation: Sendable {
    public let sessionID: UUID
    public let confirmedAt: Date
    public init(sessionID: UUID, confirmedAt: Date = Date()) { self.sessionID = sessionID; self.confirmedAt = confirmedAt }
}

public struct CaptionCandidate: Sendable {
    public let text: String
    public let tone: CaptionTone
    public init(text: String, tone: CaptionTone) { self.text = text; self.tone = tone }
}

public enum CaptionTone: String, CaseIterable, Sendable {
    case poetic, minimal, descriptive, conversational
}

public struct ProseVariant: Sendable {
    public let text: String
    public let style: ProseStyle
    public init(text: String, style: ProseStyle) { self.text = text; self.style = style }
}

public enum ProseStyle: String, CaseIterable, Sendable {
    case journal, haiku, bullet, narrative
}

// MARK: - Graph Export

public struct GraphExport: Sendable {
    public let moments: [Moment]
    public let placeHistory: [PlaceRecord]
    public let moodMap: [MoodPoint]
    public init(moments: [Moment], placeHistory: [PlaceRecord], moodMap: [MoodPoint]) {
        self.moments = moments
        self.placeHistory = placeHistory
        self.moodMap = moodMap
    }
}

// MARK: - VaultQuery

public struct VaultQuery: Sendable {
    public var assetTypes: AssetTypeSet
    public var dateRange: ClosedRange<Date>?
    public var limit: Int?
    public var offset: Int
    public init(assetTypes: AssetTypeSet = .all, dateRange: ClosedRange<Date>? = nil, limit: Int? = nil, offset: Int = 0) {
        self.assetTypes = assetTypes
        self.dateRange = dateRange
        self.limit = limit
        self.offset = offset
    }
}

// MARK: - GraphQuery

public struct GraphQuery: Sendable {
    public var dateRange: ClosedRange<Date>?
    public var vibeFilter: [VibeTag]
    public var limit: Int?
    public init(dateRange: ClosedRange<Date>? = nil, vibeFilter: [VibeTag] = [], limit: Int? = nil) {
        self.dateRange = dateRange
        self.vibeFilter = vibeFilter
        self.limit = limit
    }
}

// MARK: - Capture State / Telemetry

public enum CaptureState: Sendable {
    case idle
    case ready(mode: CaptureMode)
    case capturing(mode: CaptureMode)
    case processing
    case error(CaptureError)
}

public enum CaptureError: Error, Sendable {
    case sessionFailed
    case captureFailed
    case modeSwitchFailed
    case unauthorized
}

public struct CaptureTelemetry: Sendable {
    public let mode: CaptureMode
    public let elapsed: TimeInterval
    public let ceiling: TimeInterval
    public let isWarning: Bool      // elapsed >= ceiling - 5.0
    public let audioLevel: Float?   // Echo only: 0.0–1.0
    public init(mode: CaptureMode, elapsed: TimeInterval, ceiling: TimeInterval, audioLevel: Float? = nil) {
        self.mode = mode
        self.elapsed = elapsed
        self.ceiling = ceiling
        self.isWarning = elapsed >= ceiling - 5.0
        self.audioLevel = audioLevel
    }
}

// MARK: - Reel / Story

public struct ReelAsset: Sendable {
    public let asset: Asset
    public let score: AssetScore
    public init(asset: Asset, score: AssetScore) { self.asset = asset; self.score = score }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted by CaptureMomentUseCase after a Moment is saved to the graph.
    /// Object: nil. Observers should re-fetch moments from GraphManager.
    static let niftyMomentCaptured = Notification.Name("com.hwcho99.niftymomnt.momentCaptured")
    /// Posted after a Moment is deleted from the graph and its assets removed from the vault.
    /// Object: nil. Observers should re-fetch moments from GraphManager.
    static let niftyMomentDeleted = Notification.Name("com.hwcho99.niftymomnt.momentDeleted")
}

// MARK: - MomentCluster

public struct MomentCluster: Sendable {
    public let assets: [Asset]
    public let centroid: GPSCoordinate
    public let startTime: Date
    public let endTime: Date
    public init(assets: [Asset], centroid: GPSCoordinate, startTime: Date, endTime: Date) {
        self.assets = assets
        self.centroid = centroid
        self.startTime = startTime
        self.endTime = endTime
    }
}
