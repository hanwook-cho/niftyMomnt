// NiftyCore/Sources/Domain/Protocols/IndexingProtocol.swift

import Foundation

public protocol IndexingProtocol: AnyObject, Sendable {
    func classifyImage(_ assetID: UUID, imageData: Data) async throws -> [VibeTag]
    func analyzeAudio(_ assetID: UUID, audioData: Data) async throws -> [AcousticTag]
    /// Used by SoundStamp — in-memory PCM, never a file.
    func analyzePCMBuffer(_ assetID: UUID, buffer: UnsafeBufferPointer<Float>, sampleRate: Double) async throws -> [AcousticTag]
    func extractPalette(_ assetID: UUID, imageData: Data) async throws -> ChromaticPalette
    func harvestAmbientMetadata(at location: GPSCoordinate?, at time: Date) async throws -> AmbientMetadata
    func clusterMoments(assets: [Asset]) async throws -> [Moment]
}
