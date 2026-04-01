// NiftyData/Sources/Platform/CoreMLIndexingAdapter.swift
// Wraps Vision, SoundAnalysis, CoreImage. All inference on Neural Engine.

import CoreImage
import CoreML
import Foundation
import NiftyCore
import SoundAnalysis
import Vision

public final class CoreMLIndexingAdapter: IndexingProtocol, Sendable {
    private let config: AppConfig

    public init(config: AppConfig) {
        self.config = config
    }

    public func classifyImage(_ assetID: UUID, imageData: Data) async throws -> [VibeTag] {
        // TODO: VNClassifyImageRequest
        return []
    }

    public func analyzeAudio(_ assetID: UUID, audioData: Data) async throws -> [AcousticTag] {
        // TODO: SNClassifySoundRequest with audioData
        return []
    }

    public func analyzePCMBuffer(
        _ assetID: UUID,
        buffer: UnsafeBufferPointer<Float>,
        sampleRate: Double
    ) async throws -> [AcousticTag] {
        // TODO: SNClassifySoundRequest with in-memory PCM — never a file
        return []
    }

    public func extractPalette(_ assetID: UUID, imageData: Data) async throws -> ChromaticPalette {
        // TODO: CoreImage dominant color extraction, up to 5 HSL colors
        return ChromaticPalette(colors: [])
    }

    public func harvestAmbientMetadata(at location: GPSCoordinate?, at time: Date) async throws -> AmbientMetadata {
        return AmbientMetadata()
    }

    public func clusterMoments(assets: [Asset]) async throws -> [Moment] {
        // TODO: 90-min / 200m clustering window
        return []
    }
}
