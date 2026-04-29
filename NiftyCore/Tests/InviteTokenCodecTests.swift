// NiftyCore/Tests/InviteTokenCodecTests.swift
// Piqd v0.6 — invite token wire-format tests. See Docs/Piqd/invite_token_v1.md.

import XCTest
@testable import NiftyCore

final class InviteTokenCodecTests: XCTestCase {

    // MARK: - Test seams

    /// Deterministic fake: signature is `SHA256-ish` (just byte-reverse of payload here).
    /// Real impl uses Curve25519. Codec contract: signer/verifier are opaque to the codec.
    private struct ReverseSigner: InviteSigner {
        func sign(_ payload: Data) throws -> Data {
            Data(payload.reversed())
        }
    }

    private struct ReverseVerifier: InviteVerifier {
        func verify(_ signature: Data, payload: Data, publicKey: Data) -> Bool {
            // publicKey ignored — this fake doesn't bind sig to key. The
            // codec's job is to wire up bytes, not to enforce crypto strength;
            // that is `IdentityKeyService`'s job (Task 4).
            return signature == Data(payload.reversed())
        }
    }

    private func makeToken(
        displayName: String = "Alex",
        publicKeyByte: UInt8 = 0x42,
        nonceByte: UInt8 = 0xAB
    ) -> InviteToken {
        InviteToken(
            senderID: UUID(uuidString: "8B23E2F4-1234-5678-9ABC-DEF012345678")!,
            displayName: displayName,
            publicKey: Data(repeating: publicKeyByte, count: 32),
            nonce: Data(repeating: nonceByte, count: 16),
            createdAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    private let codec = InviteTokenCodec()

    // MARK: - Round trip

    func test_roundTrip_preservesAllFields() throws {
        let original = makeToken()
        let wire = try codec.encode(original, signer: ReverseSigner())
        let decoded = try codec.decode(wire, verifier: ReverseVerifier())
        XCTAssertEqual(decoded, original)
    }

    func test_encode_outputIsURLSafeBase64() throws {
        let wire = try codec.encode(makeToken(), signer: ReverseSigner())
        XCTAssertFalse(wire.contains("+"))
        XCTAssertFalse(wire.contains("/"))
        XCTAssertFalse(wire.contains("="))
    }

    // MARK: - Signature failures

    func test_decode_signatureMismatch_throwsSignatureInvalid() throws {
        let wire = try codec.encode(makeToken(), signer: ReverseSigner())

        // Flip the last byte (which lives in the signature region).
        var bytes = Array(InviteTokenCodec_TestSupport.base64URLDecode(wire)!)
        bytes[bytes.count - 1] ^= 0xFF
        let tampered = InviteTokenCodec_TestSupport.base64URLEncode(Data(bytes))

        XCTAssertThrowsError(try codec.decode(tampered, verifier: ReverseVerifier())) { err in
            XCTAssertEqual(err as? InviteTokenCodec.Error, .signatureInvalid)
        }
    }

    func test_decode_tamperedPayload_throwsSignatureInvalid() throws {
        let wire = try codec.encode(makeToken(), signer: ReverseSigner())

        // Flip a byte inside the payload region (offset 3 + 5, mid-JSON).
        var bytes = Array(InviteTokenCodec_TestSupport.base64URLDecode(wire)!)
        bytes[3 + 5] ^= 0x01
        let tampered = InviteTokenCodec_TestSupport.base64URLEncode(Data(bytes))

        // Either the JSON no longer parses (malformedPayload) or the signature
        // doesn't match (signatureInvalid). Both are acceptable for a tamper —
        // the contract is "doesn't quietly succeed".
        XCTAssertThrowsError(try codec.decode(tampered, verifier: ReverseVerifier())) { err in
            let e = err as? InviteTokenCodec.Error
            XCTAssertTrue(e == .signatureInvalid || e == .malformedPayload, "got \(String(describing: e))")
        }
    }

    // MARK: - Version

    func test_decode_unsupportedVersionByte_throws() throws {
        let wire = try codec.encode(makeToken(), signer: ReverseSigner())
        var bytes = Array(InviteTokenCodec_TestSupport.base64URLDecode(wire)!)
        bytes[0] = 0x02  // future v2
        let bumped = InviteTokenCodec_TestSupport.base64URLEncode(Data(bytes))

        XCTAssertThrowsError(try codec.decode(bumped, verifier: ReverseVerifier())) { err in
            XCTAssertEqual(err as? InviteTokenCodec.Error, .unsupportedVersion(0x02))
        }
    }

    // MARK: - Malformed inputs

    func test_decode_malformedBase64_throws() {
        XCTAssertThrowsError(try codec.decode("!!! not base64 !!!", verifier: ReverseVerifier())) { err in
            XCTAssertEqual(err as? InviteTokenCodec.Error, .malformedBase64)
        }
    }

    func test_decode_truncatedEnvelope_throwsMalformedPayload() throws {
        // Length header says 200 bytes but envelope only has 10.
        let bogus = Data([0x01, 0x00, 200, 0x7B, 0x7D]) // {} payload, no sig, plen lies
        let wire = InviteTokenCodec_TestSupport.base64URLEncode(bogus)
        XCTAssertThrowsError(try codec.decode(wire, verifier: ReverseVerifier())) { err in
            XCTAssertEqual(err as? InviteTokenCodec.Error, .malformedPayload)
        }
    }

    // MARK: - Oversized payload

    func test_encode_oversizedPayload_throws() {
        // Display name longer than maxPayloadBytes by itself blows the cap.
        let huge = String(repeating: "x", count: 2048)
        let token = makeToken(displayName: huge)
        XCTAssertThrowsError(try codec.encode(token, signer: ReverseSigner())) { err in
            guard case .oversized(let n) = err as? InviteTokenCodec.Error else {
                return XCTFail("expected .oversized, got \(err)")
            }
            XCTAssertGreaterThan(n, InviteTokenCodec.maxPayloadBytes)
        }
    }
}

// MARK: - Test helpers (mirror codec's internal base64-URL implementation)

enum InviteTokenCodec_TestSupport {
    static func base64URLEncode(_ data: Data) -> String {
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "=", with: "")
        return s
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        s.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: s)
    }
}
