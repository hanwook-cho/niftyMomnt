// NiftyCore/Sources/Domain/Models/MotionSample.swift
// Piqd v0.4 — domain model emitted by `MotionMonitor` (NiftyData) and consumed by
// `LevelIndicatorView` (Apps/Piqd). Roll is in degrees: 0 = phone level (long edge
// horizontal in portrait sense), positive = right side down. The level-line view fades
// in when |roll| > 3°. See piqd_UIUX_Spec_v1.0.md §2.10.

import Foundation

public struct MotionSample: Sendable, Equatable {
    public let rollDegrees: Double
    public let timestamp: Date

    public init(rollDegrees: Double, timestamp: Date) {
        self.rollDegrees = rollDegrees
        self.timestamp = timestamp
    }
}
