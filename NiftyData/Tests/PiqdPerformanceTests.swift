// NiftyData/Tests/PiqdPerformanceTests.swift
// v0.1 plan §5.3 P1 + P3 baselines.
// P1: VaultRepository.save(asset,data) — capture→vault file write, <500ms p95
// P3: GraphRepository.saveMoment — single-moment GRDB write, <100ms
// P2 (cold launch) lives in PiqdUITests because it needs XCUIApplication.

import Foundation
import XCTest
@testable import NiftyCore
@testable import NiftyData

final class PiqdPerformanceTests: XCTestCase {

    private var piqdDocs: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("piqd", isDirectory: true)
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

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: piqdDocs)
    }

    // P1 — capture → vault file write. `measure` runs the block 10× and reports
    // an average; v0.1 baseline is loose (<500ms p95) and tightens in v0.4.
    func test_perf_P1_vaultSave_stillJPEG() throws {
        let vault = VaultRepository(config: piqdConfig())
        let data = Self.samplePayload
        measure {
            let asset = Asset(type: .still, capturedAt: Date())
            let exp = expectation(description: "save")
            Task {
                try? await vault.save(asset, data: data)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5)
        }
    }

    // P3 — single-moment GRDB write. Baseline <100ms.
    func test_perf_P3_graphSaveMoment() throws {
        let graph = GraphRepository(config: piqdConfig())
        measure {
            let asset = Asset(type: .still, capturedAt: Date())
            let moment = Moment(
                id: UUID(),
                label: "perf",
                assets: [asset],
                centroid: GPSCoordinate(latitude: 0, longitude: 0),
                startTime: asset.capturedAt,
                endTime: asset.capturedAt,
                dominantVibes: [],
                moodPoint: nil,
                isStarred: false,
                heroAssetID: asset.id
            )
            let exp = expectation(description: "saveMoment")
            Task {
                try? await graph.saveMoment(moment)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5)
        }
    }

    // ~1 KB placeholder — real JPEGs are larger, but this exercises the same
    // FileManager.write path and keeps the baseline stable across runs.
    private static let samplePayload: Data = Data(repeating: 0xAB, count: 1024)
}
