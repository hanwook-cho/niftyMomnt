// Apps/niftyMomnt/UI/Journal/JournalFeedView.swift
// Spec §5.1 v1.7 — Film Archive dark editorial feed.
//
// Header:  "Film" 26pt/900 · amber "N rolls" badge · search + grid glass buttons
// Section: "THIS WEEK · MAR 28–31" 10pt/800 at 22% opacity
// Cards:   MomentCardView dark editorial (see MomentCardView.swift)
// Detail:  MomentDetailView sheet on card tap

import NiftyCore
import NiftyData
import os
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
import AVFoundation
import AVKit
import Photos
import PhotosUI
import SwiftUI
import UIKit

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "FilmFeed")

// MARK: - PHLivePhotoView representable

/// Wraps PHLivePhotoView for SwiftUI. Starts .full playback automatically on load.
struct LivePhotoPlayerView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let replayToken: Int

    final class Coordinator {
        var lastReplayToken: Int = -1
        var lastLivePhotoID: ObjectIdentifier?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        let livePhotoID = ObjectIdentifier(livePhoto)
        let livePhotoChanged = context.coordinator.lastLivePhotoID != livePhotoID
        let replayRequested = context.coordinator.lastReplayToken != replayToken

        if livePhotoChanged {
            uiView.livePhoto = livePhoto
            context.coordinator.lastLivePhotoID = livePhotoID
        }

        if livePhotoChanged || replayRequested {
            uiView.stopPlayback()
            uiView.startPlayback(with: .full)
            context.coordinator.lastReplayToken = replayToken
        }
    }
}

// MARK: - UIActivityViewController representable

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct InlineVideoPlayerView: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}

