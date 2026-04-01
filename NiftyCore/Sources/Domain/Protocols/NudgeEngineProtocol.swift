// NiftyCore/Sources/Domain/Protocols/NudgeEngineProtocol.swift

import Combine
import Foundation

@MainActor
public protocol NudgeEngineProtocol: AnyObject, Sendable {
    var pendingNudge: AnyPublisher<NudgeCard?, Never> { get }
    func evaluateTriggers(for moment: Moment) async
    func submitResponse(_ response: NudgeResponse) async throws
    func dismiss(nudgeID: UUID)
    func snooze(nudgeID: UUID, until: Date)
    /// Called by BGAppRefreshTask to poll for new nudge triggers without a capture event.
    func refresh() async
}
