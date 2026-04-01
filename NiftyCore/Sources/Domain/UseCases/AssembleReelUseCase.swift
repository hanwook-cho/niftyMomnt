// NiftyCore/Sources/Domain/UseCases/AssembleReelUseCase.swift

import Foundation

public final class AssembleReelUseCase: Sendable {
    private let engine: StoryEngine

    public init(engine: StoryEngine) {
        self.engine = engine
    }

    public func execute(moment: Moment) async throws -> [ReelAsset] {
        try await engine.assembleReel(for: moment)
    }
}
