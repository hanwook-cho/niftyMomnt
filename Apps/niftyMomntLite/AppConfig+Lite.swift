// Apps/niftyMomntLite/AppConfig+Lite.swift

import NiftyCore

extension AppConfig {
    static let lite = AppConfig(
        appVariant: .lite,
        assetTypes: .basic,         // Still + Clip only
        aiModes: [.onDevice],
        features: [.rollMode, .widgetKit],  // no photoFix, no soundStamp
        sharing: SharingConfig(maxCircleSize: 5, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )
}
