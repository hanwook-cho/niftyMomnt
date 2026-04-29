// Apps/Piqd/Piqd/UI/Circle/IncomingInviteSheet.swift
// Piqd v0.6 — modal sheet shown when a `piqd://invite/<token>` URL resolves.
// Presents the sender's display name + 4-byte SHA256 key fingerprint so the
// user can spot-check identity before tapping Accept.
//
// Bound to an `IncomingInviteState` whose `pending` field drives presentation.

import SwiftUI
import NiftyCore

public struct IncomingInviteSheet: View {

    @Bindable var state: IncomingInviteState

    public init(state: IncomingInviteState) {
        self.state = state
    }

    public var body: some View {
        if let token = state.pending {
            content(token: token)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func content(token: InviteToken) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Invite from")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(token.displayName)
                    .font(.title.bold())
                    .accessibilityIdentifier("piqd.incomingInvite.displayName")
            }
            .padding(.top, 24)

            VStack(spacing: 4) {
                Text("Key fingerprint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(IncomingInviteState.fingerprint(of: token.publicKey))
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("piqd.incomingInvite.fingerprint")
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    state.decline()
                } label: {
                    Text("Decline").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("piqd.incomingInvite.decline")

                Button {
                    Task { await state.accept() }
                } label: {
                    Text("Accept").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("piqd.incomingInvite.accept")
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .presentationDetents([.medium])
        // No root identifier — would mask the per-leaf displayName / fingerprint /
        // accept / decline IDs that XCUITest queries.
    }
}
