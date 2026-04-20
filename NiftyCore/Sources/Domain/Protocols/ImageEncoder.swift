// NiftyCore/Sources/Domain/Protocols/ImageEncoder.swift
// Piqd v0.2 — abstracted image encoder so the capture use case can crop + re-encode
// without coupling NiftyCore to ImageIO. Concrete implementations live in NiftyData
// (HEICEncoder, JPEGEncoder).

import Foundation

public enum ImageEncoderError: Error, Sendable {
    case decodeFailed
    case encodeFailed
}

public protocol ImageEncoder: Sendable {
    /// File extension (no leading dot) the produced bytes should be saved under.
    var fileExtension: String { get }

    /// Decode `sourceData` (typically JPEG bytes from AVCapturePhotoOutput), optionally
    /// center-crop to `crop`, and re-encode. `quality` is clamped to 0…1 by implementations.
    func encode(sourceData: Data, crop: AspectRatio?, quality: Double) throws -> Data
}
