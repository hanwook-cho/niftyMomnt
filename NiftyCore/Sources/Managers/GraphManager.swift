// NiftyCore/Sources/Managers/GraphManager.swift
// actor — serialises all graph mutations.

import Foundation

public actor GraphManager {
    private let graph: any GraphProtocol

    public init(graph: any GraphProtocol) {
        self.graph = graph
    }

    public func saveMoment(_ moment: Moment) async throws {
        try await graph.saveMoment(moment)
    }

    public func deleteMoment(_ momentID: UUID) async throws {
        try await graph.deleteMoment(momentID)
    }

    public func updatePlaceRecord(_ record: PlaceRecord) async throws {
        try await graph.updatePlaceRecord(record)
    }

    public func fetchMoments(query: GraphQuery = GraphQuery()) async throws -> [Moment] {
        try await graph.fetchMoments(query: query)
    }

    public func updatePreset(_ name: String, for assetID: UUID) async throws {
        try await graph.updatePreset(name, for: assetID)
    }

    public func fetchAcousticTags(for assetID: UUID) async throws -> [AcousticTag] {
        try await graph.fetchAcousticTags(for: assetID)
    }

    public func fetchTodayMomentCount() async throws -> Int {
        try await graph.fetchTodayMomentCount()
    }

    public func saveDerivativeRecord(_ derivative: DerivativeAsset) async throws {
        try await graph.saveDerivativeRecord(derivative)
    }

    public func deleteDerivativeRecord(for assetID: UUID) async throws {
        try await graph.deleteDerivativeRecord(for: assetID)
    }

    public func exportForCompanion() async throws -> GraphExport {
        try await graph.exportForCompanion()
    }

    // MARK: - v0.7

    public func fetchAssets(for momentID: UUID) async throws -> [Asset] {
        try await graph.fetchAssets(for: momentID)
    }

    // MARK: - v0.8

    public func markAssetPrivate(assetID: UUID, isPrivate: Bool) async throws {
        try await graph.markAssetPrivate(assetID: assetID, isPrivate: isPrivate)
    }

    // MARK: - L4C

    public func saveL4CRecord(_ record: L4CRecord) async throws {
        try await graph.saveL4CRecord(record)
    }

    public func fetchL4CRecords() async throws -> [L4CRecord] {
        try await graph.fetchL4CRecords()
    }

    /// Returns source asset IDs so the caller can delete them from the vault.
    public func deleteL4CRecord(_ id: UUID) async throws -> [UUID] {
        try await graph.deleteL4CRecord(id)
    }
}
