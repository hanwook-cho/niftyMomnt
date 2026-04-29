// Apps/Piqd/Piqd/UI/Settings/PiqdSettingsView.swift
// Piqd v0.6 — Settings root. UIUX §8 sections:
//
//   CIRCLE     (interactive — Task 16 wires My friends / Add friend / My invite QR)
//   CAPTURE    (read-only display — toggles wire in v0.9)
//   ROLL MODE  (read-only display — Unlock time configurable v1.1; Film sim v0.9)
//   SNAP MODE  (read-only display — toggles surface in DevSettings until v0.9)
//   ABOUT      (read-only — version + bundle info)
//
// Per UIUX §8: read-only rows render the current value with no chevron / no
// disclosure. Toggle rows that are actually wired (CIRCLE) get NavigationLinks
// in Task 16.

import SwiftUI

struct PiqdSettingsView: View {

    let container: PiqdAppContainer

    var body: some View {
        Form {
            circleSection
            captureSection
            rollModeSection
            snapModeSection
            aboutSection
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("piqd.settings.root")
    }

    // MARK: - CIRCLE  (Task 16 — wired via CircleSettingsView)

    private var circleSection: some View {
        CircleSettingsView(container: container)
    }

    // MARK: - CAPTURE

    private var captureSection: some View {
        Section("Capture") {
            row(title: "Default Snap format", value: "Still")
            row(title: "Default Roll format", value: "Still")
            row(title: "Clip max duration",   value: "10s")
            row(title: "Sequence interval",   value: "333 ms")
        }
    }

    private var rollModeSection: some View {
        Section("Roll Mode") {
            row(title: "Unlock time",      value: "9:00 PM")
            row(title: "Daily shot limit", value: "24")
            row(title: "Film simulation",  value: "kodakWarm")
        }
    }

    private var snapModeSection: some View {
        Section("Snap Mode") {
            row(title: "Subject guidance", value: dev(\.subjectGuidanceEnabled))
            row(title: "Vibe hint",        value: dev(\.vibeHintEnabled))
            row(title: "Invisible level",  value: dev(\.levelIndicatorEnabled))
        }
    }

    private var aboutSection: some View {
        Section("About") {
            row(title: "Version",      value: marketingVersion)
            row(title: "Build",        value: buildNumber)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("piqd.settings.row.\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }

    private func dev(_ keyPath: KeyPath<DevSettingsStore, Bool>) -> String {
        container.devSettings[keyPath: keyPath] ? "On" : "Off"
    }

    private var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
