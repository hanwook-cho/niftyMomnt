// Apps/Piqd/Piqd/UI/Settings/CircleSettingsView.swift
// Piqd v0.6 — Settings → CIRCLE section. UIUX §8.
//
// Returns a `Section` for embedding inside `PiqdSettingsView`'s `Form`.
// Three rows:
//   - "My friends"     → NavigationLink to `FriendsListView`
//   - "Add friend"     → confirmationDialog (Scan QR / Share my invite link)
//   - "My invite QR"   → NavigationLink to `MyInviteView`
//
// QR scanning routes the scanned URL through `IncomingInviteState.handle(url:)`
// — the existing root-level `IncomingInviteSheet` then takes over for the
// Accept/Decline confirmation.

import SwiftUI
import NiftyCore

struct CircleSettingsView: View {

    let container: PiqdAppContainer
    @State private var showAddFriendDialog = false
    @State private var showScanner = false

    var body: some View {
        Section("Circle") {
            NavigationLink {
                FriendsListView(container: container)
            } label: {
                row("My friends", systemImage: "person.2")
            }
            .accessibilityIdentifier("piqd.circle.myFriends")

            Button {
                showAddFriendDialog = true
            } label: {
                row("Add friend", systemImage: "person.badge.plus")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("piqd.circle.addFriend")

            NavigationLink {
                MyInviteView(container: container)
            } label: {
                row("My invite QR", systemImage: "qrcode")
            }
            .accessibilityIdentifier("piqd.circle.myInviteQR")
        }
        // No section-level identifier — would mask the per-row IDs.
        .confirmationDialog(
            "Add a friend",
            isPresented: $showAddFriendDialog,
            titleVisibility: .visible
        ) {
            Button("Scan QR") {
                showScanner = true
            }
            .accessibilityIdentifier("piqd.circle.addFriend.scan")

            Button("Share my invite link") {
                Task {
                    if let url = try? await container.inviteCoordinator.myInviteURL() {
                        ShareHandoffCoordinator().share(url: url)
                    }
                }
            }
            .accessibilityIdentifier("piqd.circle.addFriend.shareLink")

            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showScanner) {
            scannerSheet
        }
    }

    // MARK: - Row label

    @ViewBuilder
    private func row(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
            Spacer()
        }
    }

    // MARK: - Scanner sheet (mirrors O3InviteView's pattern)

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
                        .accessibilityIdentifier("piqd.circle.scan.cancel")
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
        .accessibilityIdentifier("piqd.circle.scan.sheet")
    }
}
