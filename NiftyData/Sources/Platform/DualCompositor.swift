// NiftyData/Sources/Platform/DualCompositor.swift
// Piqd v0.3 — Dual Video composite. Combines the two MOV streams produced by
// AVCaptureAdapter's dual-video path into a single 9:16 MP4 in one of three layouts:
//   .pip        — rear full-frame, front inset top-right (default)
//   .topBottom  — rear top half, front bottom half
//   .sideBySide — rear left half, front right half
// Audio is taken from the primary stream only.

import AVFoundation
import CoreGraphics
import Foundation
import NiftyCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "DualCompositor")

public struct DualCompositor: Sendable {

    public enum CompositorError: Error, Sendable {
        case missingVideoTrack
        case compositionTrackInsertionFailed
        case exporterUnavailable
        case exportFailed(underlying: Error?)
    }

    /// Canvas size — 9:16 portrait, 1080×1920.
    public let canvasSize: CGSize
    /// Layout used to place the two streams into the canvas.
    public let layout: DualLayout

    public init(canvasSize: CGSize = CGSize(width: 1080, height: 1920),
                layout: DualLayout = .pip) {
        self.canvasSize = canvasSize
        self.layout = layout
    }

    /// Produces a composite MOV at `outputURL`. Overwrites `outputURL` if it exists.
    /// Returns the duration of the output clip (min of the two input durations).
    public func composite(primaryURL: URL, secondaryURL: URL, outputURL: URL) async throws -> CMTime {
        let primary = AVURLAsset(url: primaryURL)
        let secondary = AVURLAsset(url: secondaryURL)

        let primVideoTracks = try await primary.loadTracks(withMediaType: .video)
        let secVideoTracks = try await secondary.loadTracks(withMediaType: .video)
        guard let primVideo = primVideoTracks.first else { throw CompositorError.missingVideoTrack }
        guard let secVideo = secVideoTracks.first else { throw CompositorError.missingVideoTrack }

        let primDuration = try await primary.load(.duration)
        let secDuration = try await secondary.load(.duration)
        let finalDuration = CMTimeMinimum(primDuration, secDuration)
        let timeRange = CMTimeRange(start: .zero, duration: finalDuration)

        let composition = AVMutableComposition()

        guard
            let primCompTrack = composition.addMutableTrack(withMediaType: .video,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid),
            let secCompTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw CompositorError.compositionTrackInsertionFailed
        }
        do {
            try primCompTrack.insertTimeRange(timeRange, of: primVideo, at: .zero)
            try secCompTrack.insertTimeRange(timeRange, of: secVideo, at: .zero)
        } catch {
            throw CompositorError.compositionTrackInsertionFailed
        }

        if let primAudio = try await primary.loadTracks(withMediaType: .audio).first,
           let audTrack = composition.addMutableTrack(withMediaType: .audio,
                                                     preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audTrack.insertTimeRange(timeRange, of: primAudio, at: .zero)
        }

        let primNatural = try await primVideo.load(.naturalSize)
        let primXform = try await primVideo.load(.preferredTransform)
        let secNatural = try await secVideo.load(.naturalSize)
        let secXform = try await secVideo.load(.preferredTransform)

        let rects = DualCompositor.layoutRects(canvas: canvasSize, layout: layout)

        // PIP uses aspect-fill (primary == canvas; secondary is small enough that minor
        // overflow stays within canvas). Split layouts use aspect-fit because layer
        // instructions don't clip to target — aspect-fill would overflow into the
        // other half. Fit gives small black bars instead of overlap.
        let useFill = (layout == .pip)
        let primFill = DualCompositor.transform(natural: primNatural,
                                                preferred: primXform,
                                                target: rects.primary,
                                                useAspectFill: useFill)
        let secFill = DualCompositor.transform(natural: secNatural,
                                               preferred: secXform,
                                               target: rects.secondary,
                                               useAspectFill: useFill)

        let primLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: primCompTrack)
        primLayer.setTransform(primFill, at: .zero)

        let secLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: secCompTrack)
        secLayer.setTransform(secFill, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        // Layer instructions render front-to-back in array order. Secondary first puts the
        // front-camera frame on top — only matters for .pip; split layouts don't overlap.
        instruction.layerInstructions = [secLayer, primLayer]

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = canvasSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)
        videoComp.instructions = [instruction]

        guard let exporter = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetHighestQuality) else {
            throw CompositorError.exporterUnavailable
        }
        try? FileManager.default.removeItem(at: outputURL)
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.videoComposition = videoComp
        exporter.shouldOptimizeForNetworkUse = true

        log.info("DualCompositor — exporting layout=\(layout.rawValue, privacy: .public) duration=\(CMTimeGetSeconds(finalDuration))s")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    cont.resume()
                case .failed, .cancelled:
                    cont.resume(throwing: CompositorError.exportFailed(underlying: exporter.error))
                default:
                    cont.resume(throwing: CompositorError.exportFailed(underlying: nil))
                }
            }
        }

        log.info("DualCompositor — export completed")
        return finalDuration
    }

    // MARK: - Layout

    /// Returns target rects (in canvas coordinates, top-left origin) for primary and
    /// secondary streams under the given layout. Shared by Dual Video and Dual Still.
    public static func layoutRects(canvas: CGSize, layout: DualLayout) -> (primary: CGRect, secondary: CGRect) {
        switch layout {
        case .pip:
            let insetWidthFraction: CGFloat = 0.30
            let insetPadding: CGFloat = 40
            let primary = CGRect(origin: .zero, size: canvas)
            let insetW = canvas.width * insetWidthFraction
            // Match the inset's aspect to the canvas (9:16) so the front camera scales
            // sensibly regardless of source orientation.
            let insetH = insetW * (canvas.height / canvas.width)
            let secondary = CGRect(x: canvas.width - insetW - insetPadding,
                                   y: insetPadding,
                                   width: insetW,
                                   height: insetH)
            return (primary, secondary)

        case .topBottom:
            let halfH = canvas.height / 2
            let primary = CGRect(x: 0, y: 0, width: canvas.width, height: halfH)
            let secondary = CGRect(x: 0, y: halfH, width: canvas.width, height: halfH)
            return (primary, secondary)

        case .sideBySide:
            let halfW = canvas.width / 2
            let primary = CGRect(x: 0, y: 0, width: halfW, height: canvas.height)
            let secondary = CGRect(x: halfW, y: 0, width: halfW, height: canvas.height)
            return (primary, secondary)
        }
    }

    // MARK: - Transform

    /// Builds the affine transform that places a source of `natural` size, oriented by
    /// `preferred`, into `target` (in canvas coords). `useAspectFill` chooses between
    /// max-scale (fill, may overflow target) and min-scale (fit, letterbox within target).
    private static func transform(natural: CGSize,
                                  preferred: CGAffineTransform,
                                  target: CGRect,
                                  useAspectFill: Bool) -> CGAffineTransform {
        let orientedRect = CGRect(origin: .zero, size: natural).applying(preferred)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))

        let sx = target.width / orientedSize.width
        let sy = target.height / orientedSize.height
        let scale = useAspectFill ? max(sx, sy) : min(sx, sy)
        let scaledW = orientedSize.width * scale
        let scaledH = orientedSize.height * scale
        let tx = target.minX + (target.width - scaledW) / 2
        let ty = target.minY + (target.height - scaledH) / 2

        var m = preferred
        m = m.concatenating(CGAffineTransform(translationX: -orientedRect.minX,
                                              y: -orientedRect.minY))
        m = m.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        m = m.concatenating(CGAffineTransform(translationX: tx, y: ty))
        return m
    }
}
