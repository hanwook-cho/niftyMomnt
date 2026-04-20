// NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift
// @MainActor — orchestrates @MainActor-isolated engine and vault dependencies.

import Foundation
import QuartzCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "CaptureUseCase")

@MainActor
public final class CaptureMomentUseCase {
    private let engine: any CaptureEngineProtocol
    private let vault: VaultManager
    private let indexing: IndexingEngine
    private let graph: GraphManager
    private let geocoder: (any GeocoderProtocol)?
    private let nudge: (any NudgeEngineProtocol)?
    /// Called on MainActor with the resolved place name after geocoding completes.
    public var onPlaceResolved: ((String) -> Void)?

    public init(
        engine: any CaptureEngineProtocol,
        vault: VaultManager,
        indexing: IndexingEngine,
        graph: GraphManager,
        geocoder: (any GeocoderProtocol)? = nil,
        nudge: (any NudgeEngineProtocol)? = nil
    ) {
        self.engine = engine
        self.vault = vault
        self.indexing = indexing
        self.graph = graph
        self.geocoder = geocoder
        self.nudge = nudge
    }

    /// Starts the capture session for live preview without capturing an asset.
    public func startPreview(mode: CaptureMode, config: AppConfig) async throws {
        log.debug("startPreview mode=\(mode.rawValue)")
        try await engine.startSession(mode: mode, config: config)
        log.debug("startPreview done")
    }

    /// Stops the running session.
    public func stopPreview() async {
        log.debug("stopPreview")
        await engine.stopSession()
    }

    public func focusAndLock(at point: CGPoint, frameSize: CGSize) async throws {
        try await engine.focusAndLock(at: point, frameSize: frameSize)
    }

    public func unlockFocusAndExposure() async {
        await engine.unlockFocusAndExposure()
    }

    public func execute(mode: CaptureMode, config: AppConfig) async throws -> Asset {
        try await engine.startSession(mode: mode, config: config)
        let asset = try await engine.captureAsset()
        return asset
    }

