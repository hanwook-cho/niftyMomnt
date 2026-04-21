// NiftyCore/Sources/Engines/StoryEngine.swift
// Nonisolated — stateless scoring and arc assembly.

import Foundation

public enum ReelArc: Sendable {
    /// Consistent mood throughout — assets loop in vibe-coherence order.
    case vibeLoop
    /// 5+ assets — build from calm to motion climax.
    case risingAction
    /// Default — simple chronological sequence.
    case quietChronicle
}

public final class StoryEngine: Sendable {
    private let config: AppConfig
    private let vault: any VaultProtocol
    private let graph: any GraphProtocol
    private let lab: any LabClientProtocol
    // Piqd v0.3 — optional so existing niftyMomnt callers don't need to inject one.
    // Required only for Sequence assembly. `assembleSequence` throws `.assemblerUnavailable`
    // if the app forgot to wire it.
    private let sequenceAssembler: (any SequenceAssemblerProtocol)?

    public init(
        config: AppConfig,
        vault: any VaultProtocol,
        graph: any GraphProtocol,
        lab: any LabClientProtocol,
        sequenceAssembler: (any SequenceAssemblerProtocol)? = nil
    ) {
        self.config = config
        self.vault = vault
        self.graph = graph
        self.lab = lab
        self.sequenceAssembler = sequenceAssembler
    }

    // MARK: - assembleSequence (Piqd v0.3)

    public enum SequenceAssemblyError: Error, Equatable {
        case assemblerUnavailable
        case wrongFrameCount(got: Int, expected: Int)
        case missingFrame(URL)
    }

    /// Compose `frameURLs` (HEIC, in capture order) into a looping 9:16 H.264 MP4 and return
    /// a `SequenceStrip` with `shareReady=true`. `outputURL` is where the MP4 should land —
    /// typically the vault's temp or final location. Throws `.assemblerUnavailable` if no
    /// `SequenceAssemblerProtocol` was injected. The controller already guarantees
    /// `frameURLs.count == 6` under normal paths, but we still validate here for defensive
    /// depth in case a future caller passes a partial list.
    public func assembleSequence(
        frameURLs: [URL],
        outputURL: URL,
        frameDurationSeconds: Double = 0.333
    ) async throws -> SequenceStrip {
        guard let assembler = sequenceAssembler else {
            throw SequenceAssemblyError.assemblerUnavailable
        }
        guard frameURLs.count == 6 else {
            throw SequenceAssemblyError.wrongFrameCount(got: frameURLs.count, expected: 6)
        }
        for url in frameURLs where !FileManager.default.fileExists(atPath: url.path) {
            throw SequenceAssemblyError.missingFrame(url)
        }

        let (assembledURL, duration) = try await assembler.assemble(
            frameURLs: frameURLs,
            outputURL: outputURL,
            frameDurationSeconds: frameDurationSeconds
        )
        return SequenceStrip(
            frameURLs: frameURLs,
            assembledVideoURL: assembledURL,
            durationSeconds: duration,
            shareReady: true
        )
    }

    // MARK: - assembleReel

    /// Scores all assets in `moment`, selects an arc, orders them, and returns a
    /// capped sequence (≤60 s of content at 2.5 s per still frame).
    public func assembleReel(for moment: Moment) async throws -> [ReelAsset] {
        // Fetch fresh assets so scores reflect current GRDB state.
        let allAssets = try await graph.fetchAssets(for: moment.id)
        guard !allAssets.isEmpty else { return [] }

        // Restrict to composable types for v0.7 (AVReelComposer handles still/live/l4c).
        // Filtering here keeps arc selection and duration-cap honest about what will render.
        // Clips, echo, and atmosphere are deferred to v0.9 full AVComposition support.
        let assets = allAssets.filter { [.still, .live, .l4c].contains($0.type) }
        guard !assets.isEmpty else { return [] }

        // Score every asset in the context of this moment.
        let scored: [ReelAsset] = assets.map { asset in
            ReelAsset(asset: asset, score: score(asset, in: moment))
        }

        let arc = selectArc(scored: scored)
        let ordered = order(scored: scored, arc: arc)

        // Cap at 60 s: each still = 2.5 s, video assets counted at their duration (min 1 s).
        return capToSixtySeconds(ordered)
    }

    // MARK: - Public scoring

    /// Scores an asset within its moment cluster per §6.3 weights.
    public func score(_ asset: Asset, in moment: Moment) -> AssetScore {
        AssetScore(
            motionInterest: computeMotionInterest(asset),
            vibeCoherence: computeVibeCoherence(asset, in: moment),
            chromaticHarmony: computeChromaticHarmony(asset, in: moment),
            uniqueness: computeUniqueness(asset, in: moment)
        )
    }

    // MARK: - Arc selection

    public func selectArc(scored: [ReelAsset]) -> ReelArc {
        guard !scored.isEmpty else { return .quietChronicle }

        let coherenceValues = scored.map(\.score.vibeCoherence)
        let spread = coherenceValues.max()! - coherenceValues.min()!

        if spread < 0.2 { return .vibeLoop }
        if scored.count >= 5 { return .risingAction }
        return .quietChronicle
    }

