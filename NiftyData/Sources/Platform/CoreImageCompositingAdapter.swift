// NiftyData/Sources/Platform/CoreImageCompositingAdapter.swift
// Implements CompositingAdapterProtocol using CGContext + CoreText.
// No UIKit — safe to call from a background task.
//
// Strip geometry (all in pixels, canvas = 1080 × 1920):
//   border:      28px all sides
//   gap between slots: 20px
//   slot height: fit four slots vertically while leaving a bottom stamp zone
//   slot width:  derived from the selected booth photo shape (4:3 or 3:4)
//   stamp zone:  64px (below slot 4, within border)

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import NiftyCore
import os
import UIKit  // UIFont/UIImage for convenience; no UIView

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "CoreImageCompositing")

// Canvas constants
private let kW: CGFloat      = 1080
private let kBorder: CGFloat = 28
private let kGap: CGFloat    = 20
private let kStampH: CGFloat = 160

public final class CoreImageCompositingAdapter: CompositingAdapterProtocol {

    public init() {}

    public func compositeStrip(
        photos: [Data],
        photoShape: L4CPhotoShape,
        borderColor: L4CBorderColor,
        frameAssetName: String?,
        stamp: L4CStampConfig
    ) async throws -> Data {
        // Run heavy CGContext work on a detached background task
        return try await Task.detached(priority: .userInitiated) {
            try Self.renderStrip(photos: photos, photoShape: photoShape, borderColor: borderColor,
                                 frameAssetName: frameAssetName, stamp: stamp)
        }.value
    }

    // MARK: - Render

    private static func renderStrip(
        photos: [Data],
        photoShape: L4CPhotoShape,
        borderColor: L4CBorderColor,
        frameAssetName: String?,
        stamp: L4CStampConfig
    ) throws -> Data {
        guard photos.count == 4 else {
            throw CompositingError.wrongPhotoCount(photos.count)
        }

        let layout = stripLayout(for: photoShape)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let rendered = UIGraphicsImageRenderer(size: layout.canvasSize, format: format).image { rendererContext in
            let ctx = rendererContext.cgContext

            // 1. Fill border colour
            ctx.setFillColor(borderColor.cgColor)
            ctx.fill(CGRect(origin: .zero, size: layout.canvasSize))

            // 2. Draw 4 photos into slots
            for (i, photoData) in photos.enumerated() {
                let slotRect = layout.slotRects[i]
                if let image = image(from: photoData) {
                    drawImageFill(image, in: slotRect, context: ctx)
                } else {
                    ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
                    ctx.fill(slotRect)
                }
            }

            // 3. Bottom stamp
            drawStamp(
                stamp,
                in: CGRect(
                    x: kBorder,
                    y: layout.stampOriginY,
                    width: layout.slotRects.first?.width ?? (kW - 2 * kBorder),
                    height: kStampH
                ),
                context: ctx
            )

            // 4. Featured Frame overlay
            if let assetName = frameAssetName, assetName != "none",
               let frameImage = UIImage(named: assetName) {
                frameImage.draw(in: CGRect(origin: .zero, size: layout.canvasSize))
                log.debug("compositeStrip — frame '\(assetName)' composited")
            }
        }

        // 5. Export JPEG
        guard let jpegData = rendered.jpegData(compressionQuality: 0.88) else {
            throw CompositingError.encodingFailed
        }
        log.debug("compositeStrip done — \(jpegData.count) bytes")
        return jpegData
    }

    // MARK: - Helpers

    /// Decode booth photo data into an upright image that can be cropped consistently.
    private static func image(from data: Data) -> UIImage? {
        UIImage(data: data)?.normalizedOrientationImage()
    }

    /// Draw `image` filling `rect` with aspect-fill (center crop).
    private static func drawImageFill(_ image: UIImage, in rect: CGRect, context ctx: CGContext) {
        let imgW = image.size.width
        let imgH = image.size.height
        let scaleW = rect.width  / imgW
        let scaleH = rect.height / imgH
        let scale  = max(scaleW, scaleH)
        let drawW  = imgW * scale
        let drawH  = imgH * scale
        let drawX  = rect.minX - (drawW - rect.width)  / 2
        let drawY  = rect.minY - (drawH - rect.height) / 2

        ctx.saveGState()
        ctx.clip(to: rect)
        UIGraphicsPushContext(ctx)
        image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        UIGraphicsPopContext()
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

    private static func stripLayout(for shape: L4CPhotoShape) -> BoothStripLayout {
        let slotWidth = kW - 2 * kBorder
        let slotHeight = slotWidth / shape.widthToHeightAspect
        let slotRects = (0..<4).map { index in
            CGRect(
                x: kBorder,
                y: kBorder + CGFloat(index) * (slotHeight + kGap),
                width: slotWidth,
                height: slotHeight
            )
        }
        let stampOriginY = (slotRects.last?.maxY ?? kBorder) + kGap
        let canvasHeight = stampOriginY + kStampH + kBorder
        return BoothStripLayout(
            canvasSize: CGSize(width: kW, height: canvasHeight),
            slotRects: slotRects,
            stampOriginY: stampOriginY
        )
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

private extension L4CPhotoShape {
    var widthToHeightAspect: CGFloat {
        switch self {
        case .fourByThree:
            return 4.0 / 3.0
        case .threeByFour:
            return 3.0 / 4.0
        }
    }
}

private struct BoothStripLayout {
    let canvasSize: CGSize
    let slotRects: [CGRect]
    let stampOriginY: CGFloat
}

private extension UIImage {
    func normalizedOrientationImage() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