    /// Captures a still photo, classifies it, persists to vault + graph, posts notification.
    /// Full v0.2 pipeline: camera → classify + palette + ambient (concurrent) → geocode → vault → graph → notify.
    /// - Parameters:
    ///   - preset: v0.4 — user-selected preset name to persist with the asset.
    ///   - aspectRatio: Piqd v0.2 — center-crop the captured frame before encoding. nil = no crop.
    ///   - encoder: Piqd v0.2 — re-encode the cropped image (e.g. HEIC). nil = save raw sensor bytes.
    ///   - locked: Piqd v0.2 — Roll-mode captures route bytes into the locked sub-namespace.
    public func captureAsset(
        preset: String? = nil,
        aspectRatio: AspectRatio? = nil,
        encoder: ImageEncoder? = nil,
        locked: Bool = false
    ) async throws -> Asset {
        log.debug("── captureAsset pipeline start ──")

        // 1. Capture from camera → writes JPEG to temp dir, returns Asset with id
        log.debug("[1/8] requesting photo from camera")
        var asset = try await engine.captureAsset()
        log.debug("[1/8] camera returned asset id=\(asset.id.uuidString)")

        // 2. Read JPEG from temp dir (written by AVCaptureAdapter)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(asset.id.uuidString).jpg")
        log.debug("[2/8] reading JPEG from temp: \(tempURL.lastPathComponent)")
        let sourceData = try Data(contentsOf: tempURL)
        log.debug("[2/8] JPEG read OK — \(sourceData.count) bytes")

        // 2b. Piqd v0.2 — optional center-crop + re-encode. Piqd callers pass an `encoder`
        // (HEIC) plus target `aspectRatio`; the source JPEG is decoded, center-cropped, and
        // re-encoded. niftyMomnt passes `encoder: nil` → the raw JPEG bytes are saved as-is.
        let imageData: Data
        let storageExtension: String?
        if let enc = encoder {
            do {
                imageData = try enc.encode(sourceData: sourceData, crop: aspectRatio, quality: 0.9)
                storageExtension = enc.fileExtension
                log.debug("[2b/8] re-encode OK — \(imageData.count)B ext=\(enc.fileExtension) crop=\(aspectRatio?.rawValue ?? "none")")
            } catch {
                log.error("[2b/8] encode failed (\(error)) — falling back to raw JPEG")
                imageData = sourceData
                storageExtension = nil
            }
        } else {
            imageData = sourceData
            storageExtension = nil
        }

        // 3. Classify + palette + ambient metadata concurrently (all local/background)
        // Capture stable values before launching concurrent tasks to avoid data-race on `asset`.
        let assetID = asset.id
        let assetLocation = asset.location
        let assetCapturedAt = asset.capturedAt

        // Fetch secondary-camera frame (non-nil only on dual-cam hardware with toggle on).
        // Passed to classifyImmediate to supplement scene-content tags with a second viewpoint.
        let secondaryFrameData = engine.latestSecondaryFrameData()
        if let sec = secondaryFrameData {
            log.info("[3/8] dual-cam: primary=\(imageData.count)B secondary=\(sec.count)B (different sizes = different cameras ✓)")
        } else {
            log.debug("[3/8] no secondary frame (single-cam or toggle off) — primary-only classification")
        }

        log.debug("[3/8] classify + palette + ambient (concurrent)…")
        async let vibeTags = indexing.classifyImmediate(id: assetID, imageData: imageData, supplementaryImageData: secondaryFrameData)
        async let palette = indexing.extractPaletteImmediate(id: assetID, imageData: imageData)
        async let ambient = indexing.harvestAmbientImmediate(location: assetLocation, time: assetCapturedAt)
        let (tags, pal, amb) = await (vibeTags, palette, ambient)
        asset.vibeTags = tags
        asset.palette = pal
        asset.ambient = amb
        asset.selectedPresetName = preset
        log.debug("[3/8] classify=[\(tags.map(\.rawValue).joined(separator: ","))] palette=\(pal?.colors.count ?? 0)colors sun=\(amb.sunPosition?.rawValue ?? "nil") preset=\(preset ?? "nil")")

        // 4. Reverse-geocode (network, may be nil if no location or geocoder unavailable)
        log.debug("[4/8] reverse-geocode…")
        var placeRecord: PlaceRecord? = nil
        if let location = asset.location, let geocoder {
            placeRecord = try? await geocoder.reverseGeocode(location)
            log.debug("[4/8] geocode → '\(placeRecord?.placeName ?? "nil")'")
        } else if asset.location == nil {
            log.warning("[4/8] skipped — asset.location is nil (no GPS fix). Check Location Services permission and that CLLocationManager delivered a fix before capture.")
        } else {
            log.warning("[4/8] skipped — geocoder is nil (not injected into CaptureMomentUseCase)")
        }

        // 5. Persist to vault
        log.debug("[5/8] saving to vault… locked=\(locked) ext=\(storageExtension ?? "default")")
        if storageExtension != nil || locked {
            try await vault.save(asset, data: imageData, fileExtension: storageExtension, locked: locked)
        } else {
            try await vault.save(asset, data: imageData)
        }
        log.debug("[5/8] vault save OK")

        // 5b. For Live assets: also move the companion MOV from temp to vault.
        if asset.type == .live {
            let tempMovURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(assetID.uuidString).mov")
            if FileManager.default.fileExists(atPath: tempMovURL.path) {
                log.debug("[5b/8] saving Live Photo companion MOV…")
                try await vault.saveLiveMovieFile(asset, sourceURL: tempMovURL)
                log.debug("[5b/8] live MOV save OK")
            } else {
                log.warning("[5b/8] live MOV not found at temp — saved as JPEG-only Live")
            }
        }

        // 6. Merge into existing nearby moment or create a new one.
        let label = placeRecord?.placeName ?? dateLabel(for: asset)
        onPlaceResolved?(label)

        let recentMoments = (try? await graph.fetchMoments(query: GraphQuery())) ?? []
        log.debug("[6/8] checking \(recentMoments.count) existing moment(s) for merge candidate…")
        let moment = mergedOrNew(
            asset: asset, tags: tags, label: label, preset: preset,
            recentMoments: recentMoments
        )
        log.debug("[6/8] moment id=\(moment.id.uuidString) assets=\(moment.assets.count) label='\(moment.label)'")

        // 7. Save to intelligence graph (moment + optional place record)
        log.debug("[7/8] saving to graph…")
        try await graph.saveMoment(moment)
        if let preset { try? await graph.updatePreset(preset, for: asset.id) }
        if let placeRecord {
            try? await graph.updatePlaceRecord(placeRecord)
        }
        log.debug("[7/8] graph save OK")

        // 8. Fire nudge (publishes NudgeCard to pendingNudge; UI presents after overlay closes)
        log.debug("[8/8] evaluating nudge triggers…")
        await nudge?.evaluateTriggers(for: moment)
        log.debug("[8/8] nudge evaluated")

        // 9. Notify feed to refresh
        log.debug("[9/9] posting niftyMomentCaptured notification")
        NotificationCenter.default.post(name: .niftyMomentCaptured, object: nil)

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
        log.debug("── captureAsset pipeline complete ──")

        return asset
    }

