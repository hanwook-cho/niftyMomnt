// NiftyData/Sources/Platform/CoreImageCompositingAdapter.swift
// Implements CompositingAdapterProtocol using CGContext + CoreText.
// No UIKit — safe to call from a background task.
//
// Strip geometry (all in pixels, canvas = 1080 × 1920):
//   border:      28px all sides
//   gap between slots: 20px
//   slot width:  1080 − 2×28 = 1024px
//   slot height: (1920 − 2×28 − 3×20) / 4 = 444px
//   stamp zone:  64px (below slot 4, within border)
//   slot y[i]:   28 + i × (444 + 20)

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import NiftyCore
import os
import UIKit  // UIFont/UIImage for convenience; no UIView

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "CoreImageCompositing")

// Canvas constants
private let kW: CGFloat     = 1080
private let kH: CGFloat     = 1920
private let kBorder: CGFloat = 28
private let kGap: CGFloat    = 20
private let kSlotW: CGFloat  = kW - 2 * kBorder          // 1024
private let kSlotH: CGFloat  = (kH - 2 * kBorder - 3 * kGap) / 4  // 444
private let kStampH: CGFloat = 64

public final class CoreImageCompositingAdapter: CompositingAdapterProtocol {

    public init() {}

    public func compositeStrip(
        photos: [Data],
        borderColor: L4CBorderColor,
        frameAssetName: String?,
        stamp: L4CStampConfig
    ) async throws -> Data {
        // Run heavy CGContext work on a detached background task
        return try await Task.detached(priority: .userInitiated) {
            try Self.renderStrip(photos: photos, borderColor: borderColor,
                                 frameAssetName: frameAssetName, stamp: stamp)
        }.value
    }

    // MARK: - Render

    private static func renderStrip(
        photos: [Data],
        borderColor: L4CBorderColor,
        frameAssetName: String?,
        stamp: L4CStampConfig
    ) throws -> Data {
        guard photos.count == 4 else {
            throw CompositingError.wrongPhotoCount(photos.count)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(kW), height: Int(kH),
            bitsPerComponent: 8,
            bytesPerRow: Int(kW) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CompositingError.contextCreationFailed
        }

        // CoreGraphics origin is bottom-left; flip to top-left for easier layout
        ctx.translateBy(x: 0, y: kH)
        ctx.scaleBy(x: 1, y: -1)

        // 1. Fill border colour
        ctx.setFillColor(borderColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: kW, height: kH))

        // 2. Draw 4 photos into slots
        for (i, photoData) in photos.enumerated() {
            let slotY = kBorder + CGFloat(i) * (kSlotH + kGap)
            let slotRect = CGRect(x: kBorder, y: slotY, width: kSlotW, height: kSlotH)
            if let cgImage = cgImage(from: photoData) {
                drawImageFill(cgImage, in: slotRect, context: ctx)
            } else {
                // Fallback: dark placeholder
                ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
                ctx.fill(slotRect)
            }
        }

        // 3. Bottom stamp
        let stampY = kBorder + 4 * (kSlotH + kGap) - kGap  // start of stamp zone
        drawStamp(stamp, in: CGRect(x: kBorder, y: stampY, width: kSlotW, height: kStampH), context: ctx)

        // 4. Featured Frame overlay
        if let assetName = frameAssetName, assetName != "none",
           let frameImage = UIImage(named: assetName)?.cgImage {
            ctx.draw(frameImage, in: CGRect(x: 0, y: 0, width: kW, height: kH))
            log.debug("compositeStrip — frame '\(assetName)' composited")
        }

        // 5. Export JPEG
        guard let cgResult = ctx.makeImage() else {
            throw CompositingError.renderFailed
        }
        let uiImage = UIImage(cgImage: cgResult)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.88) else {
            throw CompositingError.encodingFailed
        }
        log.debug("compositeStrip done — \(jpegData.count) bytes")
        return jpegData
    }

    // MARK: - Helpers

    /// Decode JPEG/PNG Data → CGImage
    private static func cgImage(from data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        // Try JPEG first, then PNG
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            ?? CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Draw `image` filling `rect` with aspect-fill (center crop).
    private static func drawImageFill(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let scaleW = rect.width  / imgW
        let scaleH = rect.height / imgH
        let scale  = max(scaleW, scaleH)
        let drawW  = imgW * scale
        let drawH  = imgH * scale
        let drawX  = rect.minX - (drawW - rect.width)  / 2
        let drawY  = rect.minY - (drawH - rect.height) / 2

        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.draw(image, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        ctx.restoreGState()
    }

    /// Draws the niftyMomnt wordmark + date/location into the stamp zone.
    private static func drawStamp(_ stamp: L4CStampConfig, in rect: CGRect, context ctx: CGContext) {
        // App wordmark — centred, ~22pt bold white
        if stamp.showAppLogo {
            let wordmark = "niftyMomnt" as NSString
            let logoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .black),
                .foregroundColor: UIColor.white.withAlphaComponent(0.82)
            ]
            let logoSize = wordmark.size(withAttributes: logoAttrs)
            let logoX = rect.midX - logoSize.width / 2
            let logoY = rect.minY + 6
            wordmark.draw(at: CGPoint(x: logoX, y: logoY), withAttributes: logoAttrs)
        }

        // Date + location line — centred, ~11pt regular white
        var subParts: [String] = []
        if !stamp.dateText.isEmpty     { subParts.append(stamp.dateText) }
        if !stamp.locationText.isEmpty { subParts.append(stamp.locationText) }
        let subLine = subParts.joined(separator: " · ") as NSString
        if !subLine.isEqual(to: "") {
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55)
            ]
            let subSize = subLine.size(withAttributes: subAttrs)
            let subX = rect.midX - subSize.width / 2
            let subY = rect.minY + 30
            subLine.draw(at: CGPoint(x: subX, y: subY), withAttributes: subAttrs)
        }
    }
}

// MARK: - L4CBorderColor → CGColor

private extension L4CBorderColor {
    var cgColor: CGColor {
        switch self {
        case .white:      return CGColor(red: 1,    green: 1,    blue: 1,    alpha: 1)
        case .black:      return CGColor(red: 0,    green: 0,    blue: 0,    alpha: 1)
        case .pastelPink: return CGColor(red: 1,    green: 0.84, blue: 0.88, alpha: 1)
        case .skyBlue:    return CGColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1)
        }
    }
}

// MARK: - Error

public enum CompositingError: Error {
    case wrongPhotoCount(Int)
    case contextCreationFailed
    case renderFailed
    case encodingFailed
}
