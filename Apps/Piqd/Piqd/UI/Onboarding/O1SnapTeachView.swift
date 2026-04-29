// Apps/Piqd/Piqd/UI/Onboarding/O1SnapTeachView.swift
// Piqd v0.6 — Onboarding O1. UIUX §7.2.
//
// Live Snap-mode viewfinder with a teaching overlay over the bottom 40%:
// "Tap to capture." / "Swipe to send." plus a working shutter button. A tap
// flashes a brief "captured" confirmation overlay (visual teach-by-doing).
// "Next →" advances to O2.
//
// v0.6 scope: visual confirmation only — the full capture path stays in
// `PiqdCaptureView` post-onboarding. See plan §7.12 for the open question
// about persisting a real first photo.

import SwiftUI
import AVFoundation

struct O1SnapTeachView: View {

    let container: PiqdAppContainer
    @Bindable var coordinator: OnboardingCoordinator
    @State private var showFlash = false
    @State private var hasCaptured = false

    var body: some View {
        ZStack {
            CameraPreviewView(session: container.captureSession)
                .ignoresSafeArea()

            // Brief white flash on shutter tap
            Color.white
                .opacity(showFlash ? 0.85 : 0.0)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.18), value: showFlash)
                .allowsHitTesting(false)

            VStack {
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
                Text("Tap to capture.")
                Text("Swipe to send.")
            }
            .font(.title.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer().frame(height: 24)

            ZStack {
                // Shutter
                Button {
                    triggerShutter()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 64, height: 64)
                    }
                }
                .accessibilityIdentifier("piqd.onboarding.O1.shutter")

                // "Next →" — bottom-right
                HStack {
                    Spacer()
                    Button {
                        coordinator.advance()
                    } label: {
                        Text("Next →")
                            .font(.body.weight(.medium))
                            .foregroundStyle(PiqdTokens.Color.snapYellow)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("piqd.onboarding.O1.next")
                }
                .padding(.trailing, 16)
            }

            // "Captured ✓" toast
            Text("Captured ✓")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
                .padding(.top, 8)
                .opacity(hasCaptured ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: hasCaptured)

            Spacer().frame(height: 32)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                .fill(Color.black.opacity(0.5))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func triggerShutter() {
        showFlash = true
        hasCaptured = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showFlash = false
        }
    }
}
