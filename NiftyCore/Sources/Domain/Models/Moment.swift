// NiftyCore/Sources/Domain/Models/Moment.swift
// Pure Swift — zero platform imports.

import Foundation

public struct Moment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var label: String              // e.g. "Rainy Walk · Siena · Tuesday"
    public var assets: [Asset]
    public var centroid: GPSCoordinate
    public var startTime: Date
    public var endTime: Date
    public var dominantVibes: [VibeTag]
    public var moodPoint: MoodPoint?
    public var isStarred: Bool
    public var heroAssetID: UUID?
    public var selectedPresetName: String? // v0.4: user-chosen preset at capture time

    public init(
        id: UUID = UUID(),
        label: String,
        assets: [Asset] = [],
        centroid: GPSCoordinate,
        startTime: Date,
        endTime: Date,
        dominantVibes: [VibeTag] = [],
        moodPoint: MoodPoint? = nil,
        isStarred: Bool = false,
        heroAssetID: UUID? = nil,
        selectedPresetName: String? = nil
    ) {
        self.id = id
        self.label = label
        self.assets = assets
        self.centroid = centroid
        self.startTime = startTime
        self.endTime = endTime
        self.dominantVibes = dominantVibes
        self.moodPoint = moodPoint
        self.isStarred = isStarred
        self.heroAssetID = heroAssetID
        self.selectedPresetName = selectedPresetName
    }
}
