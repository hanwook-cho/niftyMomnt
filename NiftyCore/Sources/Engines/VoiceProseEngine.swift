// NiftyCore/Sources/Engines/VoiceProseEngine.swift

import Foundation

public final class VoiceProseEngine: Sendable {
    private let lab: any LabClientProtocol

    public init(lab: any LabClientProtocol) {
        self.lab = lab
    }

    // MARK: - On-device prose (no network)

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

    // MARK: - Network prose (Lab Mode, v0.9+)

    public func transform(_ transcript: String, styles: [ProseStyle]) async throws -> [ProseVariant] {
        try await lab.transformProse(transcript, styles: styles)
    }

    // MARK: - Helpers

    /// Moment label format: "Morning · San Francisco · Thursday"
    /// Extracts the middle segment (e.g. "San Francisco") as the place name.
    private static func extractLocation(from label: String) -> String {
        let parts = label.components(separatedBy: " · ")
        guard parts.count >= 2 else { return "" }
        return parts[1]
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
