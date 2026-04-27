// NiftyCore/Sources/Domain/Protocols/PhotoLibraryExporterProtocol.swift
// Piqd v0.5 — drafts-tray "save" target. PRD FR-SNAP-DRAFT-06.
// Pure Swift — zero platform imports so tests can mock without Photos.framework.

import Foundation

/// Outcome of an export attempt. The UI uses `.permissionDenied` to surface a
/// "open Settings" affordance instead of a generic error toast.
public enum PhotoLibraryExportResult: Equatable, Sendable {
    case saved
    case permissionDenied
    case failed(reason: String)
}

public protocol PhotoLibraryExporterProtocol: Sendable {
    /// Save a vault file to the user's iOS Photos library. Lazily prompts for
    /// `.addOnly` authorization on first call. Always returns — never throws —
    /// so callers can branch on result without losing the URL/asset context.
    func exportToPhotos(_ url: URL, kind: AssetType) async -> PhotoLibraryExportResult
}
