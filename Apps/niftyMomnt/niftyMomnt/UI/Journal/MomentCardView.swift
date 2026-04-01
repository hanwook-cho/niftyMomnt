// Apps/niftyMomnt/UI/Journal/MomentCardView.swift
// Spec §5.1 v1.7 — Dark editorial roll card on Film Archive (#0F0D0B).
//
// Card anatomy (top → bottom):
//   1. Hero gradient (130pt, full width, preset left 3pt accent strip)
//   2. Shot count badge (top-right of hero)
//   3. Title row: "PRESET · Location" 15pt/900 white
//   4. Date subtitle: small caption
//   5. Thumbnail strip: 4 thumbs + "+N" overflow slot
//   6. Vibe tags row: emoji + text muted white
//   7. Play circle (right-aligned, preset-coloured)

import NiftyCore
import SwiftUI

struct MomentCardView: View {
    let moment: Moment
    let presetName: String
    let presetAccent: Color
    let onTap: () -> Void
    let onPlay: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                infoSection
            }
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Hero gradient placeholder — replaced by actual asset thumbnail
            heroGradient
                .frame(height: 130)

            // Left 3pt accent strip (spec: "3pt" not 8pt from v1.6)
            HStack(spacing: 0) {
                presetAccent
                    .frame(width: 3)
                Spacer()
            }

            // Shot count badge — top right
            VStack {
                HStack {
                    Spacer()
                    if !moment.assets.isEmpty {
                        Text("\(moment.assets.count) shots")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, NiftySpacing.md)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.62))
                            .clipShape(Capsule())
                            .padding([.top, .trailing], NiftySpacing.sm)
                    }
                }
                Spacer()
            }
        }
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
        // Warm editorial tone — replaced by real thumbnail in production
        LinearGradient(
            colors: heroColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var heroColors: [Color] {
        // Derive from dominant vibe, fall back to warm-dark default
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
            // Title + date
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

            // Thumbnail strip
            thumbnailStrip
                .padding(.horizontal, NiftySpacing.sm)
                .padding(.top, NiftySpacing.sm)

            // Vibe tags row + play circle
            HStack(alignment: .center) {
                Text(vibeTagsLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.40))
                    .lineLimit(1)

                Spacer()

                // Preset-coloured play circle
                Button(action: onPlay) {
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
            .padding(.vertical, NiftySpacing.sm)
        }
    }

    private var thumbnailStrip: some View {
        HStack(spacing: 4) {
            let visible = min(moment.assets.count, 4)
            let overflow = max(0, moment.assets.count - 4)

            ForEach(0..<visible, id: \.self) { i in
                thumbCell(asset: moment.assets[i], isFirst: i == 0)
            }

            if overflow > 0 {
                overflowCell(count: overflow)
            }

            Spacer()
        }
    }

    private func thumbCell(asset: Asset, isFirst: Bool) -> some View {
        // Placeholder — real integration: use a thumbnail image view
        RoundedRectangle(cornerRadius: 6)
            .fill(
                isFirst
                    ? LinearGradient(colors: heroColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)],
                                     startPoint: .top, endPoint: .bottom)
            )
            .frame(width: 38, height: 28)
    }

    private func overflowCell(count: Int) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.06))
            .frame(width: 38, height: 28)
            .overlay(
                Text("+\(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.28))
            )
    }

    // MARK: - Helpers

    private var cardTitle: String {
        "\(presetName) · \(placeLabel)"
    }

    private var placeLabel: String {
        // Extract place from moment label, fall back to label itself
        let parts = moment.label.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.first ?? moment.label
    }

    private var dateSubtitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        let sunPos = moment.assets.first?.ambient.sunPosition?.rawValue ?? ""
        let parts = [fmt.string(from: moment.startTime), time.string(from: moment.startTime), sunPos]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private var vibeTagsLine: String {
        moment.dominantVibes.prefix(3).map { tag in
            "\(tag.emoji) \(tag.rawValue)"
        }.joined(separator: "  ·  ")
    }
}

// Note: VibeTag.emoji is declared in JournalFeedView.swift (module-internal extension).
