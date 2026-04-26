// NiftyCore/Sources/Domain/Models/ZoomLevel.swift
// Piqd v0.4 — discrete zoom levels surfaced by the zoom pill. See PRD §5.4 / FR-SNAP-ZOOM.
//
// All three are hardware-optical on iPhone 15+ rear camera (ultra-wide / wide / tele).
// Front camera is fixed focal length: only `.wide` is valid; pinch can digital-crop up to 2×
// but the pill renders only the 1× segment.

import Foundation

public enum ZoomLevel: String, CaseIterable, Sendable {
    case ultraWide
    case wide
    case telephoto

    public var factor: Double {
        switch self {
        case .ultraWide: return 0.5
        case .wide:      return 1.0
        case .telephoto: return 2.0
        }
    }

    /// Levels available for a given camera position. Front camera is `.wide` only.
    public static func available(for position: CameraPosition) -> [ZoomLevel] {
        switch position {
        case .back:  return [.ultraWide, .wide, .telephoto]
        case .front: return [.wide]
        }
    }
}

public enum CameraPosition: String, Sendable {
    case back
    case front
}
