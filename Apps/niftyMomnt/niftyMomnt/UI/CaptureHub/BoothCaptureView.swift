// Apps/niftyMomnt/UI/CaptureHub/BoothCaptureView.swift
// Life Four Cuts — full-screen photo-booth capture flow.
//
// Layout (top → bottom while idle):
//   • Full-bleed live camera preview
//   • Top overlay: 4-shot progress strip
//   • Full overlay: low-opacity Featured Frame PNG
//   • Bottom: Frame Carousel + "✦ START" button
//
// Capture loop (after START):
//   Countdown 3→2→1 → white flash → capture → freeze frame 0.4s → repeat ×4
//   After shot 4 → StripPreviewSheet appears

import AVFoundation
import NiftyCore
import QuartzCore
import SwiftUI
import UIKit

struct BoothCaptureView: View {
    let container: AppContainer
    let onDismiss: () -> Void  // back to CaptureHub

    // Frame selection
    @State private var selectedFrame: FeaturedFrame = .none

    // Capture state
    @State private var isCapturing: Bool = false
    @State private var shotsDone: Int = 0          // 0…4
    @State private var countdownValue: Int? = nil  // 3, 2, 1, nil
    @State private var flashOpacity: Double = 0
    @State private var freezeImage: UIImage? = nil  // shown 0.4s after each shot

    // Captured data
    @State private var capturedShots: [(Asset, Data)] = []

    // Sheet
    @State private var showPreviewSheet: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        ZStack {
            // No CameraPreviewView here — the parent CaptureHubView keeps a single
            // persistent preview layer beneath this overlay to avoid re-connection stalls.

            // Freeze-frame overlay (shown 0.4s after each shot)
            if let freeze = freezeImage {
                Image(uiImage: freeze)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // Featured Frame live overlay
            if selectedFrame.id != "none" {
                frameOverlay
            }

            // White flash
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Top UI: back button + progress strip
            VStack {
                topBar
                Spacer()
            }

            // Centre: countdown
            if let count = countdownValue {
                countdownLabel(count)
            }

            // Bottom: frame carousel + start button (hidden during capture)
            if !isCapturing {
                VStack {
                    Spacer()
                    bottomPanel
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPreviewSheet, onDismiss: handlePreviewDismiss) {
            StripPreviewSheet(
                container: container,
                shots: capturedShots,
                initialFrame: selectedFrame,
                initialBorder: .white,
                photoShape: .fourByThree,
                onSaved: { _ in showPreviewSheet = false; onDismiss() },
                onRetake: { showPreviewSheet = false; resetCapture() }
            )
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 60)

            Spacer()

            // 4-shot progress strip
            progressStrip
                .padding(.trailing, 16)
                .padding(.top, 66)
        }
    }

    private var progressStrip: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i < shotsDone ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 22, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - Featured Frame Overlay

    private var frameOverlay: some View {
        Image(selectedFrame.id)
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .opacity(0.55)
            .allowsHitTesting(false)
            // Fallback: if the PNG bundle asset isn't present, show a tinted overlay
            .background(
                Color(hex: selectedFrame.previewColorHex).opacity(0.18)
            )
    }

    // MARK: - Countdown

    private func countdownLabel(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 96, weight: .black))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .animation(reduceMotion ? .none : .spring(response: 0.3), value: value)
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // Frame carousel
            frameCarousel
                .padding(.bottom, 16)

            // Start button
            startButton
                .padding(.bottom, 48)
        }
        .background(.ultraThinMaterial.opacity(0.7))
    }

    private var frameCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FeaturedFrame.allCases) { frame in
                    frameCell(frame)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func frameCell(_ frame: FeaturedFrame) -> some View {
        let isSelected = frame.id == selectedFrame.id
        return Button { selectedFrame = frame } label: {
            VStack(spacing: 6) {
                // Miniature strip thumbnail (2:3 aspect ratio)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: frame.previewColorHex))
                    .frame(width: 44, height: 66)
                    .overlay(
                        // Simulate the 4-slot strip visually
                        VStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.black.opacity(0.35))
                                    .frame(height: 13)
                            }
                        }
                        .padding(4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? Color.white : .white.opacity(0.2),
                                          lineWidth: isSelected ? 2 : 0.5)
                    )

                Text(frame.displayName)
                    .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var startButton: some View {
        Button(action: startBoothCapture) {
            HStack(spacing: 8) {
                Text("✦")
                    .font(.system(size: 18, weight: .black))
                Text("START")
                    .font(.system(size: 16, weight: .black))
                    .kerning(2)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 44)
            .padding(.vertical, 16)
            .background(.white)
            .clipShape(Capsule())
        }
    }

    // MARK: - Capture Loop

    private func startBoothCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        capturedShots = []
        shotsDone = 0
        Task { await prepareAndRunBoothLoop() }
    }

    /// Ensures the session is in photo mode (may need to reconfigure from video class),
    /// then runs the capture loop. The reconfiguration happens before the first countdown
    /// so the user sees a spinner/indicator rather than a frozen UI.
    private func prepareAndRunBoothLoop() async {
        let t0 = CACurrentMediaTime()
        do {
            // Switch to .still to guarantee photo output is active.
            // No-op if already in photo class; ~0.4s if coming from video class.
            try await container.captureUseCase.switchMode(to: .still, config: container.config)
            print("[BoothCapture] session prep done: \(String(format: "%.3f", CACurrentMediaTime() - t0))s")
        } catch {
            isCapturing = false
            print("[BoothCapture] session prep failed after \(String(format: "%.3f", CACurrentMediaTime() - t0))s: \(error)")
            return
        }
        await runBoothLoop()
    }

    private func runBoothLoop() async {
        for shotIndex in 0..<4 {
            // Countdown 3 → 2 → 1
            for count in stride(from: 3, through: 1, by: -1) {
                withAnimation { countdownValue = count }
                try? await Task.sleep(for: .seconds(1))
            }
            withAnimation { countdownValue = nil }

            // White flash
            withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 1 }
            withAnimation(.easeOut(duration: 0.25).delay(0.08)) { flashOpacity = 0 }

            // Capture
            do {
                let (asset, data) = try await container.lifeFourCutsUseCase.captureOneShot()
                capturedShots.append((asset, data))
                shotsDone = shotIndex + 1

                // Freeze frame
                let image = UIImage(data: data)
                withAnimation(.easeIn(duration: 0.1)) { freezeImage = image }
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeOut(duration: 0.15)) { freezeImage = nil }

            } catch {
                // Abort on capture failure
                isCapturing = false
                withAnimation { countdownValue = nil; flashOpacity = 0; freezeImage = nil }
                #if DEBUG
                print("[BoothCapture] captureOneShot failed: \(error)")
                #endif
                return
            }

            // Gap between shots (except after the last)
            if shotIndex < 3 {
                try? await Task.sleep(for: .milliseconds(600))
            }
        }

        // All 4 done — show preview sheet
        isCapturing = false
        withAnimation { showPreviewSheet = true }
    }

    private func resetCapture() {
        capturedShots = []
        shotsDone = 0
        isCapturing = false
        countdownValue = nil
        flashOpacity = 0
        freezeImage = nil
    }

    private func handlePreviewDismiss() {
        // If sheet dismissed without save (e.g. swipe down), stay in booth
        if capturedShots.count == 4 && !showPreviewSheet {
            // User swiped away — reset
            resetCapture()
        }
    }
}
