// Apps/Piqd/Piqd/UI/Debug/PiqdVaultDebugView.swift
// Minimal debug grid of captured assets, used to verify v0.1 persistence on-device.
// Flattens all Moments' assets into a single grid so every captured frame is visible.

import NiftyCore
import SwiftUI
import UIKit

struct PiqdVaultDebugView: View {
    let container: PiqdAppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [Asset] = []
    @State private var errorText: String?
    @State private var rollUsed: Int = 0
    @State private var rollLimit: Int = 24
    @State private var showDevSettings = false

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 4)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }

                HStack(spacing: 8) {
                    Label("Roll \(rollUsed)/\(rollLimit)", systemImage: "film")
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.orange.opacity(0.15)))
                    Label("Mode: \(container.modeStore.mode.rawValue)", systemImage: "camera.aperture")
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.gray.opacity(0.15)))
                    Spacer()
                }
                .padding(.horizontal, 8)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(assets, id: \.id) { asset in
                        ZStack(alignment: .topLeading) {
                            PiqdDebugThumbnail(assetID: asset.id, vault: container.vaultManager)
                                .aspectRatio(1, contentMode: .fit)
                            PiqdTypeBadge(type: asset.type)
                                .padding(4)
                            if asset.type == .clip || asset.type == .dual {
                                // Play affordance — actual AVPlayer inline playback wires
                                // to `Documents/piqd/assets/{id}.mp4` once the real Clip /
                                // Dual capture paths land. Tap triggers audio playback.
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.85), .black.opacity(0.5))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .accessibilityIdentifier("piqd.vault.play.\(asset.id.uuidString)")
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("piqd-vault-row-\(asset.id.uuidString)")
                    }
                }
                .padding(4)
            }
            .navigationTitle("Vault (\(assets.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDevSettings = true } label: {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                    .accessibilityIdentifier("piqd-debug-dev-settings")
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(isPresented: $showDevSettings) {
                PiqdDevSettingsView(store: container.devSettings, onClose: { showDevSettings = false })
            }
        }
    }

    private func reload() async {
        do {
            let moments = try await container.graphManager.fetchMoments(query: GraphQuery())
            // Flatten to a flat list sorted newest-first. Multiple moments across merges all
            // contribute their assets — we care about frame count matching shutter taps.
            assets = moments
                .flatMap { $0.assets }
                .sorted { $0.capturedAt > $1.capturedAt }
            rollUsed = (try? await container.rollCounter.currentCount()) ?? 0
            rollLimit = await container.rollCounter.currentLimit()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Piqd v0.3 — type-badge overlay for the vault-debug grid. Four codes map 1:1 from the
/// AssetType set that the Snap format-selector produces. XCUITest UI17 reads the badge
/// text via `piqd.vault.badge.<code>`.
private struct PiqdTypeBadge: View {
    let type: AssetType

    private var code: String {
        switch type {
        case .still:    return "STL"
        case .sequence: return "SEQ"
        case .clip:     return "CLP"
        case .dual:     return "DUAL"
        default:        return type.rawValue.prefix(3).uppercased()
        }
    }

    private var tint: Color {
        switch type {
        case .still:    return .white
        case .sequence: return .cyan
        case .clip:     return .red
        case .dual:     return .orange
        default:        return .gray
        }
    }

    var body: some View {
        Text(code)
            .font(.caption2.weight(.bold).monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(tint.opacity(0.75), in: Capsule())
            .accessibilityIdentifier("piqd.vault.badge.\(code)")
    }
}

private struct PiqdDebugThumbnail: View {
    let assetID: UUID
    let vault: VaultManager
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.gray.opacity(0.2))
                    .overlay(ProgressView())
            }
        }
        .clipped()
        .task(id: assetID) {
            await load()
        }
    }

    private func load() async {
        do {
            let (_, data) = try await vault.loadPrimary(assetID)
            if let ui = UIImage(data: data) {
                await MainActor.run { self.image = ui }
            }
        } catch {
            // Silent — debug view; keep placeholder on failure.
        }
    }
}
