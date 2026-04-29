// Apps/Piqd/Piqd/UI/Settings/FriendsListView.swift
// Piqd v0.6 — trusted friends list. UIUX §8 (CIRCLE → My friends).
//
// Loads from `TrustedFriendsRepositoryProtocol` on `.task`. Each row shows a
// 40pt initial-avatar, display name, and last-activity date (always "—" in
// v0.6; populated v0.7 when send/receive events land). Tap-to-confirm-remove
// hits `repo.remove(id:)`.

import SwiftUI
import NiftyCore

struct FriendsListView: View {

    let container: PiqdAppContainer
    @State private var friends: [Friend] = []
    @State private var pendingRemoval: Friend?

    var body: some View {
        List {
            if friends.isEmpty {
                Text("No friends yet.\nTap “Add friend” to invite someone.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .accessibilityIdentifier("piqd.circle.friends.empty")
            } else {
                ForEach(friends) { friend in
                    Button {
                        pendingRemoval = friend
                    } label: {
                        FriendRowView(friend: friend)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("piqd.circle.friend.\(friend.id.uuidString).row")
                }
            }
        }
        .navigationTitle("My friends")
        .accessibilityIdentifier("piqd.circle.friendsList")
        .task { await reload() }
        .confirmationDialog(
            removalPrompt,
            isPresented: removalBinding,
            titleVisibility: .visible
        ) {
            Button("Remove from circle", role: .destructive) {
                Task {
                    if let friend = pendingRemoval {
                        try? await container.trustedFriendsRepository.remove(id: friend.id)
                        await reload()
                    }
                    pendingRemoval = nil
                }
            }
            .accessibilityIdentifier("piqd.circle.friend.remove.confirm")

            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }

    // MARK: - Helpers

    private var removalPrompt: String {
        if let friend = pendingRemoval {
            return "Remove \(friend.displayName) from your circle?"
        }
        return ""
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { newValue in if !newValue { pendingRemoval = nil } }
        )
    }

    private func reload() async {
        let all = (try? await container.trustedFriendsRepository.all()) ?? []
        await MainActor.run { self.friends = all }
    }
}

// MARK: - Row

struct FriendRowView: View {

    let friend: Friend

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(lastActivityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Color(white: 0.20))
            Text(initials)
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
    }

    private var initials: String {
        let parts = friend.displayName.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return chars.isEmpty ? "?" : chars.joined()
    }

    private var lastActivityLabel: String {
        guard let date = friend.lastActivityAt else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
