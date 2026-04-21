// Apps/Piqd/Piqd/UI/Capture/SafeRenderBorderView.swift
// Piqd v0.3 — 9:16 crop-guide overlay. 1pt snapChrome border at 15% opacity, inscribed in
// the given canvas so it always matches what will land on disk for Sequence / Clip / Dual.
// Motion-based auto-retreat (CMMotionManager >2°/s dissolves the border) is deferred to
// v0.4 per §3; this view is a pure visual overlay for v0.3.
//
// XCUITest attaches `piqd.safeRenderBorder` as the existence probe (UI15).

import SwiftUI

struct SafeRenderBorderView: View {

    /// Width-to-height ratio of the crop guide. Defaults to 9:16 (portrait Snap).
    let ratio: CGFloat

    init(ratio: CGFloat = 9.0 / 16.0) {
        self.ratio = ratio
    }

    var body: some View {
        GeometryReader { geo in
            let rect = inscribedRect(in: geo.size, ratio: ratio)
            Rectangle()
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
        .accessibilityElement()
        .accessibilityIdentifier("piqd.safeRenderBorder")
    }

    private func inscribedRect(in size: CGSize, ratio: CGFloat) -> CGRect {
        let canvasRatio = size.width / size.height
        if ratio >= canvasRatio {
            let h = size.width / ratio
            let y = (size.height - h) / 2
            return CGRect(x: 0, y: y, width: size.width, height: h)
        } else {
            let w = size.height * ratio
            let x = (size.width - w) / 2
            return CGRect(x: x, y: 0, width: w, height: size.height)
        }
    }
}

#if DEBUG
#Preview("Safe render border") {
    ZStack {
        Color.gray
        SafeRenderBorderView()
    }
}
#endif
