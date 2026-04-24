// Apps/Piqd/Piqd/UI/Capture/ModePill.swift
// Piqd v0.2 — always-visible mode pill. Tapping registers with ModeStore (5-tap reveals
// the dev menu). Long-press past `longHoldDurationSeconds` triggers the confirmation
// sheet for switching between Snap ↔ Roll. A progress ring fills during the hold and
// a soft haptic pulses at completion.

import SwiftUI
import NiftyCore

#if canImport(UIKit)
import UIKit
#endif

struct ModePill: View {

    let mode: CaptureMode
    let holdDuration: Double
    let hapticEnabled: Bool
    /// Piqd v0.3 — while a Sequence/Clip/Dual capture is running, the pill dims to 40%,
    /// rejects hit-testing, and cancels any in-flight long-hold timer (FR-MODE-09). Driven
    /// by `CaptureActivityStore.isCapturing` from the parent.
    let isLocked: Bool
    let onTap: () -> Void
    let onLongHoldTriggered: () -> Void

    @State private var holdProgress: Double = 0
    @State private var holdTask: Task<Void, Never>?
    @State private var pressStart: Date?
    @State private var didFireLongHold = false

    private var label: String {
        switch mode {
        case .snap: return "SNAP"
        case .roll: return "ROLL"
        default:    return mode.rawValue.uppercased()
        }
    }

    private var accent: Color {
        switch mode {
        case .snap: return .yellow
        case .roll: return Color(red: 0.95, green: 0.75, blue: 0.35) // warm amber for film
        default:    return .white
        }
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.55))
                .overlay(Capsule().stroke(accent.opacity(0.6), lineWidth: 1.5))
                .frame(width: 92, height: 32)

            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .tracking(1.2)

            // Progress ring fills clockwise during long-press.
            if holdProgress > 0 {
                Capsule()
                    .trim(from: 0, to: holdProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 92, height: 32)
                    .animation(.linear(duration: 0.05), value: holdProgress)
            }
        }
        .opacity(isLocked ? 0.4 : 1.0)
        .allowsHitTesting(!isLocked)
        .animation(.easeInOut(duration: 0.12), value: isLocked)
        .onChange(of: isLocked) { _, locked in
            // Cancel any in-flight long-hold timer the moment a capture starts.
            if locked { cancelInFlightHold() }
        }
        .contentShape(Capsule())
        // Use DragGesture(minimumDistance:0) over .onLongPressGesture so XCUITest's
        // press(forDuration:) synthesis reliably fires onChanged (touch-down) and
        // onEnded (release). We schedule our own completion timer from onChanged.
        // highPriorityGesture ensures the first touch-down on the pill is claimed by
        // this DragGesture instead of losing the hit-test to an ancestor (the camera
        // preview's UIView) — otherwise the first press falls through and the sheet
        // only appears on the second attempt.
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if pressStart == nil { beginPress() }
                }
                .onEnded { _ in endPress() }
        )
        // Collapse internal Text/ZStack into a single a11y element on the gesture-bearing
        // view, so XCUITest's press(forDuration:) routes through the long-press gesture.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("piqd-mode-pill")
        .accessibilityLabel("Mode: \(label). Long-press to change.")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isLocked ? "locked" : "")
    }

    /// Cancels the outstanding long-hold deadline task and winds back the ring without
    /// firing `onLongHoldTriggered`. Used when the parent tells us we're locked mid-hold.
    private func cancelInFlightHold() {
        holdTask?.cancel()
        holdTask = nil
        pressStart = nil
        didFireLongHold = false
        withAnimation(.easeOut(duration: 0.15)) { holdProgress = 0 }
    }

    private func beginPress() {
        pressStart = Date()
        didFireLongHold = false
        holdProgress = 0
        withAnimation(.linear(duration: holdDuration)) { holdProgress = 1.0 }
        holdTask?.cancel()
        let duration = holdDuration
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            if pressStart != nil && !didFireLongHold {
                completeHold()
            }
        }
    }

    /// Called by `.onLongPressGesture(perform:)` when the press reaches `holdDuration`.
    private func completeHold() {
        didFireLongHold = true
        #if canImport(UIKit)
        if hapticEnabled {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        #endif
        // Presenting the mode sheet steals touch tracking, so .onEnded won't fire for
        // this drag. Reset gesture state here — otherwise pressStart stays non-nil and
        // the *next* touch-down (in the new mode) is ignored by the `pressStart == nil`
        // guard, requiring a stray tap to clear it.
        pressStart = nil
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.15)) { holdProgress = 0 }
        onLongHoldTriggered()
    }

    private func endPress() {
        let elapsed = pressStart.map { Date().timeIntervalSince($0) } ?? 0
        pressStart = nil
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.15)) { holdProgress = 0 }
        if !didFireLongHold && elapsed < holdDuration {
            onTap()
        }
        didFireLongHold = false
    }
}
