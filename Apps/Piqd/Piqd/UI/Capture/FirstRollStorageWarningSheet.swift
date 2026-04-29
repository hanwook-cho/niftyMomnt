// Apps/Piqd/Piqd/UI/Capture/FirstRollStorageWarningSheet.swift
// Piqd v0.6 — first-Roll storage warning. PRD §11 FR-STORAGE-08.
//
// Shown exactly once, before the user's first Roll-mode capture. Dismissible
// via "Got it" (sets the persistence flag) but NOT via swipe-down — `not
// skippable on first Roll`. After dismissal, the in-flight shutter tap is
// consumed; the user must tap shutter again to capture (chosen for clarity
// of consent semantics — the warning is informational, not a confirmation).

import SwiftUI
import NiftyCore

// MARK: - Gate (logic)

@MainActor @Observable
public final class FirstRollWarningGate {

    private static let flagKey = "piqd.firstRollWarning.shown"

    public private(set) var hasShown: Bool
    public var isPresented: Bool = false

    private let defaults: UserDefaults

    /// `forceShow` clears the persisted flag — used by `PIQD_DEV_ROLL_WARNING_RESET=1`
    /// (Task 17) to re-arm the warning for testing.
    public init(defaults: UserDefaults = .standard, forceShow: Bool = false) {
        self.defaults = defaults
        if forceShow {
            defaults.removeObject(forKey: Self.flagKey)
        }
        self.hasShown = defaults.bool(forKey: Self.flagKey)
    }

    /// Call from the shutter handler. Returns `true` if the warning was just
    /// presented (caller should consume the tap and NOT proceed to capture).
    /// Returns `false` for any non-Roll mode or when already shown.
    @discardableResult
    public func interceptShutterTap(mode: CaptureMode) -> Bool {
        guard mode == .roll, !hasShown else { return false }
        isPresented = true
        return true
    }

    /// "Got it" — persist the flag and dismiss.
    public func acknowledge() {
        defaults.set(true, forKey: Self.flagKey)
        hasShown = true
        isPresented = false
    }
}

// MARK: - Sheet

public struct FirstRollStorageWarningSheet: View {

    @Bindable var gate: FirstRollWarningGate
    /// Callback invoked when the user taps "Got it". The host view (`PiqdCaptureView`)
    /// uses this to flip its local sheet-presentation @State; the sheet's own
    /// `gate.acknowledge()` persists the FR-STORAGE-08 flag.
    public var onAcknowledge: (() -> Void)?

    public init(gate: FirstRollWarningGate, onAcknowledge: (() -> Void)? = nil) {
        self.gate = gate
        self.onAcknowledge = onAcknowledge
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(PiqdTokens.Color.rollAmber)
                Text("Heads up")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Roll Mode photos live in Piqd only — export to Photos to keep them forever.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("piqd.firstRollWarning.body")
            }

            Spacer()

            Button {
                gate.acknowledge()
                onAcknowledge?()
            } label: {
                Text("Got it")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(PiqdTokens.Color.snapYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityIdentifier("piqd.firstRollWarning.gotIt")
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08).ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .presentationDetents([.medium])
        // No root identifier — would mask the per-leaf body / gotIt IDs.
    }
}
