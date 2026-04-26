// Apps/Piqd/Piqd/UI/Capture/SubjectGuidancePillView.swift
// Piqd v0.4 — "Step back for the full vibe" pill (UIUX §2.11).
//
// Subscribes to `SubjectGuidanceDetector.signals` and surfaces the pill for 1.5s on
// each `.edgeProximity` emission. Ignores `.ok` (it's informational; the pill auto-
// dismisses on its own timer). Snap-only — owner gates this view by mode/format/
// recording state.
//
// IMPORTANT: the pill text is always rendered (with opacity controlling visibility)
// so the `.task` modifier reliably attaches at view-appear and the AsyncStream
// subscription registers. An earlier impl wrapped the text in `Group { if isVisible }`,
// which collapsed to EmptyView at first appear and silently dropped the .task.

import NiftyCore
import NiftyData
import SwiftUI

struct SubjectGuidancePillView: View {

    let detector: SubjectGuidanceDetector

    private static let displaySeconds: TimeInterval = 1.5

    @State private var isVisible: Bool = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Text("Step back for the full vibe")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(PiqdTokens.Color.snapChrome)
            .padding(.horizontal, PiqdTokens.Spacing.md)
            .padding(.vertical, PiqdTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: PiqdTokens.Shape.pillRadius)
                    .fill(.ultraThinMaterial)
            )
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1.0 : 0.95)
            .allowsHitTesting(false)
            .accessibilityIdentifier("piqd.subjectGuidancePill")
            .accessibilityHidden(!isVisible)
            .animation(.easeInOut(duration: 0.18), value: isVisible)
            .task {
                for await signal in detector.signals {
                    if case .edgeProximity = signal {
                        show()
                    }
                }
            }
    }

    private func show() {
        dismissTask?.cancel()
        isVisible = true
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.displaySeconds * 1_000_000_000))
            if !Task.isCancelled {
                isVisible = false
            }
        }
    }
}
