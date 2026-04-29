# Invite Token Wire Format — v1

_Piqd v0.6 — Trusted Circle invite payload. See `piqd_interim_v0.6_plan.md` task 3._

## Purpose

Encodes an `InviteToken` (sender UUID, display name, Curve25519 public key, nonce, timestamp) into a URL-safe string suitable for a QR code or `piqd://invite/<token>` deep link. The recipient decodes, verifies the signature against the embedded public key, and adds the sender to their local trusted circle.

## Envelope

```
[0]            magic byte           = 0x01  (version 1)
[1..2]         payload length       UInt16 big-endian
[3..3+L-1]     payload bytes        deterministic JSON (see below)
[3+L..end]    signature bytes      Curve25519.Signing over the payload
```

The whole envelope is base64-URL encoded (RFC 4648 §5: `+` → `-`, `/` → `_`, padding `=` stripped).

## Payload

JSON with `sortedKeys` + `withoutEscapingSlashes`, dates as `secondsSince1970` (Double), `Data` fields as base64 strings:

```json
{
  "createdAt": 1780000000.0,
  "displayName": "Alex",
  "nonce": "<base64>",
  "publicKey": "<base64>",
  "senderID": "8B23E2F4-...-..."
}
```

Sort order is alphabetical key order (`JSONEncoder.OutputFormatting.sortedKeys`). The encoder MUST produce a byte-stable output for a given input — the signature covers exactly these bytes, and any whitespace or key-order drift breaks verification.

## Limits

- `maxPayloadBytes = 1024` — caps QR size and rejects pathological display names.
- Encode throws `oversized(_:)` if the payload exceeds the limit.
- Decode rejects envelopes < 3 bytes, payloads of declared length 0, and any envelope where `3 + payloadLength >= totalLength` (no room for a signature).

## Versioning

The magic byte (offset 0) gates version compatibility. v0.7+ may add fields to the payload by:

1. Bumping the magic byte (e.g. 0x02 for v2).
2. Keeping a v1 decode branch so older invites in the wild still resolve.

A v0.6 client decoding a v2 envelope returns `unsupportedVersion(0x02)`. A v2 client decoding a v1 envelope falls through to its v1 branch.

## Signature

The signer parameter receives **the raw payload bytes** (not the envelope, not the base64 string). Curve25519.Signing produces a 64-byte signature; the codec doesn't bake that in — it just appends whatever the signer returns and slices "everything after `3 + L`" back out on decode.

Verification re-decodes the payload first, then verifies `signature` over `payload` using `publicKey` carried inside the payload itself. A mismatch returns `signatureInvalid`.
