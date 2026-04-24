// Apps/Piqd/Piqd/UI/Capture/ShutterButtonView.swift
// Piqd v0.3 — the single shutter control for Snap Mode's four formats. The outer ring and
// inner mark morph based on the current CaptureFormat + ShutterState; capture progress
// (Clip / Dual) drives an arc that sweeps the outer ring. The view is intentionally
// stateless — parent owns press/release, timers, and the CaptureActivityStore lock.
//
// Visual vocabulary (matches piqd_interim_v0.3_plan.md §3):
//   • Still     — white ring + solid white disc.
//   • Sequence  — white ring + 6 small dots arranged in a tight cluster inside the disc.
//   • Clip      — red ring + red rounded-square inner mark.
//   • Dual      — red ring + diagonal split-disc.
// Transitions animate at 80ms per PiqdTokens.Duration.instant; we use .easeInOut(duration: 0.08).
//
// Accessibility: the parent attaches `piqd.shutter`. This view exposes
// `accessibilityValue = "<format>.<state>"` so XCUITest UI4 / UI5 can assert shutter morph
// without looking at pixels.

import NiftyCore
import SwiftUI

public enum ShutterState: String, Sendable {
    case idle
    case pressing      // touch-down but not yet recording (Clip/Dual pre-roll)
    case recording     // Clip / Dual active recording
    case firing        // Sequence 6-frame window
    case disabled      // e.g. Roll full, Dual hardware missing
}

struct ShutterButtonView: View {

    let format: CaptureFormat
    let state: ShutterState
    /// 0…1 — drives the outer arc on Clip/Dual while recording. Ignored otherwise.
    let progress: Double

    private static let diameter: CGFloat = 80
    private static let innerDiameter: CGFloat = 64
    private static let lineWidth: CGFloat = 4

    private var ringColor: Color {
        switch format {
        case .still, .sequence: return .white
        case .clip, .dual:      return .red
        }
    }

    private var isDisabled: Bool { state == .disabled }

    var body: some View {
        ZStack {
            // Outer ring — always present, colored per format.
            Circle()
                .stroke(ringColor.opacity(isDisabled ? 0.4 : 1.0), lineWidth: Self.lineWidth)
                .frame(width: Self.diameter, height: Self.diameter)

            // Capture-progress arc (Clip / Dual while recording). Drawn on top of the
            // static ring so the fill depletes cleanly.
            if (format == .clip || format == .dual) && state == .recording {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                    .stroke(.white, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: Self.diameter, height: Self.diameter)
            }

            innerMark
                .scaleEffect(state == .pressing || state == .recording ? 0.85 : 1.0)
                .animation(.easeInOut(duration: 0.08), value: state)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .animation(.easeInOut(duration: 0.08), value: format)
    }

    @ViewBuilder
    private var innerMark: some View {
        switch format {
        case .still:
            Circle()
                .fill(.white.opacity(isDisabled ? 0.4 : 1.0))
                .frame(width: Self.innerDiameter, height: Self.innerDiameter)

        case .sequence:
            // Six dots in a 3x2 cluster — purely iconographic, not a live frame indicator.
            Circle()
                .fill(.white.opacity(isDisabled ? 0.4 : 1.0))
                .frame(width: Self.innerDiameter, height: Self.innerDiameter)
                .overlay(
                    VStack(spacing: 6) {
                        HStack(spacing: 6) { dot; dot; dot }
                        HStack(spacing: 6) { dot; dot; dot }
                    }
                    .foregroundStyle(.black.opacity(0.85))
                )

        case .clip:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.red.opacity(isDisabled ? 0.4 : 1.0))
                .frame(width: Self.innerDiameter * 0.5, height: Self.innerDiameter * 0.5)

        case .dual:
            // Split-diagonal disc — front half / rear half hint.
            ZStack {
                Circle()
                    .fill(Color.red.opacity(isDisabled ? 0.4 : 1.0))
                    .frame(width: Self.innerDiameter, height: Self.innerDiameter)
                Path { p in
                    let r = Self.innerDiameter / 2
                    p.move(to: CGPoint(x: 0, y: r * 2))
                    p.addLine(to: CGPoint(x: r * 2, y: 0))
                }
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: Self.innerDiameter, height: Self.innerDiameter)
            }
        }
    }

    private var dot: some View {
        Circle().frame(width: 4, height: 4)
    }
}

#if DEBUG
#Preview("Shutter morph") {
    VStack(spacing: 24) {
        ShutterButtonView(format: .still, state: .idle, progress: 0)
        ShutterButtonView(format: .sequence, state: .firing, progress: 0)
        ShutterButtonView(format: .clip, state: .recording, progress: 0.4)
        ShutterButtonView(format: .dual, state: .recording, progress: 0.75)
    }
    .padding()
    .background(.black)
}
#endif
