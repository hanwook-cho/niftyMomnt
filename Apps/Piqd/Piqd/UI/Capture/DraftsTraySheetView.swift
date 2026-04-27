// Apps/Piqd/Piqd/UI/Capture/DraftsTraySheetView.swift
// Piqd v0.5 — drafts tray bottom sheet. PRD FR-SNAP-DRAFT-03..09, UIUX §2.14.
// Presented as `.medium` detent from `PiqdCaptureView` when the user taps the
// unsent badge.
//
// Lifecycle:
//   • `.task` starts the 1Hz ticker so timer-label colors flip live; ticker
//     stops on dismiss.
//   • Rows pull from `bindings.rows` (oldest-first, expired filtered).
//   • An empty list shows "All caught up." rather than a blank panel.

import NiftyCore
import NiftyData
import SwiftUI

struct DraftsTraySheetView: View {

    @Bindable var bindings: DraftsStoreBindings
    let exporter: any PhotoLibraryExporterProtocol
    let shareHandoff: ShareHandoffCoordinator
    let resolveURL: @Sendable (UUID, AssetType) async -> URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if bindings.rows.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(bindings.rows, id: \.item.id) { row in
                            DraftRowView(
                                item: row.item,
                                state: row.state,
                                exporter: exporter,
                                shareHandoff: shareHandoff,
                                resolveURL: resolveURL
                            )
                            Divider()
                                .padding(.leading, PiqdTokens.Spacing.md + 52 + PiqdTokens.Spacing.md)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("piqd.draftsTraySheet")
        .task {
            bindings.startTicker()
        }
        .onDisappear {
            bindings.stopTicker()
        }
    }

    private var header: some View {
        HStack {
            Text("Unsent")
                .font(.body)
                .fontWeight(.medium)
            Spacer()
            Text(itemCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, PiqdTokens.Spacing.md)
        .padding(.vertical, PiqdTokens.Spacing.md)
        .accessibilityIdentifier("piqd.draftsTraySheet.header")
    }

    private var itemCountText: String {
        let n = bindings.liveCount
        return n == 1 ? "1 item" : "\(n) items"
    }

    private var empty: some View {
        VStack(spacing: PiqdTokens.Spacing.sm) {
            Spacer()
            Text("All caught up.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
