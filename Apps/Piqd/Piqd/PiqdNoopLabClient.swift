// Apps/Piqd/Piqd/PiqdNoopLabClient.swift
// Piqd doesn't use Lab (Mode-1 captions, Mode-2 encrypted VLM) in the v0.x cycle. StoryEngine
// requires a LabClientProtocol in its init only because niftyMomnt's reel/caption paths use it;
// Piqd's only current StoryEngine consumer is `assembleSequence`, which never touches `lab`.
// This no-op conformance satisfies the signature without pulling in LabNetworkAdapter's URLSession
// + certificate-pinning surface.

import Foundation
import NiftyCore

final class PiqdNoopLabClient: LabClientProtocol, @unchecked Sendable {
    func generateCaption(for moment: Moment, tone: CaptionTone) async throws -> [CaptionCandidate] { [] }
    func transformProse(_ transcript: String, styles: [ProseStyle]) async throws -> [ProseVariant] { [] }
    func requestLabSession(assets: [UUID], consent: LabConsent) async throws -> LabSession {
        LabSession(assetIDs: [])
    }
    func processLabSession(_ session: LabSession) async throws -> LabResult {
        LabResult(sessionID: session.id, captions: [])
    }
    func verifyPurge(sessionID: UUID) async throws -> PurgeConfirmation {
        PurgeConfirmation(sessionID: sessionID)
    }
}
