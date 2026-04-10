// NiftyData/Sources/Platform/SoundStampAdapter.swift
// Wraps AVAudioEngine + SoundAnalysis for ambient PCM capture at shutter moment.
// PRIVACY: PCM samples held in-memory only. Max in-memory lifetime ~4.5s (~864KB).
//          A single Int16 CAF is written to NSTemporaryDirectory() during classification
//          and deleted via defer before classify() returns — never touches Documents/.
//
// Swift 6 concurrency notes:
//   - AVAudioPCMBuffer is not Sendable; float samples are copied into [Float] on the tap thread
//     before any async hop, so no non-Sendable value ever crosses an actor boundary.
//   - Task.detached receives only [Float] + Double + UInt32 (all Sendable); AVAudioPCMBuffer is
//     reconstructed locally inside the closure.
//
// SNAudioStreamAnalyzer vs SNAudioFileAnalyzer:
//   - SNAudioStreamAnalyzer is designed for real-time streaming. Its internal windowing engine
//     expects audio arriving in real-time cadence; feeding a pre-recorded buffer synchronously
//     causes it to silently produce 0 classification windows.
//   - SNAudioFileAnalyzer is the correct batch API. classify() writes samples to a temp CAF
//     (Int16 PCM), opens it with SNAudioFileAnalyzer, and calls analyze(completionHandler:).
//     The semaphore blocks the Task.detached thread until the completion fires — no RunLoop needed.
//
// Ring buffer sizing:
//   - SNClassifySoundRequest default windowDuration = 3.0s, overlapFactor = 0.5.
//   - Minimum audio required for ≥1 classification window = 3.0s.
//   - ringDuration = 4.5s gives ~3.5s pre-roll + 1.0s post-shutter = 4.5s → 1–2 windows.
//   - Memory: 4.5s × 48000Hz × 4 bytes = ~864KB max in-memory.

import AVFoundation
import Combine
import CoreMedia
import Foundation
import NiftyCore
import os
import SoundAnalysis

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "SoundStamp")

// Chunk stored in the ring: a copy of the mono float samples + the sample rate.
private struct PCMChunk: Sendable {
    let samples: [Float]
    let sampleRate: Double
}

