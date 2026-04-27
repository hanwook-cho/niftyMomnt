// NiftyCore/Sources/Domain/DraftEnrollmentPolicy.swift
// Piqd v0.5 — single point of truth for "does this completed capture enroll
// in the drafts tray?". PRD FR-SNAP-DRAFT-01 + FR-SNAP-DRAFT-10.
// Pure Swift — zero platform imports.

import Foundation

public enum DraftEnrollmentPolicy {
    /// Snap captures land in the drafts tray; Roll captures bypass it because
    /// Roll has its own locked-vault lifecycle (9 PM unlock).
    public static func shouldEnroll(mode: CaptureMode) -> Bool {
        mode == .snap
    }
}
