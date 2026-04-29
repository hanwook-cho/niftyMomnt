// Apps/Piqd/Piqd/UI/Onboarding/O2RollTeachView.swift
// Piqd v0.6 — Onboarding O2. UIUX §7.3.
//
// Live Roll-mode viewfinder with grain overlay active. Teaching overlay over
// the bottom 40%: "Shoot all day." / "Opens at 9." A film counter ("24 left")
// is displayed in the top safe area to teach the daily-shot mechanic. "Next →"
// (rollAmber) advances to O3.

import SwiftUI

struct O2RollTeachView: View {

    let container: PiqdAppContainer
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        ZStack {
            CameraPreviewView(session: container.captureSession)
                .ignoresSafeArea()

            // Roll-mode grain
            GrainOverlayView(intensity: 0.40, density: 2200)
                .ignoresSafeArea()

            VStack {
                // Film counter — top-right, OCR-A-ish monospaced (system fallback)
                HStack {
                    Spacer()
                    Text("24 left")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.4))
                        .clipShape(Capsule())
                        .accessibilityIdentifier("piqd.onboarding.O2.filmCounter")
                }
                .padding(.top, 16)
                .padding(.trailing, 16)

                Spacer()

                bottomOverlay
            }
        }
        .background(Color.black)
        // No `.accessibilityIdentifier` on the root — would mask per-leaf IDs.
    }

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shoot all day.")
                Text("Opens at 9.")
            }
            .font(.title.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer().frame(height: 32)

            HStack {
                Spacer()
                Button {
                    coordinator.advance()
                } label: {
                    Text("Next →")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PiqdTokens.Color.rollAmber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .accessibilityIdentifier("piqd.onboarding.O2.next")
            }
            .padding(.trailing, 16)

            Spacer().frame(height: 32)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                .fill(Color.black.opacity(0.5))
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