    // MARK: - Ordering

    private func order(scored: [ReelAsset], arc: ReelArc) -> [ReelAsset] {
        switch arc {
        case .vibeLoop:
            // Most coherent first — reinforces the dominant mood
            return scored.sorted { $0.score.vibeCoherence > $1.score.vibeCoherence }
        case .risingAction:
            // Primary: ascending motionInterest (calm → high-energy).
            // Secondary: ascending vibeCoherence (off-vibe → on-vibe) as tiebreaker —
            // stills all score 0.4 so this produces a "builds to dominant mood" feel.
            return scored.sorted {
                if $0.score.motionInterest != $1.score.motionInterest {
                    return $0.score.motionInterest < $1.score.motionInterest
                }
                return $0.score.vibeCoherence < $1.score.vibeCoherence
            }
        case .quietChronicle:
            // Chronological
            return scored.sorted { $0.asset.capturedAt < $1.asset.capturedAt }
        }
    }

    // MARK: - Duration cap

    private func capToSixtySeconds(_ assets: [ReelAsset]) -> [ReelAsset] {
        var result: [ReelAsset] = []
        var totalSeconds: Double = 0
        for ra in assets {
            let duration: Double
            switch ra.asset.type {
            case .clip, .atmosphere, .echo, .sequence, .dual:
                duration = ra.asset.duration ?? 2.5
            default:
                duration = 2.5
            }
            if totalSeconds + duration > 60 { break }
            result.append(ra)
            totalSeconds += duration
        }
        return result
    }

    // MARK: - Scoring helpers

    private func computeMotionInterest(_ asset: Asset) -> Double {
        switch asset.type {
        case .clip:        return 0.9
        case .atmosphere:  return 0.6
        case .echo:        return 0.5
        case .still, .live, .l4c: return 0.4
        // Piqd asset types — only reachable when Piqd uses StoryEngine (v0.8+).
        case .sequence, .dual:    return 0.85
        case .movingStill:         return 0.5
        }
    }

    private func computeVibeCoherence(_ asset: Asset, in moment: Moment) -> Double {
        guard !moment.dominantVibes.isEmpty else { return 0 }
        let overlap = asset.vibeTags.filter { moment.dominantVibes.contains($0) }
        return Double(overlap.count) / Double(moment.dominantVibes.count)
    }

    /// Cosine similarity between asset's palette centroid (RGB) and moment's median palette.
    private func computeChromaticHarmony(_ asset: Asset, in moment: Moment) -> Double {
        guard let assetPalette = asset.palette, !assetPalette.colors.isEmpty else { return 0.5 }

        // Collect all palette colors across moment assets for median computation.
        let allColors = moment.assets.compactMap(\.palette).flatMap(\.colors)
        guard !allColors.isEmpty else { return 0.5 }

        let assetRGB  = rgbCentroid(assetPalette.colors)
        let momentRGB = rgbCentroid(allColors)
        return cosineSimilarity(assetRGB, momentRGB)
    }

    /// Fraction of moment assets that do NOT share a similar palette with this asset.
    private func computeUniqueness(_ asset: Asset, in moment: Moment) -> Double {
        let others = moment.assets.filter { $0.id != asset.id }
        guard !others.isEmpty else { return 1.0 }
        guard let assetPalette = asset.palette, !assetPalette.colors.isEmpty else { return 0.7 }

        let assetRGB = rgbCentroid(assetPalette.colors)
        let similarCount = others.filter { other in
            guard let otherPalette = other.palette, !otherPalette.colors.isEmpty else { return false }
            return cosineSimilarity(assetRGB, rgbCentroid(otherPalette.colors)) > 0.9
        }.count
        return 1.0 - (Double(similarCount) / Double(others.count))
    }

    // MARK: - Colour math (pure Swift, zero platform imports)

    private func rgbCentroid(_ colors: [HSLColor]) -> (Double, Double, Double) {
        guard !colors.isEmpty else { return (0, 0, 0) }
        let rgbs = colors.map { hslToRGB($0.hue, $0.saturation, $0.lightness) }
        let count = Double(rgbs.count)
        let r = rgbs.map(\.0).reduce(0, +) / count
        let g = rgbs.map(\.1).reduce(0, +) / count
        let b = rgbs.map(\.2).reduce(0, +) / count
        return (r, g, b)
    }

    private func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case   0..<60:  (r, g, b) = (c, x, 0)
        case  60..<120: (r, g, b) = (x, c, 0)
        case 120..<180: (r, g, b) = (0, c, x)
        case 180..<240: (r, g, b) = (0, x, c)
        case 240..<300: (r, g, b) = (x, 0, c)
        default:        (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    private func cosineSimilarity(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dot  = a.0 * b.0 + a.1 * b.1 + a.2 * b.2
        let normA = sqrt(a.0 * a.0 + a.1 * a.1 + a.2 * a.2)
        let normB = sqrt(b.0 * b.0 + b.1 * b.1 + b.2 * b.2)
        guard normA > 0, normB > 0 else { return 0.5 }
        return dot / (normA * normB)
    }
}
