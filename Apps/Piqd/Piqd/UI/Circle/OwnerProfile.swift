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
    private static let inviteNonceKey = "piqd.owner.inviteNonce"
    private static let inviteCreatedAtKey = "piqd.owner.inviteCreatedAt"

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

    /// Stable per-install random nonce baked into the invite token. Lazy-generated
    /// once and cached so the QR / `piqd://invite/...` URL is byte-stable across
    /// app relaunches — same keypair + same nonce + same createdAt → identical
    /// payload, identical QR pixels.
    public var inviteNonce: Data {
        lock.lock(); defer { lock.unlock() }
        if let d = defaults.data(forKey: Self.inviteNonceKey), d.count == 16 {
            return d
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        let data = Data(bytes)
        defaults.set(data, forKey: Self.inviteNonceKey)
        return data
    }

    /// Stable invite-token timestamp. Lazy-set on first read.
    public var inviteCreatedAt: Date {
        lock.lock(); defer { lock.unlock() }
        let stored = defaults.double(forKey: Self.inviteCreatedAtKey)
        if stored > 0 {
            return Date(timeIntervalSince1970: stored)
        }
        let now = Date()
        defaults.set(now.timeIntervalSince1970, forKey: Self.inviteCreatedAtKey)
        return now
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
