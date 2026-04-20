// Apps/Piqd/Piqd/UI/Debug/PiqdDevSettingsView.swift
// Piqd v0.2 — hidden dev knobs UI. Reached via 5-tap on the mode pill or via the debug
// menu. All edits write through DevSettingsStore so they persist for the next launch.

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
