// Apps/niftyMomnt/UI/DesignSystem.swift
// Design tokens, typography, animation constants, and vibe presets for the UI layer.

import SwiftUI

// MARK: - Color Tokens

extension Color {
    // Brand — v1.7: deepened #5B4FCF → #6B4EFF for stronger contrast on dark surfaces
    static let niftyBrand         = Color(hex: "#6B4EFF")
    static let niftyBrandSubtle   = Color(hex: "#EAE8FC")
    static let niftyBrandDark     = Color(hex: "#3C3489")

    // Capture surface (always dark)
    static let niftyCaptureBg     = Color(hex: "#0A0A0A")

    // Film Archive background — always dark editorial (#0F0D0B), not system-adaptive
    static let niftyFilmBg        = Color(hex: "#0F0D0B")

    // Accent — amber
    static let niftyAmber         = Color(hex: "#BA7517")
    static let niftyAmberVivid    = Color(hex: "#E8A020") // Amalfi accent, film strip counter
    static let niftyAmberLight    = Color(hex: "#FAEEDA")

    // Accent — lavender (v1.7: replaces cyan. Tokyo Neon, Film tab active, Share glyphs)
    static let niftyLavender      = Color(hex: "#C4B5FD")

    // Adaptive surface
    static let niftySurfaceRaised = Color(hex: "#F8F7F4")
    static let niftyBorderColor   = Color(hex: "#D3D1C7")

    // Text
    static let niftyTextPrimary   = Color(hex: "#1A1A1A")
    static let niftyTextSecondary = Color(hex: "#5F5E5A")
    static let niftyTextTertiary  = Color(hex: "#888780")

    // Hex initializer (presentation layer only)
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hex: UInt64 = 0
        scanner.scanHexInt64(&hex)
        let r = Double((hex & 0xFF0000) >> 16) / 255
        let g = Double((hex & 0x00FF00) >> 8) / 255
        let b = Double(hex & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Typography

extension Font {
    /// 28pt / 700 — Moment label on hero card, onboarding headings
    static let niftyDisplay = Font.system(size: 28, weight: .bold)
    /// 20pt / 600 — Section headings, Nudge card question
    static let niftyTitle   = Font.system(size: 20, weight: .semibold)
    /// 15pt / 400 — Body text, card descriptions
    static let niftyBody    = Font.system(size: 15, weight: .regular)
    /// 12pt / 400 — Vibe tags, timestamps, metadata lines
    static let niftyCaption = Font.system(size: 12, weight: .regular)
    /// 11pt / 600 — Buttons, badges, mode labels
    static let niftyLabel   = Font.system(size: 11, weight: .semibold)
    /// 28pt / 600 — Mode ghost label (E C H O). Use .tracking(24) at call site.
    static let niftyGhost   = Font.system(size: 28, weight: .semibold)
}

// MARK: - Animation Constants

extension Animation {
    /// Standard spring for all positional animations (§2.5)
    static let niftySpring        = Animation.spring(response: 0.35, dampingFraction: 0.72)
    /// Ghost label: exactly 500ms easeOut
    static let niftyGhostFade     = Animation.easeOut(duration: 0.5)
    /// Preset crossfade: 120ms
    static let niftyPresetSwitch  = Animation.easeOut(duration: 0.12)
    /// Screen transitions: 280–350ms
    static let niftyScreen        = Animation.spring(response: 0.32, dampingFraction: 0.80)
}

// MARK: - Spacing (4pt base grid)

enum NiftySpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

enum NiftyRadius {
    static let card:    CGFloat = 12
    static let chip:    CGFloat = 8
    static let overlay: CGFloat = 20
}

// MARK: - Vibe Presets (UI layer)
// Maps to NiftyCore.VibePreset but carries a resolved SwiftUI Color.

struct VibePresetUI: Identifiable, Equatable {
    let id: Int
    let name: String          // Display name in ALLCAPS
    let accentColor: Color

    static let defaults: [VibePresetUI] = [
        VibePresetUI(id: 0, name: "FILM ROLL",  accentColor: Color(hex: "#C8A882")),
        VibePresetUI(id: 1, name: "AMALFI",     accentColor: Color(hex: "#E8A020")),
        VibePresetUI(id: 2, name: "TOKYO NEON", accentColor: Color(hex: "#C4B5FD")), // v1.7: #00E5CC → #C4B5FD (soft lavender)
        VibePresetUI(id: 3, name: "NORDIC",     accentColor: Color(hex: "#8EB4D4")),
        VibePresetUI(id: 4, name: "DISPOSABLE", accentColor: Color(hex: "#FF6B6B")),
    ]
}
