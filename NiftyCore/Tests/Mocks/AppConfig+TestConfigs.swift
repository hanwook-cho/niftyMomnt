// Tests/Mocks/AppConfig+TestConfigs.swift
// Test-only AppConfig presets used in unit tests.

import Foundation
@testable import NiftyCore

extension AppConfig {
    /// Lite config for unit tests — mirrors Apps/niftyMomntLite/AppConfig+Lite.swift
    static let lite = AppConfig(
        appVariant: .lite,
        assetTypes: .basic,         // Still + Clip only
        aiModes: [.onDevice],
        features: [.rollMode, .widgetKit],  // no photoFix, no soundStamp
        sharing: SharingConfig(maxCircleSize: 5, labEnabled: false),
        storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
    )
}
