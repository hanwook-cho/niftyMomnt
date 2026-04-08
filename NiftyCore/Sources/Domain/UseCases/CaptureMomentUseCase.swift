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
    /// Called on MainActor with the resolved place name after geocoding completes.
    public var onPlaceResolved: ((String) -> Void)?

    public init(
        engine: any CaptureEngineProtocol,
        vault: VaultManager,
        indexing: IndexingEngine,
        graph: GraphManager,
        geocoder: (any GeocoderProtocol)? = nil
    ) {
        self.engine = engine
        self.vault = vault
        self.indexing = indexing
        self.graph = graph
        self.geocoder = geocoder
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
    public func captureAsset() async throws -> Asset {
        log.debug("── captureAsset pipeline start ──")

        // 1. Capture from camera → writes JPEG to temp dir, returns Asset with id
        log.debug("[1/8] requesting photo from camera")
        var asset = try await engine.captureAsset()
        log.debug("[1/8] camera returned asset id=\(asset.id.uuidString)")

        // 2. Read JPEG from temp dir (written by AVCaptureAdapter)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(asset.id.uuidString).jpg")
        log.debug("[2/8] reading JPEG from temp: \(tempURL.lastPathComponent)")
        let imageData = try Data(contentsOf: tempURL)
        log.debug("[2/8] JPEG read OK — \(imageData.count) bytes")

        // 3. Classify + palette + ambient metadata concurrently (all local/background)
        // Capture stable values before launching concurrent tasks to avoid data-race on `asset`.
        let assetID = asset.id
        let assetLocation = asset.location
        let assetCapturedAt = asset.capturedAt
        log.debug("[3/8] classify + palette + ambient (concurrent)…")
        async let vibeTags = indexing.classifyImmediate(id: assetID, imageData: imageData)
        async let palette = indexing.extractPaletteImmediate(id: assetID, imageData: imageData)
        async let ambient = indexing.harvestAmbientImmediate(location: assetLocation, time: assetCapturedAt)
        let (tags, pal, amb) = await (vibeTags, palette, ambient)
        asset.vibeTags = tags
        asset.palette = pal
        asset.ambient = amb
        log.debug("[3/8] classify=[\(tags.map(\.rawValue).joined(separator: ","))] palette=\(pal?.colors.count ?? 0)colors sun=\(amb.sunPosition?.rawValue ?? "nil")")

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
        log.debug("[5/8] saving to vault…")
        try await vault.save(asset, data: imageData)
        log.debug("[5/8] vault JPEG save OK")

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

        // 6. Build Moment (label = place name if available, otherwise date)
        let label = placeRecord?.placeName ?? dateLabel(for: asset)
        onPlaceResolved?(label)
        let moment = Moment(
            label: label,
            assets: [asset],
            centroid: asset.location ?? GPSCoordinate(latitude: 0, longitude: 0),
            startTime: asset.capturedAt,
            endTime: asset.capturedAt,
            dominantVibes: tags
        )
        log.debug("[6/8] moment built id=\(moment.id.uuidString) label='\(moment.label)'")

        // 7. Save to intelligence graph (moment + optional place record)
        log.debug("[7/8] saving to graph…")
        try await graph.saveMoment(moment)
        if let placeRecord {
            try? await graph.updatePlaceRecord(placeRecord)
        }
        log.debug("[7/8] graph save OK")

        // 8. Notify feed to refresh
        log.debug("[8/8] posting niftyMomentCaptured notification")
        NotificationCenter.default.post(name: .niftyMomentCaptured, object: nil)

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
        log.debug("── captureAsset pipeline complete ──")

        return asset
    }

    /// Switches capture mode — reconfigures the session outputs if crossing photo↔video boundary.
    /// `gestureTime` is `CACurrentMediaTime()` captured at the swipe gesture receipt for end-to-end latency logging.
    public func switchMode(to mode: CaptureMode, config: AppConfig, gestureTime: Double = 0) async throws {
        let t = CACurrentMediaTime()
        if gestureTime > 0 {
            log.debug("switchMode → \(mode.rawValue)  [task-start lag: \(String(format: "%.3f", t - gestureTime))s]")
        } else {
            log.debug("switchMode → \(mode.rawValue)")
        }
        try await engine.switchMode(to: mode, gestureTime: gestureTime > 0 ? gestureTime : t)
    }

    /// Starts video recording (Clip / Echo / Atmosphere). Call stopVideoRecording() to finalise.
    public func startVideoRecording(mode: CaptureMode, config: AppConfig) async throws {
        log.debug("startVideoRecording mode=\(mode.rawValue)")
        try await engine.startRecording(mode: mode)
    }

    /// Stops video recording, runs the save pipeline, returns the saved Asset.
    public func stopVideoRecording(config: AppConfig) async throws -> Asset {
        log.debug("── stopVideoRecording pipeline start ──")

        // 1. Stop engine → asset with duration; temp file at tmpdir/{id}.mov
        let asset = try await engine.stopRecording()
        log.debug("[1] engine stopped — id=\(asset.id.uuidString) duration=\(String(format: "%.1f", asset.duration ?? 0))s")

        // 2. Harvest ambient (sun position + weather) — no image to classify for video
        let assetID = asset.id
        let assetLocation = asset.location
        let assetCapturedAt = asset.capturedAt
        var enrichedAsset = asset
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

        // 4. Move video file from temp → vault
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(assetID.uuidString)
            .appendingPathExtension("mov")
        log.debug("[4] saving video to vault…")
        try await vault.saveVideoFile(enrichedAsset, sourceURL: tempURL)
        log.debug("[4] vault save OK")

        // 5. Build Moment
        let label = placeRecord?.placeName ?? dateLabel(for: enrichedAsset)
        onPlaceResolved?(label)
        let moment = Moment(
            label: label,
            assets: [enrichedAsset],
            centroid: enrichedAsset.location ?? GPSCoordinate(latitude: 0, longitude: 0),
            startTime: enrichedAsset.capturedAt,
            endTime: enrichedAsset.capturedAt,
            dominantVibes: enrichedAsset.vibeTags
        )
        log.debug("[5] moment id=\(moment.id.uuidString) label='\(moment.label)'")

        // 6. Save to graph
        log.debug("[6] saving to graph…")
        try await graph.saveMoment(moment)
        if let placeRecord { try? await graph.updatePlaceRecord(placeRecord) }
        log.debug("[6] graph save OK")

        // 7. Notify feed
        log.debug("[7] posting niftyMomentCaptured")
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
}
