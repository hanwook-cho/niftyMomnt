// Apps/niftyMomnt/UI/Settings/SettingsView.swift
// Spec §8 — AI & Privacy · Presets & Style · Storage & Sync · Capture.
// TODO: Implement full settings sections per spec §8.

import NiftyCore
import SwiftUI

struct SettingsView: View {
    let container: AppContainer

    // Persisted settings — in real integration back to UserDefaults / AppConfig mutations
    @AppStorage("nifty.soundStampEnabled")      private var soundStampEnabled: Bool = false
    @AppStorage("nifty.dualCameraEnabled")       private var dualCameraEnabled: Bool = true
    @AppStorage("nifty.rollModeEnabled")         private var rollModeEnabled: Bool = false
    @AppStorage("nifty.iCloudSyncEnabled")       private var iCloudSyncEnabled: Bool = false
    @AppStorage("nifty.nudgeCardMode")           private var nudgeCardMode: String = "full"

    var body: some View {
        NavigationStack {
            Form {
                captureSection
                aiPrivacySection
                storageSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        Section("Capture") {
            if container.config.features.contains(.soundStamp) {
                Toggle(isOn: $soundStampEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound Stamp")
                            .font(.niftyBody)
                        Text("1.5s ambient audio at capture. Analysed on-device, never stored.")
                            .font(.niftyCaption)
                            .foregroundStyle(Color.niftyTextSecondary)
                    }
                }
                .tint(Color.niftyBrand)
            }

            Toggle(isOn: $dualCameraEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contextual context capture")
                        .font(.niftyBody)
                    Text("Secondary camera captures scene context — never saved or shown.")
                        .font(.niftyCaption)
                        .foregroundStyle(Color.niftyTextSecondary)
                }
            }
            .tint(Color.niftyBrand)

            if container.config.features.contains(.rollMode) {
                Toggle(isOn: $rollModeEnabled) {
                    Text("Roll Mode")
                        .font(.niftyBody)
                }
                .tint(Color.niftyBrand)
            }

            if container.config.features.contains(.nudgeEngine) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capture Reflection")
                            .font(.niftyBody)
                        Text("Off · Quick (emoji tap) · Full (text note)")
                            .font(.niftyCaption)
                            .foregroundStyle(Color.niftyTextSecondary)
                    }
                    Picker("Capture Reflection", selection: $nudgeCardMode) {
                        Text("Off").tag("off")
                        Text("Quick").tag("quick")
                        Text("Full").tag("full")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - AI & Privacy

    private var aiPrivacySection: some View {
        Section("AI & Privacy") {
            NavigationLink("AI Mode") {
                aiModeDetail
            }
            if container.config.sharing.labEnabled {
                NavigationLink("Lab Settings") {
                    labDetail
                }
            }
            NavigationLink("Privacy & Data") {
                privacyDetail
            }
        }
    }

    private var aiModeDetail: some View {
        Form {
            Section {
                aiModeRow(title: "On-Device Only",
                          subtitle: "All processing stays on your device.",
                          isActive: container.config.aiModes.contains(.onDevice))
                aiModeRow(title: "Enhanced AI",
                          subtitle: "Text-based analysis via encrypted API.",
                          isActive: container.config.aiModes.contains(.enhancedAI))
                aiModeRow(title: "Lab",
                          subtitle: "Visual AI analysis with explicit consent per asset.",
                          isActive: container.config.aiModes.contains(.lab))
            } footer: {
                Text("AI Mode is configured per app variant. Contact support to change.")
                    .font(.niftyCaption)
            }
        }
        .navigationTitle("AI Mode")
    }

    private func aiModeRow(title: String, subtitle: String, isActive: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.niftyBody)
                Text(subtitle).font(.niftyCaption).foregroundStyle(Color.niftyTextSecondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.niftyBrand)
                    .font(.niftyLabel)
            }
        }
    }

    private var labDetail: some View {
        Form {
            Section("Lab") {
                Text("Lab processes your moments with visual AI to generate richer captions and vibe tags. Each submission requires explicit consent.")
                    .font(.niftyBody)
                    .foregroundStyle(Color.niftyTextSecondary)
            }
        }
        .navigationTitle("Lab Settings")
    }

    private var privacyDetail: some View {
        Form {
            Section("Data") {
                Button("Export All Data", role: .none) {}
                    .foregroundStyle(Color.niftyBrand)
                Button("Delete All Moments", role: .destructive) {}
            }
        }
        .navigationTitle("Privacy & Data")
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section("Storage & Sync") {
            if container.config.storage.iCloudSyncEnabled {
                Toggle(isOn: $iCloudSyncEnabled) {
                    Text("iCloud Sync")
                        .font(.niftyBody)
                }
                .tint(Color.niftyBrand)
            }
            if container.config.storage.smartArchiveEnabled {
                NavigationLink("Smart Archive") {
                    Form {
                        Section {
                            Text("niftyMomnt automatically archives older moments to reduce device storage while preserving your vault.")
                                .font(.niftyBody)
                                .foregroundStyle(Color.niftyTextSecondary)
                        }
                    }
                    .navigationTitle("Smart Archive")
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Variant")
                Spacer()
                Text(container.config.appVariant.rawValue.capitalized)
                    .foregroundStyle(Color.niftyTextSecondary)
            }
            .font(.niftyBody)

            Link("Privacy Policy", destination: URL(string: "https://example.com")!)
                .font(.niftyBody)
                .foregroundStyle(Color.niftyBrand)
        }
    }
}
