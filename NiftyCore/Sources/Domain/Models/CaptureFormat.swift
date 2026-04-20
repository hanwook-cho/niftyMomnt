// NiftyCore/Sources/Domain/Models/CaptureFormat.swift
// Piqd v0.3 — Snap Mode format selector. Four formats cycle via the Layer 2 format pill:
// Still → Sequence → Clip → Dual. Persisted per-user as the last-used Snap format.
// Roll Mode ignores this enum (Roll is Still-only through v0.8; Roll Live Photo arrives in v0.9).

import Foundation

public enum CaptureFormat: String, CaseIterable, Sendable {
    case still
    case sequence
    case clip
    case dual

    /// One-to-one mapping onto the Asset type that a capture in this format produces.
    /// Every format maps to exactly one AssetType; sequence → sequence, etc.
    public var assetType: AssetType {
        switch self {
        case .still:    return .still
        case .sequence: return .sequence
        case .clip:     return .clip
        case .dual:     return .dual
        }
    }

    /// True when the format is a video recording (press-and-hold shutter, no photo output).
    public var isVideoRecording: Bool {
        switch self {
        case .still, .sequence: return false
        case .clip, .dual:      return true
        }
    }
}
