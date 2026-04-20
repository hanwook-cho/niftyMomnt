// Apps/Piqd/Piqd/AppConfig+Piqd.swift
// Piqd AppConfig variants. See piqd_SRS_v1.0.md §2.
// v0.1 = Snap Still only; all other Piqd capabilities gated off for incremental rollout.

import NiftyCore

extension AppConfig {

    /// Full Piqd capability set — SRS §2.1. This is the v1.0 target.
    /// Interim versions below mask features off until they are implemented and verified.
    static let piqd = AppConfig(
        appVariant: .piqd,
        assetTypes: .piqdAll,
        aiModes: .onDevice,
        features: [.snapMode, .rollMode, .trustedSharing, .sequenceCapture,
                   .p2pSharing, .iCloudRollPackage],
        sharing: SharingConfig(
            maxCircleSize: 10,
            labEnabled: false,
            ephemeralPolicy: .snap
        ),
        storage: StorageConfig(
            smartArchiveEnabled: true,
            iCloudSyncEnabled: true,
            clipQuality: ClipQualityConfig(
                maxResolution: .uhd4K,
                maxFrameRate: 60,
                proOnlyHighFPS: true
            )
        )
    )

    /// v0.1 — Snap Still only. No mode switch, no sharing, no Sequence / Clip / Dual,
    /// no grain, no Roll Mode, no drafts tray. Validates NiftyCore wiring + new Piqd Xcode target.
    /// See piqd_interim_v0.1_plan.md.
    static let piqd_v0_1 = AppConfig(
        appVariant: .piqd,
        assetTypes: .still,
        aiModes: .onDevice,
        features: [.snapMode],
        sharing: SharingConfig(maxCircleSize: 0, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )

    /// v0.2 — Mode System. Adds Roll Mode to v0.1: long-hold mode pill + confirmation sheet,
    /// grain overlay in Roll viewfinder, 24-shot Roll counter, per-mode aspect ratio default
    /// (Snap 9:16 / Roll 4:3), HEIF vault writes. Still Sequence / Clip / Dual / sharing /
    /// drafts all gated off. See piqd_interim_v0.2_plan.md.
    static let piqd_v0_2 = AppConfig(
        appVariant: .piqd,
        assetTypes: .still,
        aiModes: .onDevice,
        features: [.snapMode, .rollMode],
        sharing: SharingConfig(maxCircleSize: 0, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )
}
