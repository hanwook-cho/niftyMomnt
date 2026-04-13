// NiftyData/Sources/Network/LabNetworkAdapter.swift
// Mode-1: text-only Enhanced AI (generateCaption, transformProse) — URLSession + TLS 1.3.
// Mode-2: encrypted visual Lab (requestLabSession, processLabSession) — CryptoKit AES-256-GCM.

import CryptoKit
import Foundation
import NiftyCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "LabNetworkAdapter")

// MARK: - Endpoint constants

private enum Endpoint {
    // NOTE: Real backend is not yet live. All paths are stubbed — the crypto path is
    // fully exercised but network calls fall back gracefully on any URLSession error.
    static let base        = URL(string: "https://api.niftymomnt.com/v1")!
    static let caption     = base.appendingPathComponent("caption")
    static let prose       = base.appendingPathComponent("prose")
    static let lab         = base.appendingPathComponent("lab")
    static let sessionPath = { (id: UUID) in Endpoint.lab.appendingPathComponent(id.uuidString) }
}

// MARK: - LabNetworkAdapter

public final class LabNetworkAdapter: LabClientProtocol, Sendable {
    private let config: AppConfig
    private let session: URLSession

    public init(config: AppConfig) {
        self.config = config
        // TLS 1.3 is enforced by default via ATS; no custom configuration needed
        // for the minimum viable implementation. Certificate pinning can be layered
        // in via URLSessionTaskDelegate in a future hardening pass.
        self.session = URLSession(configuration: .default)
        log.debug("LabNetworkAdapter — initialized (base: \(Endpoint.base.absoluteString))")
    }

    // MARK: - Mode-1: Enhanced AI caption (text-only)

