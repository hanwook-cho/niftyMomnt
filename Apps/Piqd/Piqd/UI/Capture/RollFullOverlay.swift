// Apps/Piqd/Piqd/UI/Capture/RollFullOverlay.swift
// Piqd v0.2 — overlay shown when the user attempts a Roll capture but the daily limit
// has already been reached. Locks the shutter, dims the viewfinder, and exposes a
// dismiss + "switch to Snap" affordance.

import SwiftUI

struct RollFullOverlay: View {

    let limit: Int
    let onDismiss: () -> Void
    let onSwitchToSnap: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Roll Full")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("You've used all \(limit) shots for today.\nCome back tomorrow, or switch to Snap.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Capsule().fill(.white.opacity(0.12)))
                    }
                    .accessibilityIdentifier("piqd-roll-full-dismiss")
                    Button(action: onSwitchToSnap) {
                        Text("Switch to Snap")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Capsule().fill(.yellow))
                    }
                    .accessibilityIdentifier("piqd-roll-full-switch")
                }
                .padding(.top, 6)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("piqd-roll-full-overlay")
    }
}
