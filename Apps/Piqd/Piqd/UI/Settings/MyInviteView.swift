// Apps/Piqd/Piqd/UI/Settings/MyInviteView.swift
// Piqd v0.6 — re-render the user's invite QR + share-link button. UIUX §8
// (CIRCLE → My invite QR). Used both from Settings and (indirectly) from
// onboarding O3 — both go through `inviteCoordinator.myInviteURL()` and
// produce the same payload (the keypair + ownerProfile are stable).

import SwiftUI

struct MyInviteView: View {

    let container: PiqdAppContainer
    @State private var inviteURL: URL?
    @State private var qrImage: UIImage?
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                qrPanel
                    .padding(.top, 24)

                Text("Friends scan this QR to add you to their circle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let url = inviteURL {
                    Text(url.absoluteString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    if let url = inviteURL {
                        ShareHandoffCoordinator().share(url: url)
                    }
                } label: {
                    Label("Share link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .disabled(inviteURL == nil)
                .accessibilityIdentifier("piqd.circle.myInvite.share")

                Spacer(minLength: 24)
            }
        }
        .navigationTitle("My invite QR")
        .accessibilityIdentifier("piqd.circle.myInvite")
        .task { await loadInviteURL() }
    }

    // MARK: - QR

    @ViewBuilder
    private var qrPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .frame(width: 232, height: 232)

            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                    .accessibilityIdentifier("piqd.circle.myInvite.qr")
            } else if loadError != nil {
                Text("Couldn't generate invite")
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.6))
            } else {
                ProgressView()
            }
        }
    }

    private func loadInviteURL() async {
        do {
            let url = try await container.inviteCoordinator.myInviteURL()
            let img = QRCodeImageRenderer.image(for: url, size: 200)
            await MainActor.run {
                self.inviteURL = url
                self.qrImage = img
                if img == nil { self.loadError = "render-failed" }
            }
        } catch {
            await MainActor.run { self.loadError = "\(error)" }
        }
    }
}