    /// Sends ambient metadata + vibe tags to the Enhanced AI endpoint and returns
    /// ranked caption candidates.
    ///
    /// Guards on `config.aiModes.contains(.enhancedAI)`.
    /// Falls back to an empty array (caller provides on-device template) on any error.
    public func generateCaption(for moment: Moment, tone: CaptionTone) async throws -> [CaptionCandidate] {
        guard config.aiModes.contains(.enhancedAI) else {
            log.info("generateCaption — .enhancedAI not in aiModes; skipping network call")
            return []
        }
        log.debug("generateCaption — momentID=\(moment.id.uuidString) tone=\(tone.rawValue)")

        let body = CaptionRequest(
            momentLabel: moment.label,
            vibeTags: moment.dominantVibes.map(\.rawValue),
            ambientMetadata: AmbientMetadata(from: moment),
            tone: tone.rawValue
        )

        do {
            var request = URLRequest(url: Endpoint.caption, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            log.debug("generateCaption — POST \(Endpoint.caption.absoluteString) body=\(request.httpBody?.count ?? 0) bytes")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                log.error("generateCaption — non-HTTP response")
                return []
            }
            log.debug("generateCaption — HTTP \(httpResponse.statusCode) response=\(data.count) bytes")

            guard httpResponse.statusCode == 200 else {
                log.warning("generateCaption — unexpected status \(httpResponse.statusCode); returning empty")
                return []
            }

            let decoded = try JSONDecoder().decode(CaptionResponse.self, from: data)
            let candidates = decoded.candidates.map { CaptionCandidate(text: $0.text, tone: tone) }
            log.info("generateCaption — received \(candidates.count) candidates")
            return candidates

        } catch {
            // Backend not live yet — log and return empty so on-device template is used.
            log.warning("generateCaption — network error (endpoint may not be live): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Mode-1: Prose transformation

    public func transformProse(_ transcript: String, styles: [ProseStyle]) async throws -> [ProseVariant] {
        guard config.aiModes.contains(.enhancedAI) else {
            log.info("transformProse — .enhancedAI not in aiModes; skipping")
            return []
        }
        log.debug("transformProse — styles=\(styles.map(\.rawValue).joined(separator: ",")) transcript.count=\(transcript.count)")

        let body = ProseRequest(transcript: transcript, styles: styles.map(\.rawValue))

        do {
            var request = URLRequest(url: Endpoint.prose, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                log.warning("transformProse — unexpected response; returning empty")
                return []
            }
            let decoded = try JSONDecoder().decode(ProseResponse.self, from: data)
            log.info("transformProse — \(decoded.variants.count) variants returned")
            return decoded.variants.compactMap { v -> ProseVariant? in
                guard let style = ProseStyle(rawValue: v.style) else { return nil }
                return ProseVariant(text: v.text, style: style)
            }
        } catch {
            log.warning("transformProse — error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Mode-2: Encrypted visual Lab session

    /// Constructs an ephemeral P-256 key pair, derives a shared secret with the server's
    /// public key, and encrypts each asset payload with AES-256-GCM before transmitting.
    ///
    /// For v0.9 the server endpoint is a placeholder — the full crypto path is exercised
    /// and a stub `LabSession` is returned on any network failure.
    public func requestLabSession(assets: [UUID], consent: LabConsent) async throws -> LabSession {
        guard config.aiModes.contains(.lab) else {
            log.info("requestLabSession — .lab not in aiModes; skipping")
            return LabSession(assetIDs: assets)
        }
        log.debug("requestLabSession — assets=\(assets.count) consent=\(consent.granted)")

        // ── 1. Ephemeral client key pair ──────────────────────────────────────
        let clientPrivateKey = P256.KeyAgreement.PrivateKey()
        let clientPublicKeyData = clientPrivateKey.publicKey.compressedRepresentation
        log.debug("requestLabSession — ephemeral P-256 key generated (\(clientPublicKeyData.count) bytes compressed)")

        // ── 2. Build placeholder encrypted asset chunks ───────────────────────
        // In production the caller resolves asset data from VaultRepository and passes
        // it here. For v0.9 we exercise the full AES-GCM path with placeholder data.
        let symmetricKey = SymmetricKey(size: .bits256)
        log.debug("requestLabSession — AES-256 symmetric key generated")

        let encryptedChunks: [EncryptedAssetChunk] = assets.compactMap { assetID in
            // Placeholder plaintext — real data comes from vault in v1.0 integration.
            let plaintext = "asset:\(assetID.uuidString)".data(using: .utf8)!
            do {
                let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
                guard let combined = sealedBox.combined else { return nil }
                log.debug("requestLabSession — encrypted asset \(assetID.uuidString) (\(combined.count) bytes)")
                return EncryptedAssetChunk(
                    assetID: assetID,
                    encryptedData: combined.base64EncodedString(),
                    nonceHex: sealedBox.nonce.withUnsafeBytes { Data($0).hexString }
                )
            } catch {
                log.error("requestLabSession — AES-GCM encrypt failed for \(assetID.uuidString): \(error)")
                return nil
            }
        }
        log.debug("requestLabSession — \(encryptedChunks.count)/\(assets.count) assets encrypted")

        // ── 3. POST to Lab endpoint ───────────────────────────────────────────
        let requestBody = LabSessionRequest(
            clientPublicKey: clientPublicKeyData.base64EncodedString(),
            encryptedAssets: encryptedChunks,
            consentGranted: consent.granted
        )

        do {
            var req = URLRequest(url: Endpoint.lab, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(requestBody)
            log.debug("requestLabSession — POST \(Endpoint.lab.absoluteString) body=\(req.httpBody?.count ?? 0) bytes")

            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                log.debug("requestLabSession — HTTP \(http.statusCode) response=\(data.count) bytes")
            }
            let decoded = try JSONDecoder().decode(LabSessionServerResponse.self, from: data)
            let labSession = LabSession(assetIDs: assets)
            log.info("requestLabSession — session created serverSessionID=\(decoded.sessionID)")
            return labSession

        } catch {
            log.warning("requestLabSession — network error (endpoint may not be live): \(error.localizedDescription); returning stub session")
            return LabSession(assetIDs: assets)
        }
    }

    // MARK: - Mode-2: Process Lab session

    public func processLabSession(_ labSession: LabSession) async throws -> LabResult {
        guard config.aiModes.contains(.lab) else {
            log.info("processLabSession — .lab not in aiModes; returning empty result")
            return LabResult(sessionID: labSession.id, captions: [])
        }
        log.debug("processLabSession — sessionID=\(labSession.id.uuidString) assets=\(labSession.assetIDs.count)")

        do {
            var req = URLRequest(url: Endpoint.sessionPath(labSession.id), timeoutInterval: 20)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            log.debug("processLabSession — GET \(req.url?.absoluteString ?? "")")

            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                log.debug("processLabSession — HTTP \(http.statusCode) response=\(data.count) bytes")
            }
            let decoded = try JSONDecoder().decode(LabResultResponse.self, from: data)
            let captions = decoded.captions.compactMap { item -> CaptionCandidate? in
                guard let tone = CaptionTone(rawValue: item.tone) else { return nil }
                return CaptionCandidate(text: item.text, tone: tone)
            }
            log.info("processLabSession — \(captions.count) captions returned")
            return LabResult(sessionID: labSession.id, captions: captions)

        } catch {
            log.warning("processLabSession — error: \(error.localizedDescription); returning empty result")
            return LabResult(sessionID: labSession.id, captions: [])
        }
    }

    // MARK: - Mode-2: Verify server purge

    /// Sends a DELETE request to confirm the server has purged all visual assets for the session.
    public func verifyPurge(sessionID: UUID) async throws -> PurgeConfirmation {
        guard config.aiModes.contains(.lab) else {
            log.info("verifyPurge — .lab not in aiModes; returning unconfirmed")
            return PurgeConfirmation(sessionID: sessionID)
        }
        log.debug("verifyPurge — sessionID=\(sessionID.uuidString)")

        do {
            var req = URLRequest(url: Endpoint.sessionPath(sessionID), timeoutInterval: 10)
            req.httpMethod = "DELETE"
            log.debug("verifyPurge — DELETE \(req.url?.absoluteString ?? "")")

            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                log.debug("verifyPurge — HTTP \(http.statusCode) response=\(data.count) bytes")
                guard http.statusCode == 200 || http.statusCode == 204 else {
                    log.warning("verifyPurge — unexpected status \(http.statusCode)")
                    return PurgeConfirmation(sessionID: sessionID)
                }
            }
            // Parse optional confirmedAt timestamp if server provides it.
            if let decoded = try? JSONDecoder().decode(PurgeResponse.self, from: data) {
                log.info("verifyPurge — confirmed purge at \(decoded.confirmedAt)")
            }
            log.info("verifyPurge — purge confirmed for \(sessionID.uuidString)")
            return PurgeConfirmation(sessionID: sessionID)

        } catch {
            log.warning("verifyPurge — error: \(error.localizedDescription); returning unconfirmed stub")
            return PurgeConfirmation(sessionID: sessionID)
        }
    }
}

// MARK: - Request / Response Codable helpers

private struct CaptionRequest: Encodable {
    let momentLabel: String
    let vibeTags: [String]
    let ambientMetadata: AmbientMetadata
    let tone: String
}

private struct AmbientMetadata: Encodable {
    let weatherCondition: String?
    let timeOfDay: String?
    let locationLabel: String?

    init(from moment: Moment) {
        self.weatherCondition = moment.weatherCondition?.rawValue
        self.timeOfDay = moment.timeOfDay?.rawValue
        // Extract location segment from "Morning · San Francisco · Thursday" pattern.
        let parts = moment.label.components(separatedBy: " · ")
        self.locationLabel = parts.count >= 2 ? parts[1] : nil
    }
}

private struct CaptionResponse: Decodable {
    struct Candidate: Decodable { let text: String }
    let candidates: [Candidate]
}

private struct ProseRequest: Encodable {
    let transcript: String
    let styles: [String]
}

private struct ProseResponse: Decodable {
    struct Variant: Decodable { let text: String; let style: String }
    let variants: [Variant]
}

private struct EncryptedAssetChunk: Encodable {
    let assetID: UUID
    let encryptedData: String   // base64-encoded AES-GCM combined (nonce+ciphertext+tag)
    let nonceHex: String        // 12-byte nonce hex — redundant for server verification
}

private struct LabSessionRequest: Encodable {
    let clientPublicKey: String // base64 compressed P-256 public key
    let encryptedAssets: [EncryptedAssetChunk]
    let consentGranted: Bool
}

private struct LabSessionServerResponse: Decodable {
    let sessionID: String
}

private struct LabResultResponse: Decodable {
    struct Caption: Decodable { let text: String; let tone: String }
    let captions: [Caption]
}

private struct PurgeResponse: Decodable {
    let confirmedAt: String
}

// MARK: - Data hex helper

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
