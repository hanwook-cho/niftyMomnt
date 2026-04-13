// NiftyData/Sources/Platform/JournalSuggestionsAdapter.swift
// JournalingSuggestions framework — iOS 17.2+.
// Foundation Models (on-device LLM) — iOS 26+ — used to generate richer NudgeCard questions.
//
// Architecture note:
//   JournalingSuggestions has NO programmatic fetch API. Suggestions are delivered exclusively
//   through the SwiftUI `JournalingSuggestionsPicker` picker via its `onCompletion` callback.
//   The UI layer (e.g. CaptureHubView post-capture overlay) presents the picker and calls
//   `receiveSuggestion(_:)` on this adapter when the user selects one.
//   `evaluateTriggers(for:)` then matches stored suggestions against the captured moment.
//
// Entitlement required: com.apple.developer.journaling-suggestion
// (Enable in Xcode → Signing & Capabilities before running on device.)

import Combine
import Foundation
import NiftyCore
import os

#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "JournalSuggestionsAdapter")

// MARK: - JournalSuggestionsAdapter

@MainActor
public final class JournalSuggestionsAdapter: NudgeEngineProtocol {
    private let nudgeSubject = CurrentValueSubject<NudgeCard?, Never>(nil)
    private let config: AppConfig
    private let onDeviceLLM: (any OnDeviceLLMProtocol)?

    // Suggestions fed in from JournalingSuggestionsPicker (UI layer).
    // Keyed by suggestion title hash for deduplication.
#if canImport(JournalingSuggestions)
    @available(iOS 17.2, *)
    private var storedSuggestions: [JournalingSuggestion] {
        get { _storedSuggestions as? [JournalingSuggestion] ?? [] }
        set { _storedSuggestions = newValue }
    }
#endif
    private var _storedSuggestions: Any = [String: Any]()

    // MARK: - Init

    public init(config: AppConfig, onDeviceLLM: (any OnDeviceLLMProtocol)? = nil) {
        self.config = config
        self.onDeviceLLM = onDeviceLLM
        if #available(iOS 17.2, *) {
#if canImport(JournalingSuggestions)
            _storedSuggestions = [JournalingSuggestion]()
#endif
        }
        log.debug("JournalSuggestionsAdapter — initialized; journalSuggest=\(config.features.contains(.journalSuggest)); onDeviceLLM=\(onDeviceLLM?.isAvailable == true ? "available" : "unavailable")")
    }

    // MARK: - Public: receive suggestion from picker

    /// Called by the UI layer after `JournalingSuggestionsPicker` completes.
    /// The picker handles all authorization; no explicit auth call needed here.
    ///
    /// - Parameter suggestion: The suggestion selected by the user.
#if canImport(JournalingSuggestions)
    @available(iOS 17.2, *)
    public func receiveSuggestion(_ suggestion: JournalingSuggestion) async {
        guard config.features.contains(.journalSuggest) else {
            log.debug("receiveSuggestion — .journalSuggest not in features; ignoring")
            return
        }
        storedSuggestions.append(suggestion)
        log.info("receiveSuggestion — title=\"\(suggestion.title)\" date=\(suggestion.date?.start.description ?? "nil") stored=\(storedSuggestions.count)")
    }
#endif

    // MARK: - NudgeEngineProtocol

    public var pendingNudge: AnyPublisher<NudgeCard?, Never> {
        nudgeSubject.eraseToAnyPublisher()
    }

    public func evaluateTriggers(for moment: Moment) async {
        guard config.features.contains(.journalSuggest) else {
            log.debug("evaluateTriggers — .journalSuggest not in features; skipping")
            return
        }
        if #available(iOS 17.2, *) {
#if canImport(JournalingSuggestions)
            await matchStoredSuggestions(for: moment)
#else
            log.warning("evaluateTriggers — JournalingSuggestions not importable at compile time")
#endif
        } else {
            log.info("evaluateTriggers — iOS 17.2+ required for JournalingSuggestions; skipping")
        }
    }

    public func submitResponse(_ response: NudgeResponse) async throws {
        log.debug("submitResponse — nudgeID=\(response.nudgeID.uuidString) type=\(response.responseType)")
    }

    public func dismiss(nudgeID: UUID) {
        log.debug("dismiss — nudgeID=\(nudgeID.uuidString)")
        nudgeSubject.send(nil)
    }

    public func snooze(nudgeID: UUID, until: Date) {
        log.debug("snooze — nudgeID=\(nudgeID.uuidString) until=\(until)")
        nudgeSubject.send(nil)
    }

    public func refresh() async {
        guard config.features.contains(.journalSuggest) else { return }
        if #available(iOS 17.2, *) {
#if canImport(JournalingSuggestions)
            evictStaleSuggestions()
            if storedSuggestions.isEmpty {
                log.debug("refresh — no stored suggestions after eviction; clearing nudge")
                nudgeSubject.send(nil)
            }
#endif
        }
    }

    // MARK: - Internal (iOS 17.2+)

