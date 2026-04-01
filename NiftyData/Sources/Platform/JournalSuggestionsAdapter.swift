// NiftyData/Sources/Platform/JournalSuggestionsAdapter.swift
// JournalingSuggestions framework — iOS 17.2+, available iOS 26.

import Combine
import Foundation
import NiftyCore

@MainActor
public final class JournalSuggestionsAdapter: NudgeEngineProtocol {
    private let nudgeSubject = CurrentValueSubject<NudgeCard?, Never>(nil)

    public init(config: AppConfig) {}

    public var pendingNudge: AnyPublisher<NudgeCard?, Never> {
        nudgeSubject.eraseToAnyPublisher()
    }

    public func evaluateTriggers(for moment: Moment) async {
        // TODO: JSAuthorizationStatus check, fetch journaling suggestions
    }

    public func submitResponse(_ response: NudgeResponse) async throws {}
    public func dismiss(nudgeID: UUID) { nudgeSubject.send(nil) }
    public func snooze(nudgeID: UUID, until: Date) { nudgeSubject.send(nil) }
    public func refresh() async {
        // TODO: re-fetch JournalingApp suggestions on background refresh
    }
}
