// NiftyCore/Sources/Domain/UseCases/ShareMomentUseCase.swift

import Foundation

public final class ShareMomentUseCase: Sendable {
    private let vault: VaultManager
    private let config: AppConfig

    public init(vault: VaultManager, config: AppConfig) {
        self.vault = vault
        self.config = config
    }

    public func exportToPhotoLibrary(assetID: UUID) async throws {
        try await vault.exportToPhotoLibrary(assetID: assetID)
    }
}
