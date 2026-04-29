// NiftyCore/Sources/Domain/InviteTokenCodec.swift
// Piqd v0.6 — invite-token wire codec. PRD §9 (FR-CIRCLE-03), SRS §6.3.4.
// Pure Swift + Foundation. The codec doesn't depend on CryptoKit directly —
// it accepts `InviteSigner` / `InviteVerifier` seams so callers (and tests)
// can plug in deterministic fakes. The Curve25519 implementation lives in
// `IdentityKeyService` (Task 4) and conforms to these protocols.
//
// Wire format documented in `Docs/Piqd/invite_token_v1.md`.

import Foundation

// MARK: - Crypto seams

public protocol InviteSigner: Sendable {
    /// Produce a signature over `payload` using the signer's private key.
    func sign(_ payload: Data) throws -> Data
}

public protocol InviteVerifier: Sendable {
    /// Verify `signature` over `payload` against `publicKey`. Returns true on success.
    func verify(_ signature: Data, payload: Data, publicKey: Data) -> Bool
}

// MARK: - Codec

public struct InviteTokenCodec: Sendable {

    /// Wire-format version. Bumped (and a new branch added) when the layout
    /// of the deterministic payload changes incompatibly.
    public static let magicByte: UInt8 = 0x01

    /// Deterministic-payload size ceiling. Caps display-name + nonce growth so
    /// a malformed/hostile token can't expand into multi-kB QR images.
    public static let maxPayloadBytes = 1024

    public enum Error: Swift.Error, Equatable, Sendable {
        case unsupportedVersion(UInt8)
        case malformedBase64
        case malformedPayload
        case signatureInvalid
        case oversized(Int)
    }

    public init() {}

    // MARK: Encode

    public func encode(_ token: InviteToken, signer: InviteSigner) throws -> String {
        let payload = try Self.deterministicPayload(token)
        guard payload.count <= Self.maxPayloadBytes else {
            throw Error.oversized(payload.count)
        }
        let signature = try signer.sign(payload)

        var envelope = Data()
        envelope.append(Self.magicByte)
        envelope.append(UInt8((payload.count >> 8) & 0xFF))
        envelope.append(UInt8(payload.count & 0xFF))
        envelope.append(payload)
        envelope.append(signature)

        return Self.base64URLEncode(envelope)
    }

    // MARK: Decode

    public func decode(_ string: String, verifier: InviteVerifier) throws -> InviteToken {
        guard let envelope = Self.base64URLDecode(string) else {
            throw Error.malformedBase64
        }
        guard envelope.count >= 3 else {
            throw Error.malformedPayload
        }
        let magic = envelope[0]
        guard magic == Self.magicByte else {
            throw Error.unsupportedVersion(magic)
        }
        let plen = (Int(envelope[1]) << 8) | Int(envelope[2])
        guard plen > 0, plen <= Self.maxPayloadBytes, envelope.count > 3 + plen else {
            throw Error.malformedPayload
        }
        let payload = envelope.subdata(in: 3 ..< 3 + plen)
        let signature = envelope.subdata(in: 3 + plen ..< envelope.count)

        let token = try Self.decodePayload(payload)

        guard verifier.verify(signature, payload: payload, publicKey: token.publicKey) else {
            throw Error.signatureInvalid
        }
        return token
    }

    // MARK: - Deterministic payload (JSON, sorted keys, seconds-since-1970)

    private struct PayloadV1: Codable {
        let senderID: UUID
        let displayName: String
        let publicKey: Data
        let nonce: Data
        let createdAt: Date
    }

    private static func deterministicPayload(_ token: InviteToken) throws -> Data {
        let p = PayloadV1(
            senderID: token.senderID,
            displayName: token.displayName,
            publicKey: token.publicKey,
            nonce: token.nonce,
            createdAt: token.createdAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.dataEncodingStrategy = .base64
        return try encoder.encode(p)
    }

    private static func decodePayload(_ data: Data) throws -> InviteToken {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.dataDecodingStrategy = .base64
        let p: PayloadV1
        do {
            p = try decoder.decode(PayloadV1.self, from: data)
        } catch {
            throw Error.malformedPayload
        }
        return InviteToken(
            senderID: p.senderID,
            displayName: p.displayName,
            publicKey: p.publicKey,
            nonce: p.nonce,
            createdAt: p.createdAt
        )
    }

    // MARK: - URL-safe base64

    private static func base64URLEncode(_ data: Data) -> String {
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "=", with: "")
        return s
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        s.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: s)
    }
}
