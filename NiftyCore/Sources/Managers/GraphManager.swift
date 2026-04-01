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

    public func saveDerivativeRecord(_ derivative: DerivativeAsset) async throws {
        try await graph.saveDerivativeRecord(derivative)
    }

    public func deleteDerivativeRecord(for assetID: UUID) async throws {
        try await graph.deleteDerivativeRecord(for: assetID)
    }

    public func exportForCompanion() async throws -> GraphExport {
        try await graph.exportForCompanion()
    }
}
