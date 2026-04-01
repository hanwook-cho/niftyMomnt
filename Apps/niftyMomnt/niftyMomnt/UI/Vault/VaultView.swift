// Apps/niftyMomnt/UI/Vault/VaultView.swift
// Spec §3.1 — Private archive, Face ID gated, tab ② in the Journal sheet.
// TODO: Implement Face ID gate, asset grid, and share flow per spec §6.

import NiftyCore
import SwiftUI

struct VaultView: View {
    let container: AppContainer

    @State private var isUnlocked: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if isUnlocked {
                    unlockedContent
                } else {
                    lockedState
                }
            }
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Locked state

    private var lockedState: some View {
        VStack(spacing: NiftySpacing.xxl) {
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(hex: "#D85A30"))

            VStack(spacing: NiftySpacing.sm) {
                Text("Private Vault")
                    .font(.niftyTitle)
                    .foregroundStyle(Color.niftyTextPrimary)
                Text("Unlock to view your private archive.")
                    .font(.niftyBody)
                    .foregroundStyle(Color.niftyTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                // TODO: Authenticate with LocalAuthentication (Face ID / Passcode)
                withAnimation(.niftySpring) { isUnlocked = true }
            } label: {
                Label("Unlock with Face ID", systemImage: "faceid")
                    .font(.niftyLabel)
                    .foregroundStyle(.white)
                    .padding(.horizontal, NiftySpacing.xl)
                    .padding(.vertical, NiftySpacing.md)
                    .background(Color(hex: "#D85A30"))
                    .clipShape(Capsule())
            }
        }
        .padding(NiftySpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Unlocked content

    private var unlockedContent: some View {
        VStack(spacing: NiftySpacing.xl) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: "#D85A30").opacity(0.6))

            Text("Your private archive appears here.")
                .font(.niftyBody)
                .foregroundStyle(Color.niftyTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, NiftySpacing.xxl)

            // TODO: Asset grid view — spec §6
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.niftySpring) { isUnlocked = false }
                } label: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color(hex: "#D85A30"))
                }
            }
        }
    }
}
