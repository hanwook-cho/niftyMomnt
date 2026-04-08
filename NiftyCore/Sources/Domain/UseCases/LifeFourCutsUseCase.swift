// NiftyCore/Sources/Domain/UseCases/LifeFourCutsUseCase.swift
// @MainActor — orchestrates booth capture, compositing, and persistence.
//
// Caller (BoothCaptureView) drives the per-shot capture loop and calls
// captureOneShot() four times, then buildAndSave() with the chosen frame/border.

import Foundation
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "L4CUseCase")

@MainActor
public final class LifeFourCutsUseCase {
    private let captureEngine: any CaptureEngineProtocol
    private let compositor: any CompositingAdapterProtocol
    private let vault: VaultManager
    private let graph: GraphManager
    private let geocoder: (any GeocoderProtocol)?

    /// Called after geocoding resolves, same pattern as CaptureMomentUseCase.
    public var onPlaceResolved: ((String) -> Void)?

    public init(
        captureEngine: any CaptureEngineProtocol,
        compositor: any CompositingAdapterProtocol,
        vault: VaultManager,
        graph: GraphManager,
        geocoder: (any GeocoderProtocol)? = nil
    ) {
        self.captureEngine = captureEngine
        self.compositor = compositor
        self.vault = vault
        self.graph = graph
        self.geocoder = geocoder
    }

    // MARK: - Per-shot capture

    /// Captures one still photo. Returns the JPEG data and the Asset stub.
    /// The caller stores the data array and passes all 4 to `buildAndSave`.
    public func captureOneShot() async throws -> (Asset, Data) {
        log.debug("captureOneShot")
        let asset = try await captureEngine.captureAsset()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(asset.id.uuidString)
            .appendingPathExtension("jpg")
        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        log.debug("captureOneShot done — id=\(asset.id.uuidString) \(data.count)B")
        return (asset, data)
    }

    // MARK: - Build & Save (called after all 4 shots)

    /// Composites the strip, persists everything, posts notification.
    /// - Parameters:
    ///   - shots: The 4 (Asset, Data) pairs returned by `captureOneShot()`.
    ///   - frame: The selected Featured Frame (`FeaturedFrame.none` for plain border).
    ///   - borderColor: Border/background colour.
    ///   - config: App config.
    /// - Returns: The composite `L4CRecord`.
    public func buildAndSave(
        shots: [(Asset, Data)],
        frame: FeaturedFrame,
        borderColor: L4CBorderColor,
        config: AppConfig
    ) async throws -> L4CRecord {
        precondition(shots.count == 4, "buildAndSave requires exactly 4 shots")
        log.debug("── buildAndSave start ── frame=\(frame.id) border=\(borderColor.rawValue)")

        let sourceAssets = shots.map(\.0)
        let photoDatas   = shots.map(\.1)

        // 1. Save source stills to vault (without creating Moments — they're linked to the L4C record)
        log.debug("[1] saving 4 source stills to vault…")
        for (asset, data) in shots {
            try await vault.save(asset, data: data)
        }
        log.debug("[1] source stills saved")

        // 2. Geocode using first shot's location
        log.debug("[2] geocoding…")
        let location = sourceAssets.first?.location
        var placeRecord: PlaceRecord? = nil
        if let location, let geocoder {
            placeRecord = try? await geocoder.reverseGeocode(location)
            log.debug("[2] geocode → '\(placeRecord?.placeName ?? "nil")'")
        }

        let capturedAt = sourceAssets.first?.capturedAt ?? Date()
        let label = placeRecord?.placeName ?? dateLabel(for: capturedAt)
        onPlaceResolved?(label)

        // 3. Build stamp config
        let stamp = L4CStampConfig(
            dateText: stampDateString(capturedAt),
            locationText: placeRecord?.placeName ?? "",
            showAppLogo: true
        )

        // 4. Composite strip
        log.debug("[3] compositing strip…")
        let frameAssetName: String? = frame.id == "none" ? nil : frame.id
        let compositeData = try await compositor.compositeStrip(
            photos: photoDatas,
            borderColor: borderColor,
            frameAssetName: frameAssetName,
            stamp: stamp
        )
        log.debug("[3] composite done — \(compositeData.count)B")

        // 5. Save composite to vault as .l4c asset
        let compositeID = UUID()
        let compositeAsset = Asset(id: compositeID, type: .l4c, capturedAt: capturedAt, location: location)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(compositeID.uuidString)
            .appendingPathExtension("jpg")
        try compositeData.write(to: tempURL)
        // VaultRepository.saveVideoFile moves the file; reuse for any non-JPEG data blob
        // Actually for L4C the composite IS a JPEG, use save(_:data:) directly
        try await vault.save(compositeAsset, data: compositeData)
        log.debug("[4] composite saved to vault — id=\(compositeID.uuidString)")

        // 6. Build and save L4CRecord
        let record = L4CRecord(
            id: compositeID,
            sourceAssetIDs: sourceAssets.map(\.id),
            frameID: frame.id,
            borderColor: borderColor,
            capturedAt: capturedAt,
            location: location,
            label: label
        )
        log.debug("[5] saving L4CRecord to graph…")
        try await graph.saveL4CRecord(record)
        if let placeRecord { try? await graph.updatePlaceRecord(placeRecord) }
        log.debug("[5] graph save OK")

        // 7. Notify feed
        NotificationCenter.default.post(name: .niftyMomentCaptured, object: nil)
        log.debug("── buildAndSave complete ──")

        return record
    }

    // MARK: - Re-composite only (for border/frame changes in preview sheet)

    /// Re-composites the strip without persisting — used for live preview updates.
    public func recomposite(
        photos: [Data],
        frame: FeaturedFrame,
        borderColor: L4CBorderColor
    ) async throws -> Data {
        let frameAssetName: String? = frame.id == "none" ? nil : frame.id
        return try await compositor.compositeStrip(
            photos: photos,
            borderColor: borderColor,
            frameAssetName: frameAssetName,
            stamp: L4CStampConfig(dateText: "", locationText: "", showAppLogo: false)
        )
    }

    // MARK: - Helpers

    private func dateLabel(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d · h:mm a"
        return fmt.string(from: date)
    }

    private func stampDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d · yyyy"
        return fmt.string(from: date)
    }
}
