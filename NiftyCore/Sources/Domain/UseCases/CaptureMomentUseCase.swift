// NiftyCore/Sources/Domain/UseCases/CaptureMomentUseCase.swift
// @MainActor — orchestrates @MainActor-isolated engine and vault dependencies.

import Foundation

@MainActor
public final class CaptureMomentUseCase {
    private let engine: any CaptureEngineProtocol
    private let vault: VaultManager
    private let indexing: IndexingEngine

    public init(engine: any CaptureEngineProtocol, vault: VaultManager, indexing: IndexingEngine) {
        self.engine = engine
        self.vault = vault
        self.indexing = indexing
    }

    /// Starts the capture session for live preview without capturing an asset.
    /// Call this when the capture UI appears; pair with stopPreview() on disappear.
    public func startPreview(mode: CaptureMode, config: AppConfig) async throws {
        try await engine.startSession(mode: mode, config: config)
    }

    /// Stops the running session. Call on capture UI disappear or when Journal opens.
    public func stopPreview() async {
        await engine.stopSession()
    }

    public func execute(mode: CaptureMode, config: AppConfig) async throws -> Asset {
        try await engine.startSession(mode: mode, config: config)
        let asset = try await engine.captureAsset()
        // Vault save and indexing scheduled via engine/vault pipeline
        return asset
    }
}