    /// Reconfigures the active capture session for a new mode — reshuffles outputs when crossing
    /// photo↔video boundaries. `gestureTime` is `CACurrentMediaTime()` captured at the gesture
    /// receipt for end-to-end latency logging. Piqd v0.2 renamed from `switchMode` to capture the
    /// semantic that mode change is not just a UI toggle — it reconfigures the session.
    public func reconfigureSession(to mode: CaptureMode, config: AppConfig, gestureTime: Double = 0) async throws {
        let t = CACurrentMediaTime()
        if gestureTime > 0 {
            log.debug("reconfigureSession → \(mode.rawValue)  [task-start lag: \(String(format: "%.3f", t - gestureTime))s]")
        } else {
            log.debug("reconfigureSession → \(mode.rawValue)")
        }
        try await engine.reconfigureSession(to: mode, gestureTime: gestureTime > 0 ? gestureTime : t)
    }

    /// Starts media recording for Clip / Echo / Atmosphere. Call stopVideoRecording() to finalise.
    public func startVideoRecording(mode: CaptureMode, config: AppConfig) async throws {
        log.debug("startVideoRecording mode=\(mode.rawValue)")
        try await engine.startRecording(mode: mode)
    }

    /// Stops Clip / Echo / Atmosphere capture, runs the save pipeline, returns the saved Asset.
    /// - Parameter preset: v0.4 — user-selected preset name to persist with the asset.
    public func stopVideoRecording(config: AppConfig, preset: String? = nil) async throws -> Asset {
        log.debug("── stopVideoRecording pipeline start ──")

        // 1. Stop engine → asset with duration; temp file at tmpdir/{id}.mov
        let asset = try await engine.stopRecording()
        log.debug("[1] engine stopped — id=\(asset.id.uuidString) duration=\(String(format: "%.1f", asset.duration ?? 0))s")

        // 2. Harvest ambient (sun position + weather) — no image to classify for video
        let assetID = asset.id
        let assetLocation = asset.location
        let assetCapturedAt = asset.capturedAt
        var enrichedAsset = asset
        enrichedAsset.selectedPresetName = preset
        log.debug("[2] harvesting ambient…")
        let amb = await indexing.harvestAmbientImmediate(location: assetLocation, time: assetCapturedAt)
        enrichedAsset.ambient = amb
        log.debug("[2] sun=\(amb.sunPosition?.rawValue ?? "nil") weather=\(amb.weather?.rawValue ?? "nil")")

        // 3. Geocode
        log.debug("[3] reverse-geocode…")
        var placeRecord: PlaceRecord? = nil
        if let location = assetLocation, let geocoder {
            placeRecord = try? await geocoder.reverseGeocode(location)
            log.debug("[3] geocode → '\(placeRecord?.placeName ?? "nil")'")
        }

        // 4. Move media file from temp → vault
        let tempMediaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(assetID.uuidString)
            .appendingPathExtension(enrichedAsset.type == .echo ? "m4a" : "mov")
        log.debug("[4] saving \(enrichedAsset.type.rawValue) to vault…")
        if enrichedAsset.type == .echo || enrichedAsset.type == .atmosphere {
            // Atmosphere also has a JPEG frame generated at stopRecording
            if enrichedAsset.type == .atmosphere {
                let tempJpegURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(assetID.uuidString).jpg")
                if let data = try? Data(contentsOf: tempJpegURL) {
                    try await vault.save(enrichedAsset, data: data)
                    log.debug("[4] atmosphere JPEG save OK")
                    try? FileManager.default.removeItem(at: tempJpegURL)
                }
            }
            try await vault.saveAudioFile(enrichedAsset, sourceURL: tempMediaURL)
        } else {
            try await vault.saveVideoFile(enrichedAsset, sourceURL: tempMediaURL)
        }
        log.debug("[4] vault save OK")

        // 5. Build Moment — merge into existing nearby moment if within 2h / 500m.
        let label = placeRecord?.placeName ?? dateLabel(for: enrichedAsset)
        onPlaceResolved?(label)
        let recentMomentsV = (try? await graph.fetchMoments(query: GraphQuery())) ?? []
        log.debug("[5] checking \(recentMomentsV.count) existing moment(s) for merge candidate…")
        let moment = mergedOrNew(
            asset: enrichedAsset, tags: enrichedAsset.vibeTags, label: label, preset: preset,
            recentMoments: recentMomentsV
        )
        log.debug("[5] moment id=\(moment.id.uuidString) assets=\(moment.assets.count) label='\(moment.label)'")

        // 6. Save to graph
        log.debug("[6] saving to graph…")
        try await graph.saveMoment(moment)
        if let preset { try? await graph.updatePreset(preset, for: enrichedAsset.id) }
        if let placeRecord { try? await graph.updatePlaceRecord(placeRecord) }
        log.debug("[6] Asset duration before graph save: \(enrichedAsset.duration ?? 0)s")
        log.debug("[6] graph save OK")

        // 7. Fire nudge
        log.debug("[7] evaluating nudge triggers…")
        await nudge?.evaluateTriggers(for: moment)
        log.debug("[7] nudge evaluated")

        // 8. Notify feed
        log.debug("[8] posting niftyMomentCaptured")
        NotificationCenter.default.post(name: .niftyMomentCaptured, object: nil)
        log.debug("── stopVideoRecording pipeline complete ──")

        return enrichedAsset
    }

