// Apps/Piqd/Piqd/UI/Debug/PiqdVaultDebugView.swift
// Minimal debug grid of captured assets, used to verify v0.1 persistence on-device.
// Flattens all Moments' assets into a single grid so every captured frame is visible.

import AVFoundation
import AVKit
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
    @State private var playerURL: URL?

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
                        let isVideo = asset.type == .clip || asset.type == .dual || asset.type == .sequence
                        ZStack(alignment: .topLeading) {
                            PiqdDebugThumbnail(assetID: asset.id, vault: container.vaultManager)
                                .aspectRatio(1, contentMode: .fit)
                            PiqdTypeBadge(type: asset.type)
                                .padding(4)
                            if isVideo {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.85), .black.opacity(0.5))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .accessibilityIdentifier("piqd.vault.play.\(asset.id.uuidString)")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard isVideo else { return }
                            Task { await playVideo(assetID: asset.id) }
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
            .sheet(item: Binding(
                get: { playerURL.map { IdentifiedURL(url: $0) } },
                set: { playerURL = $0?.url }
            )) { item in
                PiqdVideoPlayerSheet(url: item.url) { playerURL = nil }
            }
        }
    }

    private func playVideo(assetID: UUID) async {
        do {
            let (_, data) = try await container.vaultManager.loadPrimary(assetID)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("play-\(assetID.uuidString)")
                .appendingPathExtension("mov")
            try data.write(to: tmp)
            await MainActor.run { self.playerURL = tmp }
        } catch {
            await MainActor.run { self.errorText = "playback failed: \(error.localizedDescription)" }
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
            // Images (still/sequence-frame stubs under UI_TEST_MODE) decode directly.
            if let ui = UIImage(data: data) {
                await MainActor.run { self.image = ui }
                return
            }
            // Video payload (real Sequence MP4, future Clip/Dual): generate a poster frame
            // by writing bytes to tmp and pulling the first image via AVAssetImageGenerator.
            if let ui = Self.posterFrame(from: data) {
                await MainActor.run { self.image = ui }
            }
        } catch {
            // Silent — debug view; keep placeholder on failure.
        }
    }

    /// Extracts frame-0 from an MP4/MOV payload. Used for `.sequence` (and later `.clip`/`.dual`)
    /// where the vault's primary file is a video. Synchronous generator; a ~2s loop decodes in <50ms.
    private static func posterFrame(from data: Data) -> UIImage? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (try? data.write(to: tmp)) != nil else { return nil }
        let asset = AVURLAsset(url: tmp)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        guard let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct PiqdVideoPlayerSheet: View {
    let url: URL
    let onClose: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    Color.black.overlay(ProgressView().tint(.white))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
            }
        }
        .task {
            let p = AVPlayer(url: url)
            p.actionAtItemEnd = .pause
            self.player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            try? FileManager.default.removeItem(at: url)
        }
    }
}
