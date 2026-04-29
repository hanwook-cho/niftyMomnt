// Apps/Piqd/Piqd/UI/Circle/OwnerProfile.swift
// Piqd v0.6 — UserDefaults-backed owner identity used by `InviteCoordinator`
// to populate the `senderID` + `displayName` fields on outbound invites.
//
// First-launch behavior:
//   - `senderID` is generated lazily on first read and persisted; stable
//     across launches until the user reinstalls (matches keypair lifecycle).
//   - `displayName` defaults to the iOS device name. The user can override
//     it later via Settings → CIRCLE (UI lands in Task 16).

import Foundation
import UIKit

public final class OwnerProfile: @unchecked Sendable {

    private static let senderIDKey    = "piqd.owner.senderID"
    private static let displayNameKey = "piqd.owner.displayName"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Stable per-install UUID. Lazy-generated on first read.
    public var senderID: UUID {
        lock.lock(); defer { lock.unlock() }
        if let s = defaults.string(forKey: Self.senderIDKey),
           let id = UUID(uuidString: s) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.senderIDKey)
        return id
    }

    /// Display name shown to friends in invites. Defaults to the iOS device name.
    public var displayName: String {
        get {
            lock.lock(); defer { lock.unlock() }
            if let s = defaults.string(forKey: Self.displayNameKey), !s.isEmpty {
                return s
            }
            return UIDevice.current.name
        }
        set {
            lock.lock(); defer { lock.unlock() }
            defaults.set(newValue, forKey: Self.displayNameKey)
        }
    }
}
