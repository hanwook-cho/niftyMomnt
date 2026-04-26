// Apps/Piqd/Piqd/UI/Capture/Layer1ChromeView.swift
// Piqd v0.4 — Layer 1 chrome shell. Composes the per-feature views (zoom pill, aspect
// ratio pill, flip button, drafts badge slot) and drives the 220ms-in / 150ms-out fade
// off `LayerStore.state`. The invisible level + subject guidance + vibe glyph are NOT
// in this container — they have independent visibility rules and live as siblings on
// the capture view.
//
// In v0.4 this view ships with empty slots; child views land in Tasks 7 / 9 / 10.

import SwiftUI

struct Layer1ChromeView<TopRight: View, ZoomSlot: View, RatioSlot: View, BadgeSlot: View>: View {

    let isRevealed: Bool
    @ViewBuilder var topRight: () -> TopRight
    @ViewBuilder var zoom: () -> ZoomSlot
    @ViewBuilder var ratio: () -> RatioSlot
    @ViewBuilder var draftsBadge: () -> BadgeSlot

    var body: some View {
        // Parent ZStack uses `Color.black.ignoresSafeArea()` which makes safe-area
        // propagation unreliable. Use the same hardcoded top offset as `topHUD`
        // (`.padding(.top, 52)`) for consistency with the rest of PiqdCaptureView.
        ZStack {
            // Top-right slot — flip button. Sits below status bar / Dynamic Island.
            VStack {
                HStack {
                    Spacer()
                    topRight()
                        .allowsHitTesting(isRevealed)
                }
                Spacer()
            }
            .padding(.top, PiqdTokens.Layout.statusBarOffset)
            .padding(.trailing, PiqdTokens.Spacing.md)

            // Top-left slot — drafts badge (currently empty in v0.4).
            VStack {
                HStack {
                    draftsBadge()
                        .allowsHitTesting(isRevealed)
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, PiqdTokens.Layout.statusBarOffset)
            .padding(.leading, PiqdTokens.Spacing.md)

            // Bottom-center slot — zoom pill + ratio pill, just above the shutter.
            VStack {
                Spacer()
                HStack(spacing: PiqdTokens.Spacing.sm) {
                    zoom()
                    ratio()
                }
                .allowsHitTesting(isRevealed)
            }
            .padding(.bottom, PiqdTokens.Layout.zoomPillBottomPadding)
        }
        .opacity(isRevealed ? 1 : 0)
        .animation(
            .easeOut(duration: Double(isRevealed
                                      ? PiqdTokens.Animation.layerRevealMs
                                      : PiqdTokens.Animation.layerRetreatMs) / 1000.0),
            value: isRevealed
        )
        // Container itself never blocks taps in empty space — only the leaf controls
        // are hit-testable, and only while revealed. Required so the chrome layer can
        // sit above the shutter without swallowing shutter taps in the empty space.
        //
        // No `.accessibilityIdentifier` on the container: SwiftUI propagates a parent
        // identifier to every descendant button, which would mask the per-leaf IDs
        // (`piqd.flipButton`, `piqd.zoomPill.wide`, `piqd.ratioPill`) that XCUITest
        // relies on.
    }
}
