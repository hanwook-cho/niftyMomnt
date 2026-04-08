// NiftyCore/Sources/Engines/StoryEngine.swift
// Nonisolated — stateless scoring and assembly.

import Foundation

public final class StoryEngine: Sendable {
    private let config: AppConfig
    private let vault: any VaultProtocol
    private let graph: any GraphProtocol
    private let lab: any LabClientProtocol

    public init(
        config: AppConfig,
        vault: any VaultProtocol,
        graph: any GraphProtocol,
        lab: any LabClientProtocol
    ) {
        self.config = config
        self.vault = vault
        self.graph = graph
        self.lab = lab
    }

    public func assembleReel(for moment: Moment) async throws -> [ReelAsset] {
        let scored = moment.assets.compactMap { asset -> ReelAsset? in
            guard let score = asset.score else { return nil }
            return ReelAsset(asset: asset, score: score)
        }
        return scored.sorted { $0.score.composite > $1.score.composite }
    }

    /// Scores an asset within its moment cluster per §6.3 weights.
    public func score(_ asset: Asset, in moment: Moment) -> AssetScore {
        AssetScore(
            motionInterest: computeMotionInterest(asset),
            vibeCoherence: computeVibeCoherence(asset, in: moment),
            chromaticHarmony: computeChromaticHarmony(asset, in: moment),
            uniqueness: computeUniqueness(asset, in: moment)
        )
    }

    // MARK: - Private scoring helpers

    private func computeMotionInterest(_ asset: Asset) -> Double {
        switch asset.type {
        case .clip: return 0.8  // placeholder — motion analysis TBD
        case .still, .live: return 0.4
        case .echo, .atmosphere: return 0.5
        case .l4c: return 0.4
        }
    }

    private func computeVibeCoherence(_ asset: Asset, in moment: Moment) -> Double {
        guard !moment.dominantVibes.isEmpty else { return 0 }
        let overlap = asset.vibeTags.filter { moment.dominantVibes.contains($0) }
        return Double(overlap.count) / Double(moment.dominantVibes.count)
    }

    private func computeChromaticHarmony(_ asset: Asset, in moment: Moment) -> Double {
        // Placeholder — HSL distance computation TBD
        return 0.5
    }

    private func computeUniqueness(_ asset: Asset, in moment: Moment) -> Double {
        // Placeholder — cosine similarity TBD
        return 0.7
    }
}
