// Apps/Piqd/Piqd/UI/Onboarding/OnboardingCoordinator.swift
// Piqd v0.6 — drives the four-screen onboarding flow (O0–O3).
//
// Persistence:
//   - `piqd.onboarding.completed` (Bool) — true once the user finishes O3.
//   - `piqd.onboarding.lastStep`  (String) — current step rawValue, written
//     on each `advance()` so a force-quit mid-flow resumes at the same step.
//
// Cleared on first launch (no defaults entries) → starts at `.twoModes`.
// Onboarding is one-shot per install — re-show requires
// `piqd.onboarding.completed = false`, which is what
// `PIQD_DEV_ONBOARDING_RESET` (Task 17) flips.

import Foundation
import Observation

public enum OnboardingStep: String, Sendable, Equatable, CaseIterable {
    case twoModes   // O0 — split-aesthetic title screen
    case snap       // O1 — Snap teach (live viewfinder, real shutter)
    case roll       // O2 — Roll teach (grain on, "24 left" counter)
    case invite     // O3 — QR + share-link + Add friend
}

@MainActor @Observable
public final class OnboardingCoordinator {

    private static let completedKey = "piqd.onboarding.completed"
    private static let lastStepKey  = "piqd.onboarding.lastStep"

    public private(set) var step: OnboardingStep
    public private(set) var isComplete: Bool

    private let defaults: UserDefaults

    /// `forceShow` resets persisted progress before reading defaults — used by
    /// dev launch arg `PIQD_DEV_ONBOARDING_RESET=1` (wired in Task 17).
    /// `forceComplete` pre-sets the completed flag — used by `PIQD_DEV_ONBOARDING_COMPLETE=1`
    /// in XCUITest to bypass onboarding entirely without driving the screens.
    public init(defaults: UserDefaults = .standard, forceShow: Bool = false, forceComplete: Bool = false) {
        self.defaults = defaults
        if forceShow {
            defaults.removeObject(forKey: Self.completedKey)
            defaults.removeObject(forKey: Self.lastStepKey)
        }
        if forceComplete {
            defaults.set(true, forKey: Self.completedKey)
            defaults.removeObject(forKey: Self.lastStepKey)
        }
        self.isComplete = defaults.bool(forKey: Self.completedKey)
        if let raw = defaults.string(forKey: Self.lastStepKey),
           let resumed = OnboardingStep(rawValue: raw) {
            self.step = resumed
        } else {
            self.step = .twoModes
        }
    }

    /// Move forward one step. From `.invite` calls `complete()`.
    public func advance() {
        switch step {
        case .twoModes: setStep(.snap)
        case .snap:     setStep(.roll)
        case .roll:     setStep(.invite)
        case .invite:   complete()
        }
    }

    /// O0 "Skip" — jumps directly to the invite screen so the user can still
    /// generate their QR before bailing out of onboarding.
    public func skipToInvite() {
        setStep(.invite)
    }

    /// O3 "Start shooting →" — atomically marks onboarding as complete and
    /// clears the resume key so a subsequent `init` doesn't reopen mid-flow.
    public func complete() {
        defaults.set(true, forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.lastStepKey)
        isComplete = true
    }

    private func setStep(_ next: OnboardingStep) {
        step = next
        defaults.set(next.rawValue, forKey: Self.lastStepKey)
    }
}
