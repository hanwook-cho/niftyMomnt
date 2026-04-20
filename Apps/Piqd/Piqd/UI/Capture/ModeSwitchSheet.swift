// Apps/Piqd/Piqd/UI/Capture/ModeSwitchSheet.swift
// Piqd v0.2 — confirmation sheet shown after long-press on the mode pill. Two big
// segments (SNAP, ROLL) with brief one-line explainers. Tapping a segment commits the
// switch via ModeStore and dismisses; cancel dismisses without changing mode.

import SwiftUI
import NiftyCore

struct ModeSwitchSheet: View {

    let current: CaptureMode
    let onSelect: (CaptureMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(width: 44, height: 4)
                .padding(.top, 8)

            Text("Choose Mode")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityIdentifier("piqd-mode-sheet")

            VStack(spacing: 12) {
                segment(.snap,
                        title: "SNAP",
                        subtitle: "Reactive · share now · ephemeral",
                        accent: .yellow)
                segment(.roll,
                        title: "ROLL",
                        subtitle: "Slow film · 24/day · revealed at 9 PM",
                        accent: Color(red: 0.95, green: 0.75, blue: 0.35))
            }
            .padding(.horizontal, 16)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .accessibilityIdentifier("piqd-mode-sheet-cancel")
            .padding(.bottom, 8)
        }
        .padding(.bottom, 20)
        .background(Color.black)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func segment(_ mode: CaptureMode, title: String, subtitle: String, accent: Color) -> some View {
        let isCurrent = mode == current
        Button { onSelect(mode) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(accent)
                            .tracking(1.5)
                        if isCurrent {
                            Text("· current")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrent ? accent.opacity(0.15) : .white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isCurrent ? accent.opacity(0.6) : .white.opacity(0.1), lineWidth: 1)
            )
        }
        .accessibilityIdentifier("piqd-mode-sheet-\(mode.rawValue)")
    }
}
