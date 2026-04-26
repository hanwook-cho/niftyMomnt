// NiftyCore/Tests/AppConfigPiqdTests.swift
// Confirms the Piqd AppConfig variants expose the shape promised by piqd_SRS_v1.0.md §2.
// v0.1 mask locks the feature set to Snap Still only — a regression in this file indicates a
// feature leaked out of the interim plan.

import XCTest
@testable import NiftyCore

final class AppConfigPiqdTests: XCTestCase {

    // MARK: - Full piqd (v1.0 target)

    func test_piqd_full_hasAllPiqdFeatures() {
        let c = piqdFull()
        XCTAssertEqual(c.appVariant, .piqd)
        XCTAssertTrue(c.features.contains(.snapMode))
        XCTAssertTrue(c.features.contains(.rollMode))
        XCTAssertTrue(c.features.contains(.trustedSharing))
        XCTAssertTrue(c.features.contains(.sequenceCapture))
        XCTAssertTrue(c.features.contains(.p2pSharing))
        XCTAssertTrue(c.features.contains(.iCloudRollPackage))
    }

    func test_piqd_full_hasPiqdAllAssetTypes() {
        let c = piqdFull()
        XCTAssertTrue(c.assetTypes.contains(.still))
        XCTAssertTrue(c.assetTypes.contains(.clip))
        XCTAssertTrue(c.assetTypes.contains(.sequence))
        XCTAssertTrue(c.assetTypes.contains(.movingStill))
        XCTAssertTrue(c.assetTypes.contains(.dual))
    }

    func test_piqd_full_ephemeralPolicyIsSnap() {
        XCTAssertEqual(piqdFull().sharing.ephemeralPolicy, .snap)
    }

    // MARK: - v0.3 mask — Snap Format Selector

    func test_piqd_v0_3_snapFormatsFeatureFlags() {
        let c = piqdV03()
        XCTAssertTrue(c.features.contains(.snapMode))
        XCTAssertTrue(c.features.contains(.rollMode))
        XCTAssertTrue(c.features.contains(.sequenceCapture))
        XCTAssertTrue(c.features.contains(.dualCamera))
        XCTAssertFalse(c.features.contains(.p2pSharing))
        XCTAssertFalse(c.features.contains(.iCloudRollPackage))
        XCTAssertFalse(c.features.contains(.trustedSharing))
    }

    func test_piqd_v0_3_assetTypesAreFour() {
        let c = piqdV03()
        XCTAssertTrue(c.assetTypes.contains(.still))
        XCTAssertTrue(c.assetTypes.contains(.sequence))
        XCTAssertTrue(c.assetTypes.contains(.clip))
        XCTAssertTrue(c.assetTypes.contains(.dual))
        XCTAssertFalse(c.assetTypes.contains(.live))
        XCTAssertFalse(c.assetTypes.contains(.movingStill))
    }

    func test_piqd_v0_3_isStrictSupersetOf_v0_2() {
        // U12 — v0.3 = v0.2 + exactly { .sequenceCapture, .dualCamera } features and
        // { .sequence, .clip, .dual } asset types. No other bits flipped.
        let v2 = piqdV02()
        let v3 = piqdV03()

        let newFeatures = v3.features.subtracting(v2.features)
        XCTAssertEqual(newFeatures, [.sequenceCapture, .dualCamera])
        XCTAssertTrue(v3.features.isSuperset(of: v2.features))

        let newAssets = v3.assetTypes.subtracting(v2.assetTypes)
        XCTAssertEqual(newAssets, [.sequence, .clip, .dual])
        XCTAssertTrue(v3.assetTypes.isSuperset(of: v2.assetTypes))

        XCTAssertEqual(v3.sharing.maxCircleSize, v2.sharing.maxCircleSize)
        XCTAssertFalse(v3.storage.iCloudSyncEnabled)
        XCTAssertFalse(v3.storage.smartArchiveEnabled)
    }

    func test_piqd_v0_3_clipQualityIsWired() {
        let c = piqdV03()
        XCTAssertNotNil(c.storage.clipQuality)
        XCTAssertEqual(c.storage.clipQuality?.maxFrameRate, 60)
        XCTAssertTrue(c.storage.clipQuality?.proOnlyHighFPS ?? false)
    }

    // MARK: - v0.4 mask — Pre-shutter Layer 1 chrome

    func test_piqd_v0_4_addsPreShutterChromeOnly() {
        // v0.4 = v0.3 + exactly { .preShutterChrome }. No asset-type or capture-format change.
        let v3 = piqdV03()
        let v4 = piqdV04()

        let newFeatures = v4.features.subtracting(v3.features)
        XCTAssertEqual(newFeatures, [.preShutterChrome])
        XCTAssertTrue(v4.features.isSuperset(of: v3.features))

        XCTAssertEqual(v4.assetTypes, v3.assetTypes)
        XCTAssertEqual(v4.sharing.maxCircleSize, v3.sharing.maxCircleSize)
        XCTAssertFalse(v4.storage.iCloudSyncEnabled)
        XCTAssertFalse(v4.storage.smartArchiveEnabled)
    }

