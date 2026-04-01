// NiftyCore/Sources/Engines/NudgeEngine.swift
// @MainActor — NudgeCard publisher subscribed by ViewModel on main thread.

import Combine
import Foundation

@MainActor
public final class NudgeEngine: NudgeEngineProtocol {
    private let config: AppConfig
    private let graph: any GraphProtocol
    private let lab: any LabClientProtocol
    private let triggerSource: any NudgeEngineProtocol

    private let nudgeSubject = CurrentValueSubject<NudgeCard?, Never>(nil)

    public var pendingNudge: AnyPublisher<NudgeCard?, Never> {
        nudgeSubject.eraseToAnyPublisher()
    }

    public init(
        config: AppConfig,
        graph: any GraphProtocol,
        lab: any LabClientProtocol,
        triggerSource: any NudgeEngineProtocol
    ) {
        self.config = config
        self.graph = graph
        self.lab = lab
        self.triggerSource = triggerSource
    }

    public func evaluateTriggers(for moment: Moment) async {
        guard config.features.contains(.nudgeEngine) else { return }
        // TODO: evaluate triggers via triggerSource and graph
    }

    public func submitResponse(_ response: NudgeResponse) async throws {
        try await graph.saveNudgeResponse(response)
        nudgeSubject.send(nil)
    }

    public func dismiss(nudgeID: UUID) {
        nudgeSubject.send(nil)
    }

    public func snooze(nudgeID: UUID, until: Date) {
        nudgeSubject.send(nil)
    }

    public func refresh() async {
        guard config.features.contains(.nudgeEngine) else { return }
        // TODO: poll triggerSource for new suggestions without a capture event
        await triggerSource.refresh()
    }
}
