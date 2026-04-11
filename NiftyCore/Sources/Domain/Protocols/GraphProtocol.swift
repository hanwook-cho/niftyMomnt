// NiftyCore/Sources/Domain/Protocols/GraphProtocol.swift

import Foundation

public protocol GraphProtocol: AnyObject, Sendable {
    func saveMoment(_ moment: Moment) async throws
    func updateVibeTag(_ tag: VibeTag, for assetID: UUID) async throws
    func updatePreset(_ name: String, for assetID: UUID) async throws   // v0.4
    func updateAcousticTag(_ tag: AcousticTag, for assetID: UUID) async throws
    func fetchAcousticTags(for assetID: UUID) async throws -> [AcousticTag]
    func saveNudgeResponse(_ response: NudgeResponse) async throws
    func mergeAcousticVibes(_ vibes: [VibeTag], for assetID: UUID) async throws  // v0.6
    func saveMoodPoint(_ point: MoodPoint) async throws
    func updatePlaceRecord(_ record: PlaceRecord) async throws
    func saveDerivativeRecord(_ derivative: DerivativeAsset) async throws
    func deleteDerivativeRecord(for assetID: UUID) async throws
    func deleteMoment(_ momentID: UUID) async throws
    func fetchMoments(query: GraphQuery) async throws -> [Moment]
    func fetchTodayMomentCount() async throws -> Int                    // v0.4
    func fetchPlaceHistory(limit: Int) async throws -> [PlaceRecord]
    func fetchMoodMap(range: DateInterval) async throws -> [MoodPoint]
    func exportForCompanion() async throws -> GraphExport
    // MARK: L4C
    func saveL4CRecord(_ record: L4CRecord) async throws
    func fetchL4CRecords() async throws -> [L4CRecord]
    func deleteL4CRecord(_ id: UUID) async throws -> [UUID]  // returns source asset IDs for vault cleanup
}
