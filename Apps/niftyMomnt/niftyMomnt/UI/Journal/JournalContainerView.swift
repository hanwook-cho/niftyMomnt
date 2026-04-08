// Apps/niftyMomnt/UI/Journal/JournalContainerView.swift
// Spec §3.1 v1.7 — Film Archive shell.
//
// v1.7 changes:
//   • Section renamed from "Journal" → "Film Archive"
//   • Background always-dark editorial #0F0D0B
//   • Tab bar: floating iOS 26 Liquid Glass pill (border-radius 29px)
//     Tabs: Film (lavender active + active dot) · Vault · Settings
//   • Film tab icon: film strip SVG glyph (lavender #C4B5FD when active)

import NiftyCore
import SwiftUI

struct JournalContainerView: View {
    let container: AppContainer
    let onNavigateToCapture: () -> Void

    @State private var selectedTab: FilmTab = .film
    @State private var isFilmFeedAtTop: Bool = true

    var body: some View {
        ZStack(alignment: .bottom) {
            // Always-dark editorial background
            Color.niftyFilmBg
                .ignoresSafeArea()

            // Swipe-down handle
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 36, height: 4)
                    .padding(.top, NiftySpacing.md)

                // Tab content
                Group {
                    switch selectedTab {
                    case .film:
                        FilmFeedView(
                            container: container,
                            onScrollTopChanged: { isAtTop in
                                isFilmFeedAtTop = isAtTop
                            },
                            onPullDownToDismiss: {
                                onNavigateToCapture()
                            }
                        )
                    case .vault:
                        VaultView(container: container)
                    case .settings:
                        SettingsView(container: container)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating tab bar bottom padding
                Spacer().frame(height: 72)
            }

            // Floating glass pill tab bar
            floatingTabBar
                .padding(.bottom, 28) // sits above home indicator
        }
        .preferredColorScheme(.dark)
        // Swipe down → return to Capture Hub
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.height > 60
                        && abs(value.translation.height) > abs(value.translation.width)
                        && (selectedTab != .film || isFilmFeedAtTop) {
                        onNavigateToCapture()
                    }
                }
        )
    }

    // MARK: - Floating Glass Pill Tab Bar (§5 v1.7)

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(FilmTab.allCases) { tab in
                Button {
                    withAnimation(.niftySpring) { selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        filmTabIcon(tab)
                            .frame(width: 20, height: 20)
                        Text(tab.label)
                            .font(.system(size: 9, weight: .bold))
                        // Active indicator dot below label (Film tab only per spec)
                        if tab == selectedTab {
                            Circle()
                                .fill(Color.niftyLavender)
                                .frame(width: 4, height: 4)
                        } else {
                            Color.clear.frame(width: 4, height: 4)
                        }
                    }
                    .foregroundStyle(
                        selectedTab == tab ? Color.niftyLavender : Color.white.opacity(0.26)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NiftySpacing.md)
                }
            }
        }
        .padding(.horizontal, NiftySpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 29)
                .fill(Color(red: 20/255, green: 16/255, blue: 12/255).opacity(0.76))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 29))
                .overlay(
                    RoundedRectangle(cornerRadius: 29)
                        .strokeBorder(.white.opacity(0.13), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, NiftySpacing.xl)
    }

    @ViewBuilder
    private func filmTabIcon(_ tab: FilmTab) -> some View {
        let isActive = selectedTab == tab
        let color = isActive ? Color.niftyLavender : Color.white.opacity(0.26)

        switch tab {
        case .film:
            // Film strip icon per spec wireframe
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color, lineWidth: 1.4)
                    .frame(width: 16, height: 11)
                    .offset(y: 2)
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2, height: 5)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2, height: 5)
                }
                .offset(y: -4)
            }
        case .vault:
            Image(systemName: "lock.fill")
                .font(.system(size: 16))
                .foregroundStyle(color)
        case .settings:
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16))
                .foregroundStyle(color)
        }
    }
}

// MARK: - FilmTab

enum FilmTab: String, CaseIterable, Identifiable {
    case film, vault, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .film:     return "Film"
        case .vault:    return "Vault"
        case .settings: return "Settings"
        }
    }
}
