// Apps/Piqd/Piqd/UI/Debug/PiqdDevSettingsView.swift
// Piqd v0.2 — hidden dev knobs UI. Reached via 5-tap on the mode pill or via the debug
// menu. All edits write through DevSettingsStore so they persist for the next launch.

import NiftyCore
import SwiftUI

struct PiqdDevSettingsView: View {

    @Bindable var store: DevSettingsStore
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Roll") {
                    Stepper(value: $store.rollDailyLimit, in: 1...240, step: 1) {
                        HStack {
                            Text("Daily limit")
                            Spacer()
                            Text("\(store.rollDailyLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("piqd-dev-roll-limit")
                }

                Section("Viewfinder") {
                    Toggle("Grain overlay", isOn: $store.grainOverlayEnabled)
                        .accessibilityIdentifier("piqd-dev-grain-toggle")
                    Toggle("Long-press haptic", isOn: $store.hapticEnabled)
                        .accessibilityIdentifier("piqd-dev-haptic-toggle")
                    HStack {
                        Text("Long-hold")
                        Spacer()
                        Text("\(store.longHoldDurationSeconds, specifier: "%.2f")s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.longHoldDurationSeconds, in: 0.05...2.0, step: 0.05)
                        .accessibilityIdentifier("piqd-dev-longhold-slider")
                }

                Section("Snap — Clip") {
                    // Clip ceiling is one of three discrete values (5 / 10 / 15s), per the
                    // v0.3 plan. We use a Picker bound to an IntEnum-like set to enforce it.
                    Picker("Ceiling", selection: $store.clipMaxDurationSeconds) {
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("15s").tag(15)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("piqd-dev-clip-ceiling")
                }

                Section("Snap — Sequence") {
                    HStack {
                        Text("Interval")
                        Spacer()
                        Text("\(store.sequenceIntervalMs) ms")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(store.sequenceIntervalMs) },
                        set: { store.sequenceIntervalMs = Int($0) }
                    ), in: 100...1000, step: 50)
                        .accessibilityIdentifier("piqd-dev-sequence-interval")

                    Stepper(value: $store.sequenceFrameCount, in: 3...12, step: 1) {
                        HStack {
                            Text("Frame count")
                            Spacer()
                            Text("\(store.sequenceFrameCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("piqd-dev-sequence-frame-count")

                    Toggle("Force assembly failure", isOn: $store.forceSequenceAssemblyFailure)
                        .accessibilityIdentifier("piqd-dev-force-asm-fail")
                }

                Section("Snap — Dual") {
                    Toggle("Force dual-cam unavailable", isOn: $store.forceDualCamUnavailable)
                        .accessibilityIdentifier("piqd-dev-force-dual-unavail")
                    Picker("Layout", selection: $store.dualLayout) {
                        Text("PIP").tag(DualLayout.pip)
                        Text("Top/Bottom").tag(DualLayout.topBottom)
                        Text("Side-by-Side").tag(DualLayout.sideBySide)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("piqd-dev-dual-layout")
                }

                Section("Pre-shutter chrome (v0.4)") {
                    Toggle("Backlight EV bias (+0.5)", isOn: $store.backlightCorrectionEnabled)
                        .accessibilityIdentifier("piqd-dev-backlight-toggle")
                    Toggle("Invisible level", isOn: $store.levelIndicatorEnabled)
                        .accessibilityIdentifier("piqd-dev-level-toggle")
                    Toggle("Subject guidance pill", isOn: $store.subjectGuidanceEnabled)
                        .accessibilityIdentifier("piqd-dev-guidance-toggle")
                    Toggle("Vibe hint glyph", isOn: $store.vibeHintEnabled)
                        .accessibilityIdentifier("piqd-dev-vibe-toggle")
                }

                Section {
                    Button("Reset to defaults", role: .destructive) {
                        store.resetDefaults()
                    }
                    .accessibilityIdentifier("piqd-dev-reset")
                }

                Section("Notes") {
                    Text("These knobs are for testing only. Settings persist across launches.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("piqd-dev-settings")
            .navigationTitle("Piqd Dev Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                        .accessibilityIdentifier("piqd-dev-done")
                }
            }
        }
    }
}
