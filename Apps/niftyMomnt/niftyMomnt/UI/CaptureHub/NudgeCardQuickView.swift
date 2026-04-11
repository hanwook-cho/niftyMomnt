// Apps/niftyMomnt/UI/CaptureHub/NudgeCardQuickView.swift
// v0.6 Quick mode — one-tap emoji reaction. No typing required.
// Appears after post-capture overlay closes; dismisses in < 1s.

import NiftyCore
import SwiftUI

struct NudgeCardQuickView: View {
    let card: NudgeCard
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    // Emoji reactions ordered by energy: calm → intense
    private let reactions: [(emoji: String, label: String)] = [
        ("🌿", "calm"),
        ("💙", "serene"),
        ("✨", "magical"),
        ("🔥", "intense"),
        ("🌙", "moody"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            // Drag indicator space is handled by presentationDragIndicator
            Text(card.question)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                ForEach(reactions, id: \.emoji) { reaction in
                    Button {
                        onSelect(reaction.emoji)
                    } label: {
                        VStack(spacing: 4) {
                            Text(reaction.emoji)
                                .font(.system(size: 38))
                            Text(reaction.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Button("Skip") {
                onDismiss()
            }
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .padding(.bottom, 4)
        }
        .padding(.top, 20)
        .presentationDetents([.height(190)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}