public actor SoundStampAdapter: SoundStampPipelineProtocol {

    // MARK: - State

    nonisolated(unsafe) private let isActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private let graph: any GraphProtocol
    private let engine = AVAudioEngine()
    private var ringBuffer: [PCMChunk] = []   // [Float]-backed, fully Sendable
    private var tapSampleRate: Double = 44100
    private var tapChannelCount: UInt32 = 1

    /// SNClassifySoundRequest default windowDuration = 3.0s, overlapFactor = 0.5.
    /// Ring keeps 4.5s: ~3.5s pre-roll + 1.0s post-shutter = 4.5s → 1-2 windows.
    private static let ringDuration: TimeInterval = 4.5
    private static let postShutterDuration: TimeInterval = 1.0
    private static let confidenceThreshold: Float = 0.35

    // MARK: - Init

    public init(config: AppConfig, graph: any GraphProtocol) {
        self.graph = graph
    }

    // MARK: - SoundStampPipelineProtocol

    public nonisolated var isActive: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Activates the microphone pre-roll buffer. Call on entry to Still mode.
    /// Does NOT call AVAudioSession.setCategory/setActive — AVCaptureSession owns the shared
    /// audio session in photo mode. We only install a tap and start the engine graph.
    public func activatePreRoll() async throws {
        guard !isActiveSubject.value else {
            log.debug("activatePreRoll — already active, skipping")
            return
        }
        log.debug("activatePreRoll — starting")

        // Reset engine state cleanly before (re-)installing tap
        if engine.isRunning { engine.pause() }
        engine.inputNode.removeTap(onBus: 0)

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            log.error("activatePreRoll — inputNode sampleRate=0, audio session not ready")
            return
        }
        tapSampleRate = format.sampleRate
        tapChannelCount = format.channelCount
        ringBuffer = []
        log.debug("activatePreRoll — tap format sampleRate=\(format.sampleRate) channels=\(format.channelCount)")

        // Copy samples to [Float] on the tap thread — AVAudioPCMBuffer stays on this thread only.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0, let src = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: src[0], count: frameCount))
            let sampleRate = buffer.format.sampleRate
            let chunk = PCMChunk(samples: samples, sampleRate: sampleRate)
            Task { await self.appendToRing(chunk) }
        }

        engine.prepare()
        try engine.start()
        isActiveSubject.send(true)
        log.debug("activatePreRoll — engine started, pre-roll active")
    }

    /// Stops the pre-roll buffer. Uses engine.pause() instead of engine.stop() to avoid
    /// AVAudioEngine internally calling AVAudioSession.setActive(false), which would
    /// break AVCaptureSession's audio session and cause -17281 / sessionFailed on restart.
    public func deactivatePreRoll() async {
        guard isActiveSubject.value else { return }
        log.debug("deactivatePreRoll — pausing engine")
        engine.inputNode.removeTap(onBus: 0)
        engine.pause()   // pause, NOT stop — stop deactivates the shared AVAudioSession
        ringBuffer = []
        isActiveSubject.send(false)
        log.debug("deactivatePreRoll — done")
    }

    /// Captures 1.0s post-shutter, combines with pre-roll, classifies, persists tags, clears buffer.
    /// Fire-and-forget safe — errors are swallowed by the caller in CaptureEngine.
    public func analyzeAndTag(assetID: UUID) async throws -> [AcousticTag] {
        guard isActiveSubject.value else {
            log.debug("analyzeAndTag — pre-roll not active, skipping assetID=\(assetID.uuidString)")
            return []
        }
        log.debug("analyzeAndTag — sleeping \(Self.postShutterDuration)s post-shutter assetID=\(assetID.uuidString)")

        // Collect 1.0s of post-shutter audio
        try await Task.sleep(for: .seconds(Self.postShutterDuration))

        // Snapshot ring (pre-roll + post-shutter = up to 4.5s); clear immediately
        let snapshot = ringBuffer
        let sampleRate = tapSampleRate
        ringBuffer = []
        let totalSamples = snapshot.reduce(0) { $0 + $1.samples.count }
        log.debug("analyzeAndTag — captured \(totalSamples) samples at \(sampleRate)Hz")

        guard !snapshot.isEmpty else {
            log.warning("analyzeAndTag — ring buffer empty, no audio captured")
            return []
        }

        // Flatten all chunks to one [Float] — Sendable, safe to pass to Task.detached
        let allSamples: [Float] = snapshot.flatMap(\.samples)
        let channelCount = tapChannelCount

        // Classify on a detached task — SNAudioFileAnalyzer.analyze() blocks synchronously.
        // AVAudioPCMBuffer is constructed inside the closure so it never crosses a boundary.
        let tags: [AcousticTag] = try await Task.detached(priority: .userInitiated) {
            try Self.classify(samples: allSamples, sampleRate: sampleRate, channelCount: channelCount)
        }.value

        log.debug("analyzeAndTag — classification returned \(tags.count) tag(s): \(tags.map(\.tag.rawValue).joined(separator: ", "))")

        // Persist each tag to graph
        for tag in tags {
            try? await graph.updateAcousticTag(tag, for: assetID)
        }

        // Notify observers (MomentDetailView) that tags are ready — fires after the 1s delay
        if !tags.isEmpty {
            NotificationCenter.default.post(
                name: .niftyAcousticTagsUpdated,
                object: assetID.uuidString
            )
            log.debug("analyzeAndTag — posted niftyAcousticTagsUpdated for assetID=\(assetID.uuidString)")
        }

        return tags
    }

    // MARK: - Ring buffer management

    private func appendToRing(_ chunk: PCMChunk) {
        ringBuffer.append(chunk)
        let maxSamples = Int(Self.ringDuration * tapSampleRate)
        var total = ringBuffer.reduce(0) { $0 + $1.samples.count }
        while total > maxSamples, !ringBuffer.isEmpty {
            total -= ringBuffer[0].samples.count
            ringBuffer.removeFirst()
        }
    }

    // MARK: - Classification (static — no actor state, safe in Task.detached)

    private static func classify(samples: [Float], sampleRate: Double, channelCount: UInt32) throws -> [AcousticTag] {
        // Write as CAF / Int16 PCM — universally readable by SNAudioFileAnalyzer.
        // Float32 non-interleaved is silently unreadable by the analyzer.
        let writeSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: sampleRate,
                                       channels: 1,
                                       interleaved: false)
        guard let readFormat else {
            log.error("classify — AVAudioFormat nil")
            return []
        }

        // Temp CAF file — deleted via defer before this function returns.
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let writeBuffer = AVAudioPCMBuffer(pcmFormat: readFormat,
                                                 frameCapacity: AVAudioFrameCount(samples.count)),
              let dst = writeBuffer.floatChannelData else {
            log.error("classify — AVAudioPCMBuffer creation failed")
            return []
        }
        writeBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            dst[0].assign(from: ptr.baseAddress!, count: samples.count)
        }

        // Write in a do-scope so AVAudioFile deinits (flushes + closes fd) before
        // SNAudioFileAnalyzer opens the same URL.
        do {
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: writeSettings)
            try audioFile.write(from: writeBuffer)
        }

        let observer = AcousticObserver()
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let fileAnalyzer = try SNAudioFileAnalyzer(url: tempURL)
        try fileAnalyzer.add(request, withObserver: observer)

        // analyze(completionHandler:) delivers observer callbacks on its own internal queue —
        // no RunLoop needed. Semaphore blocks this Task.detached thread until done.
        let sem = DispatchSemaphore(value: 0)
        fileAnalyzer.analyze { _ in sem.signal() }
        sem.wait()

        log.debug("classify — \(observer.results.count) window(s), top identifiers:")
        let allAboveFloor = observer.results.flatMap(\.classifications)
            .filter { $0.confidence >= 0.10 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(15)
        for c in allAboveFloor {
            let mapped = mapAudioSetIdentifier(c.identifier).map(\.rawValue) ?? "—"
            log.debug("  \(c.identifier) conf=\(String(format: "%.2f", c.confidence)) → \(mapped)")
        }

        var best: [AcousticTagType: AcousticTag] = [:]
        for result in observer.results {
            for classification in result.classifications {
                guard Float(classification.confidence) >= confidenceThreshold,
                      let tagType = mapAudioSetIdentifier(classification.identifier) else { continue }
                let confidence = Float(classification.confidence)
                if best[tagType] == nil || confidence > best[tagType]!.confidence {
                    best[tagType] = AcousticTag(tag: tagType, source: .soundStamp, confidence: confidence)
                }
            }
        }
        return best.values.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - AudioSet → AcousticTagType allowlist

    /// Exposed as `internal` so `CoreMLIndexingAdapter` can reuse the same allowlist.
    static func mapAudioSetIdentifier(_ identifier: String) -> AcousticTagType? {
        let id = identifier.lowercased()
        for (tagType, prefixes) in allowlist {
            if prefixes.contains(where: { id.hasPrefix($0) }) { return tagType }
        }
        return nil
    }

    /// Ordered by specificity — more specific prefixes first to prevent false matches.
    private static let allowlist: [(AcousticTagType, [String])] = [
        (.beach,    ["beach", "surf", "ocean", "wave"]),
        (.river,    ["stream", "river", "babbling"]),
        (.water,    ["water", "waterfall", "dripping"]),
        (.rain,     ["rain"]),
        (.thunder,  ["thunder"]),
        (.wind,     ["wind"]),
        (.fire,     ["fire", "crackling"]),
        (.speech,   ["speech", "male_speech", "female_speech", "child_speech"]),
        (.laughter, ["laughter"]),
        (.crowd,    ["crowd", "chatter", "hubbub"]),
        (.singing,  ["singing", "choir", "vocal_music"]),
        (.music,    ["music"]),
        (.bird,     ["bird"]),
        (.dog,      ["dog", "bark", "bow-wow"]),
        (.insect,   ["insect", "cricket", "bee"]),
        (.airplane, ["airplane", "aircraft", "jet_engine"]),
        (.train,    ["train", "railroad", "rail_transport"]),
        (.car,      ["car", "vehicle", "engine", "traffic"]),
        (.alarm,    ["alarm", "siren", "smoke_detector"]),
    ]
}

// MARK: - SNResultsObserving bridge

private final class AcousticObserver: NSObject, SNResultsObserving {
    var results: [SNClassificationResult] = []
    var observerError: Error?

    func request(_ request: SNRequest, didProduce result: SNResult) {
        if let r = result as? SNClassificationResult { results.append(r) }
    }
    func request(_ request: SNRequest, didFailWithError error: Error) {
        log.error("AcousticObserver — didFailWithError: \(error)")
        observerError = error
    }
    func requestDidComplete(_ request: SNRequest) {}
}
