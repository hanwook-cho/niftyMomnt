// Apps/niftyMomnt/UI/RootView.swift
// Spec §3.1 — Capture-first, swipe-up navigation model.
//
// The app opens directly to the Capture Hub (dark viewfinder).
// Swiping up from the capture surface reveals the Journal sheet.
// Swiping down from the Journal returns to capture.
//
// Implementation uses a ZStack with a vertically offset Journal sheet
// driven by a spring animation, matching the spec "sheet transition —
// capture pauses, journal slides up."

import NiftyCore
import SwiftUI

struct RootView: View {
    let container: AppContainer

    @State private var showJournal: Bool = false
    @State private var dragOffset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // ── Layer 0: Capture Hub (always present beneath the journal) ──
                CaptureHubView(
                    container: container,
                    onNavigateToJournal: { openJournal() },
                    isCaptureActive: !showJournal && dragOffset == 0
                )
                .ignoresSafeArea()

                // ── Layer 1: Journal sheet (slides up over capture) ──
                if showJournal || dragOffset < 0 {
                    JournalContainerView(
                        container: container,
                        onNavigateToCapture: { closeJournal() }
                    )
                    .frame(
                        width: geo.size.width,
                        height: geo.size.height
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: showJournal ? 0 : NiftyRadius.overlay)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 24, y: -8)
                    .offset(y: showJournal ? dragOffset : geo.size.height)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom)
                    )
                    // Interactive drag-to-dismiss
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Only track downward drag
                                if value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 120 || value.predictedEndTranslation.height > 280 {
                                    closeJournal()
                                } else {
                                    withAnimation(.niftySpring) { dragOffset = 0 }
                                }
                            }
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Navigation

    private func openJournal() {
        dragOffset = 0
        withAnimation(reduceMotion ? .linear(duration: 0.2) : .niftyScreen) {
            showJournal = true
        }
    }

    private func closeJournal() {
        withAnimation(reduceMotion ? .linear(duration: 0.2) : .niftyScreen) {
            dragOffset = 0
            showJournal = false
        }
    }
}
