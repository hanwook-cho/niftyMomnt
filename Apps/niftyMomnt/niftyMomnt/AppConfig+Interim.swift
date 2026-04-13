// Apps/niftyMomnt/AppConfig+Interim.swift
// Interim version configs for incremental v0.1 → v0.9 verification.
// Each config gates only the features in scope for that version.

import NiftyCore

extension AppConfig {

    /// v0.1 — Minimum viable capture-to-share.
    /// Still only · Mode-0 (VNClassifyImageRequest) · No SoundStamp / Fix / Presets / Nudge.
    static let v0_1 = AppConfig(
        appVariant: .full,
        assetTypes: .still,
        aiModes: .onDevice,
        features: [],
        sharing: SharingConfig(maxCircleSize: 1, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.2 — Adds ambient metadata harvesting + chromatic palette.
    static let v0_2 = AppConfig(
        appVariant: .full,
        assetTypes: .still,
        aiModes: .onDevice,
        features: [],
        sharing: SharingConfig(maxCircleSize: 1, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.3.5 — Adds Life Four Cuts (photo booth mode).
    static let v0_3_5 = AppConfig(
        appVariant: .full,
        assetTypes: .all,
        aiModes: .onDevice,
        features: .l4c,
        sharing: SharingConfig(maxCircleSize: 1, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.3 — All 5 asset types enabled.
    static let v0_3 = AppConfig(
        appVariant: .full,
        assetTypes: .all,
        aiModes: .onDevice,
        features: [],
        sharing: SharingConfig(maxCircleSize: 1, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.4 — Adds Roll Mode. Carries forward .l4c from v0.3.5.
    static let v0_4 = AppConfig(
        appVariant: .full,
        assetTypes: .all,
        aiModes: .onDevice,
        features: [.l4c, .rollMode],
        sharing: SharingConfig(maxCircleSize: 1, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.5 — Adds Sound Stamp. Carries forward .l4c + .rollMode.
    static let v0_5 = AppConfig(
        appVariant: .full,
        assetTypes: .all,
        aiModes: .onDevice,
        features: [.l4c, .rollMode, .soundStamp],
        sharing: SharingConfig(maxCircleSize: 1, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.6 — Adds Nudge Engine.
    static let v0_6 = AppConfig(
        appVariant: .full,
        assetTypes: .all,
        aiModes: .onDevice,
        features: [.l4c, .rollMode, .soundStamp, .nudgeEngine],
        sharing: SharingConfig(maxCircleSize: 1, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.7 — Adds Story Engine + Reel Assembler.
    static let v0_7 = AppConfig(
        appVariant: .full,
        assetTypes: .all,
        aiModes: .onDevice,
        features: [.l4c, .rollMode, .soundStamp, .nudgeEngine, .journalSuggest],
        sharing: SharingConfig(maxCircleSize: 5, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.8 — Adds Private Vault + Face ID.
    static let v0_8 = AppConfig(
        appVariant: .full,
        assetTypes: .all,
        aiModes: .onDevice,
        features: [.l4c, .rollMode, .soundStamp, .nudgeEngine, .journalSuggest, .trustedSharing],
        sharing: SharingConfig(maxCircleSize: 5, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.9 — Adds Enhanced AI (Lab Mode) + Photo Fix.
    static let v0_9 = AppConfig(
        appVariant: .full,
        assetTypes: .all,
        aiModes: [.onDevice, .enhancedAI, .lab],
        features: [.l4c, .rollMode, .soundStamp, .nudgeEngine, .trustedSharing, .journalSuggest, .photoFix],
        sharing: SharingConfig(maxCircleSize: 10, labEnabled: true),
        storage: StorageConfig(smartArchiveEnabled: true, iCloudSyncEnabled: false)
    )
}
