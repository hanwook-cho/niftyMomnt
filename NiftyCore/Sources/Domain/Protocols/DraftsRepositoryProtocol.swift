// NiftyCore/Sources/Domain/Protocols/DraftsRepositoryProtocol.swift
// Piqd v0.5 — persistence seam for the drafts tray. PRD §5.5.
//
// The concrete GRDB-backed adapter lives in NiftyData. An in-memory adapter
// (also in NiftyData) is used by tests + by callers that need a zero-IO seam.

import Foundation

public protocol DraftsRepositoryProtocol: AnyObject, Sendable {
    /// Persist a draft row. Idempotent on `assetID` — a second call with the same
    /// `assetID` is a no-op. Roll-mode items are rejected (FR-SNAP-DRAFT-10).
    /// Returns `true` if a new row was written.
    @discardableResult
    func insert(_ item: DraftItem) async throws -> Bool

    /// All persisted drafts ordered by `capturedAt` ascending (oldest first).
    func all() async throws -> [DraftItem]

    /// Delete every row whose `expiresAt <= now`. Returns the asset IDs that
    /// were purged so the caller can cascade to vault + graph.
    @discardableResult
    func purgeExpired(now: Date) async throws -> [UUID]

    /// Explicit removal by asset id (used post-share-handoff if/when the user
    /// elects to discard the row in v0.6+; in v0.5 only the purger calls this).
    func remove(assetID: UUID) async throws
}
