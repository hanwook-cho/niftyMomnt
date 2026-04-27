// Apps/Piqd/Piqd/UI/Capture/DraftRowView.swift
// Piqd v0.5 — one row in the drafts tray sheet. PRD FR-SNAP-DRAFT-04..07,
// UIUX §2.14.
//
// Row anatomy (72pt height, 0.5pt divider underneath):
//   ┌─────────────┬──────────────────────────────────┬─────────────┐
//   │  thumbnail  │  asset-type label                │  save       │
//   │  (52pt)     │  timer label (4-state color)     │  send →     │
//   └─────────────┴──────────────────────────────────┴─────────────┘
//
// Three sub-variants:
//   • Still       — static `Image` from HEIC bytes
//   • Sequence    — `SilentLoopingPlayerView` (auto-loop, muted)
//   • Clip / Dual — static thumbnail with 18pt play overlay; tap to play with audio
//
// The save / send actions are routed through the container so this view stays
// composable; failures are surfaced as inline `Text` next to the action link
// (no separate alert, no separate toast).

import AVFoundation
import NiftyCore
import NiftyData
import SwiftUI
import UIKit

struct DraftRowView: View {

    let item: DraftItem
    let state: DraftExpiryState
    let exporter: any PhotoLibraryExporterProtocol
    let shareHandoff: ShareHandoffCoordinator
    let resolveURL: @Sendable (UUID, AssetType) async -> URL?

    @State private var thumbnail: UIImage?
    @State private var resolvedURL: URL?
    @State private var saveStatus: SaveStatus = .idle

    private enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case denied
        case failed
    }

    var body: some View {
        HStack(spacing: PiqdTokens.Spacing.md) {
            thumbnailView
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: PiqdTokens.Shape.thumbRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(typeLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                if let timer = timerLabel {
                    Text(timer)
                        .font(.caption2)
                        .foregroundStyle(timerColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: PiqdTokens.Spacing.md) {
                Button(action: tapSave) {
                    Text(saveActionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("piqd.draftRow.\(item.assetID.uuidString).save")

                Button(action: tapSend) {
                    Text("send →")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(sendColor)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("piqd.draftRow.\(item.assetID.uuidString).send")
            }
        }
        .frame(height: 72)
        .padding(.horizontal, PiqdTokens.Spacing.md)
        .task(id: item.assetID) {
            await loadResources()
        }
    }

    // MARK: - Thumbnail / playback variants

    @ViewBuilder
    private var thumbnailView: some View {
        switch item.assetType {
        case .sequence:
            if let url = resolvedURL {
                SilentLoopingPlayerView(url: url)
            } else {
                placeholderThumb
            }
        case .clip, .dual:
            ZStack {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholderThumb
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
            }
        default:
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderThumb
            }
        }
    }

    private var placeholderThumb: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
    }

    // MARK: - Labels

    private var typeLabel: String {
        switch item.assetType {
        case .still:    return "Still"
        case .sequence: return "Sequence"
        case .clip:     return "Clip"
        case .dual:     return "Dual"
        case .live:     return "Live"
        case .l4c:      return "L4C"
        case .movingStill: return "Moving Still"
        case .echo:     return "Echo"
        case .atmosphere: return "Atmosphere"
        }
    }

    /// FR-SNAP-DRAFT-05 timer text. Hidden when >3h remain.
    private var timerLabel: String? {
        switch state {
        case .hidden:
            return nil
        case .normal(let remaining):
            return Self.formatHoursMinutes(remaining)
        case .amber(let remaining), .red(let remaining):
            return Self.formatMinutes(remaining)
        case .expired:
            return nil
        }
    }

    private var timerColor: Color {
        switch state {
        case .amber: return PiqdTokens.Color.rollAmber
        case .red:   return PiqdTokens.Color.recordRed
        default:     return .secondary
        }
    }

    /// FR-SNAP-DRAFT-05: "send →" turns red at <15min remaining.
    private var sendColor: Color {
        if case .red = state { return PiqdTokens.Color.recordRed }
        return .primary
    }

    private var saveActionLabel: String {
        switch saveStatus {
        case .idle, .failed: return "save"
        case .saving:        return "saving…"
        case .saved:         return "saved"
        case .denied:        return "open Settings"
        }
    }

    // MARK: - Actions

    private func tapSave() {
        if saveStatus == .denied {
            // Surface settings deep-link rather than re-attempting save.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        guard saveStatus != .saving else { return }
        saveStatus = .saving
        Task {
            let url: URL?
            if let cached = resolvedURL {
                url = cached
            } else {
                url = await resolveURL(item.assetID, item.assetType)
            }
            guard let url else {
                saveStatus = .failed
                return
            }
            let result = await exporter.exportToPhotos(url, kind: item.assetType)
            switch result {
            case .saved:            saveStatus = .saved
            case .permissionDenied: saveStatus = .denied
            case .failed:           saveStatus = .failed
            }
        }
    }

    private func tapSend() {
        Task {
            let url: URL?
            if let cached = resolvedURL {
                url = cached
            } else {
                url = await resolveURL(item.assetID, item.assetType)
            }
            guard let url else {
                return
            }
            shareHandoff.share(url: url)
        }
    }

    // MARK: - Resource loading

    private func loadResources() async {
        let url = await resolveURL(item.assetID, item.assetType)
        await MainActor.run { self.resolvedURL = url }
        guard let url else { return }

        switch item.assetType {
        case .still, .live, .l4c, .movingStill:
            await loadStillThumbnail(from: url)
        case .clip, .dual:
            await loadVideoFrameThumbnail(from: url)
        case .sequence, .echo, .atmosphere:
            // Sequence renders via SilentLoopingPlayerView; echo/atmosphere don't
            // surface in Snap drafts in v0.5.
            break
        }
    }

    private func loadStillThumbnail(from url: URL) async {
        let img: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return nil }
            return image
        }.value
        await MainActor.run { self.thumbnail = img }
    }

    private func loadVideoFrameThumbnail(from url: URL) async {
        let img: UIImage? = await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: 0.0, preferredTimescale: 600)
            do {
                let cg = try await generator.image(at: time).image
                return UIImage(cgImage: cg)
            } catch {
                return nil
            }
        }.value
        await MainActor.run { self.thumbnail = img }
    }

    // MARK: - Formatters

    private static func formatHoursMinutes(_ remaining: TimeInterval) -> String {
        let totalMinutes = max(0, Int(remaining / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m left"
    }

    private static func formatMinutes(_ remaining: TimeInterval) -> String {
        let totalMinutes = max(0, Int(remaining / 60))
        return "\(totalMinutes)m left"
    }
}
