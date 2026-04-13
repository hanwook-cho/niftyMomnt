// NiftyData/Sources/Platform/AVReelComposer.swift
// Implements ReelComposerProtocol.
// Strategy: JPEG stills → pixel buffer video via AVAssetWriter (2.5 s per frame, 30 fps).
// Video/audio assets (clip, atmosphere, echo) are skipped in v0.7.
// Output: Documents/reels/{momentID}.mov
//
// Concurrency: all AVFoundation objects are created and used entirely on a dedicated
// serial DispatchQueue via requestMediaDataWhenReady(on:using:). No actor crossings.

@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import NiftyCore
import os
import UIKit

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "AVReelComposer")

public final class AVReelComposer: ReelComposerProtocol {
    private let vault: any VaultProtocol

    public init(vault: any VaultProtocol) {
        self.vault = vault
    }

    // MARK: - ReelComposerProtocol

    public func compose(reelAssets: [ReelAsset], momentID: UUID) async throws -> URL {
        // Filter to still-image types; video composition deferred to v0.9.
        let stillAssets = reelAssets.filter { [.still, .live, .l4c].contains($0.asset.type) }
        guard !stillAssets.isEmpty else { throw ReelComposerError.noSupportedAssets }

        let outputURL = Self.reelURL(for: momentID)
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Load JPEG data for all assets up front (async, before entering the sync writer path).
        let fps: Int32 = 30
        var frameData: [(CVPixelBuffer, Int64)] = []

        // Determine output dimensions from the first successfully decoded image.
        var outputWidth = 1080
        var outputHeight = 1920

        for ra in stillAssets {
            guard let (_, data) = try? await vault.loadPrimary(ra.asset.id),
                  let img = UIImage(data: data) else { continue }

            if frameData.isEmpty {
                let scale = min(1080 / img.size.width, 1920 / img.size.height, 1.0)
                outputWidth  = Int((img.size.width  * scale).rounded(.down) / 2) * 2
                outputHeight = Int((img.size.height * scale).rounded(.down) / 2) * 2
            }

            if let pb = Self.pixelBuffer(from: img, width: outputWidth, height: outputHeight) {
                let frameCount = Int64(2.5 * Double(fps))   // 2.5 s per still
                frameData.append((pb, frameCount))
            }
        }
        guard !frameData.isEmpty else { throw ReelComposerError.noSupportedAssets }

        // AVAssetWriter setup (created before handing off to the serial queue).
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
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

        // Pre-expand per-still bursts into a flat (pixelBuffer, presentationTime) array
        // so we can check isReadyForMoreMediaData before every single frame append.
        // CVPixelBuffer is a reference type — duplicating the tuple is cheap.
        var flatFrames: [(CVPixelBuffer, CMTime)] = []
        flatFrames.reserveCapacity(frameData.reduce(0) { $0 + Int($1.1) })
        var cursor = CMTime.zero
        for (pb, frameCount) in frameData {
            for f in 0..<frameCount {
                flatFrames.append((pb, CMTimeAdd(cursor, CMTimeMake(value: f, timescale: fps))))
            }
            cursor = CMTimeAdd(cursor, CMTimeMake(value: frameCount, timescale: fps))
        }

        // Drive the write loop via requestMediaDataWhenReady — the proper non-real-time API.
        // isReadyForMoreMediaData is rechecked before every frame to avoid the
        // "cannot append when readyForMoreMediaData is NO" crash.
        let writerQueue = DispatchQueue(label: "com.hwcho99.niftymomnt.reelWriter",
                                        qos: .userInitiated)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var frameIndex = 0

            writerInput.requestMediaDataWhenReady(on: writerQueue) {
                while writerInput.isReadyForMoreMediaData {
                    guard frameIndex < flatFrames.count else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .failed {
                                cont.resume(throwing: writer.error ?? ReelComposerError.exportFailed)
                            } else {
                                cont.resume()
                            }
                        }
                        return
                    }
                    let (pixelBuffer, time) = flatFrames[frameIndex]
                    adaptor.append(pixelBuffer, withPresentationTime: time)
                    frameIndex += 1
                }
            }
        }

        log.debug("compose done — \(frameData.count) still(s), \(flatFrames.count) frame(s) → \(outputURL.lastPathComponent)")
        return outputURL
    }

    // MARK: - File layout

    static func reelURL(for momentID: UUID) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reels", isDirectory: true)
            .appendingPathComponent("\(momentID.uuidString).mov")
    }

    // MARK: - Pixel buffer helpers

    private static func pixelBuffer(from image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
        // Render through UIKit's drawing stack to bake in EXIF/UIImage orientation.
        // Drawing UIImage.cgImage directly skips the orientation transform and produces
        // a 90°-rotated frame for portrait photos captured on iPhone.
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

// MARK: - Errors

public enum ReelComposerError: Error {
    case noSupportedAssets
    case exportFailed
}
