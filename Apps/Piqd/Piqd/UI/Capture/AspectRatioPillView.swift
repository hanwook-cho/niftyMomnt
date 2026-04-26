// Apps/Piqd/Piqd/UI/Capture/AspectRatioPillView.swift
// Piqd v0.4 — aspect-ratio pill (9:16 ↔ 1:1). See PRD §5.4 / FR-SNAP-RATIO-01..04 and
// UIUX §2.5. Sits beside the zoom pill in Layer 1's bottom-center slot.
// FR-SNAP-RATIO-04: Sequence/Clip/Dual force 9:16; pill greys at 50% opacity and is
// non-interactive. v0.4 ships Still-only ratio cycling — non-Still formats stay 9:16.

import NiftyCore
import SwiftUI

struct AspectRatioPillView: View {

    let current: AspectRatio
    /// True when format is Sequence (or Clip/Dual once we extend) — pill greys + non-interactive.
    let isLocked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(PiqdTokens.Color.snapChrome)
                .frame(minWidth: 44)
                .padding(.horizontal, PiqdTokens.Spacing.sm)
                .padding(.vertical, PiqdTokens.Spacing.xs)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: PiqdTokens.Shape.pillRadius)
                        .fill(.ultraThinMaterial)
                )
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.5 : 1.0)
        .allowsHitTesting(!isLocked)
        .accessibilityIdentifier("piqd.ratioPill")
        .accessibilityValue(label)
    }

    private var label: String {
        switch current {
        case .nineSixteen: return "9:16"
        case .oneOne:      return "1:1"
        case .fourThree:   return "4:3"
        }
    }
}
