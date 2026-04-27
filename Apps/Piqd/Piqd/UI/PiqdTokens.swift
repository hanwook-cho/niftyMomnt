// Apps/Piqd/Piqd/UI/PiqdTokens.swift
// Piqd v0.4 — minimal design-token surface introduced for Layer 1 chrome work.
// See piqd_UIUX_Spec_v1.0.md §1 (PiqdTokens.Color / Spacing). Earlier versions inlined
// these values per-view; v0.4 lifts them so the new chrome views (zoom pill, ratio pill,
// flip button, level, vibe glyph) share one source of truth.

import SwiftUI
import UIKit

enum PiqdTokens {

    enum Color {
        /// Signal yellow — Snap accent. Active zoom segment, mode pill, sequence ring.
        static let snapYellow = SwiftUI.Color(red: 0xF5 / 255.0, green: 0xC4 / 255.0, blue: 0x20 / 255.0)
        /// White at 92% — pill backgrounds and shutter ring.
        static let snapChrome = SwiftUI.Color.white.opacity(0.92)
        /// White at 55% — secondary chrome elements.
        static let snapChromeSubtle = SwiftUI.Color.white.opacity(0.55)
        /// White at 70% — invisible level line.
        static let levelLine = SwiftUI.Color.white.opacity(0.70)
        /// Drafts tray amber — timer label at <1h remaining (UIUX §2.14, FR-SNAP-DRAFT-05).
        static let rollAmber = SwiftUI.Color(red: 0xC9 / 255.0, green: 0x7B / 255.0, blue: 0x2A / 255.0)
        /// Drafts tray red / Snap-record red — timer at <15min, urgent badge tint, "send →" red text.
        static let recordRed = SwiftUI.Color(red: 0xE5 / 255.0, green: 0x37 / 255.0, blue: 0x2A / 255.0)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }

    enum Shape {
        /// Mode indicator, zoom pill, ratio pill, badges. UIUX §1.
        static let pillRadius: CGFloat = 14
        /// Drafts tray thumbnails. UIUX §1.5.
        static let thumbRadius: CGFloat = 8
    }

    enum Animation {
        /// Layer 1 entrance fade.
        static let layerRevealMs: Int = 220
        /// Layer 1 exit fade.
        static let layerRetreatMs: Int = 150
        /// Invisible level appear/disappear fade.
        static let levelFadeMs: Int = 150
    }

    enum Layer {
        /// Idle interval before Layer 1 auto-retreats. Plan §1.3.
        static let idleRetreatSeconds: TimeInterval = 3.0
        /// XCUITest accelerated value (UI_TEST_MODE). Set to 1.5s to outlast
        /// `XCTNSPredicateExpectation`'s default ~1s polling cadence — at 0.3s the
        /// reveal→retreat transition happens between polls and tests intermittently
        /// missed the revealed state entirely.
        static let idleRetreatSecondsUITest: TimeInterval = 1.5
    }

    enum Layout {
        /// Reads the system safe-area top inset from the active UIWindowScene at runtime
        /// — model-agnostic. Fallback `52` matches what `topHUD` has hardcoded since v0.2
        /// (covers Dynamic Island on iPhone 14 Pro+). Not a constant; recompute on every
        /// access in case the user rotates or the active scene changes.
        @MainActor
        static var statusBarOffset: CGFloat {
            let scenes = UIApplication.shared.connectedScenes
            for case let scene as UIWindowScene in scenes where scene.activationState == .foregroundActive {
                if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                    return window.safeAreaInsets.top + 8
                }
            }
            return 52
        }
        /// Bottom padding under the shutter button. Mirrors `PiqdCaptureView.shutterControl`.
        static let shutterBottomPadding: CGFloat = 48
        /// Actual shutter outer diameter from `ShutterButtonView` (not the spec 58pt — the
        /// shipped impl uses 80pt for a more pressable target).
        static let shutterDiameter: CGFloat = 80
        /// Gap between shutter top edge and the zoom-pill bottom edge — matches iPhone
        /// Camera app placement: pill floats just above the shutter row.
        static let zoomPillAboveShutter: CGFloat = 16
        /// Distance from safe-area bottom to the zoom-pill bottom edge. Shares baseline
        /// with `shutterControl` (Layer1ChromeView no longer ignores safe area).
        static var zoomPillBottomPadding: CGFloat {
            shutterBottomPadding + shutterDiameter + zoomPillAboveShutter
        }
    }
}
