// NiftyCore/Sources/Domain/UseCases/AssembleReelUseCase.swift

import Foundation

public final class AssembleReelUseCase: Sendable {
    private let engine: StoryEngine
    private let composer: any ReelComposerProtocol

    public init(engine: StoryEngine, composer: any ReelComposerProtocol) {
        self.engine = engine
        self.composer = composer
    }

    /// Score and order assets, then export to a `.mov` file.
    /// Returns the file URL of the assembled reel. The caller owns the file lifetime.
    public func execute(moment: Moment) async throws -> URL {
        let reelAssets = try await engine.assembleReel(for: moment)
        return try await composer.compose(reelAssets: reelAssets, momentID: moment.id)
    }

    /// Score and order only — no export. Used when the caller wants just the asset sequence.
    public func scoreOnly(moment: Moment) async throws -> [ReelAsset] {
        try await engine.assembleReel(for: moment)
    }
}