    func test_piqd_v0_4_preShutterChromeFlagSet() {
        XCTAssertTrue(piqdV04().features.contains(.preShutterChrome))
        XCTAssertFalse(piqdV03().features.contains(.preShutterChrome))
    }

    // MARK: - v0.1 mask

    func test_piqd_v0_1_onlySnapMode() {
        let c = piqdV01()
        XCTAssertEqual(c.features, [.snapMode])
    }

    func test_piqd_v0_1_stillAssetsOnly() {
        XCTAssertEqual(piqdV01().assetTypes, .still)
    }

    func test_piqd_v0_1_noSharingNoStorage() {
        let c = piqdV01()
        XCTAssertEqual(c.sharing.maxCircleSize, 0)
        XCTAssertFalse(c.storage.smartArchiveEnabled)
        XCTAssertFalse(c.storage.iCloudSyncEnabled)
        XCTAssertNil(c.sharing.ephemeralPolicy)
        XCTAssertNil(c.storage.clipQuality)
    }

    func test_piqd_namespace_isPiqd() {
        XCTAssertEqual(piqdFull().namespace, "piqd")
        XCTAssertEqual(piqdV01().namespace, "piqd")
    }

    func test_legacy_namespace_isNil() {
        // niftyMomnt full/lite keep the flat Documents/ layout via nil namespace.
        let lite = AppConfig.lite
        XCTAssertNil(lite.namespace)
    }

    // MARK: - U3: FeatureSet bit uniqueness

    func test_featureSet_piqdFlags_haveUniqueRawValues() {
        // Every named FeatureSet flag must map to a distinct bit. Regression guard: if someone
        // renumbers flags and collides, this test catches it before runtime config bugs.
        let allFlags: [FeatureSet] = [
            .rollMode, .nudgeEngine, .moodMap, .liveActivity, .journalSuggest,
            .trustedSharing, .widgetKit, .photoFix, .soundStamp, .l4c, .dualCamera,
            .snapMode, .sequenceCapture, .p2pSharing, .iCloudRollPackage, .preShutterChrome
        ]
        let raws = allFlags.map { $0.rawValue }
        XCTAssertEqual(Set(raws).count, raws.count, "FeatureSet raw values must be unique")

        // Piqd flags occupy bits 11–15.
        XCTAssertEqual(FeatureSet.snapMode.rawValue,          1 << 11)
        XCTAssertEqual(FeatureSet.sequenceCapture.rawValue,   1 << 12)
        XCTAssertEqual(FeatureSet.p2pSharing.rawValue,        1 << 13)
        XCTAssertEqual(FeatureSet.iCloudRollPackage.rawValue, 1 << 14)
        XCTAssertEqual(FeatureSet.preShutterChrome.rawValue,  1 << 15)
    }

    // MARK: - Helpers
    // Piqd variants live in the Apps/Piqd target, not in NiftyCore. We reconstruct them locally
    // so this test exercises the config values without a cross-target dependency.

    private func piqdFull() -> AppConfig {
        AppConfig(
            appVariant: .piqd,
            assetTypes: .piqdAll,
            aiModes: .onDevice,
            features: [.snapMode, .rollMode, .trustedSharing, .sequenceCapture,
                       .p2pSharing, .iCloudRollPackage],
            sharing: SharingConfig(maxCircleSize: 10, labEnabled: false, ephemeralPolicy: .snap),
            storage: StorageConfig(
                smartArchiveEnabled: true,
                iCloudSyncEnabled: true,
                clipQuality: ClipQualityConfig(maxResolution: .uhd4K, maxFrameRate: 60, proOnlyHighFPS: true)
            )
        )
    }

    private func piqdV01() -> AppConfig {
        AppConfig(
            appVariant: .piqd,
            assetTypes: .still,
            aiModes: .onDevice,
            features: [.snapMode],
            sharing: SharingConfig(maxCircleSize: 0, labEnabled: false),
            storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
        )
    }

    private func piqdV02() -> AppConfig {
        AppConfig(
            appVariant: .piqd,
            assetTypes: .still,
            aiModes: .onDevice,
            features: [.snapMode, .rollMode],
            sharing: SharingConfig(maxCircleSize: 0, labEnabled: false),
            storage: StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)
        )
    }

    private func piqdV03() -> AppConfig {
        AppConfig(
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
    }

    private func piqdV04() -> AppConfig {
        AppConfig(
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
    }
}
