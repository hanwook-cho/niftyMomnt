// NiftyData/Sources/Platform/PhotoLibraryExporter.swift
// Piqd v0.5 — concrete `PhotoLibraryExporterProtocol` over `PHPhotoLibrary`.
// Auth is delegated to a `PhotoLibraryAuthorizer` seam so unit tests can drive
// every branch (notDetermined → grant, denied, restricted, etc.) without
// touching the real photo library.

import Foundation
import NiftyCore
import os
import Photos

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "PhotoLibraryExporter")

// MARK: - Authorizer seam

public protocol PhotoLibraryAuthorizer: Sendable {
    func currentStatus() -> PHAuthorizationStatus
    func requestAddOnly() async -> PHAuthorizationStatus
}

public struct SystemPhotoLibraryAuthorizer: PhotoLibraryAuthorizer {
    public init() {}
    public func currentStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }
    public func requestAddOnly() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }
}

// MARK: - Save seam

/// Thin wrapper over `PHPhotoLibrary.shared().performChanges` so tests can
/// exercise the result-mapping layer without crossing the system framework.
public protocol PhotoLibrarySaver: Sendable {
    func performChanges(_ changes: @escaping @Sendable () -> Void) async throws
}

public struct SystemPhotoLibrarySaver: PhotoLibrarySaver {
    public init() {}
    public func performChanges(_ changes: @escaping @Sendable () -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: ExporterError.performChangesFailed)
                }
            }
        }
    }

    enum ExporterError: Error { case performChangesFailed }
}

// MARK: - Exporter

public actor PhotoLibraryExporter: PhotoLibraryExporterProtocol {

    private let authorizer: PhotoLibraryAuthorizer
    private let saver: PhotoLibrarySaver

    public init(
        authorizer: PhotoLibraryAuthorizer = SystemPhotoLibraryAuthorizer(),
        saver: PhotoLibrarySaver = SystemPhotoLibrarySaver()
    ) {
        self.authorizer = authorizer
        self.saver = saver
    }

    public func exportToPhotos(_ url: URL, kind: AssetType) async -> PhotoLibraryExportResult {
        // Auth flow — `.addOnly` because we never read existing library state.
        switch authorizer.currentStatus() {
        case .authorized, .limited:
            break
        case .notDetermined:
            let granted = await authorizer.requestAddOnly()
            guard granted == .authorized || granted == .limited else {
                return .permissionDenied
            }
        case .denied, .restricted:
            return .permissionDenied
        @unknown default:
            return .permissionDenied
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            log.error("exportToPhotos — vault file missing at \(url.path)")
            return .failed(reason: "vault file missing")
        }

        let resourceType = Self.resourceType(for: kind)
        do {
            try await saver.performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = url.lastPathComponent
                request.addResource(with: resourceType, fileURL: url, options: options)
            }
            log.debug("exportToPhotos — saved \(url.lastPathComponent) as \(kind.rawValue)")
            return .saved
        } catch {
            log.error("exportToPhotos — performChanges failed: \(error)")
            return .failed(reason: String(describing: error))
        }
    }

    // MARK: - Mapping

    private static func resourceType(for kind: AssetType) -> PHAssetResourceType {
        switch kind {
        case .still, .live, .l4c, .movingStill:
            // Live's paired video is handled by VaultRepository.exportToPhotoLibrary;
            // the drafts tray "save" surfaces single-resource flows only.
            return .photo
        case .clip, .atmosphere, .sequence, .dual:
            return .video
        case .echo:
            return .audio
        }
    }
}
