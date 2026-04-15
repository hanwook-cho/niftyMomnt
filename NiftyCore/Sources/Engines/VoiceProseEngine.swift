// NiftyCore/Sources/Engines/VoiceProseEngine.swift
// Zero platform imports — pure Swift domain engine.
//
// Caption / prose generation priority ladder:
//   1. On-device LLM (FoundationModels, iOS 26+) — when onDeviceLLM.isAvailable
//   2. Enhanced AI network (Mode-1) — when config.aiModes.contains(.enhancedAI)
//   3. On-device templates — always available as final fallback

import Foundation
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "VoiceProseEngine")

public final class VoiceProseEngine: Sendable {
    private let lab: any LabClientProtocol
    /// Optional on-device LLM (FoundationModelAdapter). Nil-safe: engine degrades
    /// gracefully to Mode-1 network or template when this is nil or unavailable.
    private let onDeviceLLM: (any OnDeviceLLMProtocol)?

    // MARK: - Init

    /// - Parameters:
    ///   - lab:          Network Lab client (Mode-1 Enhanced AI, Mode-2 visual Lab).
    ///   - onDeviceLLM:  On-device LLM adapter (FoundationModels iOS 26+). Pass `nil`
    ///                   on older deployments; the engine falls back automatically.
    public init(lab: any LabClientProtocol, onDeviceLLM: (any OnDeviceLLMProtocol)? = nil) {
        self.lab = lab
        self.onDeviceLLM = onDeviceLLM
    }

    // MARK: - On-device prose (no network, all iOS versions)

    /// Generates one `ProseVariant` per `ProseStyle` from the moment's dominant vibe and label.
    /// Deterministic — same moment always produces the same variant index.
    public func generateProse(for moment: Moment) -> [ProseVariant] {
        let vibe     = moment.dominantVibes.first?.rawValue ?? "quiet"
        let location = Self.extractLocation(from: moment.label).isEmpty
                       ? "here"
                       : Self.extractLocation(from: moment.label)
        let seed = abs(moment.id.hashValue)

        return ProseStyle.allCases.map { style in
            let templates = Self.templates[style]!
            let text = templates[seed % templates.count]
                .replacingOccurrences(of: "{vibe}", with: vibe)
                .replacingOccurrences(of: "{location}", with: location)
            return ProseVariant(text: text, style: style)
        }
    }

    // MARK: - Network prose (Lab Mode-1, v0.9+)

    public func transform(_ transcript: String, styles: [ProseStyle]) async throws -> [ProseVariant] {
        try await lab.transformProse(transcript, styles: styles)
    }

    // MARK: - AI caption (v0.9+)