private struct EchoAudioPlayerCardView: View {
    let player: AVPlayer
    let duration: TimeInterval?

    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 18) {
            Circle()
                .fill(Color.niftyAmberVivid.opacity(0.16))
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(Color.niftyAmberVivid)
                )

            VStack(spacing: 6) {
                Text("Echo")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white.opacity(0.92))
                Text(duration.map(Self.durationString) ?? "Audio only")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.46))
            }

            Button {
                if isPlaying {
                    player.pause()
                } else {
                    player.seek(to: .zero)
                    player.play()
                }
                isPlaying.toggle()
            } label: {
                Label(isPlaying ? "Pause Echo" : "Play Echo", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black.opacity(0.86))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Color.niftyAmberVivid)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "#130A04"), Color(hex: "#2E1605"), Color(hex: "#130A04")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onDisappear {
            player.pause()
            isPlaying = false
        }
    }

    fileprivate static func durationString(_ duration: TimeInterval) -> String {
        let total = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct FilmFeedView: View {
    let container: AppContainer
    let onScrollTopChanged: (Bool) -> Void
    let onPullDownToDismiss: () -> Void

    @State private var moments: [Moment] = []
    @State private var l4cRecords: [L4CRecord] = []
    @State private var selectedMoment: Moment? = nil
    @State private var selectedL4C: L4CRecord? = nil
    @State private var isGridLayout: Bool = false
    @State private var topSafeArea: CGFloat = 59
    @State private var isAtTop: Bool = true

    var body: some View {
        ZStack(alignment: .top) {
            Color.niftyFilmBg.ignoresSafeArea()

            if moments.isEmpty && l4cRecords.isEmpty {
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

                        // Sectioned card feed (Moments + L4C interleaved chronologically)
                        ForEach(groupedFeedItems, id: \.0) { (sectionLabel, items) in
                            sectionHeader(sectionLabel)
                                .padding(.horizontal, NiftySpacing.lg)
                                .padding(.top, NiftySpacing.xs)

                            ForEach(items, id: \.id) { item in
                                switch item {
                                case .moment(let moment):
                                    MomentCardView(
                                        moment: moment,
                                        presetName: derivedPresetName(for: moment),
                                        presetAccent: derivedPresetAccent(for: moment),
                                        onTap: {
                                            log.debug("MomentCardView tapped: \(moment.id.uuidString)")
                                            selectedMoment = moment
                                        },
                                        onPlay: {
                                            log.debug("MomentCardView play tapped: \(moment.id.uuidString)")
                                            selectedMoment = moment
                                        }
                                    )
                                    .padding(.horizontal, NiftySpacing.sm)
                                case .l4c(let record):
                                    L4CMomentCardView(
                                        record: record
                                    ) { // This is the single onTap closure
                                        log.debug("L4CMomentCardView tapped: \(record.id.uuidString)")
                                        selectedL4C = record
                                    }
                                    .padding(.horizontal, NiftySpacing.sm)
                                }
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
                            log.debug("FilmFeedView: Pull-down gesture detected (h: \(value.translation.height))")
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
        .sheet(item: $selectedL4C) { record in
            L4CDetailView(record: record, container: container)
        }
        .onAppear {
            readWindowSafeArea()
            log.debug("FilmFeedView appeared — loading moments")
            Task { await loadFeed() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .niftyMomentCaptured)) { _ in
            log.debug("FilmFeedView received niftyMomentCaptured — refreshing")
            Task { await loadFeed() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .niftyMomentDeleted)) { _ in
            log.debug("FilmFeedView received niftyMomentDeleted — refreshing")
            Task { await loadFeed() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .niftyVaultChanged)) { _ in
            log.debug("FilmFeedView received niftyVaultChanged — refreshing")
            Task { await loadFeed() }
        }
    }

    private func loadFeed() async {
        log.debug("loadFeed called")
        async let fetchMoments = container.graphManager.fetchMoments()
        async let fetchL4C = container.graphManager.fetchL4CRecords()
        do {
            let (m, l) = try await (fetchMoments, fetchL4C)
            moments = m
            l4cRecords = l
            log.debug("loadFeed — \(m.count) moment(s), \(l.count) L4C(s)")
        } catch {
            log.error("loadFeed — failed: \(error)")
        }
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

    // MARK: - Feed Item

    /// Union type for items in the chronological feed (Moments and L4C records).
    enum FeedItem: Identifiable {
        case moment(Moment)
        case l4c(L4CRecord)

        var id: UUID {
            switch self {
            case .moment(let m): return m.id
            case .l4c(let r):   return r.id
            }
        }
        var date: Date {
            switch self {
            case .moment(let m): return m.startTime
            case .l4c(let r):   return r.capturedAt
            }
        }
    }

    private var groupedFeedItems: [(String, [FeedItem])] {
        let calendar = Calendar.current
        let now = Date()

        var all: [FeedItem] = moments.map { .moment($0) } + l4cRecords.map { .l4c($0) }
        all.sort { $0.date > $1.date }

        var result: [(String, [FeedItem])] = []
        var seen: [String: Int] = [:]
        for item in all {
            let key = sectionLabel(for: item.date, calendar: calendar, now: now)
            if let idx = seen[key] {
                result[idx].1.append(item)
            } else {
                seen[key] = result.count
                result.append((key, [item]))
            }
        }
        return result
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

    // MARK: - Preset derivation (v0.4: prefers stored preset, falls back to AI-classified vibes)

    private func derivedPresetName(for moment: Moment) -> String {
        // v0.4: use stored preset if available
        if let stored = moment.selectedPresetName,
           VibePresetUI.defaults.contains(where: { $0.name == stored }) {
            return stored
        }
        // Fallback: derive from AI-classified dominant vibe
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
        // v0.4: use stored preset accent if available
        if let stored = moment.selectedPresetName,
           let preset = VibePresetUI.defaults.first(where: { $0.name == stored }) {
            return preset.accentColor
        }
        // Fallback: derive from AI-classified dominant vibe
        switch moment.dominantVibes.first {
        case .golden:    return Color(hex: "#E8A020")
        case .moody:     return Color(hex: "#8EB4D4")
        case .nostalgic: return Color(hex: "#C8A882")
        case .electric:  return Color(hex: "#C4B5FD")
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

private let detailLog = Logger(subsystem: "com.hwcho99.niftymomnt", category: "MomentDetail")

struct MomentDetailView: View {
    let moment: Moment
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @State private var currentAssetIndex: Int = 0
    @State private var isSharePresented: Bool = false
    @State private var shareItems: [Any] = []
    @State private var isDeleteConfirmPresented: Bool = false
    @State private var isDeleting: Bool = false
    @State private var isExportingToPhotoLibrary: Bool = false
    @State private var exportAlertMessage: String? = nil
    @State private var heroImage: UIImage? = nil
    @State private var livePhoto: PHLivePhoto? = nil
    @State private var videoPlayer: AVPlayer? = nil
    @State private var videoAspectRatio: CGFloat? = nil
    @State private var audioPlayer: AVPlayer? = nil
    @State private var audioDuration: TimeInterval? = nil
    @State private var livePhotoReplayToken: Int = 0
    @State private var heroLoadRequestID: String? = nil
    /// Acoustic tags loaded separately — SoundStamp writes them ~1s after capture,
    /// after the moment is already in the feed. Refreshed via niftyAcousticTagsUpdated notification.
    @State private var acousticTags: [AcousticTag] = []
    // v0.7 — Reel assembly
    @State private var isAssemblingReel: Bool = false
    @State private var reelURL: URL? = nil
    @State private var isReelPlayerPresented: Bool = false
    @State private var reelError: String? = nil
    // v0.8 — Move to Vault
    @State private var isMovingToVault: Bool = false
    @State private var vaultActionMessage: String? = nil
    @State private var dismissAfterVaultAlert: Bool = false
    // v0.9 — AI Caption
    @State private var isGeneratingCaption: Bool = false
    @State private var generatedCaption: String? = nil
    @State private var captionUpgradeNotice: String? = nil
    // v0.9 — Journaling Suggestions picker
    @State private var isJournalPickerPresented: Bool = false
    @State private var isFixing: Bool = false
    @State private var fixResultMessage: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "#100C08").ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Zone A — detail nav bar
                    detailNavBar

                    // Photo zone — constrained to a fraction of the available height
                    ZStack(alignment: .bottom) {
                        heroPhoto
                        paginationIndicator
                            .padding(.bottom, NiftySpacing.lg)
                    }
                    .frame(height: max(160, geo.size.height * 0.72))
                    .clipped()
                    .gesture(
                        DragGesture(minimumDistance: 30)
                            .onEnded { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                if value.translation.width < 0 {
                                    // swipe left → next asset
                                    if currentAssetIndex < moment.assets.count - 1 {
                                        currentAssetIndex += 1
                                    }
                                } else {
                                    // swipe right → previous asset
                                    if currentAssetIndex > 0 {
                                        currentAssetIndex -= 1
                                    }
                                }
                            }
                    )

                    Spacer(minLength: 0)
                }
            }
        }
        // safeAreaInset pins the bottom sheet above the home indicator regardless of
        // sheet presentation context — more reliable than hardcoded padding(bottom: 34).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            glassBottomSheet
        }
        .preferredColorScheme(.dark)
        .task(id: moment.id) {
            currentAssetIndex = 0
            await loadHeroImage(at: 0)
            await loadAcousticTags()
        }
        .onChange(of: currentAssetIndex) { _, newIndex in
            Task { await loadHeroImage(at: newIndex) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .niftyAcousticTagsUpdated)) { note in
            guard let assetIDStr = note.object as? String,
                  moment.assets.contains(where: { $0.id.uuidString == assetIDStr }) else { return }
            Task { await loadAcousticTags() }
        }
        .alert(
            "Photo Library Export",
            isPresented: Binding(
                get: { exportAlertMessage != nil },
                set: { if !$0 { exportAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportAlertMessage ?? "")
        }
        .alert(
            "Reel Error",
            isPresented: Binding(get: { reelError != nil }, set: { if !$0 { reelError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reelError ?? "")
        }
        .alert(
            "Private Vault",
            isPresented: Binding(get: { vaultActionMessage != nil }, set: { if !$0 { vaultActionMessage = nil } })
        ) {
            Button("OK", role: .cancel) {
                if dismissAfterVaultAlert {
                    dismissAfterVaultAlert = false
                    dismiss()
                }
            }
        } message: {
            Text(vaultActionMessage ?? "")
        }
        .alert(
            "Photo Fix",
            isPresented: Binding(get: { fixResultMessage != nil }, set: { if !$0 { fixResultMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fixResultMessage ?? "")
        }
        .sheet(isPresented: $isReelPlayerPresented) {
            if let url = reelURL {
                ReelPlayerView(url: url)
            }
        }
        // v0.9 — Journaling Suggestions picker.
        // Must be on the outermost view so SwiftUI has a full-screen presentation anchor.
        // bottomPanel is too small a subview — picker silently fails to present from there.
#if canImport(JournalingSuggestions)
        .journalingSuggestionsPicker(isPresented: $isJournalPickerPresented) { suggestion in
            detailLog.info("journalSuggestionsPicker — received: \"\(suggestion.title)\" date=\(suggestion.date?.start.description ?? "nil")")
            await container.journalSuggestionsAdapter.receiveSuggestion(suggestion)
            detailLog.info("journalSuggestionsPicker — forwarded to adapter ✓")
        }
#endif
    }

    private func assembleAndPlayReel() {
        guard !isAssemblingReel else { return }
        isAssemblingReel = true
        Task {
            do {
                let url = try await container.storyUseCase.execute(moment: moment)
                reelURL = url
                isReelPlayerPresented = true
            } catch {
                detailLog.error("assembleReel failed: \(error)")
                reelError = "Could not assemble reel: \(error.localizedDescription)"
            }
            isAssemblingReel = false
        }
    }

    private func moveCurrentAssetToVault() {
        guard !isMovingToVault else { return }
        guard moment.assets.indices.contains(currentAssetIndex) else { return }
        let asset = moment.assets[currentAssetIndex]
        guard !asset.isPrivate else {
            vaultActionMessage = "This shot is already in your private vault."
            return
        }
        isMovingToVault = true
        detailLog.debug("moveToVault — assetID=\(asset.id.uuidString)")
        Task {
            do {
                try await container.vaultManager.moveToVault(assetID: asset.id)
                detailLog.debug("moveToVault done — assetID=\(asset.id.uuidString)")
                await MainActor.run {
                    isMovingToVault = false
                    dismissAfterVaultAlert = true
                    vaultActionMessage = "Shot moved to your private vault."
                    // dismiss() is called in the alert OK button, not here
                }
            } catch {
                detailLog.error("moveToVault failed — \(error)")
                await MainActor.run {
                    isMovingToVault = false
                    vaultActionMessage = "Could not move to vault: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadAcousticTags() async {
        guard let first = moment.assets.first else { return }
        let tags = (try? await container.graphManager.fetchAcousticTags(for: first.id)) ?? []
        acousticTags = tags
    }

    private func loadHeroImage(at index: Int = 0) async {
        guard moment.assets.indices.contains(index) else { return }
        let first = moment.assets[index]
        let requestID = UUID().uuidString
        heroLoadRequestID = requestID
        detailLog.debug("loadHeroImage[\(requestID)] start — momentID=\(moment.id.uuidString) assetID=\(first.id.uuidString) type=\(first.type.rawValue) index=\(index)/\(moment.assets.count) cancelled=\(Task.isCancelled)")
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let assetsDir = dir.appendingPathComponent("assets")
        let jpegURL = assetsDir.appendingPathComponent("\(first.id.uuidString).jpg")
        detailLog.debug("loadHeroImage[\(requestID)] — jpeg=\(jpegURL.lastPathComponent)")
        heroImage = nil
        livePhoto = nil
        videoPlayer = nil
        videoAspectRatio = nil
        audioPlayer = nil
        audioDuration = nil
        if first.type == .echo || first.type == .atmosphere {
            let audioURL = assetsDir.appendingPathComponent("\(first.id.uuidString).m4a")
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                detailLog.error("loadHeroImage[\(requestID)] — missing M4A for echo assetID=\(first.id.uuidString)")
                return
            }
            let avAsset = AVURLAsset(url: audioURL)
            let playerItem = AVPlayerItem(asset: avAsset)
            let player = AVPlayer(playerItem: playerItem)
            
            // Loop Atmosphere audio
            if first.type == .atmosphere {
                player.actionAtItemEnd = .none
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
                    player.seek(to: .zero)
                    player.play()
                }
            }
            
            audioPlayer = player
            let duration = (try? await avAsset.load(.duration))?.seconds ?? first.duration ?? 0
            audioDuration = duration
            let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
            let fileSize = attributes?[.size] as? Int64 ?? 0
            detailLog.debug("loadHeroImage[\(requestID)] — audio player ready for \(audioURL.lastPathComponent) (size: \(fileSize)B, duration: \(String(format: "%.2f", duration))s)")
            
            if first.type == .echo { return }
            // Atmosphere continues to load JPEG below
        }
        guard let data = try? Data(contentsOf: jpegURL), let img = UIImage(data: data) else {
            if first.type == .clip {
                let movURL = assetsDir.appendingPathComponent("\(first.id.uuidString).mov")
                guard FileManager.default.fileExists(atPath: movURL.path) else {
                    detailLog.error("loadHeroImage[\(requestID)] — missing MOV for video assetID=\(first.id.uuidString)")
                    return
                }

                let avAsset = AVURLAsset(url: movURL)
                let generator = AVAssetImageGenerator(asset: avAsset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1600, height: 1600)

                if let ratio = await resolvedVideoAspectRatio(for: avAsset) {
                    videoAspectRatio = ratio
                    detailLog.debug("loadHeroImage[\(requestID)] — video aspectRatio=\(ratio)")
                }

                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    heroImage = UIImage(cgImage: cgImage)
                } else {
                    detailLog.warning("loadHeroImage[\(requestID)] — could not extract poster frame for video assetID=\(first.id.uuidString)")
                }

                let player = AVPlayer(url: movURL)
                player.actionAtItemEnd = .pause
                videoPlayer = player
                detailLog.debug("loadHeroImage[\(requestID)] — video player ready for \(movURL.lastPathComponent)")
                return
            }

            detailLog.error("loadHeroImage[\(requestID)] — failed to decode JPEG for assetID=\(first.id.uuidString)")
            return
        }
        detailLog.debug("loadHeroImage[\(requestID)] — JPEG OK \(data.count)B cancelled=\(Task.isCancelled)")
        heroImage = img

        // For Live assets: also load the companion MOV as a PHLivePhoto for playback.
        if first.type == .live {
            let movURL = assetsDir.appendingPathComponent("\(first.id.uuidString).mov")
            guard FileManager.default.fileExists(atPath: movURL.path) else {
                detailLog.warning("loadHeroImage[\(requestID)] — live MOV not found at \(movURL.lastPathComponent), showing static frame")
                return
            }
            detailLog.debug("loadHeroImage[\(requestID)] — requesting PHLivePhoto jpeg=\(jpegURL.lastPathComponent) mov=\(movURL.lastPathComponent)")
            var callbackCount = 0
            PHLivePhoto.request(
                withResourceFileURLs: [jpegURL, movURL],
                placeholderImage: img,
                targetSize: CGSize(width: 1080, height: 1920),
                contentMode: .aspectFill
            ) { photo, info in
                callbackCount += 1
                let infoSummary = info
                    .map { "\($0.key)=\($0.value)" }
                    .sorted()
                    .joined(separator: ", ")
                let isDegraded = (info[PHLivePhotoInfoIsDegradedKey] as? NSNumber)?.boolValue ?? false
                detailLog.debug("loadHeroImage[\(requestID)] callback #\(callbackCount) — photoNil=\(photo == nil) degraded=\(isDegraded) activeRequest=\(heroLoadRequestID == requestID) info={\(infoSummary)}")

                guard heroLoadRequestID == requestID else {
                    detailLog.debug("loadHeroImage[\(requestID)] — ignoring stale PHLivePhoto callback #\(callbackCount)")
                    return
                }

                guard let photo else {
                    detailLog.warning("loadHeroImage[\(requestID)] — PHLivePhoto.request returned nil on callback #\(callbackCount)")
                    return
                }

                detailLog.debug("loadHeroImage[\(requestID)] — applying PHLivePhoto from callback #\(callbackCount)")
                Task { @MainActor in
                    self.livePhoto = photo
                    self.livePhotoReplayToken += 1
                }
            }
        }
        detailLog.debug("loadHeroImage[\(requestID)] finish — livePhotoSet=\(livePhoto != nil) cancelled=\(Task.isCancelled)")
    }

    private func resolvedVideoAspectRatio(for asset: AVURLAsset) async -> CGFloat? {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformed = naturalSize.applying(preferredTransform)
            let width = abs(transformed.width)
            let height = abs(transformed.height)
            guard width > 0, height > 0 else { return nil }
            return width / height
        } catch {
            detailLog.error("resolvedVideoAspectRatio — failed: \(error)")
            return nil
        }
    }

    // v0.9 — Generate Caption via VoiceProseEngine priority ladder
    private func generateCaption() async {
        isGeneratingCaption = true
        generatedCaption = nil
        captionUpgradeNotice = nil
        detailLog.info("generateCaption — triggered for momentID=\(moment.id.uuidString) vibes=[\(moment.dominantVibes.map(\.rawValue).joined(separator: ","))]")
        let result = await container.voiceProseEngine.generateAICaption(
            for: moment,
            tone: .poetic,
            config: container.config
        )
        await MainActor.run {
            generatedCaption = result.candidates.first?.text
            captionUpgradeNotice = result.llmUnavailabilityReason
            isGeneratingCaption = false
            detailLog.info("generateCaption — done: \"\(result.candidates.first?.text.prefix(60) ?? "(nil)")\" candidates=\(result.candidates.count) upgradeNotice=\(result.llmUnavailabilityReason != nil)")
        }
    }

    private func deleteMoment() async {
        isDeleting = true
        detailLog.debug("deleteMoment — momentID=\(moment.id.uuidString) assets=\(moment.assets.count)")
        do {
            // 1. Delete vault files for every asset in this moment
            for asset in moment.assets {
                try? await container.vaultManager.delete(asset.id)
            }
            // 2. Remove moment + asset rows from graph
            try await container.graphManager.deleteMoment(moment.id)
            detailLog.debug("deleteMoment — done")
        } catch {
            detailLog.error("deleteMoment — failed: \(error)")
        }
        // 3. Notify feed to refresh, then dismiss
        NotificationCenter.default.post(name: .niftyMomentDeleted, object: nil)
        dismiss()
    }

    private func exportCurrentAssetToPhotoLibrary() {
        guard moment.assets.indices.contains(currentAssetIndex) else {
            exportAlertMessage = "This shot is no longer available to export."
            return
        }

        let asset = moment.assets[currentAssetIndex]
        guard asset.type != .echo else {
            exportAlertMessage = "Echo audio can be shared from niftyMomnt, but it can’t be exported to Photo Library."
            return
        }
        isExportingToPhotoLibrary = true
        detailLog.debug("exportToPhotoLibrary — start assetID=\(asset.id.uuidString) type=\(asset.type.rawValue)")

        Task {
            do {
                try await container.shareUseCase.exportToPhotoLibrary(assetID: asset.id)
                await MainActor.run {
                    isExportingToPhotoLibrary = false
                    exportAlertMessage = asset.type == .live
                        ? "Live Photo saved to your Photo Library."
                        : exportSuccessMessage(for: asset.type)
                }
                detailLog.debug("exportToPhotoLibrary — success assetID=\(asset.id.uuidString)")
            } catch {
                await MainActor.run {
                    isExportingToPhotoLibrary = false
                    exportAlertMessage = exportFailureMessage(for: error, assetType: asset.type)
                }
                detailLog.error("exportToPhotoLibrary — failed assetID=\(asset.id.uuidString): \(error)")
            }
        }
    }

    private func presentShareSheet() {
        guard moment.assets.indices.contains(currentAssetIndex) else {
            exportAlertMessage = "This shot is no longer available to share."
            return
        }

        let asset = moment.assets[currentAssetIndex]
        guard let items = shareItems(for: asset), !items.isEmpty else {
            exportAlertMessage = "Could not prepare this shot for sharing."
            return
        }

        shareItems = items
        isSharePresented = true
        detailLog.debug("shareSheet — present assetID=\(asset.id.uuidString) type=\(asset.type.rawValue) items=\(items.count)")
    }

    private func shareItems(for asset: Asset) -> [Any]? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let assetsDir = dir.appendingPathComponent("assets")
        let jpegURL = assetsDir.appendingPathComponent("\(asset.id.uuidString).jpg")
        let movURL = assetsDir.appendingPathComponent("\(asset.id.uuidString).mov")
        let audioURL = assetsDir.appendingPathComponent("\(asset.id.uuidString).m4a")

        switch asset.type {
        case .still, .l4c:
            return FileManager.default.fileExists(atPath: jpegURL.path) ? [jpegURL] : nil
        case .live:
            if FileManager.default.fileExists(atPath: jpegURL.path),
               FileManager.default.fileExists(atPath: movURL.path) {
                return [jpegURL, movURL]
            }
            return FileManager.default.fileExists(atPath: jpegURL.path) ? [jpegURL] : nil
        case .clip, .atmosphere:
            return FileManager.default.fileExists(atPath: movURL.path) ? [movURL] : nil
        case .echo:
            return FileManager.default.fileExists(atPath: audioURL.path) ? [audioURL] : nil
        }
    }

    private func exportFailureMessage(for error: Error, assetType: AssetType) -> String {
        if String(describing: error).contains("photoLibraryAccessDenied") {
            return "Photo Library access was denied. Please allow Add Photos access in Settings and try again."
        }
        if String(describing: error).contains("unsupportedPhotoLibraryExport") {
            return "This Echo can be shared from niftyMomnt, but it can’t be added to Photo Library."
        }
        return assetType == .live
            ? "Could not save this Live Photo to your Photo Library."
            : exportFailureFallbackMessage(for: assetType)
    }

    private func exportSuccessMessage(for assetType: AssetType) -> String {
        switch assetType {
        case .still, .l4c:
            return "Photo saved to your Photo Library."
        case .live:
            return "Live Photo saved to your Photo Library."
        case .clip, .atmosphere:
            return "Video saved to your Photo Library."
        case .echo:
            return "Echo audio is ready to share."
        }
    }

    private func exportFailureFallbackMessage(for assetType: AssetType) -> String {
        switch assetType {
        case .still, .l4c:
            return "Could not save this photo to your Photo Library."
        case .live:
            return "Could not save this Live Photo to your Photo Library."
        case .clip, .atmosphere:
            return "Could not save this video to your Photo Library."
        case .echo:
            return "This Echo can’t be saved to Photo Library."
        }
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

            // Share
            Button { presentShareSheet() } label: {
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
            .sheet(isPresented: $isSharePresented) {
                ActivityViewController(activityItems: shareItems)
            }
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
            // Live Photo playback (PHLivePhotoView) when MOV companion is present.
            if let lp = livePhoto {
                LivePhotoPlayerView(livePhoto: lp, replayToken: livePhotoReplayToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { livePhotoReplayToken += 1 }
            } else if let player = audioPlayer {
                EchoAudioPlayerCardView(player: player, duration: audioDuration)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let player = videoPlayer {
                InlineVideoPlayerView(player: player)
                    .aspectRatio(videoAspectRatio ?? (9.0 / 16.0), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .clipped()
            } else if let img = heroImage {
                // Static JPEG fallback (also used for all non-Live asset types).
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#180A00"), location: 0),
                        .init(color: Color(hex: "#B06820"), location: 0.52),
                        .init(color: Color(hex: "#FFE8B0"), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

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
            HStack(spacing: 4) {
                Text("Shot \(currentAssetIndex + 1) of \(moment.assets.count)")
                if currentAssetType == .echo, let duration = audioDuration {
                    Text("· \(EchoAudioPlayerCardView.durationString(duration))")
                }
            }
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(.white.opacity(0.88))
            HStack {
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

            // Acoustic tags row (v0.5 — SoundStamp; loaded async, refreshed via notification)
            if !acousticTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NiftySpacing.sm) {
                        ForEach(acousticTags.prefix(5), id: \.tag) { tag in
                            acousticChip(tag)
                        }
                    }
                    .padding(.horizontal, NiftySpacing.lg)
                }
                .padding(.top, NiftySpacing.xs)
            }

            // v0.9 — AI Caption (capped at 3 lines so it never pushes buttons off-screen)
            if let caption = generatedCaption {
                VStack(alignment: .leading, spacing: NiftySpacing.xs) {
                    Text(caption)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(3)
                    if let notice = captionUpgradeNotice {
                        Text(notice)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, NiftySpacing.lg)
                .padding(.top, NiftySpacing.xs)
            }

            // Actions row — scrollable so buttons never overflow on narrow screens.
            // Trash is pinned outside the scroll area so it's always reachable.
            HStack(spacing: NiftySpacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NiftySpacing.sm) {
                        if currentAssetSupportsFix {
                            actionButton(title: "Fix", icon: "checkmark.circle", isGlass: true) {
                                Task { await quickApplyFix() }
                            }
                            .disabled(isFixing)
                        }
                        // v0.7 — Play Reel (visible when moment has ≥2 still-type assets)
                        let reelableCount = moment.assets.filter { [.still, .live, .l4c].contains($0.type) }.count
                        if reelableCount >= 2 {
                            actionButton(
                                title: isAssemblingReel ? "Assembling…" : "Play Reel",
                                icon: isAssemblingReel ? nil : "play.circle",
                                isGlass: false,
                                tinted: true
                            ) {
                                assembleAndPlayReel()
                            }
                            .disabled(isAssemblingReel)
                        }
                        // v0.8 — Move to Vault (only for non-private assets)
                        let currentAsset = moment.assets.indices.contains(currentAssetIndex)
                            ? moment.assets[currentAssetIndex] : nil
                        if let currentAsset, !currentAsset.isPrivate {
                            actionButton(
                                title: isMovingToVault ? "Moving…" : "Vault",
                                icon: isMovingToVault ? nil : "lock.fill",
                                isGlass: true
                            ) {
                                moveCurrentAssetToVault()
                            }
                            .disabled(isMovingToVault)
                        }
                        // v0.9 — Generate Caption
                        actionButton(
                            title: isGeneratingCaption ? "Writing…" : (generatedCaption == nil ? "Caption" : "New Caption"),
                            icon: isGeneratingCaption ? nil : "text.quote",
                            isGlass: true
                        ) {
                            Task { await generateCaption() }
                        }
                        .disabled(isGeneratingCaption)
                        // v0.9 — Journaling Suggestions picker
                        journalPickerButton
                        // Export — label kept short to fit comfortably
                        if currentAssetType != .echo {
                            actionButton(
                                title: isExportingToPhotoLibrary ? "Exporting…" : "Save to Photos",
                                icon: isExportingToPhotoLibrary ? nil : "square.and.arrow.down",
                                isGlass: false,
                                tinted: true
                            ) {
                                exportCurrentAssetToPhotoLibrary()
                            }
                        }
                    }
                    .padding(.leading, NiftySpacing.lg)
                    .padding(.trailing, NiftySpacing.lg)
                }
                // Actions button — long-press (contextMenu) for overflow actions
                actionsButton

                // Trash — always visible, pinned to trailing edge
                Button { isDeleteConfirmPresented = true } label: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.22), lineWidth: 0.5))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Group {
                                if isDeleting {
                                    ProgressView()
                                        .tint(.red.opacity(0.7))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "trash")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.red.opacity(0.70))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .padding(.trailing, NiftySpacing.lg)
                .confirmationDialog("Delete this photo?", isPresented: $isDeleteConfirmPresented, titleVisibility: .visible) {
                    Button("Delete Photo", role: .destructive) {
                        Task { await deleteMoment() }
                    }
                } message: {
                    Text("This will permanently remove the photo and its data.")
                }
            }
            .padding(.vertical, NiftySpacing.lg)
        }
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(Color(red: 12/255, green: 9/255, blue: 6/255).opacity(0.82))
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
                }
        )
    }

    private func acousticChip(_ tag: AcousticTag) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .medium))
            Text(tag.tag.rawValue)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.niftyAmberVivid.opacity(0.80))
        .padding(.horizontal, NiftySpacing.md)
        .padding(.vertical, 3)
        .background(Color.niftyAmberVivid.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.niftyAmberVivid.opacity(0.22), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

    /// "From Journal" action button — sets isJournalPickerPresented = true.
    /// The actual picker is attached via .journalingSuggestionsPicker(isPresented:) modifier
    /// on the bottom panel container so the SwiftUI system has a full-view presentation anchor.
    @ViewBuilder
    private var journalPickerButton: some View {
        if container.config.features.contains(.journalSuggest) {
            actionButton(
                title: "From Journal",
                icon: "book.closed",
                isGlass: true
            ) {
                detailLog.info("journalPickerButton — tapped; setting isJournalPickerPresented=true")
                isJournalPickerPresented = true
            }
        }
    }

    private func actionButton(
        title: String, icon: String?, isGlass: Bool, tinted: Bool = false,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
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

    private var actionsButton: some View {
        actionButton(title: "Actions", icon: "ellipsis", isGlass: true) {}
            .contextMenu {
                if currentAssetSupportsFix {
                    Button(action: { Task { await quickApplyFix() } }) {
                        Label(isFixing ? "Fixing…" : "Fix", systemImage: "wand.and.stars")
                    }
                }
                let reelableCount = moment.assets.filter { [.still, .live, .l4c].contains($0.type) }.count
                if reelableCount >= 2 {
                    Button(action: { assembleAndPlayReel() }) {
                        Label(isAssemblingReel ? "Assembling…" : "Play Reel", systemImage: "play.circle")
                    }
                }
                if let currentAsset = moment.assets.indices.contains(currentAssetIndex) ? moment.assets[currentAssetIndex] : nil,
                   !currentAsset.isPrivate {
                    Button(action: { moveCurrentAssetToVault() }) {
                        Label(isMovingToVault ? "Moving…" : "Vault", systemImage: "lock.fill")
                    }
                }
                Button(action: { Task { await generateCaption() } }) {
                    Label(isGeneratingCaption ? "Writing…" : (generatedCaption == nil ? "Caption" : "New Caption"), systemImage: "text.quote")
                }
                if container.config.features.contains(.journalSuggest) {
                    Button(action: { isJournalPickerPresented = true }) {
                        Label("From Journal", systemImage: "book.closed")
                    }
                }
                if currentAssetType != .echo {
                    Button(action: { exportCurrentAssetToPhotoLibrary() }) {
                        Label(isExportingToPhotoLibrary ? "Exporting…" : "Save to Photos", systemImage: "square.and.arrow.down")
                    }
                }
            }
    }

    private func quickApplyFix() async {
        guard !isFixing else { return }
        guard moment.assets.indices.contains(currentAssetIndex) else { return }
        let asset = moment.assets[currentAssetIndex]
        isFixing = true
        fixResultMessage = nil
        do {
            _ = try await container.fixUseCase.applyFix(to: asset.id, cropRect: nil, rotationDegrees: 0, flipH: false, flipV: false)
            Task { await loadHeroImage(at: currentAssetIndex) }
            fixResultMessage = "Fix applied successfully."
        } catch {
            fixResultMessage = "Could not apply fix: \(error.localizedDescription)"
        }
        isFixing = false
    }

    private var dateTimeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        let t = DateFormatter()
        t.dateFormat = "h:mm a"
        return "\(fmt.string(from: moment.startTime)) · \(t.string(from: moment.startTime))"
    }

    private var currentAssetType: AssetType {
        guard moment.assets.indices.contains(currentAssetIndex) else { return .still }
        return moment.assets[currentAssetIndex].type
    }

    private var currentAssetSupportsFix: Bool {
        switch currentAssetType {
        case .still, .live:
            return true
        case .clip, .echo, .atmosphere, .l4c:
            return false
        }
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

// MARK: - ReelPlayerView (v0.7)

/// Full-screen AVPlayer sheet for assembled reel playback.
private struct ReelPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button { dismiss() } label: {
                Circle()
                    .fill(.black.opacity(0.52))
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 56)
            .padding(.trailing, 16)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            player = AVPlayer(url: url)
        }
    }
}

// MARK: - WeatherCondition emoji helper

extension WeatherCondition {
    var emoji: String {
        switch self {
        case .clear:   return "☀️"
        case .cloudy:  return "☁️"
        case .rain:    return "🌧"
        case .snow:    return "❄️"
        case .fog:     return "🌫"
        case .thunder: return "⛈"
        }
    }
}
