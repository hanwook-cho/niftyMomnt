// NiftyCore/Sources/Domain/Models/LayerChromeState.swift
// Piqd v0.4 — Layer 1 chrome state. See PRD §5.4 (three-layer chrome system).
//
// Layer 0: rest — shutter + mode pill only.
// Layer 1: revealed by tap on viewfinder; auto-retreats after 3s idle.
// Layer 2: format selector — opened via swipe-up; pauses Layer 1 idle clock.

import Foundation

public enum LayerChromeState: String, CaseIterable, Sendable {
    case rest
    case revealed
    case formatSelector
}
