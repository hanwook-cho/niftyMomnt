// NiftyCore/Sources/Domain/Models/DraftItem.swift
// Piqd v0.5 — drafts tray entry. PRD §5.5 (FR-SNAP-DRAFT-01..10), SRS §3.3.
// Pure Swift — zero platform imports.

import Foundation

/// One row in the Snap-mode drafts tray. Roll Mode never produces `DraftItem`s
/// (FR-SNAP-DRAFT-10).
public struct DraftItem: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let assetID: UUID
    public let assetType: AssetType
    public let capturedAt: Date
    /// Hard expiry in hours from `capturedAt`. Snap default = 24 (FR-SNAP-DRAFT-02).
    public let hardCeilingHours: Int
    /// Always `.snap` in v0.5 — column reserved so v0.6+ can extend without a
    /// schema migration.
    public let mode: CaptureMode

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        assetType: AssetType,
        capturedAt: Date,
        hardCeilingHours: Int = 24,
        mode: CaptureMode = .snap
    ) {
        self.id = id
        self.assetID = assetID
        self.assetType = assetType
        self.capturedAt = capturedAt
        self.hardCeilingHours = hardCeilingHours
        self.mode = mode
    }

    /// Wall-clock instant the row crosses its hard ceiling.
    public var expiresAt: Date {
        capturedAt.addingTimeInterval(TimeInterval(hardCeilingHours) * 3600)
    }
}
