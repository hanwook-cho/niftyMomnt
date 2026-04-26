// NiftyCore/Sources/Domain/Models/VibeSignal.swift
// Piqd v0.4 — output of the scene classifier feeding the vibe hint glyph.
// See PRD §7.5 / SRS §4.3.4 (vibe hint, 2fps throttle).
//
// `social` triggers the glyph pulse. `quiet` and `neutral` keep the glyph hidden.
// v0.4 ships `StubVibeClassifier` always returning `.quiet`; CoreML deferred.

import Foundation

public enum VibeSignal: String, CaseIterable, Sendable {
    case quiet
    case neutral
    case social
}
