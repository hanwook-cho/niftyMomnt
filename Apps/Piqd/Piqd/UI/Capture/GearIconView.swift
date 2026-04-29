// Apps/Piqd/Piqd/UI/Capture/GearIconView.swift
// Piqd v0.6 — Layer 1 gear icon. UIUX §8 (revised — see plan §7).
//
// Spec deviation: §8 placed the gear at top-LEFT (cy=87, x=44), but that
// position collided with the mode pill (HUD top-left, x=16..108) and the
// debug ladybug (top-left at safe-area+12). The drafts badge hit the same
// kind of conflict in v0.5 and was relocated bottom-left.
//
// Resolution: gear lives top-RIGHT, vertically stacked below the flip
// button inside `Layer1ChromeView`'s top-right slot. iOS-conventional
// (Settings/⚙ commonly anchors top-right) and clears both conflicts.

import SwiftUI

struct GearIconView: View {

    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .accessibilityIdentifier("piqd.layer1.gear")
        .accessibilityLabel("Settings menu")
    }
}
