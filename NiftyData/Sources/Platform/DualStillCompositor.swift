// NiftyData/Sources/Platform/DualStillCompositor.swift
// Piqd v0.3 — Dual Still composite. Combines two photos (rear + front) into a single
// 9:16 HEIC using the same DualLayout enum as DualCompositor (Video). Layout placement
// math is shared via DualCompositor.layoutRects(canvas:layout:).

import CoreGraphics
import Foundation
import NiftyCore
import UIKit
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "DualStillCompositor")

public struct DualStillCompositor: Sendable {

    public enum CompositorError: Error, Sendable {
        case decodeFailed
        case encodeFailed
    }

    /// Canvas size — 9:16 portrait, 1080×1920 to match the Video composite.
    public let canvasSize: CGSize
    public let layout: DualLayout

    public init(canvasSize: CGSize = CGSize(width: 1080, height: 1920),
                layout: DualLayout = .pip) {
        self.canvasSize = canvasSize
        self.layout = layout
    }

    /// Composites `primaryData` (rear) and `secondaryData` (front) into a single JPEG.
    /// JPEG keeps parity with the single-camera capture path (which writes JPEG to
    /// `<assetID>.jpg` for downstream HEIC re-encoding by the vault). Both inputs may
    /// be JPEG or HEIC — UIImage decodes either and honors EXIF orientation.
    public func composite(primaryData: Data, secondaryData: Data) throws -> Data {
        guard let primaryImage = UIImage(data: primaryData),
              let secondaryImage = UIImage(data: secondaryData) else {
            throw CompositorError.decodeFailed
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        let rects = DualCompositor.layoutRects(canvas: canvasSize, layout: layout)

        let composite = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            DualStillCompositor.drawAspectFill(image: primaryImage, in: rects.primary)
            DualStillCompositor.drawAspectFill(image: secondaryImage, in: rects.secondary)
        }

        guard let jpeg = composite.jpegData(compressionQuality: 0.92) else {
            throw CompositorError.encodeFailed
        }

        log.info("DualStillCompositor — encoded layout=\(layout.rawValue, privacy: .public) bytes=\(jpeg.count)")
        return jpeg
    }

    /// Aspect-fill draw: scale the image to cover `target`, center, clip to target.
    private static func drawAspectFill(image: UIImage, in target: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.clip(to: target)

        let imgSize = image.size
        let scale = max(target.width / imgSize.width, target.height / imgSize.height)
        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale
        let drawRect = CGRect(x: target.midX - drawW / 2,
                              y: target.midY - drawH / 2,
                              width: drawW,
                              height: drawH)
        image.draw(in: drawRect)
        ctx.restoreGState()
    }
}
