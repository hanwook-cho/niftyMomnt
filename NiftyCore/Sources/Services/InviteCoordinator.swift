// NiftyCore/Sources/Services/InviteCoordinator.swift
// Piqd v0.6 — composes IdentityKeyService + TrustedFriendsRepository +
// InviteTokenCodec into the user-facing invite flow. PRD §9 (FR-CIRCLE-03).
//
// Three operations:
//   - `myInviteToken()`  — fresh signed token with own public key
//   - `myInviteURL()`    — `piqd://invite/<base64>` for QR / share-link
//   - `accept(_:)`       — validates inbound token, persists friend, maps errors
//   - `acceptURL(_:)`    — convenience that parses + verifies a deep-link URL

import Foundation

public protocol InviteCoordinatorProtocol: Sendable {
    func myInviteToken() async throws -> InviteToken
    func myInviteURL() async throws -> URL
    /// Decode + verify an invite URL without persisting. Used when the UI
    /// needs to show the sender's display name + key fingerprint before the
    /// user consents to add them.
    func inspectURL(_ url: URL) async throws -> InviteToken
    func accept(_ token: InviteToken) async throws -> Friend
    func acceptURL(_ url: URL) async throws -> Friend
}

public enum InviteCoordinatorError: Error, Equatable, Sendable {
    /// Token's public key matches the user's own public key.
    case selfInvite
    /// Friend with that public key already in the circle.
    case duplicate
    /// Circle already at `TrustedCircle.maxSize`.
    case full
    /// URL didn't parse to `piqd://invite/<token>` shape.
    case malformedURL
    /// Codec rejected the payload (bad base64 / version / shape).
    case malformedToken
    /// Codec verified payload but signature didn't match embedded public key.
    case signatureInvalid
}

public final class InviteCoordinator: InviteCoordinatorProtocol, @unchecked Sendable {

    public static let urlScheme = "piqd"
    public static let urlHost   = "invite"

    private let identity: IdentityKeyServiceProtocol
    private let repo: TrustedFriendsRepositoryProtocol
    private let codec: InviteTokenCodec
    private let ownerSenderID: @Sendable () -> UUID
    private let ownerDisplayName: @Sendable () -> String
    private let nonceGenerator: @Sendable () -> Data
    private let now: @Sendable () -> Date

    public init(
        identity: IdentityKeyServiceProtocol,
        repo: TrustedFriendsRepositoryProtocol,
        codec: InviteTokenCodec = InviteTokenCodec(),
        ownerSenderID: @escaping @Sendable () -> UUID,
        ownerDisplayName: @escaping @Sendable () -> String,
        nonceGenerator: @escaping @Sendable () -> Data = InviteCoordinator.defaultNonce,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.identity = identity
        self.repo = repo
        self.codec = codec
        self.ownerSenderID = ownerSenderID
        self.ownerDisplayName = ownerDisplayName
        self.nonceGenerator = nonceGenerator
        self.now = now
    }

    // MARK: - Build my invite

    public func myInviteToken() async throws -> InviteToken {
        let key = try await identity.currentKey()
        return InviteToken(
            senderID: ownerSenderID(),
            displayName: ownerDisplayName(),
            publicKey: key.publicKey,
            nonce: nonceGenerator(),
            createdAt: now()
        )
    }

    public func myInviteURL() async throws -> URL {
        let token = try await myInviteToken()
        let wire = try codec.encode(token, signer: identity)
        guard let url = URL(string: "\(Self.urlScheme)://\(Self.urlHost)/\(wire)") else {
            throw InviteCoordinatorError.malformedURL
        }
        return url
    }

    // MARK: - Accept inbound

    public func accept(_ token: InviteToken) async throws -> Friend {
        // Self-invite check happens BEFORE the repo touches storage so the
        // user's own public key never lands as a friend row.
        let myKey = try await identity.currentKey()
        if token.publicKey == myKey.publicKey {
            throw InviteCoordinatorError.selfInvite
        }

        let friend = Friend(
            displayName: token.displayName,
            publicKey: token.publicKey,
            addedAt: now()
        )
        do {
            try await repo.insert(friend)
        } catch let err as TrustedFriendsRepositoryError {
            switch err {
            case .duplicatePublicKey: throw InviteCoordinatorError.duplicate
            case .full:               throw InviteCoordinatorError.full
            }
        }
        return friend
    }

    public func inspectURL(_ url: URL) async throws -> InviteToken {
        guard url.scheme == Self.urlScheme, url.host == Self.urlHost else {
            throw InviteCoordinatorError.malformedURL
        }
        let path = url.path
        guard path.hasPrefix("/"), path.count > 1 else {
            throw InviteCoordinatorError.malformedURL
        }
        let payload = String(path.dropFirst())

        do {
            return try codec.decode(payload, verifier: identity)
        } catch InviteTokenCodec.Error.signatureInvalid {
            throw InviteCoordinatorError.signatureInvalid
        } catch {
            throw InviteCoordinatorError.malformedToken
        }
    }

    public func acceptURL(_ url: URL) async throws -> Friend {
        let token = try await inspectURL(url)
        return try await accept(token)
    }

    // MARK: - Default nonce

    public static func defaultNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes)
    }
}
