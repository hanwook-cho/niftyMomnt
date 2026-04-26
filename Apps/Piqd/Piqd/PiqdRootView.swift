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

            // Debug-only ladybug. Moved to top-left in v0.4 to not collide with the
            // Layer-1 flip button at top-right, and offset below the status bar so it
            // doesn't sit under the Dynamic Island. Drafts badge (top-left in Layer 1)
            // is still EmptyView in v0.4 — by v0.5 we'll need a different escape hatch
            // (the 5-tap mode-pill gesture already opens dev settings).
            VStack {
                HStack {
                    Button {
                        showDebugVault = true
                    } label: {
                        Image(systemName: "ladybug")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(12)
                    }
                    .accessibilityIdentifier("piqd.debug.open")
                    Spacer()
                }
                .padding(.top, PiqdTokens.Layout.statusBarOffset)
                Spacer()
            }
        }
        .sheet(isPresented: $showDebugVault) {
            PiqdVaultDebugView(container: container)
        }
    }
}
