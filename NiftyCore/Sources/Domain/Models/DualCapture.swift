// NiftyCore/Sources/Domain/Models/DualCapture.swift
// Piqd v0.3 — Dual format extension. Dual is a *format* (one of four pill segments) plus
// two orthogonal axes the format alone doesn't capture:
//   1. media kind — Still vs Video, chosen via a sub-toggle when Dual is active
//   2. layout — how the two camera frames compose into one asset (PIP / top-bottom /
//      side-by-side), chosen in dev settings and shared by Still and Video output

import Foundation

public enum DualMediaKind: String, CaseIterable, Sendable {
    case still
    case video
}

public enum DualLayout: String, CaseIterable, Sendable {
    /// Rear full-frame, front inset top-right (current Dual Video default).
    case pip
    /// Rear top half, front bottom half — BeReal style.
    case topBottom
    /// Rear left half, front right half.
    case sideBySide
}