    /// Generates ranked caption candidates from ambient metadata + vibe tags.
    ///
    /// **Priority ladder:**
    /// 1. **On-device LLM (iOS 26+):** If `onDeviceLLM.isAvailable`, uses Foundation Models
    ///    locally — no network, no data leaves the device.
    /// 2. **Enhanced AI network (Mode-1):** If `config.aiModes.contains(.enhancedAI)`, calls
    ///    the Lab caption endpoint via `LabClientProtocol.generateCaption`.
    /// 3. **On-device template fallback:** Always available; returns one `CaptionCandidate`
    ///    built from the deterministic template engine. A non-nil `llmUnavailabilityReason`
    ///    is returned alongside so callers can surface a capability notice to the user.
    ///
    /// - Returns: A tuple of `(candidates, llmUnavailabilityReason)`.
    ///   `llmUnavailabilityReason` is non-nil **only** when the caller is on iOS < 26 AND
    ///   no network AI mode is configured — indicating the user could unlock better captions
    ///   by updating iOS.
    @discardableResult
    public func generateAICaption(
        for moment: Moment,
        tone: CaptionTone = .poetic,
        config: AppConfig
    ) async -> (candidates: [CaptionCandidate], llmUnavailabilityReason: String?) {

        let vibeDesc = moment.dominantVibes.map(\.rawValue).joined(separator: ",")
        let llmAvail = onDeviceLLM?.isAvailable == true
        let hasNetwork = config.aiModes.contains(.enhancedAI)
        log.info("generateAICaption — moment=\(moment.id.uuidString) tone=\(tone.rawValue) vibes=[\(vibeDesc)] llmAvailable=\(llmAvail) enhancedAI=\(hasNetwork)")

        // ── 1. On-device LLM (iOS 26+) ────────────────────────────────────────
        if let llm = onDeviceLLM, llm.isAvailable {
            log.debug("generateAICaption — path: on-device LLM (iOS 26+)")
            let prompt = Self.buildCaptionPrompt(for: moment, tone: tone)
            do {
                let text = try await llm.respond(to: prompt)
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                log.info("generateAICaption — ✓ on-device LLM returned \(cleaned.count) chars: \"\(cleaned.prefix(60))\"")
                return (candidates: [CaptionCandidate(text: cleaned, tone: tone)],
                        llmUnavailabilityReason: nil)
            } catch {
                log.warning("generateAICaption — on-device LLM threw: \(error) — falling through to network/template")
            }
        } else {
            log.debug("generateAICaption — on-device LLM: skipped (isAvailable=\(llmAvail))")
        }

        // ── 2. Enhanced AI network (Mode-1) ───────────────────────────────────
        if config.aiModes.contains(.enhancedAI) {
            log.debug("generateAICaption — path: enhanced AI network (Mode-1)")
            do {
                let networkCandidates = try await lab.generateCaption(for: moment, tone: tone)
                if !networkCandidates.isEmpty {
                    log.info("generateAICaption — ✓ network returned \(networkCandidates.count) candidate(s): \"\(networkCandidates.first?.text.prefix(60) ?? "")\"")
                    return (candidates: networkCandidates, llmUnavailabilityReason: nil)
                }
                log.warning("generateAICaption — network returned empty candidates — falling through to template")
            } catch {
                log.warning("generateAICaption — network generateCaption threw: \(error) — falling through to template")
            }
        } else {
            log.debug("generateAICaption — network: skipped (enhancedAI not in aiModes)")
        }

        // ── 3. On-device template fallback ────────────────────────────────────
        log.debug("generateAICaption — path: on-device template fallback")
        let prose = generateProse(for: moment)
        let templateCandidate = prose.first.map { variant in
            CaptionCandidate(text: variant.text, tone: tone)
        } ?? CaptionCandidate(text: "A moment worth keeping.", tone: tone)

        // Determine whether to surface an iOS upgrade notice.
        // Show the notice only when: no LLM is available AND no network AI mode is configured.
        let noLLM     = onDeviceLLM?.isAvailable != true
        let noNetwork = !config.aiModes.contains(.enhancedAI)
        let reason: String? = (noLLM && noNetwork)
            ? "Enhanced AI captions require iOS 26 or later. Update iOS to unlock on-device AI."
            : nil

        log.info("generateAICaption — ✓ template fallback: \"\(templateCandidate.text.prefix(60))\" upgradeNotice=\(reason != nil)")
        return (candidates: [templateCandidate], llmUnavailabilityReason: reason)
    }

    // MARK: - Helpers

    /// Moment label format: "Morning · San Francisco · Thursday"
    /// Extracts the middle segment (e.g. "San Francisco") as the place name.
    private static func extractLocation(from label: String) -> String {
        let parts = label.components(separatedBy: " · ")
        guard parts.count >= 2 else { return "" }
        return parts[1]
    }

    /// Builds the Foundation Models prompt for caption generation.
    private static func buildCaptionPrompt(for moment: Moment, tone: CaptionTone) -> String {
        let vibe     = moment.dominantVibes.first?.rawValue ?? "quiet"
        let location = extractLocation(from: moment.label)
        let label    = moment.label
        let toneDesc: String
        switch tone {
        case .poetic:          toneDesc = "poetic and lyrical"
        case .minimal:         toneDesc = "minimal and understated"
        case .descriptive:     toneDesc = "vivid and descriptive"
        case .conversational:  toneDesc = "warm and conversational"
        }
        var parts = ["Moment: \(label)", "Vibe: \(vibe)"]
        if !location.isEmpty { parts.append("Place: \(location)") }
        let context = parts.joined(separator: ". ")

        return """
            You are a thoughtful photo journaling app. Write one \(toneDesc) caption (max 20 words) for this moment.
            \(context).
            Output only the caption text. No hashtags, no quotes.
            """
    }

    // MARK: - Template library (3 variants per style)

    private static let templates: [ProseStyle: [String]] = [
        .journal: [
            "A {vibe} afternoon in {location}, caught before it slipped away.",
            "Something {vibe} about {location} today — the kind you want to keep.",
            "{vibe} and unhurried in {location}. Everything exactly as it was.",
        ],
        .haiku: [
            "{vibe} light settles slow /\n{location} holds the quiet /\nnothing needs to move",
            "amber and {vibe} /\n{location} folds into dusk /\none frame is enough",
            "the air felt {vibe} /\njust {location} and the sky /\nsilence holds the rest",
        ],
        .bullet: [
            "• {vibe} · {location}",
            "• {vibe} · worth keeping · {location}",
            "• {vibe} · nothing added · {location}",
        ],
        .narrative: [
            "It started {vibe} in {location}, the way the good ones usually do.",
            "There's something {vibe} about {location} — hard to put into words.",
            "You were there in {location}, and it was {vibe}. That's enough.",
        ],
    ]
}
