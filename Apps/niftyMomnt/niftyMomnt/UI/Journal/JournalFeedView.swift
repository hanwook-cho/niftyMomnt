// Apps/niftyMomnt/UI/Journal/JournalFeedView.swift
// Spec §5.1 v1.7 — Film Archive dark editorial feed.
//
// Header:  "Film" 26pt/900 · amber "N rolls" badge · search + grid glass buttons
// Section: "THIS WEEK · MAR 28–31" 10pt/800 at 22% opacity
// Cards:   MomentCardView dark editorial (see MomentCardView.swift)
// Detail:  MomentDetailView sheet on card tap

import NiftyCore
import SwiftUI
import UIKit

struct FilmFeedView: View {
    let container: AppContainer
    let onScrollTopChanged: (Bool) -> Void
    let onPullDownToDismiss: () -> Void

    @State private var moments: [Moment] = Moment.filmPreviews
    @State private var selectedMoment: Moment? = nil
    @State private var isGridLayout: Bool = false
    @State private var topSafeArea: CGFloat = 59
    @State private var isAtTop: Bool = true

    var body: some View {
        ZStack(alignment: .top) {
            Color.niftyFilmBg.ignoresSafeArea()

            if moments.isEmpty {
                emptyState
                    .onAppear { onScrollTopChanged(true) }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: NiftySpacing.lg) {
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: FilmFeedScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .named("FilmFeedScrollView")).minY
                                )
                        }
                        .frame(height: 0)

                        // Header (inline, not a navigation bar)
                        filmHeader
                            .padding(.horizontal, NiftySpacing.lg)
                            .padding(.top, topSafeArea) //NiftySpacing.md)

                        // Sectioned card feed
                        ForEach(groupedMoments, id: \.0) { (sectionLabel, dayMoments) in
                            sectionHeader(sectionLabel)
                                .padding(.horizontal, NiftySpacing.lg)
                                .padding(.top, NiftySpacing.xs)

                            ForEach(dayMoments) { moment in
                                MomentCardView(
                                    moment: moment,
                                    presetName: derivedPresetName(for: moment),
                                    presetAccent: derivedPresetAccent(for: moment),
                                    onTap: { selectedMoment = moment },
                                    onPlay: { selectedMoment = moment }
                                )
                                .padding(.horizontal, NiftySpacing.sm)
                            }
                        }

