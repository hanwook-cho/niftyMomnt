// NiftyCore/Sources/Managers/LabClient.swift

import Foundation

public final class LabClient: Sendable {
    private let client: any LabClientProtocol

    public init(client: any LabClientProtocol) {
        self.client = client
    }

    public func generateCaption(for moment: Moment, tone: CaptionTone) async throws -> [CaptionCandidate] {
        try await client.generateCaption(for: moment, tone: tone)
    }

    public func requestLabSession(assets: [UUID], consent: LabConsent) async throws -> LabSession {
        try await client.requestLabSession(assets: assets, consent: consent)
    }

    public func verifyPurge(sessionID: UUID) async throws -> PurgeConfirmation {
        try await client.verifyPurge(sessionID: sessionID)
    }
}
