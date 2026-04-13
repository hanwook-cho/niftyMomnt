// NiftyData/Sources/Platform/JournalSuggestionsAdapter.swift
// JournalingSuggestions framework — iOS 17.2+.
// Foundation Models (on-device LLM) — iOS 26+ — used to generate richer NudgeCard questions.
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

    /// Authorization state for JournalingSuggestions framework.
    /// Persisted across `evaluateTriggers` calls to avoid redundant auth requests.
    private var isAuthorized: Bool = false
    private var authorizationRequested: Bool = false

    // MARK: - Init

    /// - Parameters:
    ///   - config: App feature/AI mode configuration.
    ///   - onDeviceLLM: Optional on-device LLM (Foundation Models iOS 26+) for generating
    ///     richer nudge question text from journaling suggestion content.
    public init(config: AppConfig, onDeviceLLM: (any OnDeviceLLMProtocol)? = nil) {
        self.config = config
        self.onDeviceLLM = onDeviceLLM
        log.debug("JournalSuggestionsAdapter — initialized; journalSuggest=\(config.features.contains(.journalSuggest)); onDeviceLLM=\(onDeviceLLM?.isAvailable == true ? "available" : "unavailable")")
    }

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
            await evaluateJournalingSuggestions(for: moment)
#else
            log.warning("evaluateTriggers — JournalingSuggestions not importable at compile time")
#endif
        } else {
            log.info("evaluateTriggers — iOS 17.2+ required for JournalingSuggestions; skipping (current OS too old)")
        }
    }

    public func submitResponse(_ response: NudgeResponse) async throws {
        log.debug("submitResponse — nudgeID=\(response.nudgeID.uuidString) type=\(response.responseType)")
        // Response stored via NudgeEngine — no JournalingSuggestions API call needed here.
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
            await refreshJournalingSuggestions()
#endif
        } else {
            log.info("refresh — iOS 17.2+ required; skipping")
        }
    }

    // MARK: - Internal: JournalingSuggestions (iOS 17.2+)

