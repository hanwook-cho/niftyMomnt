// NiftyCore/Tests/AssembleSequenceTests.swift
// U6 — StoryEngine.assembleSequence with 6 frames returns SequenceStrip with shareReady=true.
// U7 — assembleSequence throws + leaves no partial state when the injected assembler throws.
//
// The real AVAssetWriter wiring lives in NiftyData (AVSequenceAssembler) — verified on-device.
// These tests cover the NiftyCore-layer orchestration: guard clauses, protocol delegation,
// and SequenceStrip shape.

import XCTest
@testable import NiftyCore

final class AssembleSequenceTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seq-asm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeDummyHEIC(_ url: URL) throws {
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: url)
    }

    private func makeStoryEngine(
        assembler: (any SequenceAssemblerProtocol)?
    ) -> StoryEngine {
        StoryEngine(
            config: AppConfig.lite,
            vault: NoopVault(),
            graph: NoopGraph(),
            lab: NoopLab(),
            sequenceAssembler: assembler
        )
    }

    // MARK: - U6 — happy path

    func test_U6_assembleSequence_6Frames_returnsShareReadyStrip() async throws {
        let tmp = try makeTempDir()
        var frameURLs: [URL] = []
        for i in 0..<6 {
            let u = tmp.appendingPathComponent("frame-\(i).heic")
            try writeDummyHEIC(u)
            frameURLs.append(u)
        }
        let outputURL = tmp.appendingPathComponent("strip.mp4")
        let asm = StubAssembler(simulatedDuration: 2.0)
        let engine = makeStoryEngine(assembler: asm)

        let strip = try await engine.assembleSequence(
            frameURLs: frameURLs,
            outputURL: outputURL,
            frameDurationSeconds: 0.333
        )

        XCTAssertEqual(strip.frameURLs.count, 6)
        XCTAssertEqual(strip.frameURLs, frameURLs)
        XCTAssertEqual(strip.assembledVideoURL, outputURL)
        XCTAssertEqual(strip.durationSeconds, 2.0, accuracy: 0.001)
        XCTAssertTrue(strip.shareReady)

        XCTAssertEqual(asm.callCount, 1)
        XCTAssertEqual(asm.lastFrameDuration, 0.333, accuracy: 0.001)
    }

    // MARK: - U7 — assembler failure surfaces as thrown error

    func test_U7_assemblerFailure_throws_noShareReadyStripReturned() async throws {
        let tmp = try makeTempDir()
        var frameURLs: [URL] = []
        for i in 0..<6 {
            let u = tmp.appendingPathComponent("frame-\(i).heic")
            try writeDummyHEIC(u)
            frameURLs.append(u)
        }
        let asm = StubAssembler(throwOnAssemble: true)
        let engine = makeStoryEngine(assembler: asm)

        do {
            _ = try await engine.assembleSequence(
                frameURLs: frameURLs,
                outputURL: tmp.appendingPathComponent("strip.mp4")
            )
            XCTFail("expected throw")
        } catch StubAssembler.StubError.forced {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Guard clauses

    func test_missingAssembler_throwsAssemblerUnavailable() async throws {
        let engine = makeStoryEngine(assembler: nil)
        do {
            _ = try await engine.assembleSequence(
                frameURLs: [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b"),
                            URL(fileURLWithPath: "/tmp/c"), URL(fileURLWithPath: "/tmp/d"),
                            URL(fileURLWithPath: "/tmp/e"), URL(fileURLWithPath: "/tmp/f")],
                outputURL: URL(fileURLWithPath: "/tmp/out.mp4")
            )
            XCTFail("expected throw")
        } catch StoryEngine.SequenceAssemblyError.assemblerUnavailable {
            // expected
        }
    }

    func test_wrongFrameCount_throws() async throws {
        let tmp = try makeTempDir()
        let only3 = try (0..<3).map { i -> URL in
            let u = tmp.appendingPathComponent("frame-\(i).heic")
            try writeDummyHEIC(u)
            return u
        }
        let engine = makeStoryEngine(assembler: StubAssembler())
        do {
            _ = try await engine.assembleSequence(
                frameURLs: only3,
                outputURL: tmp.appendingPathComponent("strip.mp4")
            )
            XCTFail("expected throw")
        } catch StoryEngine.SequenceAssemblyError.wrongFrameCount(let got, let expected) {
            XCTAssertEqual(got, 3)
            XCTAssertEqual(expected, 6)
        }
    }

    func test_missingFrameOnDisk_throws() async throws {
        let tmp = try makeTempDir()
        var urls: [URL] = []
        for i in 0..<5 {
            let u = tmp.appendingPathComponent("frame-\(i).heic")
            try writeDummyHEIC(u)
            urls.append(u)
        }
        // 6th URL points at a file that doesn't exist.
        urls.append(tmp.appendingPathComponent("ghost.heic"))
        let engine = makeStoryEngine(assembler: StubAssembler())
        do {
            _ = try await engine.assembleSequence(
                frameURLs: urls,
                outputURL: tmp.appendingPathComponent("strip.mp4")
            )
            XCTFail("expected throw")
        } catch StoryEngine.SequenceAssemblyError.missingFrame {
            // expected
        }
    }
}

// MARK: - Test doubles

private final class StubAssembler: SequenceAssemblerProtocol, @unchecked Sendable {
    enum StubError: Error { case forced }
    private let throwOnAssemble: Bool
    private let simulatedDuration: Double
    private(set) var callCount: Int = 0
    private(set) var lastFrameDuration: Double = 0
    init(throwOnAssemble: Bool = false, simulatedDuration: Double = 2.0) {
        self.throwOnAssemble = throwOnAssemble
        self.simulatedDuration = simulatedDuration
    }
    func assemble(
        frameURLs: [URL],
        outputURL: URL,
        frameDurationSeconds: Double
    ) async throws -> (url: URL, durationSeconds: Double) {
        callCount += 1
        lastFrameDuration = frameDurationSeconds
        if throwOnAssemble { throw StubError.forced }
        // Simulate writing a file.
        try? Data([0x00, 0x00, 0x00, 0x20]).write(to: outputURL)
        return (outputURL, simulatedDuration)
    }
}

// MARK: - Minimal protocol stubs so StoryEngine can be instantiated.
// These are intentionally exhaustive: the real protocols require class conformance
// (AnyObject), so struct-based doubles won't compile. Every method is a no-op / empty return.

import Combine

private final class NoopVault: VaultProtocol, @unchecked Sendable {
    func save(_ asset: Asset, data: Data) async throws {}
    func saveDerivative(_ derivative: DerivativeAsset, data: Data, sourceAssetID: UUID) async throws {}
    func saveVideoFile(_ asset: Asset, sourceURL: URL) async throws {}
    func saveAudioFile(_ asset: Asset, sourceURL: URL) async throws {}
    func saveLiveMovieFile(_ asset: Asset, sourceURL: URL) async throws {}
    func load(_ assetID: UUID) async throws -> (Asset, Data) {
        (Asset(type: .still, capturedAt: .init()), Data())
    }
    func loadPrimary(_ assetID: UUID) async throws -> (Asset, Data) {
        (Asset(type: .still, capturedAt: .init()), Data())
    }
    func deleteDerivative(for assetID: UUID) async throws {}
    func delete(_ assetID: UUID) async throws {}
    func query(_ query: VaultQuery) async throws -> [Asset] { [] }
    func exportToPhotoLibrary(_ assetID: UUID) async throws {}
    var storageUsedBytes: AnyPublisher<Int64, Never> { Just(0).eraseToAnyPublisher() }
    func moveToVault(assetID: UUID) async throws {}
}

private final class NoopGraph: GraphProtocol, @unchecked Sendable {
    func saveMoment(_ moment: Moment) async throws {}
    func updateVibeTag(_ tag: VibeTag, for assetID: UUID) async throws {}
    func updatePreset(_ name: String, for assetID: UUID) async throws {}
    func updateAcousticTag(_ tag: AcousticTag, for assetID: UUID) async throws {}
    func fetchAcousticTags(for assetID: UUID) async throws -> [AcousticTag] { [] }
    func saveNudgeResponse(_ response: NudgeResponse) async throws {}
    func mergeAcousticVibes(_ vibes: [VibeTag], for assetID: UUID) async throws {}
    func saveMoodPoint(_ point: MoodPoint) async throws {}
    func updatePlaceRecord(_ record: PlaceRecord) async throws {}
    func saveDerivativeRecord(_ derivative: DerivativeAsset) async throws {}
    func deleteDerivativeRecord(for assetID: UUID) async throws {}
    func deleteMoment(_ momentID: UUID) async throws {}
    func fetchMoments(query: GraphQuery) async throws -> [Moment] { [] }
    func fetchTodayMomentCount() async throws -> Int { 0 }
    func fetchPlaceHistory(limit: Int) async throws -> [PlaceRecord] { [] }
    func fetchMoodMap(range: DateInterval) async throws -> [MoodPoint] { [] }
    func exportForCompanion() async throws -> GraphExport {
        GraphExport(moments: [], placeHistory: [], moodMap: [])
    }
    func fetchAssets(for momentID: UUID) async throws -> [Asset] { [] }
    func markAssetPrivate(assetID: UUID, isPrivate: Bool) async throws {}
    func saveL4CRecord(_ record: L4CRecord) async throws {}
    func fetchL4CRecords() async throws -> [L4CRecord] { [] }
    func deleteL4CRecord(_ id: UUID) async throws -> [UUID] { [] }
}

private final class NoopLab: LabClientProtocol, @unchecked Sendable {
    func generateCaption(for moment: Moment, tone: CaptionTone) async throws -> [CaptionCandidate] { [] }
    func transformProse(_ transcript: String, styles: [ProseStyle]) async throws -> [ProseVariant] { [] }
    func requestLabSession(assets: [UUID], consent: LabConsent) async throws -> LabSession {
        LabSession(assetIDs: [])
    }
    func processLabSession(_ session: LabSession) async throws -> LabResult {
        LabResult(sessionID: session.id, captions: [])
    }
    func verifyPurge(sessionID: UUID) async throws -> PurgeConfirmation {
        PurgeConfirmation(sessionID: sessionID)
    }
}
