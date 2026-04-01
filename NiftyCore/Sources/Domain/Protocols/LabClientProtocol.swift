// NiftyCore/Sources/Domain/Protocols/LabClientProtocol.swift

import Foundation

public protocol LabClientProtocol: AnyObject, Sendable {
    func generateCaption(for moment: Moment, tone: CaptionTone) async throws -> [CaptionCandidate]
    func transformProse(_ transcript: String, styles: [ProseStyle]) async throws -> [ProseVariant]
    func requestLabSession(assets: [UUID], consent: LabConsent) async throws -> LabSession
    func processLabSession(_ session: LabSession) async throws -> LabResult
    func verifyPurge(sessionID: UUID) async throws -> PurgeConfirmation
}