    /// Toggles between front and back camera without interrupting the session.
    public func switchCamera() async throws {
        log.debug("switchCamera")
        try await engine.switchCamera()
        log.debug("switchCamera done")
    }
}

// MARK: - Helpers

private extension CaptureMomentUseCase {
    func dateLabel(for asset: Asset) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d · h:mm a"
        return fmt.string(from: asset.capturedAt)
    }

    /// Merges `asset` into the most recent compatible moment, or creates a fresh one.
    /// Compatibility: endTime within 2 h AND centroid within 500 m.
    func mergedOrNew(
        asset: Asset,
        tags: [VibeTag],
        label: String,
        preset: String?,
        recentMoments: [Moment]
    ) -> Moment {
        let twoHours: TimeInterval = 7_200
        let maxMeters: Double = 500

        // Find the most-recent moment that is still within time + space window.
        let candidate = recentMoments
            .sorted { $0.endTime > $1.endTime }
            .first { existing in
                let timeDelta = asset.capturedAt.timeIntervalSince(existing.endTime)
                guard timeDelta >= 0, timeDelta <= twoHours else { return false }
                let dist = IndexingEngine.haversineMeters(asset.location, existing.centroid)
                return dist <= maxMeters
            }

        if let existing = candidate {
            log.debug("[merge] merging asset \(asset.id.uuidString) into moment \(existing.id.uuidString) (now \(existing.assets.count + 1) assets)")
            let mergedVibes = Array(Set(existing.dominantVibes + tags))
            var updated = existing
            updated.assets      = existing.assets + [asset]
            updated.endTime     = asset.capturedAt
            updated.dominantVibes = mergedVibes
            if let preset { updated.selectedPresetName = preset }
            return updated
        } else {
            log.debug("[merge] no compatible moment found — creating new moment for asset \(asset.id.uuidString)")
            return Moment(
                label: label,
                assets: [asset],
                centroid: asset.location ?? GPSCoordinate(latitude: 0, longitude: 0),
                startTime: asset.capturedAt,
                endTime: asset.capturedAt,
                dominantVibes: tags,
                selectedPresetName: preset
            )
        }
    }
}
