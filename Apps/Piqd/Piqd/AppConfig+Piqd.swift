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

    /// v0.3 — Snap Format Selector. Adds Sequence / Clip / Dual to v0.2's Still-only Snap.
    /// Enables `.sequenceCapture` + `.dualCamera` features and widens `assetTypes` to
    /// [still, sequence, clip, dual]. Roll Mode remains Still-only (Roll Live Photo pinned
    /// to v0.9). Sharing + drafts + iCloud still gated off.
    /// See piqd_interim_v0.3_plan.md.
    static let piqd_v0_3 = AppConfig(
        appVariant: .piqd,
        assetTypes: [.still, .sequence, .clip, .dual],
        aiModes: .onDevice,
        features: [.snapMode, .rollMode, .sequenceCapture, .dualCamera],
        sharing: SharingConfig(maxCircleSize: 0, labEnabled: false),
        storage: StorageConfig(
            smartArchiveEnabled: false,
            iCloudSyncEnabled: false,
            clipQuality: ClipQualityConfig(
                maxResolution: .uhd4K,
                maxFrameRate: 60,
                proOnlyHighFPS: true
            )
        )
    )

    /// v0.4 — Pre-shutter Layer 1 chrome. Adds the layered chrome system + zoom pill,
    /// camera flip, aspect ratio toggle, invisible level, subject guidance, backlight
    /// correction, and vibe hint glyph (stub classifier). No new asset types or capture
    /// formats relative to v0.3. Sharing + drafts + iCloud still gated off.
    /// See piqd_interim_v0.4_plan.md.
    static let piqd_v0_4 = AppConfig(
        appVariant: .piqd,
        assetTypes: [.still, .sequence, .clip, .dual],
        aiModes: .onDevice,
        features: [.snapMode, .rollMode, .sequenceCapture, .dualCamera, .preShutterChrome],
        sharing: SharingConfig(maxCircleSize: 0, labEnabled: false),
        storage: StorageConfig(
            smartArchiveEnabled: false,
            iCloudSyncEnabled: false,
            clipQuality: ClipQualityConfig(
                maxResolution: .uhd4K,
                maxFrameRate: 60,
                proOnlyHighFPS: true
            )
        )
    )

    /// v0.5 — Drafts Tray + iOS share hand-off. Adds the `.draftsTray` flag to v0.4 with no
    /// asset-type or capture-format change. Snap captures land in a 24h-expiry local drafts
    /// table; "save" exports to iOS Photos; "send →" routes to `UIActivityViewController`
    /// (interim until v0.6 Trusted Circle). Roll Mode unaffected.
    /// See piqd_interim_v0.5_plan.md.
    static let piqd_v0_5 = AppConfig(
        appVariant: .piqd,
        assetTypes: [.still, .sequence, .clip, .dual],
        aiModes: .onDevice,
        features: [.snapMode, .rollMode, .sequenceCapture, .dualCamera,
                   .preShutterChrome, .draftsTray],
        sharing: SharingConfig(maxCircleSize: 0, labEnabled: false),
        storage: StorageConfig(
            smartArchiveEnabled: false,
            iCloudSyncEnabled: false,
            clipQuality: ClipQualityConfig(
                maxResolution: .uhd4K,
                maxFrameRate: 60,
                proOnlyHighFPS: true
            )
        )
    )

    /// v0.6 — Trusted Circle foundation. Adds `.trustedCircle` (Curve25519 identity, trusted friends
    /// list, QR + custom-scheme `piqd://invite/<token>` flow) and `.onboarding` (O0–O4 first-launch
    /// flow + first-Roll storage warning) to v0.5. `maxCircleSize` opens to 10 (FR-CIRCLE-01). No
    /// asset-type or capture-format change. P2P transport still deferred — Drafts "send →" stays
    /// on `UIActivityViewController` until v0.7.
    /// See piqd_interim_v0.6_plan.md.
    static let piqd_v0_6 = AppConfig(
        appVariant: .piqd,
        assetTypes: [.still, .sequence, .clip, .dual],
        aiModes: .onDevice,
        features: [.snapMode, .rollMode, .sequenceCapture, .dualCamera,
                   .preShutterChrome, .draftsTray, .trustedCircle, .onboarding],
        sharing: SharingConfig(maxCircleSize: 10, labEnabled: false),
        storage: StorageConfig(
            smartArchiveEnabled: false,
            iCloudSyncEnabled: false,
            clipQuality: ClipQualityConfig(
                maxResolution: .uhd4K,
                maxFrameRate: 60,
                proOnlyHighFPS: true
            )
        )
    )
}