#if canImport(JournalingSuggestions)
    @available(iOS 17.2, *)
    private func evaluateJournalingSuggestions(for moment: Moment) async {
        // ── Authorization ─────────────────────────────────────────────────────
        guard await ensureAuthorized() else { return }

        // ── Fetch suggestions ─────────────────────────────────────────────────
        // JournalingSuggestions provides a SwiftUI picker (JournalingSuggestionsPicker)
        // as the primary API surface. Programmatic access fetches the same underlying
        // content the picker shows, filtered to assets matching our window.
        log.debug("evaluateJournalingSuggestions — momentID=\(moment.id.uuidString) startTime=\(moment.startTime)")

        do {
            // The framework returns suggestions for recent activity.
            // We filter to within 24 hours of the captured moment's start time.
            let suggestions = try await fetchRecentSuggestions()
            log.debug("evaluateJournalingSuggestions — fetched \(suggestions.count) raw suggestion(s)")

            let windowStart = moment.startTime.addingTimeInterval(-24 * 3600)
            let windowEnd   = moment.startTime.addingTimeInterval(24 * 3600)

            let matching = suggestions.filter { suggestion in
                let date = suggestion.date
                return date >= windowStart && date <= windowEnd
            }
            log.debug("evaluateJournalingSuggestions — \(matching.count) suggestion(s) in ±24h window")

            guard let best = matching.first else {
                log.debug("evaluateJournalingSuggestions — no matching suggestion; clearing nudge")
                nudgeSubject.send(nil)
                return
            }

            // ── Build NudgeCard question ──────────────────────────────────────
            let question = await buildNudgeQuestion(from: best, moment: moment)
            let card = NudgeCard(question: question, momentID: moment.id)
            log.info("evaluateJournalingSuggestions — publishing NudgeCard: \"\(question)\"")
            nudgeSubject.send(card)

        } catch {
            log.error("evaluateJournalingSuggestions — error: \(error.localizedDescription)")
            nudgeSubject.send(nil)
        }
    }

    @available(iOS 17.2, *)
    private func refreshJournalingSuggestions() async {
        guard await ensureAuthorized() else { return }

        do {
            let suggestions = try await fetchRecentSuggestions()
            log.debug("refresh — \(suggestions.count) suggestion(s) fetched")

            guard let latest = suggestions.first else {
                log.debug("refresh — no suggestions; clearing nudge")
                nudgeSubject.send(nil)
                return
            }
            let question = await buildNudgeQuestion(from: latest, moment: nil)
            let card = NudgeCard(question: question, momentID: nil)
            log.info("refresh — publishing refreshed NudgeCard: \"\(question)\"")
            nudgeSubject.send(card)
        } catch {
            log.error("refresh — error: \(error.localizedDescription)")
            nudgeSubject.send(nil)
        }
    }

    // MARK: - Authorization

    @available(iOS 17.2, *)
    private func ensureAuthorized() async -> Bool {
        if isAuthorized { return true }

        // Check current status first to avoid redundant system prompts.
        let status = JournalingSuggestions.authorizationStatus
        log.debug("ensureAuthorized — current status=\(String(describing: status))")

        switch status {
        case .authorized:
            isAuthorized = true
            return true
        case .denied:
            log.warning("ensureAuthorized — authorization denied by user; cannot fetch suggestions")
            return false
        case .notDetermined:
            guard !authorizationRequested else {
                log.debug("ensureAuthorized — authorization already requested but not yet determined; skipping")
                return false
            }
            authorizationRequested = true
            log.debug("ensureAuthorized — requesting authorization from system")
            await JournalingSuggestions.requestAuthorization()
            let newStatus = JournalingSuggestions.authorizationStatus
            log.info("ensureAuthorized — post-request status=\(String(describing: newStatus))")
            isAuthorized = (newStatus == .authorized)
            return isAuthorized
        @unknown default:
            log.warning("ensureAuthorized — unknown authorization status; treating as denied")
            return false
        }
    }

    // MARK: - Fetch helpers

    /// Returns up to 5 recent journaling suggestions, newest first.
    @available(iOS 17.2, *)
    private func fetchRecentSuggestions() async throws -> [JournalingSuggestion] {
        // JournalingSuggestions.current returns the suggestions the system has computed
        // for the user's recent activity (photos, workouts, locations, etc.).
        let all = await JournalingSuggestions.current
        log.debug("fetchRecentSuggestions — \(all.count) total suggestion(s) from framework")
        // Return up to 5, already sorted newest-first by the framework.
        return Array(all.prefix(5))
    }

    // MARK: - NudgeCard question generation

    /// Builds a question string for a NudgeCard.
    /// On iOS 26+ with on-device LLM available: generates a contextual question using Foundation Models.
    /// Fallback: returns a template question derived from the suggestion title.
    @available(iOS 17.2, *)
    private func buildNudgeQuestion(from suggestion: JournalingSuggestion, moment: Moment?) async -> String {
        // Try on-device LLM first (iOS 26+).
        if let llm = onDeviceLLM, llm.isAvailable {
            if #available(iOS 26, *) {
                let context = suggestion.title.isEmpty ? "a recent moment" : "\"\(suggestion.title)\""
                let momentContext = moment.map { "captured at \($0.label)" } ?? "recently"
                let prompt = """
                    You are a mindful journaling assistant. Generate one short, warm, open-ended reflection question (max 12 words) inspired by this activity: \(context), \(momentContext).
                    Only output the question text. No quotes, no extra words.
                    """
                do {
                    let question = try await llm.respond(to: prompt)
                    // Trim whitespace and ensure it ends with a question mark.
                    var clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.hasSuffix("?") { clean += "?" }
                    log.info("buildNudgeQuestion — Foundation Models question: \"\(clean)\"")
                    return clean
                } catch {
                    log.warning("buildNudgeQuestion — Foundation Models inference failed: \(error.localizedDescription); using template")
                }
            }
        }

        // Template fallback (all iOS versions).
        return templateQuestion(for: suggestion, moment: moment)
    }

    @available(iOS 17.2, *)
    private func templateQuestion(for suggestion: JournalingSuggestion, moment: Moment?) -> String {
        let title = suggestion.title.isEmpty ? "this moment" : suggestion.title
        let templates = [
            "What made \(title) worth remembering?",
            "How did you feel during \(title)?",
            "What would you tell someone about \(title)?",
            "What surprised you about \(title)?",
        ]
        // Deterministic selection based on suggestion content hash.
        let index = abs(title.hashValue) % templates.count
        return templates[index]
    }

#endif // canImport(JournalingSuggestions)
}

// MARK: - NudgeCard convenience init

private extension NudgeCard {
    init(question: String, momentID: UUID?) {
        self.init(id: UUID(), question: question, momentID: momentID)
    }
}
