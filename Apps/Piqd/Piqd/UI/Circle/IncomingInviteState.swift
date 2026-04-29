// Apps/Piqd/Piqd/UI/Circle/IncomingInviteState.swift
// Piqd v0.6 — bridges deep-link arrival to the SwiftUI sheet presentation.
// `handle(url:)` decodes (signature-verifies) the inbound invite and exposes
// it as `pending`; the sheet displays sender display name + fingerprint and
// routes Accept / Decline taps back here.
//
// Onboarding gating (defer publication while onboarding hasn't reached O3) is
// added in Task 10 — this state object only knows about the invite flow.

import Foundation
import Observation
import NiftyCore

@MainActor @Observable
public final class IncomingInviteState {

    /// The decoded invite waiting on user consent. `nil` when there's no
    /// pending invite (sheet not presented).
    public var pending: InviteToken?

    /// Last terminal message — surfaced inline by the sheet or a follow-up
    /// banner depending on context. Cleared by the consumer.
    public var resultMessage: String?

    /// URL queued because the app wasn't ready to present the sheet (e.g.,
    /// arrived mid-onboarding before O3). Drained by the gate consumer once
    /// `OnboardingCoordinator` reaches `.invite` or `isComplete`.
    public var queuedURL: URL?

    private let coordinator: any InviteCoordinatorProtocol

    public init(coordinator: any InviteCoordinatorProtocol) {
        self.coordinator = coordinator
    }

    /// Decode an incoming `piqd://invite/<token>` URL. On success the sheet
    /// presents; on failure a `resultMessage` is set and the sheet stays down.
    public func handle(url: URL) async {
        do {
            pending = try await coordinator.inspectURL(url)
        } catch let err as InviteCoordinatorError {
            resultMessage = Self.message(for: err)
        } catch {
            resultMessage = "Invalid invite"
        }
    }

    /// User tapped Accept on the sheet.
    public func accept() async {
        guard let token = pending else { return }
        do {
            let friend = try await coordinator.accept(token)
            resultMessage = "Added \(friend.displayName) to your circle."
        } catch let err as InviteCoordinatorError {
            resultMessage = Self.message(for: err)
        } catch {
            resultMessage = "Couldn't add friend."
        }
        pending = nil
    }

    /// User tapped Decline on the sheet.
    public func decline() {
        pending = nil
    }

    /// 4-byte SHA256 fingerprint of a Curve25519 public key, hex-encoded.
    /// Shown on the accept sheet so the user can spot-check the sender.
    public static func fingerprint(of publicKey: Data) -> String {
        // Using Foundation-only SHA256 via CommonCrypto would mean an extra
        // import; CryptoKit is already linked by the identity service.
        import_CryptoKitOnDemand(publicKey)
    }

    // MARK: - Error mapping

    private static func message(for err: InviteCoordinatorError) -> String {
        switch err {
        case .selfInvite:        return "That's your own invite."
        case .duplicate:         return "Already in your circle."
        case .full:              return "Circle is full (10)."
        case .malformedURL:      return "That link isn't a Piqd invite."
        case .malformedToken:    return "Invalid invite."
        case .signatureInvalid:  return "Invalid invite (signature)."
        }
    }
}

// MARK: - Local SHA256 helper (keeps CryptoKit import scoped)

import CryptoKit

private func import_CryptoKitOnDemand(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.prefix(4).map { String(format: "%02X", $0) }.joined()
}
