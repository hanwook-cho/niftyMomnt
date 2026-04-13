// NiftyCore/Sources/Managers/VaultManager.swift
// actor — serialises all vault reads, writes, and lock-state transitions.
//
// v0.8: adds Face ID gate, moveToVault (file-encrypt + graph-mark), and isVaultLocked.
// Lock state resets to `true` on every cold launch — no stored unlock token.

import Foundation
import LocalAuthentication

public actor VaultManager {
    private let vault: any VaultProtocol
    private let graph: any GraphProtocol

    /// True until the user authenticates with Face ID for this app session.
    public private(set) var isVaultLocked: Bool = true

    public init(vault: any VaultProtocol, graph: any GraphProtocol) {
        self.vault = vault
        self.graph = graph
    }

    // MARK: - Lock / Unlock

    /// Prompts Face ID (biometrics only — no silent passcode fallback per spec §6).
    /// Sets `isVaultLocked = false` on success.
    /// Throws `VaultAuthError.biometryNotAvailable` when Face ID is not enrolled.
    /// Throws `VaultAuthError.authFailed` when the user cancels or fails.
    public func unlockVault(reason: String = "Access your private archive") async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw VaultAuthError.biometryNotAvailable
        }
        let success: Bool = try await withCheckedThrowingContinuation { cont in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { ok, err in
                if let err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(returning: ok)
                }
            }
        }
        guard success else { throw VaultAuthError.authFailed }
        isVaultLocked = false
    }

    /// Locks the vault — caller must re-authenticate to access private assets.
    public func lockVault() {
        isVaultLocked = true
    }

    // MARK: - Vault passthrough

    public func save(_ asset: Asset, data: Data) async throws {
        try await vault.save(asset, data: data)
    }

    public func saveVideoFile(_ asset: Asset, sourceURL: URL) async throws {
        try await vault.saveVideoFile(asset, sourceURL: sourceURL)
    }

    public func saveAudioFile(_ asset: Asset, sourceURL: URL) async throws {
        try await vault.saveAudioFile(asset, sourceURL: sourceURL)
    }

    public func saveLiveMovieFile(_ asset: Asset, sourceURL: URL) async throws {
        try await vault.saveLiveMovieFile(asset, sourceURL: sourceURL)
    }

    public func saveDerivative(_ derivative: DerivativeAsset, data: Data, sourceAssetID: UUID) async throws {
        try await vault.saveDerivative(derivative, data: data, sourceAssetID: sourceAssetID)
    }

    public func loadPrimary(_ assetID: UUID) async throws -> (Asset, Data) {
        try await vault.loadPrimary(assetID)
    }

    public func deleteDerivative(for assetID: UUID) async throws {
        try await vault.deleteDerivative(for: assetID)
    }

    public func delete(_ assetID: UUID) async throws {
        try await vault.delete(assetID)
    }

    public func query(_ query: VaultQuery) async throws -> [Asset] {
        try await vault.query(query)
    }

    public func exportToPhotoLibrary(assetID: UUID) async throws {
        try await vault.exportToPhotoLibrary(assetID)
    }

    // MARK: - v0.8: Move to Vault

    /// Encrypts the asset file (AES-GCM) and marks it private in both the file sidecar and GRDB.
    /// Posts `niftyVaultChanged` so the journal feed refreshes.
    public func moveToVault(assetID: UUID) async throws {
        try await vault.moveToVault(assetID: assetID)
        try await graph.markAssetPrivate(assetID: assetID, isPrivate: true)
        await MainActor.run {
            NotificationCenter.default.post(name: .niftyVaultChanged, object: nil)
        }
    }
}

// MARK: - VaultAuthError

public enum VaultAuthError: LocalizedError {
    case biometryNotAvailable
    case authFailed

    public var errorDescription: String? {
        switch self {
        case .biometryNotAvailable:
            return "Face ID is not available or not enrolled on this device."
        case .authFailed:
            return "Authentication failed. Please try again."
        }
    }
}
