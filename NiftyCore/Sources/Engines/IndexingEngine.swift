// NiftyCore/Sources/Engines/IndexingEngine.swift
// actor — serialises background indexing to prevent concurrent graph writes.

import Foundation
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "IndexingEngine")

public actor IndexingEngine {
    private let config: AppConfig
    private let adapter: any IndexingProtocol
    private let graph: any GraphProtocol

    public init(config: AppConfig, adapter: any IndexingProtocol, graph: any GraphProtocol) {
        self.config = config
        self.adapter = adapter
        self.graph = graph
    }

    /// Classify a single asset immediately (inline, non-batched).
    /// Vision inference runs on a detached background task to avoid blocking any actor.
    public func classifyImmediate(id: UUID, imageData: Data) async -> [VibeTag] {
        log.debug("classifyImmediate — dispatching to background task id=\(id.uuidString)")
        let adapter = self.adapter
        let tags = await Task.detached(priority: .userInitiated) {
            do {
                return try await adapter.classifyImage(id, imageData: imageData)
            } catch {
                log.error("classifyImmediate — adapter.classifyImage threw: \(error)")
                return [] as [VibeTag]
            }
        }.value
        log.debug("classifyImmediate — done, \(tags.count) tag(s) returned")
        return tags
    }

    /// Extract chromatic palette immediately (inline, non-batched). Runs on background task.
    public func extractPaletteImmediate(id: UUID, imageData: Data) async -> ChromaticPalette? {
        log.debug("extractPaletteImmediate — id=\(id.uuidString)")
        let adapter = self.adapter
        let palette = await Task.detached(priority: .userInitiated) {
            try? await adapter.extractPalette(id, imageData: imageData)
        }.value
        log.debug("extractPaletteImmediate — done, colors=\(palette?.colors.count ?? 0)")
        return palette
    }

    /// Harvest ambient metadata (weather + sun position) immediately. Runs on background task.
    public func harvestAmbientImmediate(location: GPSCoordinate?, time: Date) async -> AmbientMetadata {
        log.debug("harvestAmbientImmediate — location=\(location != nil ? "set" : "nil")")
        let adapter = self.adapter
        let ambient = await Task.detached(priority: .userInitiated) {
            (try? await adapter.harvestAmbientMetadata(at: location, at: time)) ?? AmbientMetadata()
        }.value
        log.debug("harvestAmbientImmediate — done, weather=\(ambient.weather?.rawValue ?? "nil") sun=\(ambient.sunPosition?.rawValue ?? "nil")")
        return ambient
    }

    /// Process a batch of unindexed assets. Called by BGProcessingTask.
    public func processBatch(assets: [(id: UUID, data: Data, type: AssetType)]) async {
        for asset in assets {
            await indexAsset(id: asset.id, data: asset.data, type: asset.type)
        }
    }

    private func indexAsset(id: UUID, data: Data, type: AssetType) async {
        do {
            // Step 1: Image classification (visual types)
            if [.still, .live, .clip, .atmosphere].contains(type) {
                let vibeTags = try await adapter.classifyImage(id, imageData: data)
                for tag in vibeTags {
                    try await graph.updateVibeTag(tag, for: id)
                }
                let palette = try await adapter.extractPalette(id, imageData: data)
                _ = palette // stored via repository
            }
            // Step 2: Audio analysis
            if [.echo, .clip, .atmosphere].contains(type) {
                let acousticTags = try await adapter.analyzeAudio(id, audioData: data)
                for tag in acousticTags {
                    try await graph.updateAcousticTag(tag, for: id)
                }
            }
        } catch {
            // Log and continue — indexing failures are non-fatal
        }
    }
}
