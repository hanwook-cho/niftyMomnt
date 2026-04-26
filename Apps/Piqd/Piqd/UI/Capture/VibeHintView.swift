// Apps/Piqd/Piqd/UI/Capture/VibeHintView.swift
// Piqd v0.4 — vibe-hint glyph (UIUX §2.12). 16pt three-bar mark that pulses scale
// 1.0 → 1.2 → 1.0 over 600ms × 3 iterations on `.social`. Hidden on `.quiet` /
// `.neutral`.
//
// Classifier is injected via the `VibeClassifying` protocol. v0.4 ships
// `StubVibeClassifier` (always `.quiet`), so the glyph stays hidden unless dev
// fixtures `emit(.social)`. Real CoreML classifier lands in a later version.

import NiftyCore
import SwiftUI

struct VibeHintView: View {

    let classifier: any VibeClassifying

    @State private var current: VibeSignal = .quiet
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Group {
            if current == .social {
                bars
                    .scaleEffect(pulseScale)
                    .accessibilityIdentifier("piqd.vibeHint")
                    .onAppear {
                        // 600ms × 3 iterations, then settles. SwiftUI repeats with
                        // `repeatCount(3, autoreverses: true)` give us the 1→1.2→1 shape.
                        withAnimation(
                            .easeInOut(duration: 0.30)
                                .repeatCount(6, autoreverses: true)
                        ) {
                            pulseScale = 1.2
                        }
                    }
                    .onDisappear {
                        pulseScale = 1.0
                    }
            }
        }
        .frame(width: 16, height: 16)
        .task {
            for await signal in classifier.signals {
                current = signal
            }
        }
    }

    /// 16pt three-bar mark — short / tall / medium capsules in the snap-yellow color.
    private var bars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Capsule().frame(width: 3, height: 8)
            Capsule().frame(width: 3, height: 14)
            Capsule().frame(width: 3, height: 11)
        }
        .foregroundStyle(PiqdTokens.Color.snapYellow)
    }
}
