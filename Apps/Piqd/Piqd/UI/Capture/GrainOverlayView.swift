// Apps/Piqd/Piqd/UI/Capture/GrainOverlayView.swift
// Piqd v0.2 — lightweight viewfinder grain overlay for Roll mode. Drawn via SwiftUI's
// TimelineView + Canvas at ~30fps. Renders ~1500 small dots per frame at varying alpha;
// cheap enough to keep the preview smooth without bringing in a real CIFilter / Metal
// pipeline. v0.9 will replace this with the proper film-grain compositor.

import SwiftUI

struct GrainOverlayView: View {

    var intensity: Double = 0.35      // 0…1 — alpha multiplier for each grain dot
    var density: Int = 2200           // particles per frame
    var fps: Double = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / fps)) { context in
            Canvas { ctx, size in
                let frameSeed = UInt64(context.date.timeIntervalSinceReferenceDate * fps)
                var rng = SplitMix64(seed: frameSeed)
                let baseAlpha = max(0, min(1, intensity))
                for _ in 0..<density {
                    let x = Double(rng.nextUnitFloat()) * size.width
                    let y = Double(rng.nextUnitFloat()) * size.height
                    let a = baseAlpha * (0.4 + Double(rng.nextUnitFloat()) * 0.6)
                    // Mix white + black dots so grain reads on both bright and dark
                    // areas of the camera feed. Plain alpha — no blendMode, since the
                    // underlying CameraPreviewView is a UIView and blend modes don't
                    // cross SwiftUI/UIKit compositing boundaries.
                    let isLight = (rng.next() & 1) == 0
                    let color: Color = isLight ? .white : .black
                    let size: CGFloat = 1.4
                    let dot = Path(ellipseIn: CGRect(x: x, y: y, width: size, height: size))
                    ctx.fill(dot, with: .color(color.opacity(a)))
                }
            }
        }
        .allowsHitTesting(false)
        // Findable by XCUITest (UI7 asserts presence in Roll, absence in Snap).
        .accessibilityElement()
        .accessibilityIdentifier("piqd-grain-overlay")
    }
}

/// Tiny deterministic PRNG so each frame's noise pattern is fast and stable.
private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { self.state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnitFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}
