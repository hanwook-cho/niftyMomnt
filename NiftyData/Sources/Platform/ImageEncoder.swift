// NiftyData/Sources/Platform/ImageEncoder.swift
// Piqd v0.2 — concrete ImageEncoder implementations. Decodes source bytes with ImageIO,
// optionally center-crops via AspectRatio, and re-encodes as HEIC or JPEG.

import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import CoreImage
import NiftyCore
import os

private let encoderLog = Logger(subsystem: "com.hwcho99.niftymomnt", category: "ImageEncoder")
private let ciContext = CIContext(options: nil)

public struct HEICEncoder: ImageEncoder {
    public init() {}
    public var fileExtension: String { "heic" }

    public func encode(sourceData: Data, crop: AspectRatio?, quality: Double) throws -> Data {
        try encodeImage(sourceData: sourceData, crop: crop, quality: quality,
                        type: UTType.heic.identifier as CFString)
    }
}

public struct JPEGEncoder: ImageEncoder {
    public init() {}
    public var fileExtension: String { "jpg" }

    public func encode(sourceData: Data, crop: AspectRatio?, quality: Double) throws -> Data {
        try encodeImage(sourceData: sourceData, crop: crop, quality: quality,
                        type: UTType.jpeg.identifier as CFString)
    }
}

private func encodeImage(sourceData: Data, crop: AspectRatio?, quality: Double, type: CFString) throws -> Data {
    guard let src = CGImageSourceCreateWithData(sourceData as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw ImageEncoderError.decodeFailed
    }

    // AVCapturePhotoOutput JPEGs carry EXIF orientation (sensor is landscape; portrait
    // captures are tagged orientation=6). Bake that into the pixel buffer first so the
    // crop math runs on display-oriented coords, and so the encoded file doesn't depend
    // on consumers honoring the orientation tag.
    let exifOrientation: Int32 = {
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        if let n = props?[kCGImagePropertyOrientation] as? NSNumber {
            return n.int32Value
        }
        return 1
    }()
    encoderLog.log("encode: raw \(cgImage.width)x\(cgImage.height), exifOrientation=\(exifOrientation)")
    let upright = bakeOrientation(cgImage, exifOrientation: exifOrientation) ?? cgImage
    encoderLog.log("encode: upright \(upright.width)x\(upright.height)")

    let finalImage: CGImage
    if let crop {
        let size = CGSize(width: upright.width, height: upright.height)
        let rect = crop.centerCropRect(in: size)
        if rect.size == size {
            finalImage = upright
        } else {
            guard let cropped = upright.cropping(to: rect) else {
                throw ImageEncoderError.encodeFailed
            }
            finalImage = cropped
        }
    } else {
        finalImage = upright
    }

    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else {
        throw ImageEncoderError.encodeFailed
    }
    let clampedQuality = max(0.0, min(1.0, quality))
    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: clampedQuality
    ]
    CGImageDestinationAddImage(dest, finalImage, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw ImageEncoderError.encodeFailed
    }
    return out as Data
}

/// Bakes the EXIF orientation into the pixel buffer so the returned CGImage has natural
/// top-left pixels. Uses CIImage.oriented(forExifOrientation:) — handles all 8 EXIF cases
/// per the spec without the CG-vs-UIKit Y-axis sign ambiguity that hand-rolled affine
/// transforms suffer from.
private func bakeOrientation(_ image: CGImage, exifOrientation: Int32) -> CGImage? {
    guard exifOrientation > 1, exifOrientation <= 8 else { return image }
    let oriented = CIImage(cgImage: image).oriented(forExifOrientation: exifOrientation)
    return ciContext.createCGImage(oriented, from: oriented.extent)
}
