// Apps/niftyMomnt/UI/CaptureHub/NudgeCardView.swift
// v0.6 — Post-capture nudge card. Presented as a sheet after the vibe overlay closes.

import NiftyCore
import SwiftUI

struct NudgeCardView: View {
    let card: NudgeCard
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var responseText: String = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Question
                Text(card.question)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Response field
                TextField("Write something…", text: $responseText, axis: .vertical)
                    .focused($textFieldFocused)
                    .font(.system(size: 16))
                    .lineLimit(4...8)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                Spacer()

                // Submit
                Button {
                    onSubmit(responseText.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Text("Save")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.niftyBrand, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 22))
                    }
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { textFieldFocused = true }
    }
}