#if canImport(JournalingSuggestions)

    @available(iOS 17.2, *)
    private func matchStoredSuggestions(for moment: Moment) async {
        log.debug("matchStoredSuggestions — stored=\(storedSuggestions.count) momentID=\(moment.id.uuidString)")
        evictStaleSuggestions()

        let windowStart = moment.startTime.addingTimeInterval(-24 * 3600)
        let windowEnd   = moment.startTime.addingTimeInterval(24 * 3600)

        let matching = storedSuggestions.filter { suggestion in
            // suggestion.date is DateInterval? — use .start for window comparison.
            // If date is nil (some suggestion types omit it), include it — better to
            // show a nudge than to silently drop the user's picker selection.
            guard let interval = suggestion.date else {
                log.debug("matchStoredSuggestions — suggestion \"\(suggestion.title)\" has no date; including")
                return true
            }
            let inWindow = interval.start >= windowStart && interval.start <= windowEnd
            log.debug("matchStoredSuggestions — \"\(suggestion.title)\" start=\(interval.start) inWindow=\(inWindow)")
            return inWindow
        }
        log.debug("matchStoredSuggestions — \(matching.count) suggestion(s) in ±24h window")

        guard let best = matching.first else {
            log.debug("matchStoredSuggestions — no match; clearing nudge")
            nudgeSubject.send(nil)
            return
        }

        let question = await buildNudgeQuestion(from: best, moment: moment)
        let card = NudgeCard(id: UUID(), question: question, momentID: moment.id)
        log.info("matchStoredSuggestions — publishing NudgeCard: \"\(question)\"")
        nudgeSubject.send(card)
    }

    /// Removes suggestions older than 48 hours to prevent stale nudges.
    @available(iOS 17.2, *)
    private func evictStaleSuggestions() {
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        let before = storedSuggestions.count
        storedSuggestions.removeAll { suggestion in
            guard let interval = suggestion.date else { return false }
            return interval.end < cutoff
        }
        let evicted = before - storedSuggestions.count
        if evicted > 0 {
            log.debug("evictStaleSuggestions — removed \(evicted) stale suggestion(s); remaining=\(storedSuggestions.count)")
        }
    }

    // MARK: - NudgeCard question generation

    @available(iOS 17.2, *)
    private func buildNudgeQuestion(from suggestion: JournalingSuggestion, moment: Moment) async -> String {
        let title = suggestion.title.isEmpty ? "this moment" : suggestion.title

        // Try on-device LLM first (iOS 26+).
        if let llm = onDeviceLLM, llm.isAvailable {
            if #available(iOS 26, *) {
                let momentContext = "captured at \(moment.label)"
                let prompt = """
                    You are a mindful journaling assistant. Generate one short, warm, open-ended reflection question (max 12 words) inspired by this activity: "\(title)", \(momentContext).
                    Only output the question text. No quotes, no extra words.
                    """
                do {
                    let question = try await llm.respond(to: prompt)
                    var clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.hasSuffix("?") { clean += "?" }
                    log.info("buildNudgeQuestion — Foundation Models: \"\(clean)\"")
                    return clean
                } catch {
                    log.warning("buildNudgeQuestion — Foundation Models failed: \(error.localizedDescription); using template")
                }
            }
        }

        return templateQuestion(title: title)
    }

    @available(iOS 17.2, *)
    private func templateQuestion(title: String) -> String {
        let templates = [
            "What made \(title) worth remembering?",
            "How did you feel during \(title)?",
            "What would you tell someone about \(title)?",
            "What surprised you about \(title)?",
        ]
        let index = abs(title.hashValue) % templates.count
        return templates[index]
    }

#endif // canImport(JournalingSuggestions)
}
