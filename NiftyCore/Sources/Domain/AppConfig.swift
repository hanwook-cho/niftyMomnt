// NiftyCore/Sources/Domain/AppConfig.swift
// Zero platform imports — pure Swift.

import Foundation

// MARK: - AppVariant

public enum AppVariant: String, Sendable {
    case full
    case lite
    case piqd
}

// MARK: - AssetTypeSet

public struct AssetTypeSet: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let still       = AssetTypeSet(rawValue: 1 << 0)
    public static let live        = AssetTypeSet(rawValue: 1 << 1)
    public static let clip        = AssetTypeSet(rawValue: 1 << 2)
    public static let echo        = AssetTypeSet(rawValue: 1 << 3)
    public static let atmosphere  = AssetTypeSet(rawValue: 1 << 4)
    // Piqd additions — SRS §3.1
    public static let sequence    = AssetTypeSet(rawValue: 1 << 5)
    public static let movingStill = AssetTypeSet(rawValue: 1 << 6)
    public static let dual        = AssetTypeSet(rawValue: 1 << 7)

    /// Legacy niftyMomnt capture types. Preserved for AppConfig.v0_9 back-compat.
    public static let all: AssetTypeSet = [.still, .live, .clip, .echo, .atmosphere]
    public static let basic: AssetTypeSet = [.still, .clip]
    /// Piqd capture types — SRS §2.1.
    public static let piqdAll: AssetTypeSet = [.still, .live, .clip, .sequence, .movingStill, .dual]
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
    public static let l4c             = FeatureSet(rawValue: 1 << 9)  // Life Four Cuts v0.3.5
    public static let dualCamera      = FeatureSet(rawValue: 1 << 10) // v0.9 AVCaptureMultiCamSession
    // Piqd additions — SRS §2.2
    public static let snapMode          = FeatureSet(rawValue: 1 << 11)
    public static let sequenceCapture   = FeatureSet(rawValue: 1 << 12)
    public static let p2pSharing        = FeatureSet(rawValue: 1 << 13)
    public static let iCloudRollPackage = FeatureSet(rawValue: 1 << 14)
    public static let preShutterChrome  = FeatureSet(rawValue: 1 << 15) // Piqd v0.4 — Layer 1 chrome
    public static let draftsTray        = FeatureSet(rawValue: 1 << 16) // Piqd v0.5 — Drafts tray + iOS share hand-off

    public static let all: FeatureSet = [
        .rollMode, .nudgeEngine, .moodMap, .liveActivity,
        .journalSuggest, .trustedSharing, .widgetKit, .photoFix, .soundStamp, .l4c, .dualCamera
    ]
}

// MARK: - SharingConfig

public struct SharingConfig: Sendable {
    public let maxCircleSize: Int
    public let labEnabled: Bool
    /// Piqd ephemeral policy (nil for niftyMomnt variants).
    public let ephemeralPolicy: EphemeralPolicy?

    public init(maxCircleSize: Int, labEnabled: Bool, ephemeralPolicy: EphemeralPolicy? = nil) {
        self.maxCircleSize = maxCircleSize
        self.labEnabled = labEnabled
        self.ephemeralPolicy = ephemeralPolicy
    }
}

// MARK: - StorageConfig

public struct StorageConfig: Sendable {
    public let smartArchiveEnabled: Bool
    public let iCloudSyncEnabled: Bool
    /// Piqd clip quality ceiling (nil for niftyMomnt variants).
    public let clipQuality: ClipQualityConfig?

    public init(smartArchiveEnabled: Bool, iCloudSyncEnabled: Bool, clipQuality: ClipQualityConfig? = nil) {
        self.smartArchiveEnabled = smartArchiveEnabled
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.clipQuality = clipQuality
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

    /// Subdirectory under `Documents/` for this app variant's vault and GRDB files.
    /// Returns `nil` for the legacy niftyMomnt flat layout (`Documents/assets/`, `Documents/graph.sqlite`).
    /// Piqd uses `"piqd"` → `Documents/piqd/assets/`, `Documents/piqd/graph.sqlite`.
    public var namespace: String? {
        switch appVariant {
        case .piqd: return "piqd"
        case .full, .lite: return nil
        }
    }
}
