// Apps/Piqd/Piqd/UI/Onboarding/OnboardingRootView.swift
// Piqd v0.6 — onboarding root that switches between O0–O3 child views based
// on `OnboardingCoordinator.step`.
//
// Task 10 (this file) wires the switcher with placeholder views so the root
// switch is exercisable end-to-end. Tasks 11 + 12 replace the placeholders
// with the real `O0TwoModesView` / `O1SnapTeachView` / `O2RollTeachView` /
// `O3InviteView` per UIUX §7.

import SwiftUI

public struct OnboardingRootView: View {

    let container: PiqdAppContainer
    @Bindable var coordinator: OnboardingCoordinator

    public init(container: PiqdAppContainer) {
        self.container = container
        self._coordinator = Bindable(wrappedValue: container.onboardingCoordinator)
    }

    public var body: some View {
        switch coordinator.step {
        case .twoModes:
            O0TwoModesView(coordinator: coordinator)
        case .snap:
            O1SnapTeachView(container: container, coordinator: coordinator)
        case .roll:
            O2RollTeachView(container: container, coordinator: coordinator)
        case .invite:
            O3InviteView(container: container, coordinator: coordinator)
        }
    }

    @ViewBuilder
    private func placeholder(
        step: String,
        title: String,
        primary: (label: String, action: () -> Void),
        secondary: (label: String, action: () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Text(step)
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
            Spacer()
            Button(primary.label, action: primary.action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("piqd.onboarding.\(step.lowercased()).primary")
            if let secondary {
                Button(secondary.label, action: secondary.action)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityIdentifier("piqd.onboarding.\(step.lowercased()).secondary")
            }
            Spacer().frame(height: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundStyle(.white)
        .ignoresSafeArea()
    }
}
