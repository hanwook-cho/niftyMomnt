// Apps/Piqd/Piqd/UI/Capture/ZoomPillView.swift
// Piqd v0.4 — three-segment zoom pill (0.5× / 1× / 2×). See UIUX §2.4 / FR-SNAP-ZOOM-02.
// Front camera renders the single "1×" segment only (FR-SNAP-ZOOM-04).

import NiftyCore
import SwiftUI

struct ZoomPillView: View {

    let levels: [ZoomLevel]
    let current: ZoomLevel
    let onSelect: (ZoomLevel) -> Void

    var body: some View {
        // No `.accessibilityIdentifier` on the HStack: SwiftUI propagates a parent
        // identifier to every child Button, masking the per-segment IDs that XCUITest
        // queries. Identifiers live on each Button instead.
        HStack(spacing: 0) {
            ForEach(levels, id: \.self) { level in
                Button {
                    onSelect(level)
                } label: {
                    Text(label(for: level))
                        .font(.caption)
                        .fontWeight(level == current ? .semibold : .regular)
                        .foregroundStyle(level == current
                                         ? Color(red: 0x1A / 255.0, green: 0x12 / 255.0, blue: 0x08 / 255.0)
                                         : PiqdTokens.Color.snapChrome)
                        .padding(.horizontal, PiqdTokens.Spacing.sm)
                        .padding(.vertical, PiqdTokens.Spacing.xs)
                        .frame(minWidth: 36)
                        .background(
                            RoundedRectangle(cornerRadius: PiqdTokens.Shape.pillRadius)
                                .fill(level == current ? PiqdTokens.Color.snapYellow : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("piqd.zoomPill.\(level.rawValue)")
                .accessibilityValue(level == current ? "active" : "inactive")
            }
        }
        .padding(.horizontal, PiqdTokens.Spacing.xs)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: PiqdTokens.Shape.pillRadius)
                .fill(.ultraThinMaterial)
        )
    }

    private func label(for level: ZoomLevel) -> String {
        switch level {
        case .ultraWide: return "0.5×"
        case .wide:      return "1×"
        case .telephoto: return "2×"
        }
    }
}
