// NiftyData/Tests/PhotoLibraryExporterTests.swift
// Piqd v0.5 — exercises the auth-flow + save branches of PhotoLibraryExporter
// without touching the real PHPhotoLibrary.

import Foundation
import XCTest
import NiftyCore
import Photos
@testable import NiftyData

final class PhotoLibraryExporterTests: XCTestCase {

    // MARK: - Mocks

    /// Snapshot-only authorizer: status fixed at init, request returns the seeded value.
    private final class SnapshotAuthorizer: PhotoLibraryAuthorizer, @unchecked Sendable {
        private let status: PHAuthorizationStatus
        private let requestResult: PHAuthorizationStatus
        private let lock = NSLock()
        private var _requestCount = 0
        var requestCount: Int { lock.withLock { _requestCount } }

        init(status: PHAuthorizationStatus, requestResult: PHAuthorizationStatus = .denied) {
            self.status = status
            self.requestResult = requestResult
        }

        func currentStatus() -> PHAuthorizationStatus { status }

        func requestAddOnly() async -> PHAuthorizationStatus {
            lock.withLock { _requestCount += 1 }
            return requestResult
        }
    }

    private final class RecordingSaver: PhotoLibrarySaver, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        private let throwError: Error?

        var callCount: Int { lock.withLock { _calls } }

        init(throwError: Error? = nil) {
            self.throwError = throwError
        }

        func performChanges(_ changes: @escaping @Sendable () -> Void) async throws {
            lock.withLock { _calls += 1 }
            if let err = throwError { throw err }
            // Deliberately do NOT invoke `changes()` — touching PHAssetCreationRequest
            // outside an actual performChanges block would crash. The mock only
            // verifies that the exporter reached the save path.
        }
    }

    private struct SaveError: Error {}

    // MARK: - Helpers

    private func makeTempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).heic")
        try Data([0x01, 0x02, 0x03]).write(to: url)
        return url
    }

    // MARK: - Tests

    func test_authorized_savesAndReturnsSaved() async throws {
        let auth = SnapshotAuthorizer(status: .authorized)
        let saver = RecordingSaver()
        let exporter = PhotoLibraryExporter(authorizer: auth, saver: saver)

        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await exporter.exportToPhotos(url, kind: .still)
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(saver.callCount, 1)
        XCTAssertEqual(auth.requestCount, 0, "Should not re-prompt when already authorized")
    }

    func test_limited_alsoSaves() async throws {
        let auth = SnapshotAuthorizer(status: .limited)
        let saver = RecordingSaver()
        let exporter = PhotoLibraryExporter(authorizer: auth, saver: saver)

        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await exporter.exportToPhotos(url, kind: .sequence)
        XCTAssertEqual(result, .saved)
    }

    func test_notDetermined_promptsAndProceedsOnGrant() async throws {
        let auth = SnapshotAuthorizer(status: .notDetermined, requestResult: .authorized)
        let saver = RecordingSaver()
        let exporter = PhotoLibraryExporter(authorizer: auth, saver: saver)

        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await exporter.exportToPhotos(url, kind: .still)
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(auth.requestCount, 1)
        XCTAssertEqual(saver.callCount, 1)
    }

    func test_notDetermined_returnsPermissionDeniedOnDeny() async throws {
        let auth = SnapshotAuthorizer(status: .notDetermined, requestResult: .denied)
        let saver = RecordingSaver()
        let exporter = PhotoLibraryExporter(authorizer: auth, saver: saver)

        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await exporter.exportToPhotos(url, kind: .still)
        XCTAssertEqual(result, .permissionDenied)
        XCTAssertEqual(saver.callCount, 0, "Save must not run when permission denied")
    }

    func test_denied_returnsPermissionDeniedWithoutPrompting() async throws {
        let auth = SnapshotAuthorizer(status: .denied)
        let saver = RecordingSaver()
        let exporter = PhotoLibraryExporter(authorizer: auth, saver: saver)

        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await exporter.exportToPhotos(url, kind: .still)
        XCTAssertEqual(result, .permissionDenied)
        XCTAssertEqual(auth.requestCount, 0, "Should not re-prompt after a hard denial")
        XCTAssertEqual(saver.callCount, 0)
    }

    func test_restricted_returnsPermissionDenied() async throws {
        let auth = SnapshotAuthorizer(status: .restricted)
        let saver = RecordingSaver()
        let exporter = PhotoLibraryExporter(authorizer: auth, saver: saver)

        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await exporter.exportToPhotos(url, kind: .still)
        XCTAssertEqual(result, .permissionDenied)
    }

    func test_missingFile_returnsFailed() async throws {
        let auth = SnapshotAuthorizer(status: .authorized)
        let saver = RecordingSaver()
        let exporter = PhotoLibraryExporter(authorizer: auth, saver: saver)

        let phantomURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist.heic")

        let result = await exporter.exportToPhotos(phantomURL, kind: .still)
        if case .failed = result { /* ok */ } else {
            XCTFail("Expected .failed for missing file, got \(result)")
        }
        XCTAssertEqual(saver.callCount, 0)
    }

    func test_saveFailure_returnsFailedWithReason() async throws {
        let auth = SnapshotAuthorizer(status: .authorized)
        let saver = RecordingSaver(throwError: SaveError())
        let exporter = PhotoLibraryExporter(authorizer: auth, saver: saver)

        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await exporter.exportToPhotos(url, kind: .still)
        if case .failed = result { /* ok */ } else {
            XCTFail("Expected .failed when save throws, got \(result)")
        }
    }
}
