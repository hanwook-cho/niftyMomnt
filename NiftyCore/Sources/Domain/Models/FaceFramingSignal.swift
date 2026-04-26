// NiftyCore/Sources/Domain/Models/FaceFramingSignal.swift
// Piqd v0.4 — output of subject guidance face detection.
// See PRD §7.3 / SRS §4.3.4 / UIUX §2.11 ("Step back for the full vibe", 1.5s, 10s cooldown).
//
// `ok`: no detected face is within 15% of any frame edge (no guidance needed).
// `edgeProximity`: at least one face is too close to an edge — surface the guidance pill.

import Foundation

public enum FaceFramingSignal: Equatable, Sendable {
    case ok
    case edgeProximity(side: FrameEdge)
}

public enum FrameEdge: String, CaseIterable, Sendable {
    case top
    case bottom
    case leading
    case trailing
}
