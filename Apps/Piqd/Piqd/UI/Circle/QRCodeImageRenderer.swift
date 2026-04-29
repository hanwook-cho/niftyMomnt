// Apps/Piqd/Piqd/UI/Circle/QRCodeImageRenderer.swift
// Piqd v0.6 — `CIQRCodeGenerator`-backed UIImage helper. Used by Onboarding
// O3, Settings → CIRCLE → "My invite QR", and any place a `piqd://invite/...`
// URL needs to render as a scannable code.
//
// Pure helper (stateless), runs on the main thread on call. CIContext is
// recreated per render — fine at human scale (one QR at a time, not 60fps).

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

public enum QRCodeImageRenderer {

    /// Render `url.absoluteString` as a QR code at `size` points square.
    public static func image(
        for url: URL,
        size: CGFloat,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        image(for: url.absoluteString, size: size, scale: scale)
    }

    /// Render an arbitrary string as a QR code. Medium error correction (default).
    public static func image(
        for string: String,
        size: CGFloat,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        // Scale the bare CIImage (~21pt for short payloads) up to the requested
        // pixel size with nearest-neighbor (preserved in CGImage from the
        // bitmap context — CIQRCodeGenerator output is binary so the scale
        // doesn't introduce smoothing artifacts).
        let pixelSize = size * scale
        let scaleFactor = pixelSize / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))

        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}
