// Apps/Piqd/Piqd/PiqdRootView.swift
// v0.1 root: capture screen with a hidden long-press on the status area to open the debug vault
// list. No Drafts tray, no Roll mode, no sharing — per piqd_interim_v0.1_plan.md.

import SwiftUI

struct PiqdRootView: View {
    let container: PiqdAppContainer
    @State private var showDebugVault = false

    var body: some View {
        ZStack {
            PiqdCaptureView(container: container)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        showDebugVault = true
                    } label: {
                        Image(systemName: "ladybug")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(12)
                    }
                    .accessibilityIdentifier("piqd.debug.open")
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showDebugVault) {
            PiqdVaultDebugView(container: container)
        }
    }
}
