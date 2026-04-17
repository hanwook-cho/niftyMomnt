// Apps/niftyMomnt/UI/Journal/MomentCardView.swift
// Spec §5.1 v1.7 — Dark editorial roll card on Film Archive (#0F0D0B).
//
// Card anatomy (top → bottom):
//   1. Hero image (130pt, full width, preset left 3pt accent strip)
//      Falls back to vibe-derived gradient if image not yet loaded.
//   2. Shot count badge (top-right of hero)
//   3. Title row: "PRESET · Location" 15pt/900 white
//   4. Date subtitle: small caption
//   5. Thumbnail strip: up to 4 real thumbnails + "+N" overflow slot
//   6. Vibe tags row: emoji + text muted white
//   7. Play circle (right-aligned, preset-coloured)

import AVFoundation
import NiftyCore
import os
import SwiftUI

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "MomentCard")

struct MomentCardView: View {
    let moment: Moment
    let presetName: String
    let presetAccent: Color
    let onTap: () -> Void
    let onPlay: () -> Void

    @State private var heroImage: UIImage? = nil
    var body: some View {
        Button(action: {
            log.debug("MomentCardView: Internal button action triggered for \(moment.id.uuidString)")
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                infoSection
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        // Key on first asset ID, not moment ID: when the hero asset changes (e.g. moved to vault
        // and excluded from the feed-visible asset list), the task re-fires and reloads the hero.
        .task(id: moment.assets.first?.id) { await loadImages() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Hero: real photo or vibe-derived gradient fallback
            Group {
                if let img = heroImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    heroGradient
                }
            }
            .frame(height: 130)
            .clipped()

            // Left 3pt accent strip
            HStack(spacing: 0) {
                presetAccent.frame(width: 3)
                Spacer()
            }

            // Top-right: shot count + asset type badge
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        // Asset type badge (non-still only)
                        if let badge = moment.assets.first?.type.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .heavy))
                                .kerning(0.5)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.niftyBrand.opacity(0.72))
                                .clipShape(Capsule())
                        }
                        if !moment.assets.isEmpty {
                            Text("\(moment.assets.count) shots")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, NiftySpacing.md)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.62))
                                .clipShape(Capsule())
                        }
                    }
                    .padding([.top, .trailing], NiftySpacing.sm)
                }
                Spacer()
            }
        }
        .frame(height: 130)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18
            )
        )
    }

    private var heroGradient: some View {
        LinearGradient(colors: heroColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroColors: [Color] {
        switch moment.dominantVibes.first {
        case .golden:
            return [Color(hex: "#1E0A00"), Color(hex: "#7A3A00"), Color(hex: "#E8A020")]
        case .moody, .nostalgic:
            return [Color(hex: "#050A18"), Color(hex: "#152050"), Color(hex: "#3A58C0")]
        case .serene:
            return [Color(hex: "#041408"), Color(hex: "#0A3020"), Color(hex: "#0F6E56")]
        case .electric:
            return [Color(hex: "#0C0818"), Color(hex: "#2A1550"), Color(hex: "#6B4EFF")]
        default:
            return [Color(hex: "#1A1208"), Color(hex: "#2A1A0A")]
        }
    }

    // MARK: - Info section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cardTitle)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(dateSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, NiftySpacing.md)
            .padding(.top, NiftySpacing.sm + 2)

            HStack(alignment: .center) {
                Text(vibeTagsLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.40))
                    .lineLimit(1)

                Spacer()

                Button(action: {
                    log.debug("MomentCardView: Internal PLAY button action triggered for \(moment.id.uuidString)")
                    onPlay()
                }) {
                    Circle()
                        .fill(presetAccent)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                                .offset(x: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, NiftySpacing.md)
            .padding(.top, NiftySpacing.sm)
            .padding(.bottom, NiftySpacing.sm)
        }
    }

    // MARK: - Image loading

    private func loadImages() async {
        log.debug("loadImages — moment=\(moment.id.uuidString) assets=\(moment.assets.count)")

        // Hero: first asset
        if let first = moment.assets.first {
            if let img = await loadThumbnail(for: first) {
                log.debug("loadImages — hero loaded for \(first.id.uuidString)")
                heroImage = img
            } else {
                log.error("loadImages — hero FAILED for \(first.id.uuidString) (file missing?)")
            }
        }

        log.debug("loadImages done — hero=\(heroImage != nil)")
    }

    /// Loads a UIImage thumbnail for an asset regardless of type (still/live → JPEG, video → first frame).
    private func loadThumbnail(for asset: Asset) async -> UIImage? {
        switch asset.type {
        case .still, .live, .l4c, .movingStill:
            return loadJPEGFromVault(assetID: asset.id)
        case .clip, .atmosphere, .sequence, .dual:
            return await extractVideoThumbnail(assetID: asset.id)
        case .echo:
            return Self.echoPlaceholderImage()
        }
    }

    /// Reads the JPEG file written by VaultRepository at Documents/assets/{id}.jpg.
    private func loadJPEGFromVault(assetID: UUID) -> UIImage? {
        guard let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = dir
            .appendingPathComponent("assets")
            .appendingPathComponent("\(assetID.uuidString).jpg")
        log.debug("loadJPEGFromVault — path: \(url.path)")
        guard let data = try? Data(contentsOf: url) else {
            log.error("loadJPEGFromVault — no file at \(url.lastPathComponent)")
            return nil
        }
        guard let image = UIImage(data: data) else {
            log.error("loadJPEGFromVault — UIImage(data:) failed for \(url.lastPathComponent)")
            return nil
        }
        log.debug("loadJPEGFromVault — OK \(data.count)B → \(Int(image.size.width))×\(Int(image.size.height))px")
        return image
    }

    /// Extracts the first frame of a .mov video via AVAssetImageGenerator.
    private func extractVideoThumbnail(assetID: UUID) async -> UIImage? {
        guard let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = dir
            .appendingPathComponent("assets")
            .appendingPathComponent("\(assetID.uuidString).mov")
        guard FileManager.default.fileExists(atPath: url.path) else {
            log.error("extractVideoThumbnail — no .mov at \(url.lastPathComponent)")
            return nil
        }
        let avAsset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            log.debug("extractVideoThumbnail — OK for \(assetID.uuidString)")
            return UIImage(cgImage: cgImage)
        } catch {
            log.error("extractVideoThumbnail — failed for \(assetID.uuidString): \(error)")
            return nil
        }
    }

    /// Renders a dark-background waveform image used as the hero for Echo cards.
    /// Produces a real UIImage so heroImage is non-nil and the card is tappable.
    private static func echoPlaceholderImage() -> UIImage {
        let size = CGSize(width: 400, height: 260)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Dark amber gradient background
            let cgCtx = ctx.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(red: 0.07, green: 0.04, blue: 0.01, alpha: 1).cgColor,
                          UIColor(red: 0.18, green: 0.09, blue: 0.02, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
                cgCtx.drawLinearGradient(gradient,
                                         start: .zero,
                                         end: CGPoint(x: 0, y: size.height),
                                         options: [])
            }
            // Centered waveform icon
            let config = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
            if let icon = UIImage(systemName: "waveform.circle.fill", withConfiguration: config)?
                .withTintColor(UIColor(white: 1, alpha: 0.55), renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: (size.width - icon.size.width) / 2,
                                     y: (size.height - icon.size.height) / 2)
                icon.draw(at: origin)
            }
        }
    }

    // MARK: - Helpers

    private var cardTitle: String {
        "\(presetName) · \(moment.label)"
    }

    private var dateSubtitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        let sunPos = moment.assets.first?.ambient.sunPosition?.rawValue ?? ""
        let weatherStr: String = {
            guard let asset = moment.assets.first else { return "" }
            var parts: [String] = []
            if let cond = asset.ambient.weather { parts.append(cond.emoji) }
            if let temp = asset.ambient.temperatureC { parts.append(String(format: "%.0f°", temp)) }
            return parts.joined(separator: " ")
        }()
        let parts = [fmt.string(from: moment.startTime),
                     timeFmt.string(from: moment.startTime),
                     sunPos, weatherStr]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private var vibeTagsLine: String {
        moment.dominantVibes.prefix(3).map { "\($0.emoji) \($0.rawValue)" }.joined(separator: "  ·  ")
    }
}

// Note: VibeTag.emoji is declared in JournalFeedView.swift (module-internal extension).

// MARK: - AssetType display helpers

private extension AssetType {
    /// Short badge label shown on the hero image. nil for still (no badge needed).
    var badge: String? {
        switch self {
        case .still:      return nil
        case .live:       return "LIVE"
        case .clip:       return "CLIP"
        case .echo:       return "ECHO"
        case .atmosphere: return "ATMOS"
        case .l4c:        return nil   // L4C composites shown via L4CMomentCardView, not here
        }
    }
}