                        // Bottom padding for floating tab bar
                        Spacer().frame(height: 80)
                    }
                }
                .coordinateSpace(name: "FilmFeedScrollView")
                .onPreferenceChange(FilmFeedScrollOffsetPreferenceKey.self) { offset in
                    let atTop = offset >= -1
                    isAtTop = atTop
                    onScrollTopChanged(atTop)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            if isAtTop
                                && value.translation.height > 60
                                && abs(value.translation.height) > abs(value.translation.width) {
                                onPullDownToDismiss()
                            }
                        }
                )
                .onAppear {
                    isAtTop = true
                    onScrollTopChanged(true)
                }
            }
        }
        .sheet(item: $selectedMoment) { moment in
            MomentDetailView(moment: moment, container: container)
        }
        .onAppear { readWindowSafeArea() }
    }

    private func readWindowSafeArea() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else { return }
        topSafeArea = window.safeAreaInsets.top
    }

    // MARK: - Film Header

    private var filmHeader: some View {
        HStack(alignment: .lastTextBaseline, spacing: NiftySpacing.md) {
            Text("Film")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(.white)

            // Amber rolls badge
            Text("\(moments.count) rolls")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.niftyAmberVivid)
                .padding(.horizontal, NiftySpacing.md)
                .padding(.vertical, 3)
                .background(Color.niftyAmberVivid.opacity(0.16))
                .overlay(
                    Capsule().strokeBorder(Color.niftyAmberVivid.opacity(0.30), lineWidth: 0.5)
                )
                .clipShape(Capsule())

            Spacer()

            // Search glass button
            glassHeaderButton(systemImage: "magnifyingglass") {}

            // Grid/list toggle
            glassHeaderButton(systemImage: isGridLayout ? "rectangle.grid.1x2" : "square.grid.2x2") {
                withAnimation(.niftySpring) { isGridLayout.toggle() }
            }
        }
    }

    private func glassHeaderButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color.white.opacity(0.07))
                .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .heavy))
            .kerning(0.08 * 10)
            .foregroundStyle(.white.opacity(0.22))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: NiftySpacing.xl) {
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundStyle(Color.niftyLavender.opacity(0.4))
            Text("No moments yet")
                .font(.niftyTitle)
                .foregroundStyle(.white.opacity(0.6))
            Text("Swipe down to start capturing.")
                .font(.niftyBody)
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .padding(NiftySpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grouping

    private var groupedMoments: [(String, [Moment])] {
        let calendar = Calendar.current
        let now = Date()

        let sorted = moments.sorted { $0.startTime > $1.startTime }
        var result: [(String, [Moment])] = []
        var seen: [String: Int] = [:]

        for moment in sorted {
            let key = sectionLabel(for: moment.startTime, calendar: calendar, now: now)
            if let idx = seen[key] {
                result[idx].1.append(moment)
            } else {
                seen[key] = result.count
                result.append((key, [moment]))
            }
        }
        return result
    }

    private func sectionLabel(for date: Date, calendar: Calendar, now: Date) -> String {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now

        let fmt = DateFormatter()
        if date >= weekAgo {
            // Find week range
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? date
            fmt.dateFormat = "MMM d"
            return "THIS WEEK · \(fmt.string(from: weekStart))–\(fmt.string(from: weekEnd))".uppercased()
        } else if date >= twoWeeksAgo {
            return "LAST WEEK"
        } else {
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: date).uppercased()
        }
    }

    // MARK: - Preset derivation (stub — real integration reads asset preset metadata)

    private func derivedPresetName(for moment: Moment) -> String {
        switch moment.dominantVibes.first {
        case .golden: return "AMALFI"
        case .moody:  return "NORDIC"
        case .nostalgic: return "FILM ROLL"
        case .electric: return "TOKYO NEON"
        case .raw, .dreamy: return "DISPOSABLE"
        default: return "AMALFI"
        }
    }

    private func derivedPresetAccent(for moment: Moment) -> Color {
        switch moment.dominantVibes.first {
        case .golden:    return Color(hex: "#E8A020")
        case .moody:     return Color(hex: "#8EB4D4")
        case .nostalgic: return Color(hex: "#C8A882")
        case .electric:  return Color(hex: "#C4B5FD") // lavender v1.7
        case .raw, .dreamy: return Color(hex: "#FF6B6B")
        default: return Color(hex: "#E8A020")
        }
    }
}

private struct FilmFeedScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Moment Detail

