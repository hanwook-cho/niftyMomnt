// Apps/Piqd/Piqd/PiqdRootView.swift
// Piqd root scene. Routes between onboarding (v0.6+) and capture, hosts the
// incoming-invite sheet, and exposes the debug vault entry point.
//
// Onboarding gate: when `OnboardingCoordinator.isComplete` is false, the
// root mounts `OnboardingRootView` instead of the capture stack. The
// invite sheet defers presentation until the gate opens (handled in PiqdApp's
// `.onOpenURL`), and `.onChange` blocks here drain any queued URL when the
// coordinator transitions to `.invite` or completion.

import SwiftUI

struct PiqdRootView: View {
    let container: PiqdAppContainer
    @State private var showDebugVault = false
    @Bindable private var onboarding: OnboardingCoordinator

    init(container: PiqdAppContainer) {
        self.container = container
        self._onboarding = Bindable(wrappedValue: container.onboardingCoordinator)
    }

    var body: some View {
        // captureStack root only — gesture-disrupting modifiers (.sheet,
        // .fullScreenCover, conditional content) are NOT applied here. The
        // incoming-invite sheet attaches inside PiqdCaptureView (alongside the
        // existing sheets), and onboarding is conditionally overlaid via
        // ZStack INSIDE captureStack so the outer chain stays clean.
        captureStack
            .task {
                if onboarding.isComplete || onboarding.step == .invite {
                    drainQueuedInvite()
                }
            }
            .onChange(of: onboarding.isComplete) { _, complete in
                if complete { drainQueuedInvite() }
            }
            .onChange(of: onboarding.step) { _, step in
                if step == .invite { drainQueuedInvite() }
            }
    }

    @ViewBuilder
    private var captureStack: some View {
        ZStack {
            PiqdCaptureView(container: container)
                .ignoresSafeArea()

            // Onboarding overlay — covers entire viewfinder when not complete.
            // Conditional inside ZStack is fine because PiqdCaptureView is the
            // FIRST (always-mounted) child; the conditional only adds an
            // overlay when needed.
            if !onboarding.isComplete {
                OnboardingRootView(container: container)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

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
        .sheet(isPresented: Binding(
            get: { container.incomingInviteState.pending != nil },
            set: { newValue in
                if !newValue { container.incomingInviteState.decline() }
            }
        )) {
            IncomingInviteSheet(state: container.incomingInviteState)
        }
    }

    private func drainQueuedInvite() {
        guard let url = container.incomingInviteState.queuedURL else { return }
        container.incomingInviteState.queuedURL = nil
        Task { await container.incomingInviteState.handle(url: url) }
    }
}

