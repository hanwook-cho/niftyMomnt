// NiftyData/Sources/Platform/SubjectGuidanceDetector.swift
// Piqd v0.4 — wraps `VNDetectFaceRectanglesRequest` and turns face bounding-box geometry
// into `FaceFramingSignal` events for the "Step back for the full vibe" pill (UIUX §2.11).
//
// Behavior contract:
//   • Throttles work to ≤ 2 fps (`minProcessIntervalSeconds`). Frames arriving faster are
//     dropped — Vision face detection is still ~10ms even at lowest revision, so a 500ms
//     gap is the minimum that avoids piling up on the capture queue.
//   • Edge proximity: a face whose bounding box (in normalized 0…1 image coords) lies
//     within 15% of any frame edge emits `.edgeProximity(side:)`. The "closest" edge
//     is chosen for stable single-emission semantics.
//   • Per-edge cooldown: once an edge fires, the same edge can't re-fire for 10 seconds.
//     Other edges are free to fire during that window — matches PRD §7.3 ("don't nag").
//
// Test seams:
//   • `emit(rect:frame:)` — push a face rect directly without a CMSampleBuffer. Lets
//     unit tests and UI fixtures drive the pipeline deterministically.
//   • `NowProvider` — controls the cooldown clock under test.
//
// Wiring: PiqdAppContainer holds the singleton; PiqdCaptureView subscribes to `signals`
// and renders the pill. The frame source (a primary AVCaptureVideoDataOutput) is wired
// in a later step — until then the dev menu / UI tests drive it via `emit(...)`.

import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import NiftyCore
import os

#if canImport(Vision)
import Vision
#endif

private let guidanceLog = Logger(subsystem: "com.hwcho99.niftymomnt", category: "SubjectGuidance")

public final class SubjectGuidanceDetector: @unchecked Sendable {

    // MARK: - Tunables

    /// 15% of any frame edge → "too close". Spec §7.3.
    public static let edgeMarginFraction: Double = 0.15
    /// Per-edge cooldown after a fire. Spec §7.3.
    public static let cooldownSeconds: TimeInterval = 10.0
    /// Hard floor between Vision passes. Caps detector at ≤ 2 fps.
    public static let minProcessIntervalSeconds: TimeInterval = 0.5

    // MARK: - State

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<FaceFramingSignal>.Continuation] = [:]
    private var started = false
    private var lastProcessAt: Date?
    private var lastFireByEdge: [FrameEdge: Date] = [:]

    private let now: NowProvider

    // MARK: - Vision

    #if canImport(Vision)
    private let visionQueue = DispatchQueue(
        label: "com.hwcho99.niftymomnt.subjectGuidanceQ",
        qos: .userInitiated
    )
    #endif

    public init(now: NowProvider = SystemNowProvider()) {
        self.now = now
    }

    // MARK: - Lifecycle

    public func start() {
        lock.withLock {
            guard !started else { return }
            started = true
            // Reset cooldowns on (re)start so first frame is free to fire.
            lastFireByEdge.removeAll()
            lastProcessAt = nil
        }
    }

    public func stop() {
        lock.withLock { started = false }
    }

    public func isRunning() -> Bool { lock.withLock { started } }

    // MARK: - Stream

    public var signals: AsyncStream<FaceFramingSignal> {
        AsyncStream { continuation in
            let id = UUID()
            self.lock.withLock { self.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    // MARK: - Frame ingest

    /// Drive the detector from a real CMSampleBuffer. Off-loads Vision work to a private
    /// queue. No-op when stopped or when called within `minProcessIntervalSeconds` of the
    /// previous frame.
    ///
    /// `orientation` tells Vision how the buffer is rotated relative to the user's
    /// viewfinder. For Piqd's portrait-locked viewfinder: back camera = `.right`,
    /// front camera = `.leftMirrored`. Default `.right` covers the dominant case.
    public func process(_ buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation = .right) {
        let shouldRun: Bool = lock.withLock {
            guard started else { return false }
            let t = now.now()
            if let last = lastProcessAt, t.timeIntervalSince(last) < Self.minProcessIntervalSeconds {
                return false
            }
            lastProcessAt = t
            return true
        }
        guard shouldRun else { return }

        #if canImport(Vision)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        visionQueue.async { [weak self] in
            guard let self else { return }
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                guidanceLog.error("VNDetectFaceRectanglesRequest failed: \(String(describing: error))")
                return
            }
            let observations = request.results ?? []
            // Vision boundingBox is in normalized image coords with origin bottom-left.
            // For edge-proximity we just need normalized 0…1 — flip Y so "top" means
            // the visual top edge.
            let rects: [CGRect] = observations.map { obs in
                let r = obs.boundingBox
                return CGRect(x: r.minX, y: 1.0 - r.maxY, width: r.width, height: r.height)
            }
            let edge = rects.compactMap { Self.edgeProximity(forRect: $0) }.first
            let signal: FaceFramingSignal = edge.map { .edgeProximity(side: $0) } ?? .ok
            self.publishIfAllowed(signal)
        }
        #endif
    }

    /// Test/dev seam — push a face rect directly. `rect` and `frame` may be in any units;
    /// only their ratio matters.
    public func emit(rect: CGRect, frame: CGSize) {
        let normalized = CGRect(
            x: rect.minX / max(frame.width, 1),
            y: rect.minY / max(frame.height, 1),
            width: rect.width / max(frame.width, 1),
            height: rect.height / max(frame.height, 1)
        )
        let signal: FaceFramingSignal = Self.edgeProximity(forRect: normalized)
            .map { FaceFramingSignal.edgeProximity(side: $0) } ?? .ok
        publishIfAllowed(signal)
    }

    // MARK: - Pure helpers

    /// Closest edge within `edgeMarginFraction` of the given normalized rect, or nil.
    /// `rect` is in 0…1 coords with origin top-left.
    public static func edgeProximity(forRect rect: CGRect) -> FrameEdge? {
        let m = edgeMarginFraction
        let distances: [(FrameEdge, Double)] = [
            (.top,      rect.minY),
            (.bottom,   1.0 - rect.maxY),
            (.leading,  rect.minX),
            (.trailing, 1.0 - rect.maxX)
        ]
        let closest = distances.min(by: { $0.1 < $1.1 })
        guard let (edge, d) = closest, d < m else { return nil }
        return edge
    }

    // MARK: - Publish + cooldown

    private func publishIfAllowed(_ signal: FaceFramingSignal) {
        let conts: [AsyncStream<FaceFramingSignal>.Continuation] = lock.withLock {
            switch signal {
            case .ok:
                // OK is informational — never blocked by cooldown. Useful for the UI to
                // pre-emptively dismiss the pill if the user reframes.
                break
            case .edgeProximity(let side):
                let t = now.now()
                if let last = lastFireByEdge[side], t.timeIntervalSince(last) < Self.cooldownSeconds {
                    return []
                }
                lastFireByEdge[side] = t
            }
            return Array(continuations.values)
        }
        for c in conts { c.yield(signal) }
    }
}
