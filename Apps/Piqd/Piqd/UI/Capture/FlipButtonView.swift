// Apps/Piqd/Piqd/UI/Capture/FlipButtonView.swift
// Piqd v0.4 — flip button. See PRD §5.4 / FR-SNAP-FLIP-01..05 and UIUX §2.6.
// Sits in the top-right slot of Layer 1 chrome. Hidden (not just disabled) when
// activeFormat == .dual (FR-SNAP-FLIP-04) — render-time gate lives in PiqdCaptureView.

import SwiftUI

struct FlipButtonView: View {

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(PiqdTokens.Color.snapChrome)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(.ultraThinMaterial)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("piqd.flipButton")
        .accessibilityLabel("Flip camera")
    }
}
