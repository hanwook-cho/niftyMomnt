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
    ///
    /// - Parameters:
    ///   - id:                    Asset UUID (used for logging + Vision request tracking).
    ///   - imageData:             Primary photo JPEG.
    ///   - supplementaryImageData: Optional secondary-camera JPEG (front TrueDepth / ultra-wide
    ///                             from dual-cam session). When provided, a concurrent Vision pass
    ///                             is run and its tags are merged with the primary results.
    ///                             This lets a face/environment angle supplement scene content tags.
    /// Classify a single asset immediately (inline, non-batched).
    /// Vision inference runs on a detached background task to avoid blocking any actor.
    ///
    /// - Parameters:
    ///   - id:                    Asset UUID (used for logging + Vision request tracking).
    ///   - imageData:             Primary photo JPEG.
    ///   - supplementaryImageData: Optional secondary-camera JPEG (front TrueDepth / ultra-wide
    ///                             from a dual-cam session). When provided, a concurrent Vision pass
    ///                             runs alongside the primary and its unique tags are merged in.
    public func classifyImmediate(id: UUID, imageData: Data, supplementaryImageData: Data? = nil) async -> [VibeTag] {
        let suppDesc = supplementaryImageData.map { "\($0.count)B" } ?? "none"
        log.debug("classifyImmediate — dispatching id=\(id.uuidString) supplementary=\(suppDesc)")
        let adapter = self.adapter

        // Primary classification — always runs.
        async let primaryTags: [VibeTag] = Task.detached(priority: .userInitiated) {
            do {
                return try await adapter.classifyImage(id, imageData: imageData)
            } catch {
                log.error("classifyImmediate — primary classifyImage threw: \(error)")
                return [VibeTag]()
            }
        }.value

        // When no secondary data, skip the concurrent branch immediately.
        guard let secData = supplementaryImageData else {
            let tags = await primaryTags
            log.debug("classifyImmediate — done (primary-only), \(tags.count) tag(s)")
            return tags
        }

        // Secondary classification — runs concurrently with primary.
        async let supplementaryTags: [VibeTag] = Task.detached(priority: .userInitiated) {
            do {
                return try await adapter.classifyImage(id, imageData: secData)
            } catch {
                log.error("classifyImmediate — supplementary classifyImage threw: \(error)")
                return [VibeTag]()
            }
        }.value

        let (pTags, sTags) = await (primaryTags, supplementaryTags)

        // Merge with deduplication — preserve primary ordering, append unique tags from secondary.
        var merged = pTags
        let primarySet = Set(pTags.map(\.rawValue))
        let addedFromSecondary = sTags.filter { !primarySet.contains($0.rawValue) }
        merged.append(contentsOf: addedFromSecondary)

        log.debug("classifyImmediate — primary=[\(pTags.map(\.rawValue).joined(separator: ","))] + supplementary=[\(sTags.map(\.rawValue).joined(separator: ","))] → merged=[\(merged.map(\.rawValue).joined(separator: ","))]")
        log.debug("classifyImmediate — done (dual-cam merge), \(merged.count) tag(s)")
        return merged
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

    /// Clusters assets into moments by time (2 h) and space (500 m) proximity.
    /// Returns groups of ≥2 assets; single-asset captures are dropped (insufficient for a reel).
    public func clusterMoments(assets: [Asset]) -> [[Asset]] {
        log.debug("clusterMoments — input \(assets.count) asset(s)")
        guard !assets.isEmpty else {
            log.debug("clusterMoments — no assets, returning empty")
            return []
        }
        let sorted = assets.sorted { $0.capturedAt < $1.capturedAt }

        var clusters: [[Asset]] = []
        var current: [Asset] = [sorted[0]]

        for asset in sorted.dropFirst() {
            let prev = current.last!
            let timeDelta = asset.capturedAt.timeIntervalSince(prev.capturedAt)
            let spatialDelta = IndexingEngine.haversineMeters(prev.location, asset.location)

            if timeDelta > 7_200 || spatialDelta > 500 {
                log.debug("clusterMoments — boundary: timeDelta=\(String(format: "%.0f", timeDelta))s spatialDelta=\(String(format: "%.0f", spatialDelta))m → new cluster")
                clusters.append(current)
                current = [asset]
            } else {
                log.debug("clusterMoments — merge: timeDelta=\(String(format: "%.0f", timeDelta))s spatialDelta=\(String(format: "%.0f", spatialDelta))m → cluster now \(current.count + 1) asset(s)")
                current.append(asset)
            }
        }
        clusters.append(current)

        let qualified = clusters.filter { $0.count >= 2 }
        log.debug("clusterMoments — \(clusters.count) raw cluster(s), \(qualified.count) with ≥2 assets (reel-eligible)")
        for (i, c) in qualified.enumerated() {
            log.debug("clusterMoments — cluster[\(i)]: \(c.count) asset(s), span=\(String(format: "%.0f", c.last!.capturedAt.timeIntervalSince(c.first!.capturedAt)))s")
        }
        return qualified
    }

    // MARK: - Helpers

    /// Haversine great-circle distance in metres. Returns 0 when either coordinate is nil.
    /// Public so CaptureMomentUseCase can reuse the same threshold logic.
    public static func haversineMeters(_ a: GPSCoordinate?, _ b: GPSCoordinate?) -> Double {
        guard let a, let b else { return 0 }
        let R = 6_371_000.0
        let φ1 = a.latitude  * .pi / 180
        let φ2 = b.latitude  * .pi / 180
        let Δφ = (b.latitude  - a.latitude)  * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let sinΔφ = sin(Δφ / 2)
        let sinΔλ = sin(Δλ / 2)
        let h = sinΔφ * sinΔφ + cos(φ1) * cos(φ2) * sinΔλ * sinΔλ
        return R * 2 * atan2(sqrt(h), sqrt(1 - h))
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
