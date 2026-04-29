// Apps/Piqd/Piqd/UI/Onboarding/O0TwoModesView.swift
// Piqd v0.6 — Onboarding O0. UIUX §7.1.
//
// Split aesthetic: left half = clean Snap, right half = warm grainy Roll,
// 1pt white center divider, "Piqd" title centered on the divider, "Snap" /
// "Roll" labels below in their accent colors. Bottom: full-width "Continue →"
// (snapYellow) + "Skip" caption that jumps to O3.

import SwiftUI

struct O0TwoModesView: View {

    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    // Left half — Snap aesthetic (clean, bright)
                    Color(white: 0.10)
                        .frame(width: geo.size.width / 2)
                    // Right half — Roll aesthetic (warm) + grain overlay
                    ZStack {
                        Color(red: 0.20, green: 0.13, blue: 0.07)
                        GrainOverlayView(intensity: 0.30, density: 1400)
                    }
                    .frame(width: geo.size.width / 2)
                }
                .ignoresSafeArea()

                // 1pt centered divider
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    VStack(spacing: 18) {
                        Text("Piqd")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("piqd.onboarding.O0.title")

                        HStack(spacing: 0) {
                            Text("Snap")
                                .font(.body)
                                .foregroundStyle(PiqdTokens.Color.snapYellow)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Text("Roll")
                                .font(.body)
                                .foregroundStyle(PiqdTokens.Color.rollAmber)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        Button {
                            coordinator.advance()
                        } label: {
                            Text("Continue →")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(PiqdTokens.Color.snapYellow)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityIdentifier("piqd.onboarding.O0.continue")
                        .padding(.horizontal, 24)

                        Button {
                            coordinator.skipToInvite()
                        } label: {
                            Text("Skip")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .accessibilityIdentifier("piqd.onboarding.O0.skip")
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color.black)
    }
}