struct MomentDetailView: View {
    let moment: Moment
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @State private var currentAssetIndex: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "#100C08").ignoresSafeArea()

            VStack(spacing: 0) {
                // Zone A — detail nav bar
                detailNavBar

                // Photo zone — full bleed with sticker overlays
                ZStack(alignment: .bottom) {
                    heroPhoto
                    paginationIndicator
                        .padding(.bottom, NiftySpacing.lg)
                }
                .frame(maxHeight: .infinity)

                // Glass bottom sheet
                glassBottomSheet
            }
        }
        .preferredColorScheme(.dark)
    }

    private var detailNavBar: some View {
        HStack(spacing: 0) {
            // Back
            Button { dismiss() } label: {
                Circle()
                    .fill(.white.opacity(0.09))
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            // Title
            Text(moment.label)
                .font(.system(size: 13, weight: .black))
                .kerning(0.07 * 13)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)

            Spacer()

            // Share — lavender tint per spec
            Button {} label: {
                Circle()
                    .fill(Color.niftyBrand.opacity(0.18))
                    .overlay(Circle().strokeBorder(Color.niftyBrand.opacity(0.36), lineWidth: 0.5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.niftyLavender)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(Color(red: 8/255, green: 6/255, blue: 4/255).opacity(0.22))
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                }
        )
    }

    private var heroPhoto: some View {
        ZStack(alignment: .top) {
            // Placeholder gradient — replaced by real asset in production
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "#180A00"), location: 0),
                    .init(color: Color(hex: "#B06820"), location: 0.52),
                    .init(color: Color(hex: "#FFE8B0"), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Location chip
            HStack {
                Text("📍 \(moment.label)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, NiftySpacing.lg)
                    .padding(.vertical, NiftySpacing.sm)
                    .background(.black.opacity(0.52))
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            }
            .padding(.top, NiftySpacing.xl)
        }
    }

    private var paginationIndicator: some View {
        HStack(spacing: NiftySpacing.sm) {
            ForEach(Array(moment.assets.prefix(7).enumerated()), id: \.offset) { idx, _ in
                if idx == currentAssetIndex {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.white.opacity(0.76))
                        .frame(width: 16, height: 5)
                } else {
                    Circle()
                        .fill(.white.opacity(0.28))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private var glassBottomSheet: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, NiftySpacing.md)

            // Shot info row
            HStack {
                Text("Shot \(currentAssetIndex + 1) of \(moment.assets.count)")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text(dateTimeString)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(.horizontal, NiftySpacing.lg)
            .padding(.top, NiftySpacing.lg)

            // Vibe tags row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NiftySpacing.sm) {
                    ForEach(moment.dominantVibes.prefix(5), id: \.self) { vibe in
                        vibeChip(vibe)
                    }
                }
                .padding(.horizontal, NiftySpacing.lg)
            }
            .padding(.top, NiftySpacing.md)

            // Actions row
            HStack(spacing: NiftySpacing.sm) {
                actionButton(title: "Fix this shot", icon: "checkmark.circle", isGlass: true)
                actionButton(title: "Share", icon: nil, isGlass: false, tinted: true)
                // ··· overflow
                Button {} label: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                        .frame(width: 40, height: 40)
                        .overlay(
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Circle().fill(.white.opacity(0.58)).frame(width: 2.6, height: 2.6)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, NiftySpacing.lg)
            .padding(.vertical, NiftySpacing.lg)
        }
        .background(
            Rectangle()
                .fill(Color(red: 12/255, green: 9/255, blue: 6/255).opacity(0.82))
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
                }
        )
        .padding(.bottom, 34) // home indicator
    }

    private func vibeChip(_ vibe: VibeTag) -> some View {
        let isAmber = vibe == .golden
        return Text("\(vibe.emoji) \(vibe.rawValue)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isAmber ? Color.niftyAmberVivid : .white.opacity(0.56))
            .padding(.horizontal, NiftySpacing.md)
            .padding(.vertical, 3)
            .background(isAmber ? Color.niftyAmberVivid.opacity(0.14) : .white.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isAmber ? Color.niftyAmberVivid.opacity(0.28) : .white.opacity(0.13),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func actionButton(title: String, icon: String?, isGlass: Bool, tinted: Bool = false) -> some View {
        Button {} label: {
            HStack(spacing: NiftySpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(tinted ? Color.niftyLavender : .white.opacity(0.78))
            .padding(.horizontal, NiftySpacing.lg)
            .padding(.vertical, NiftySpacing.md)
            .background(
                tinted
                    ? Color.niftyBrand.opacity(0.20)
                    : Color.white.opacity(0.07)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        tinted ? Color.niftyBrand.opacity(0.38) : .white.opacity(0.12),
                        lineWidth: 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var dateTimeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        let t = DateFormatter()
        t.dateFormat = "h:mm a"
        return "\(fmt.string(from: moment.startTime)) · \(t.string(from: moment.startTime))"
    }
}

// MARK: - Preview data

private extension Moment {
    static var filmPreviews: [Moment] {
        let cal = Calendar.current
        let base = Date()
        var ambient1 = AmbientMetadata()
        ambient1.sunPosition = .sunset
        ambient1.temperatureC = 22
        ambient1.nowPlayingArtist = "Tame Impala"

        var ambient2 = AmbientMetadata()
        ambient2.sunPosition = .night
        ambient2.temperatureC = 14

        return [
            Moment(
                label: "Hongdae Walk",
                assets: (0..<24).map { _ in Asset(type: .still, capturedAt: base, ambient: ambient1) },
                centroid: GPSCoordinate(latitude: 37.556, longitude: 126.923),
                startTime: cal.date(byAdding: .hour, value: -4, to: base) ?? base,
                endTime: base,
                dominantVibes: [.golden, .serene]
            ),
            Moment(
                label: "Itaewon Night",
                assets: (0..<18).map { _ in Asset(type: .clip, capturedAt: cal.date(byAdding: .day, value: -1, to: base) ?? base, ambient: ambient2) },
                centroid: GPSCoordinate(latitude: 37.534, longitude: 126.994),
                startTime: cal.date(byAdding: .day, value: -1, to: base) ?? base,
                endTime: cal.date(byAdding: .day, value: -1, to: base) ?? base,
                dominantVibes: [.moody, .electric]
            ),
        ]
    }
}

// MARK: - VibeTag emoji helper (shared with MomentCardView)
extension VibeTag {
    var emoji: String {
        switch self {
        case .golden:    return "✨"
        case .moody:     return "☁️"
        case .serene:    return "🌿"
        case .electric:  return "⚡️"
        case .nostalgic: return "📷"
        case .raw:       return "🌑"
        case .dreamy:    return "🌙"
        case .cozy:      return "🕯️"
        }
    }
}
