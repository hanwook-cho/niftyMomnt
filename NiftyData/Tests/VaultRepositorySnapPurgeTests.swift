// NiftyData/Tests/VaultRepositorySnapPurgeTests.swift
// Piqd v0.5 — `VaultRepository.purgeSnapAsset(id:)` retention seam.

import Foundation
import XCTest
@testable import NiftyCore
@testable import NiftyData

final class VaultRepositorySnapPurgeTests: XCTestCase {

    private var piqdDocs: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("piqd", isDirectory: true)
    }

    private var snapAssetsDir: URL {
        piqdDocs.appendingPathComponent("assets", isDirectory: true)
    }

    private var rollAssetsDir: URL {
        piqdDocs
            .appendingPathComponent("roll", isDirectory: true)
            .appendingPathComponent("assets", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: piqdDocs)
    }

    private func piqdConfig() -> AppConfig {
        AppConfig(
            appVariant: .piqd,
            assetTypes: .still,
            aiModes: .onDevice,
            features: [.snapMode],
            sharing: SharingConfig(maxCircleSize: 0, labEnabled: false),
            storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
        )
    }

    private func makeAsset() -> Asset {
        Asset(id: UUID(), type: .still, capturedAt: Date(), location: nil,
              vibeTags: [], transcript: nil, duration: nil, isPrivate: false)
    }

    // MARK: - Tests

    func test_purgeSnapAsset_deletesFileAndSidecar() async throws {
        let vault = VaultRepository(config: piqdConfig())
        let asset = makeAsset()
        try await vault.save(asset, data: Data([0x01, 0x02, 0x03]),
                             fileExtension: "heic", locked: false)

        let fileURL = snapAssetsDir.appendingPathComponent("\(asset.id.uuidString).heic")
        let sidecar = snapAssetsDir.appendingPathComponent("\(asset.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))

        try await vault.purgeSnapAsset(id: asset.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "Snap asset bytes should be removed after purge")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path),
                       "Sidecar should be removed after purge")
    }

    func test_purgeSnapAsset_refusesRollAsset() async throws {
        let vault = VaultRepository(config: piqdConfig())
        let asset = makeAsset()
        try await vault.save(asset, data: Data([0xAA, 0xBB]),
                             fileExtension: "heic", locked: true)

        let rollFileURL = rollAssetsDir.appendingPathComponent("\(asset.id.uuidString).heic")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollFileURL.path),
                      "Roll asset should land in roll/assets/")

        do {
            try await vault.purgeSnapAsset(id: asset.id)
            XCTFail("Expected VaultError.rollAssetNotPurgeable")
        } catch let error as VaultError {
            XCTAssertEqual(error, .rollAssetNotPurgeable)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: rollFileURL.path),
                      "Roll bytes must be untouched after a refused purge")
    }

    func test_purgeSnapAsset_missingSidecar_isIdempotentNoOp() async throws {
        let vault = VaultRepository(config: piqdConfig())
        try await vault.purgeSnapAsset(id: UUID())  // never saved
        // Fall-through is the only assertion — no throw, no crash.
    }

    func test_purgeSnapAsset_doesNotTouchSiblingRollFiles() async throws {
        let vault = VaultRepository(config: piqdConfig())

        let snap = makeAsset()
        try await vault.save(snap, data: Data([0x01]),
                             fileExtension: "heic", locked: false)

        let roll = makeAsset()
        try await vault.save(roll, data: Data([0x02]),
                             fileExtension: "heic", locked: true)

        let rollFile = rollAssetsDir.appendingPathComponent("\(roll.id.uuidString).heic")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollFile.path))

        try await vault.purgeSnapAsset(id: snap.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: rollFile.path),
                      "Purging Snap asset must leave the Roll directory untouched")

        let rollDirContents = try FileManager.default
            .contentsOfDirectory(atPath: rollAssetsDir.path)
        XCTAssertEqual(rollDirContents.count, 1,
                       "Roll dir should contain exactly the Roll file")
    }
}
