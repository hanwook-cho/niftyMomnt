// NiftyCore/Sources/Engines/NudgeEngine.swift
// @MainActor — NudgeCard publisher subscribed by ViewModel on main thread.

import Combine
import Foundation
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "NudgeEngine")

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
        guard config.features.contains(.nudgeEngine) else {
            log.debug("evaluateTriggers — skipped (nudgeEngine feature not enabled)")
            return
        }
        let question = templateQuestion(for: moment.dominantVibes)
        let card = NudgeCard(question: question, momentID: moment.id)
        log.debug("evaluateTriggers — publishing nudge id=\(card.id) vibes=[\(moment.dominantVibes.map(\.rawValue).joined(separator: ","))] q='\(question)'")
        nudgeSubject.send(card)
    }

    public func submitResponse(_ response: NudgeResponse) async throws {
        log.debug("submitResponse — nudgeID=\(response.nudgeID) type=\(response.responseType)")
        try await graph.saveNudgeResponse(response)
        nudgeSubject.send(nil)
        log.debug("submitResponse — saved + cleared")
    }

    public func dismiss(nudgeID: UUID) {
        log.debug("dismiss — nudgeID=\(nudgeID)")
        nudgeSubject.send(nil)
    }

    public func snooze(nudgeID: UUID, until: Date) {
        log.debug("snooze — nudgeID=\(nudgeID) until=\(until)")
        nudgeSubject.send(nil)
    }

    public func refresh() async {
        guard config.features.contains(.nudgeEngine) else { return }
        log.debug("refresh — polling triggerSource")
        await triggerSource.refresh()
    }

    // MARK: - Template questions

    private func templateQuestion(for vibes: [VibeTag]) -> String {
        // Priority order: first dominant vibe wins; fallback for empty
        for vibe in vibes {
            if let q = Self.vibeQuestions[vibe] { return q }
        }
        return "What do you want to remember about this moment?"
    }

    private static let vibeQuestions: [VibeTag: String] = [
        .golden:    "What made this feel so golden?",
        .moody:     "What were you feeling here?",
        .serene:    "What brought you this sense of calm?",
        .electric:  "What gave this moment its energy?",
        .nostalgic: "What memory does this stir?",
        .raw:       "What were you really feeling here?",
        .dreamy:    "What were you imagining?",
        .cozy:      "What made this feel so comfortable?",
    ]
}
