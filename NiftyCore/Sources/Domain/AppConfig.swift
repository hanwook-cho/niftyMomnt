// NiftyCore/Sources/Domain/AppConfig.swift
// Zero platform imports — pure Swift.

import Foundation

// MARK: - AppVariant

public enum AppVariant: String, Sendable {
    case full
    case lite
}

// MARK: - AssetTypeSet

public struct AssetTypeSet: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let still      = AssetTypeSet(rawValue: 1 << 0)
    public static let live       = AssetTypeSet(rawValue: 1 << 1)
    public static let clip       = AssetTypeSet(rawValue: 1 << 2)
    public static let echo       = AssetTypeSet(rawValue: 1 << 3)
    public static let atmosphere = AssetTypeSet(rawValue: 1 << 4)
    public static let all: AssetTypeSet = [.still, .live, .clip, .echo, .atmosphere]
    public static let basic: AssetTypeSet = [.still, .clip]
}

// MARK: - AIModeSet

public struct AIModeSet: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let onDevice    = AIModeSet(rawValue: 1 << 0) // Mode 0 — always on
    public static let enhancedAI  = AIModeSet(rawValue: 1 << 1) // Mode 1 — text only
    public static let lab         = AIModeSet(rawValue: 1 << 2) // Mode 2 — encrypted visual
    public static let full: AIModeSet = [.onDevice, .enhancedAI, .lab]
}

// MARK: - FeatureSet

public struct FeatureSet: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let rollMode        = FeatureSet(rawValue: 1 << 0)
    public static let nudgeEngine     = FeatureSet(rawValue: 1 << 1)
    public static let moodMap         = FeatureSet(rawValue: 1 << 2)
    public static let liveActivity    = FeatureSet(rawValue: 1 << 3)
    public static let journalSuggest  = FeatureSet(rawValue: 1 << 4)
    public static let trustedSharing  = FeatureSet(rawValue: 1 << 5)
    public static let widgetKit       = FeatureSet(rawValue: 1 << 6)
    public static let photoFix        = FeatureSet(rawValue: 1 << 7)  // NEW v1.5
    public static let soundStamp      = FeatureSet(rawValue: 1 << 8)  // NEW v1.5
    public static let all: FeatureSet = [
        .rollMode, .nudgeEngine, .moodMap, .liveActivity,
        .journalSuggest, .trustedSharing, .widgetKit, .photoFix, .soundStamp
    ]
}

// MARK: - SharingConfig

public struct SharingConfig: Sendable {
    public let maxCircleSize: Int
    public let labEnabled: Bool
    public init(maxCircleSize: Int, labEnabled: Bool) {
        self.maxCircleSize = maxCircleSize
        self.labEnabled = labEnabled
    }
}

// MARK: - StorageConfig

public struct StorageConfig: Sendable {
    public let smartArchiveEnabled: Bool
    public let iCloudSyncEnabled: Bool
    public init(smartArchiveEnabled: Bool, iCloudSyncEnabled: Bool) {
        self.smartArchiveEnabled = smartArchiveEnabled
        self.iCloudSyncEnabled = iCloudSyncEnabled
    }
}

// MARK: - AppConfig

public struct AppConfig: Sendable {
    public let appVariant: AppVariant
    public let assetTypes: AssetTypeSet
    public let aiModes: AIModeSet
    public let features: FeatureSet
    public let sharing: SharingConfig
    public let storage: StorageConfig

    public init(
        appVariant: AppVariant,
        assetTypes: AssetTypeSet,
        aiModes: AIModeSet,
        features: FeatureSet,
        sharing: SharingConfig,
        storage: StorageConfig
    ) {
        self.appVariant = appVariant
        self.assetTypes = assetTypes
        self.aiModes = aiModes
        self.features = features
        self.sharing = sharing
        self.storage = storage
    }
}
