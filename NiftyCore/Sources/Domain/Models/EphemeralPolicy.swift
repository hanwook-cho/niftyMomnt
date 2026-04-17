// NiftyCore/Sources/Domain/Models/EphemeralPolicy.swift
// Disappear behavior for Piqd Snap Mode shared assets.
// SRS §3.3.

import Foundation

public struct EphemeralPolicy: Equatable, Sendable {
    /// `true` → asset purged on first view (Snap Mode default).
    public let expiresOnView: Bool

    /// Hard expiry regardless of view status. `0` → no ceiling (Roll Mode).
    public let hardCeilingHours: Int

    public init(expiresOnView: Bool, hardCeilingHours: Int) {
        self.expiresOnView = expiresOnView
        self.hardCeilingHours = hardCeilingHours
    }
}

public extension EphemeralPolicy {
    /// Snap Mode default — expires on first view, 24h hard ceiling.
    static let snap = EphemeralPolicy(expiresOnView: true, hardCeilingHours: 24)
    /// Roll Mode default — no ephemeral behavior; retained indefinitely.
    static let roll = EphemeralPolicy(expiresOnView: false, hardCeilingHours: 0)
}
