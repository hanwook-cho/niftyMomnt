// Apps/niftyMomnt/AppConfig+Full.swift

import NiftyCore

extension AppConfig {
    static let full = AppConfig(
        appVariant: .full,
        assetTypes: .all,
        aiModes: .full,
        features: .all,  // includes .photoFix + .soundStamp
        sharing: SharingConfig(maxCircleSize: 10, labEnabled: true),
        storage: StorageConfig(smartArchiveEnabled: true, iCloudSyncEnabled: true)
    )
}
