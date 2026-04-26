// Apps/Piqd/Piqd/UI/Capture/LevelIndicatorView.swift
// Piqd v0.4 — the "invisible level". Subscribes to `MotionMonitor.samples`, fades a
// 40%-width 1pt horizontal line in `levelLine` color when |roll| > 3°, fades out
// when the user returns to level. 150ms fade. Mode-agnostic — present in both Snap
// and Roll per UIUX §2.10. See piqd_interim_v0.4_plan.md §3 (Invisible level).
//
// The view doesn't drive recording state — `PiqdCaptureView` toggles
// `monitor.setRecording(_:)` directly when capture begins/ends.

import NiftyCore
import NiftyData
import SwiftUI

struct LevelIndicatorView: View {

    let monitor: MotionMonitor

    /// Threshold above which the line is visible. Spec: 3°. Below, the line fades out.
    private static let thresholdDegrees: Double = 3.0

    @State private var rollDegrees: Double = 0
    @State private var isVisible: Bool = false

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(PiqdTokens.Color.levelLine)
                .frame(width: geo.size.width * 0.40, height: 1)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .opacity(isVisible ? 1 : 0)
                .animation(.easeInOut(duration: Double(PiqdTokens.Animation.levelFadeMs) / 1000.0),
                           value: isVisible)
                .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
        .task {
            for await sample in monitor.samples {
                rollDegrees = sample.rollDegrees
                let shouldShow = abs(sample.rollDegrees) > Self.thresholdDegrees
                if shouldShow != isVisible {
                    isVisible = shouldShow
                }
            }
        }
    }
}
