// Apps/Piqd/Piqd/UI/Onboarding/O3InviteView.swift
// Piqd v0.6 — Onboarding O3. UIUX §7.4.
//
// Solid dark background (no viewfinder). Centered 200pt QR encoding the
// `piqd://invite/<token>` URL. Three actions:
//   - "Share invite link instead →"  → iOS share sheet w/ the URL
//   - "Add friend instead"           → presents `QRScannerView`; on scan,
//                                       routes through `IncomingInviteState`
//                                       (root-level invite sheet takes over)
//   - "Start shooting →"             → marks onboarding complete, mounts capture

import SwiftUI
import NiftyCore

struct O3InviteView: View {

    let container: PiqdAppContainer
    @Bindable var coordinator: OnboardingCoordinator

    @State private var inviteURL: URL?
    @State private var qrImage: UIImage?
    @State private var showScanner = false
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(maxHeight: 40)

                qrPanel
                    .padding(.bottom, 24)

                VStack(spacing: 8) {
                    Text("Invite your first friend")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("piqd.onboarding.O3.title")

                    Text("They scan this to join your circle.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 16)

                Button {
                    if let url = inviteURL {
                        ShareHandoffCoordinator().share(url: url)
                    }
                } label: {
                    Text("Share invite link instead →")
                        .font(.caption)
                        .foregroundStyle(PiqdTokens.Color.snapYellow)
                }
                .accessibilityIdentifier("piqd.onboarding.O3.shareLink")
                .disabled(inviteURL == nil)

                Spacer().frame(height: 12)

                Button {
                    showScanner = true
                } label: {
                    Text("Add friend instead")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityIdentifier("piqd.onboarding.O3.scan")

                Spacer()

                Button {
                    coordinator.complete()
                } label: {
                    Text("Start shooting →")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(PiqdTokens.Color.snapYellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("piqd.onboarding.O3.start")
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        // No `.accessibilityIdentifier` on the root — would mask per-leaf IDs.
        .task {
            await loadInviteURL()
        }
        .sheet(isPresented: $showScanner) {
            scannerSheet
        }
    }

    // MARK: - QR panel

    @ViewBuilder
    private var qrPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .frame(width: 232, height: 232)

            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)  // preserve crisp QR pixels
                    .resizable()
                    .frame(width: 200, height: 200)
                    .accessibilityIdentifier("piqd.onboarding.O3.qr")
            } else if loadError != nil {
                Text("Couldn't generate invite")
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.6))
            } else {
                ProgressView()
            }
        }
    }

    // MARK: - Scanner sheet

    @ViewBuilder
    private var scannerSheet: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            QRScannerView { url in
                showScanner = false
                Task { await container.incomingInviteState.handle(url: url) }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button("Cancel") { showScanner = false }
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                        .accessibilityIdentifier("piqd.onboarding.O3.scan.cancel")
                }
                Spacer()
                Text("Scan a Piqd invite QR")
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 48)
            }
        }
        // No root identifier — would mask cancel button + scanner descendants.
    }

    // MARK: - Async load

    private func loadInviteURL() async {
        do {
            let url = try await container.inviteCoordinator.myInviteURL()
            self.inviteURL = url
            // Render off-main isn't necessary for one QR — keep it simple.
            self.qrImage = QRCodeImageRenderer.image(for: url, size: 200)
            if qrImage == nil { loadError = "render-failed" }
        } catch {
            loadError = "\(error)"
        }
    }
}
