// Apps/Piqd/Piqd/UI/Capture/UnsentBadgeView.swift
// Piqd v0.5 — Layer 1 unsent badge. PRD FR-SNAP-DRAFT-03, UIUX §2.8.
//
// Sits left of the mode pill. Hidden when count = 0 or in Roll Mode (Roll has
// no drafts concept). Tap opens the drafts tray sheet via the closure.
// Urgent state (any draft <1h remaining) tints the background recordRed @ 60%.

import NiftyCore
import SwiftUI

struct UnsentBadgeView: View {

    let state: DraftBadgeState
    let onTap: () -> Void

    var body: some View {
        if case .hidden = state {
            EmptyView()
        } else {
            Button(action: onTap) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(textColor)
                    .padding(.horizontal, PiqdTokens.Spacing.sm)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: PiqdTokens.Shape.pillRadius)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PiqdTokens.Shape.pillRadius)
                            .fill(urgentTint)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("piqd.draftsBadge")
            .accessibilityValue(label)
        }
    }

    private var label: String {
        switch state {
        case .hidden:               return ""
        case .normal(let count):    return "\(count) unsent"
        case .urgent(let count):    return "\(count) unsent"
        }
    }

    private var textColor: Color {
        switch state {
        case .urgent: return .white
        default:      return PiqdTokens.Color.snapChrome
        }
    }

    /// Material + tint compose to give a subtle recordRed wash without losing the
    /// glass effect (UIUX §2.8 "60% opacity").
    private var urgentTint: Color {
        switch state {
        case .urgent: return PiqdTokens.Color.recordRed.opacity(0.6)
        default:      return Color.clear
        }
    }
}
