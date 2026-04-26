// NiftyCore/Sources/Domain/Protocols/VibeClassifying.swift
// Piqd v0.4 — protocol seam for the scene/vibe classifier feeding the vibe hint glyph.
// See PRD §7.5 / SRS §4.3.4.
//
// Implementations own their own frame source (typically the AVCaptureVideoDataOutput
// sample-buffer stream); this protocol exposes only the lifecycle + the published signal.
// v0.4 ships `StubVibeClassifier` (NiftyData) returning `.quiet`. CoreML scene classifier
// is deferred — see piqd_interim_v0.4_plan.md §7.

import Foundation

public protocol VibeClassifying: AnyObject, Sendable {
    /// Begin sampling frames and publishing signals on `signals`. Idempotent.
    func start()

    /// Stop sampling. Used during Sequence/Clip/Dual recording windows. Idempotent.
    func stop()

    /// The most recently published signal. UI fallbacks read this on first appearance.
    func currentSignal() -> VibeSignal

    /// Async stream of signal changes. New subscribers receive subsequent emissions.
    var signals: AsyncStream<VibeSignal> { get }
}
