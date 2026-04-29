// Apps/Piqd/PiqdTests/QRCodeImageRendererTests.swift
// Piqd v0.6 — `QRCodeImageRenderer` deterministic-output checks. Pure logic
// tests; no app launch required. Device smoke testing for `QRScannerView`
// is a manual checklist row (§7.1) — `AVCaptureSession` cannot run under
// `XCTest` without camera access.

import XCTest
import UIKit
@testable import Piqd

final class QRCodeImageRendererTests: XCTestCase {

    func test_renderURL_returnsNonNilImage() {
        let url = URL(string: "piqd://invite/AAA")!
        let img = QRCodeImageRenderer.image(for: url, size: 200, scale: 2)
        XCTAssertNotNil(img)
    }

    func test_renderImage_pixelSizeMatchesRequest() throws {
        let img = try XCTUnwrap(
            QRCodeImageRenderer.image(for: "piqd://invite/AAA", size: 200, scale: 2)
        )
        // CGImage is in pixels; UIImage.size is in points. Pixel dimension
        // should be size * scale = 400 (CIQRCodeGenerator output is square).
        XCTAssertEqual(img.cgImage?.width, 400)
        XCTAssertEqual(img.cgImage?.height, 400)
    }

    func test_render_isDeterministic_sameInputProducesIdenticalBytes() throws {
        let a = try XCTUnwrap(QRCodeImageRenderer.image(for: "piqd://invite/AAA", size: 100, scale: 1))
        let b = try XCTUnwrap(QRCodeImageRenderer.image(for: "piqd://invite/AAA", size: 100, scale: 1))
        XCTAssertEqual(a.pngData(), b.pngData())
    }

    func test_render_differentInputs_produceDifferentImages() throws {
        let a = try XCTUnwrap(QRCodeImageRenderer.image(for: "piqd://invite/AAA", size: 100, scale: 1))
        let b = try XCTUnwrap(QRCodeImageRenderer.image(for: "piqd://invite/BBB", size: 100, scale: 1))
        XCTAssertNotEqual(a.pngData(), b.pngData())
    }
}
