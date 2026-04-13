// Apps/niftyMomnt/UI/Vault/VaultView.swift
// v0.8 — Private Vault: Face ID gate + private asset grid.
// Spec §3.1 / §6: Face ID biometrics only (no passcode fallback). Lock resets on every cold launch.

import NiftyCore
import os
import SwiftUI
import UIKit

private let vaultLog = Logger(subsystem: "com.hwcho99.niftymomnt", category: "VaultView")

struct VaultView: View {
    let container: AppContainer

    @State private var isUnlocked: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var authErrorMessage: String? = nil
    @State private var privateAssets: [Asset] = []
    @State private var thumbnails: [UUID: UIImage] = [:]

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

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
                authenticate()
            } label: {
                Group {
                    if isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Unlock with Face ID", systemImage: "faceid")
                            .font(.niftyLabel)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, NiftySpacing.xl)
                .padding(.vertical, NiftySpacing.md)
                .frame(minWidth: 200)
                .background(Color(hex: "#D85A30"))
                .clipShape(Capsule())
            }
            .disabled(isAuthenticating)

            if let msg = authErrorMessage {
                Text(msg)
                    .font(.niftyCaption)
                    .foregroundStyle(Color.niftyTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, NiftySpacing.xxl)
            }
        }
        .padding(NiftySpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Unlocked content

    private var unlockedContent: some View {
        Group {
            if privateAssets.isEmpty {
                emptyVaultState
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(privateAssets) { asset in
                            assetThumbnail(asset)
                        }
                    }
                    .padding(2)
                    Spacer().frame(height: 80)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.niftySpring) {
                        isUnlocked = false
                        privateAssets = []
                        thumbnails = [:]
                    }
                    Task { await container.vaultManager.lockVault() }
                } label: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color(hex: "#D85A30"))
                }
            }
        }
        .task {
            await loadPrivateAssets()
        }
        .onReceive(NotificationCenter.default.publisher(for: .niftyVaultChanged)) { _ in
            Task { await loadPrivateAssets() }
        }
    }

    private var emptyVaultState: some View {
        VStack(spacing: NiftySpacing.xl) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: "#D85A30").opacity(0.6))

            Text("No private shots yet.")
                .font(.niftyBody)
                .foregroundStyle(Color.niftyTextSecondary)
                .multilineTextAlignment(.center)

            Text("Use \"Move to Vault\" on any shot in your journal.")
                .font(.niftyCaption)
                .foregroundStyle(Color.niftyTextSecondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, NiftySpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func assetThumbnail(_ asset: Asset) -> some View {
        ZStack {
            Color.black

            if let img = thumbnails[asset.id] {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                // Placeholder: icon for assets whose encrypted file can't be decoded inline
                VStack(spacing: 6) {
                    Image(systemName: assetIcon(asset.type))
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.35))
                    if let label = assetTypeLabel(asset.type) {
                        Text(label)
                            .font(.system(size: 9, weight: .heavy))
                            .kerning(0.5)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            // Asset type badge (top-left, non-still only)
            if let badge = assetTypeBadge(asset.type) {
                VStack {
                    HStack {
                        Text(badge)
                            .font(.system(size: 8, weight: .heavy))
                            .kerning(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.niftyBrand.opacity(0.75))
                            .clipShape(Capsule())
                            .padding(5)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // Lock badge (bottom-right corner)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(4)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: asset.id) {
            await loadThumbnail(for: asset)
        }
    }

    // MARK: - Actions

    private func authenticate() {
        isAuthenticating = true
        authErrorMessage = nil
        Task {
            do {
                try await container.vaultManager.unlockVault()
                withAnimation(.niftySpring) { isUnlocked = true }
            } catch let err as VaultAuthError {
                authErrorMessage = err.errorDescription
                vaultLog.error("VaultView authenticate — \(err.localizedDescription)")
            } catch {
                authErrorMessage = error.localizedDescription
                vaultLog.error("VaultView authenticate — \(error)")
            }
            isAuthenticating = false
        }
    }

    private func loadPrivateAssets() async {
        do {
            let moments = try await container.graphManager.fetchMoments(
                query: GraphQuery(showPrivate: true)
            )
            let assets = moments.flatMap(\.assets).sorted { $0.capturedAt > $1.capturedAt }
            privateAssets = assets
            vaultLog.debug("loadPrivateAssets — \(assets.count) private asset(s)")
        } catch {
            vaultLog.error("loadPrivateAssets — failed: \(error)")
        }
    }

    private func loadThumbnail(for asset: Asset) async {
        guard thumbnails[asset.id] == nil else { return }
        guard let (_, data) = try? await container.vaultManager.loadPrimary(asset.id),
              let img = UIImage(data: data) else { return }
        thumbnails[asset.id] = img
    }

    private func assetIcon(_ type: AssetType) -> String {
        switch type {
        case .still, .live, .l4c: return "photo"
        case .clip, .atmosphere: return "video"
        case .echo: return "waveform"
        }
    }

    /// Short badge label shown top-left on the tile. nil for still (no label needed).
    private func assetTypeBadge(_ type: AssetType) -> String? {
        switch type {
        case .still:       return nil
        case .live:        return "LIVE"
        case .clip:        return "CLIP"
        case .echo:        return "ECHO"
        case .atmosphere:  return "ATMOS"
        case .l4c:         return nil
        }
    }

    /// Longer label shown inside the placeholder icon stack for non-image assets.
    private func assetTypeLabel(_ type: AssetType) -> String? {
        switch type {
        case .still, .live, .l4c: return nil
        case .clip:        return "Video Clip"
        case .atmosphere:  return "Atmosphere"
        case .echo:        return "Echo"
        }
    }
}
