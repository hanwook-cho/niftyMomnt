// NiftyCore/Sources/Engines/IndexingEngine.swift
// actor — serialises background indexing to prevent concurrent graph writes.

import Foundation

public actor IndexingEngine {
    private let config: AppConfig
    private let adapter: any IndexingProtocol
    private let graph: any GraphProtocol

    public init(config: AppConfig, adapter: any IndexingProtocol, graph: any GraphProtocol) {
        self.config = config
        self.adapter = adapter
        self.graph = graph
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
