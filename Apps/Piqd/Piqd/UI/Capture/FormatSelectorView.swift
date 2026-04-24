// Apps/Piqd/Piqd/UI/Capture/FormatSelectorView.swift
// Piqd v0.3 — Layer 2 format-pill. Four segments (Still / Sequence / Clip / Dual) rendered
// as a compact horizontal pill that slides in from below the shutter. Invocation comes from
// the parent (swipe-up ≥40pt on the shutter, or long-press-from-Still). Collapse is driven
// externally too (tap outside, 3s idle, or format selection). This view is intentionally
// stateless — parent owns visibility + auto-dismiss timer.
//
// Dual segment can be disabled via `isDualAvailable` for devices without multi-cam, or for
// the `forceDualCamUnavailable` dev toggle (covers Device Verification 4.5).
//
// Accessibility (XCUITest UI1 / UI4 / UI11):
//   piqd.formatSelector — container
//   piqd.formatSelector.<format.rawValue> — per segment

import NiftyCore
import SwiftUI

struct FormatSelectorView: View {

    let current: CaptureFormat
    let isDualAvailable: Bool
    let onPick: (CaptureFormat) -> Void

    private let formats: [CaptureFormat] = [.still, .sequence, .clip, .dual]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(formats, id: \.self) { f in
                segment(for: f)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("piqd.formatSelector")
        .accessibilityValue(current.rawValue)
    }

    @ViewBuilder
    private func segment(for f: CaptureFormat) -> some View {
        let disabled = (f == .dual && !isDualAvailable)
        let selected = (f == current)
        Button {
            guard !disabled else { return }
            onPick(f)
        } label: {
            Text(label(for: f))
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(disabled ? 0.35 : 0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if selected {
                        Capsule().fill(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .allowsHitTesting(!disabled)
        .accessibilityIdentifier("piqd.formatSelector.\(f.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func label(for f: CaptureFormat) -> String {
        switch f {
        case .still:    return "Still"
        case .sequence: return "Seq"
        case .clip:     return "Clip"
        case .dual:     return "Dual"
        }
    }
}

#if DEBUG
#Preview("Format selector") {
    VStack(spacing: 20) {
        FormatSelectorView(current: .still, isDualAvailable: true) { _ in }
        FormatSelectorView(current: .clip, isDualAvailable: true) { _ in }
        FormatSelectorView(current: .sequence, isDualAvailable: false) { _ in }
    }
    .padding()
    .background(.black)
}
#endif
