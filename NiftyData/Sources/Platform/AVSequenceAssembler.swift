// NiftyData/Sources/Platform/AVSequenceAssembler.swift
// Piqd v0.3 — implements SequenceAssemblerProtocol.
// Strategy: HEIC frames on disk → CVPixelBuffer → AVAssetWriter H.264 MP4 (9:16).
// 6 frames at `frameDurationSeconds` apiece (default 0.333s → ~2.0s total).
// The output MP4 is designed to be played on loop by the consuming player; we emit a
// single pass (not a hard-baked loop) so the file stays small and player-agnostic.
//
// Concurrency: AVFoundation objects are driven via requestMediaDataWhenReady on a
// dedicated serial queue. No actor crossings inside the writer callback.

@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import NiftyCore
import os
import UIKit

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "AVSequenceAssembler")

public final class AVSequenceAssembler: SequenceAssemblerProtocol {

    public init() {}

    public enum AssemblerError: Error {
        case noDecodableFrames
        case pixelBufferCreationFailed
        case exportFailed
    }

    // MARK: - SequenceAssemblerProtocol

    public func assemble(
        frameURLs: [URL],
        outputURL: URL,
        frameDurationSeconds: Double
    ) async throws -> (url: URL, durationSeconds: Double) {

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Use a high-enough timescale that 0.333s lands cleanly (1/3s → timescale 600 → 200).
        let timescale: Int32 = 600
        let frameDurationTicks = Int64((frameDurationSeconds * Double(timescale)).rounded())

        // Decode all frames up front. First successfully-decoded frame sets output size
        // (rounded down to even numbers, capped at 1080×1920 9:16 canvas).
        var outputWidth = 1080
        var outputHeight = 1920
        var pixelBuffers: [CVPixelBuffer] = []
        pixelBuffers.reserveCapacity(frameURLs.count)

        for (idx, url) in frameURLs.enumerated() {
            guard let data = try? Data(contentsOf: url),
                  let img = UIImage(data: data) else {
                log.error("failed to decode frame \(idx) at \(url.lastPathComponent)")
                continue
            }
            if pixelBuffers.isEmpty {
                let scale = min(1080 / img.size.width, 1920 / img.size.height, 1.0)
                outputWidth  = Int((img.size.width  * scale).rounded(.down) / 2) * 2
                outputHeight = Int((img.size.height * scale).rounded(.down) / 2) * 2
            }
            guard let pb = Self.pixelBuffer(from: img, width: outputWidth, height: outputHeight) else {
                log.error("pixel buffer creation failed for frame \(idx)")
                continue
            }
            pixelBuffers.append(pb)
        }

        guard !pixelBuffers.isEmpty else { throw AssemblerError.noDecodableFrames }

        // AVAssetWriter setup.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  outputWidth,
            AVVideoHeightKey: outputHeight,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: outputWidth,
                kCVPixelBufferHeightKey as String: outputHeight,
            ]
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Build (buffer, presentationTime) schedule.
        var flatFrames: [(CVPixelBuffer, CMTime)] = []
        flatFrames.reserveCapacity(pixelBuffers.count)
        for (i, pb) in pixelBuffers.enumerated() {
            let pts = CMTimeMake(value: Int64(i) * frameDurationTicks, timescale: timescale)
            flatFrames.append((pb, pts))
        }
        // End-of-stream time = last PTS + one frame duration.
        let endTime = CMTimeMake(
            value: Int64(pixelBuffers.count) * frameDurationTicks,
            timescale: timescale
        )

        let writerQueue = DispatchQueue(
            label: "com.hwcho99.niftymomnt.sequenceAssembler",
            qos: .userInitiated
        )

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var frameIndex = 0
            writerInput.requestMediaDataWhenReady(on: writerQueue) {
                while writerInput.isReadyForMoreMediaData {
                    guard frameIndex < flatFrames.count else {
                        writerInput.markAsFinished()
                        writer.endSession(atSourceTime: endTime)
                        writer.finishWriting {
                            if writer.status == .failed {
                                cont.resume(throwing: writer.error ?? AssemblerError.exportFailed)
                            } else {
                                cont.resume()
                            }
                        }
                        return
                    }
                    let (pb, pts) = flatFrames[frameIndex]
                    adaptor.append(pb, withPresentationTime: pts)
                    frameIndex += 1
                }
            }
        }

        let durationSeconds = Double(pixelBuffers.count) * frameDurationSeconds
        log.debug("assembled \(pixelBuffers.count) frame(s) → \(outputURL.lastPathComponent) (\(durationSeconds)s)")
        return (outputURL, durationSeconds)
    }

    // MARK: - Pixel buffer helper (shared logic with AVReelComposer; kept local to avoid cross-file coupling)

    private static func pixelBuffer(from image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let oriented = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cgImage = oriented.cgImage else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true,
             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pb
    }
}
