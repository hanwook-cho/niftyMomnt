// NiftyCore/Sources/Engines/VoiceProseEngine.swift

import Foundation

public final class VoiceProseEngine: Sendable {
    private let lab: any LabClientProtocol

    public init(lab: any LabClientProtocol) {
        self.lab = lab
    }

    public func transform(_ transcript: String, styles: [ProseStyle]) async throws -> [ProseVariant] {
        try await lab.transformProse(transcript, styles: styles)
    }
}
