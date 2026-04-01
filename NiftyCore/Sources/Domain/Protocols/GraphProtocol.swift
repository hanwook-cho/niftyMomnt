// NiftyCore/Sources/Domain/Protocols/GraphProtocol.swift

import Foundation

public protocol GraphProtocol: AnyObject, Sendable {
    func saveMoment(_ moment: Moment) async throws
    func updateVibeTag(_ tag: VibeTag, for assetID: UUID) async throws
    func updateAcousticTag(_ tag: AcousticTag, for assetID: UUID) async throws
    func saveNudgeResponse(_ response: NudgeResponse) async throws
    func saveMoodPoint(_ point: MoodPoint) async throws
    func updatePlaceRecord(_ record: PlaceRecord) async throws
    func saveDerivativeRecord(_ derivative: DerivativeAsset) async throws
    func deleteDerivativeRecord(for assetID: UUID) async throws
    func fetchMoments(query: GraphQuery) async throws -> [Moment]
    func fetchPlaceHistory(limit: Int) async throws -> [PlaceRecord]
    func fetchMoodMap(range: DateInterval) async throws -> [MoodPoint]
    func exportForCompanion() async throws -> GraphExport
}
