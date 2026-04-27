// NiftyCore/Sources/Domain/DraftExpiryEvaluator.swift
// Piqd v0.5 — pure threshold logic for the drafts tray's per-row timer label and
// the Layer 1 unsent-badge urgency tint. PRD §5.5 FR-SNAP-DRAFT-05, UIUX §2.8 + §2.14.
// Pure Swift — zero platform imports.

import Foundation

/// Per-row display state derived from a `DraftItem`'s remaining time.
///
/// Thresholds (FR-SNAP-DRAFT-05):
/// - `>3h remaining`     → `.hidden` (no timer text rendered)
/// - `1h ≤ x ≤ 3h`       → `.normal`  ("Xh Ym left", labelSecondary)
/// - `15min ≤ x < 1h`    → `.amber`   ("Xm left", PiqdTokens.Color.rollAmber)
/// - `0 < x < 15min`     → `.red`     ("Xm left", PiqdTokens.Color.recordRed)
/// - `x ≤ 0`             → `.expired` (caller should purge the row)
public enum DraftExpiryState: Equatable, Sendable {
    case hidden(remaining: TimeInterval)
    case normal(remaining: TimeInterval)
    case amber(remaining: TimeInterval)
    case red(remaining: TimeInterval)
    case expired
}

/// Aggregate badge state for the Layer 1 unsent badge.
public enum DraftBadgeState: Equatable, Sendable {
    case hidden
    case normal(count: Int)
    case urgent(count: Int)   // any draft is < 1h remaining
}

public enum DraftExpiryEvaluator {

    public static let amberThreshold: TimeInterval = 3600          // 1h
    public static let redThreshold:   TimeInterval = 15 * 60       // 15min
    public static let hiddenThreshold: TimeInterval = 3 * 3600     // 3h

    /// Maps `(capturedAt, now, ceilingHours)` to the per-row display state.
    public static func evaluate(
        capturedAt: Date,
        now: Date,
        hardCeilingHours: Int = 24
    ) -> DraftExpiryState {
        let expiresAt = capturedAt.addingTimeInterval(TimeInterval(hardCeilingHours) * 3600)
        let remaining = expiresAt.timeIntervalSince(now)

        if remaining <= 0 { return .expired }
        if remaining < redThreshold     { return .red(remaining: remaining) }
        if remaining < amberThreshold   { return .amber(remaining: remaining) }
        if remaining <= hiddenThreshold { return .normal(remaining: remaining) }
        return .hidden(remaining: remaining)
    }

    /// Aggregate the badge state from a slice of items + `now`. Urgency is the
    /// max of all per-row states: any item < 1h remaining promotes the badge to
    /// `.urgent` (UIUX §2.8).
    public static func badgeState(items: [DraftItem], now: Date) -> DraftBadgeState {
        let live = items.filter { evaluate(capturedAt: $0.capturedAt,
                                           now: now,
                                           hardCeilingHours: $0.hardCeilingHours) != .expired }
        if live.isEmpty { return .hidden }

        let anyUrgent = live.contains { item in
            switch evaluate(capturedAt: item.capturedAt,
                            now: now,
                            hardCeilingHours: item.hardCeilingHours) {
            case .amber, .red: return true
            case .hidden, .normal, .expired: return false
            }
        }
        return anyUrgent ? .urgent(count: live.count) : .normal(count: live.count)
    }
}
