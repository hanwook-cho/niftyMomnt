// NiftyCore/Sources/Domain/UseCases/GenerateNudgeUseCase.swift

import Foundation

@MainActor
public final class GenerateNudgeUseCase {
    private let nudgeEngine: any NudgeEngineProtocol

    public init(nudgeEngine: any NudgeEngineProtocol) {
        self.nudgeEngine = nudgeEngine
    }

    public func evaluate(moment: Moment) async {
        await nudgeEngine.evaluateTriggers(for: moment)
    }
}
