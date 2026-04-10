// Apps/niftyMomnt/UI/Journal/L4CMomentCardView.swift
// Feed card for a Life Four Cuts composite strip.
// Shows the composite JPEG as hero (cover-fit), ✦ BOOTH badge, subtitle.

import NiftyCore
import os
import SwiftUI

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "L4CCard")

// MARK: - L4CMomentCardView

struct L4CMomentCardView: View {
    let record: L4CRecord
    let onTap: () -> Void

    @State private var heroImage: UIImage? = nil

    var body: some View {
        Button(action: {
            log.debug("L4CMomentCardView: Internal button action triggered for \(record.id.uuidString)")
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                infoSection
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .task(id: record.id) { await loadHero() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let img = heroImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Fallback gradient while loading
                    LinearGradient(
                        colors: [Color(hex: "#1A0A14"), Color(hex: "#4A1A28")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .frame(height: 130)
            .clipped()

            // Amber left accent strip
            HStack(spacing: 0) {
                Color.niftyAmber.frame(width: 3)
                Spacer()
            }

            // ✦ BOOTH badge — top right
            VStack {
                HStack {
                    Spacer()
                    Text("✦ BOOTH")
                        .font(.system(size: 9, weight: .heavy))
                        .kerning(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.niftyAmber.opacity(0.82))
                        .clipShape(Capsule())
                        .padding([.top, .trailing], NiftySpacing.sm)
                }
                Spacer()
            }
        }
        .frame(height: 130)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 18
            )
        )
    }

    // MARK: - Info

    private var infoSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cardTitle)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.50))
            }
            Spacer()

            // Play-style "view strip" button
            Circle()
                .fill(Color.niftyAmber)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "photo.stack")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                )
        }
        .padding(.horizontal, NiftySpacing.md)
        .padding(.vertical, NiftySpacing.sm + 2)
    }

    // MARK: - Helpers

    private var cardTitle: String { "✦ \(record.label)" }

    private var subtitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        let date = fmt.string(from: record.capturedAt)
        return "4 cuts · \(date)"
    }

    private func loadHero() async {
        guard let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = dir
            .appendingPathComponent("assets")
            .appendingPathComponent("\(record.id.uuidString).jpg")
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            log.error("L4CMomentCardView — hero not found for \(record.id.uuidString)")
            return
        }
        log.debug("L4CMomentCardView — hero loaded \(data.count)B")
        heroImage = image
    }
}

// MARK: - L4CDetailView

/// Simple full-screen detail for an L4C record: composite strip + share/delete.
struct L4CDetailView: View {
    let record: L4CRecord
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @State private var heroImage: UIImage? = nil
    @State private var showShare: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var isDeleting: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        if let img = heroImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                        } else {
                            ProgressView().tint(.white).padding(.top, 80)
                        }

                        Text(record.label)
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white)

                        Text("4 cuts · \(formattedDate)")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Photo Booth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        // Share
                        Button { showShare = true } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.niftyAmber)
                        }
                        // Delete
                        Button { showDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                if let img = heroImage { ActivityViewController(activityItems: [img]) }
            }
            .confirmationDialog("Delete this photo booth strip?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Strip", role: .destructive) { Task { await deleteRecord() } }
                Button("Cancel", role: .cancel) {}
            }
            .task { await loadHero() }
        }
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d, yyyy"
        return fmt.string(from: record.capturedAt)
    }

    private func loadHero() async {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("assets").appendingPathComponent("\(record.id.uuidString).jpg")
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
        heroImage = image
    }

    private func deleteRecord() async {
        isDeleting = true
        do {
            // 1. Remove l4c_records row; get source IDs back
            let sourceIDs = try await container.graphManager.deleteL4CRecord(record.id)
            // 2. Delete composite asset from vault
            try? await container.vaultManager.delete(record.id)
            // 3. Delete source stills from vault
            for id in sourceIDs {
                try? await container.vaultManager.delete(id)
            }
            // 4. Notify feed
            NotificationCenter.default.post(name: .niftyMomentDeleted, object: nil)
            dismiss()
        } catch {
            #if DEBUG
            print("[L4CDetailView] delete failed: \(error)")
            #endif
        }
        isDeleting = false
    }
}
