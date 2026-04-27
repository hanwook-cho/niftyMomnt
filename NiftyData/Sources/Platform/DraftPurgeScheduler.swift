// NiftyData/Sources/Platform/DraftPurgeScheduler.swift
// Piqd v0.5 — foreground sweep that reconciles the drafts table with the Snap
// vault. Triggered on app launch, on `willEnterForegroundNotification`, and on
// the 60s active timer (the timer is owned by the Apps/Piqd `DraftsStoreBindings`
// — this actor is purely the swept-state contract).
//
// Scope: drafts row + Snap vault bytes. GraphRepository cascade is deferred to
// v0.6 because Snap captures may share Moments with other assets via the
// existing `CaptureMomentUseCase` merge logic; per-asset graph removal needs
// a new `GraphProtocol.deleteAsset(id:)` method and is out of v0.5 scope.
// Stale graph rows pointing at purged vault bytes degrade gracefully —
// `VaultRepository.load(_:)` throws `.notFound`.

import Foundation
import NiftyCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "DraftPurgeScheduler")

/// Vault seam used by the scheduler. Production: `VaultRepository`. Tests: a
/// minimal mock that records the call set.
public protocol DraftPurgeVault: Sendable {
    func purgeSnapAsset(id: UUID) async throws
}

extension VaultRepository: DraftPurgeVault {}

public actor DraftPurgeScheduler {

    private let drafts: any DraftsRepositoryProtocol
    private let vault: any DraftPurgeVault
    private let now: NowProvider

    /// Stats from the most recent `sweep(now:)` — useful for the dev settings
    /// UI and for asserting idempotency in tests.
    public struct SweepResult: Equatable, Sendable {
        public let purgedAssetIDs: [UUID]
        public let vaultFailures: [UUID]
    }

    public init(
        drafts: any DraftsRepositoryProtocol,
        vault: any DraftPurgeVault,
        now: NowProvider = SystemNowProvider()
    ) {
        self.drafts = drafts
        self.vault = vault
        self.now = now
    }

    /// Idempotent sweep. Pulls expired draft rows from the table, removes them,
    /// then cascades to Snap vault bytes. Vault errors per item are recorded
    /// but do not abort the sweep — a single corrupt asset must not strand the
    /// rest of the queue.
    @discardableResult
    public func sweep(now overrideNow: Date? = nil) async throws -> SweepResult {
        let resolvedNow = overrideNow ?? now.now()
        let purgedAssetIDs = try await drafts.purgeExpired(now: resolvedNow)

        guard !purgedAssetIDs.isEmpty else {
            return SweepResult(purgedAssetIDs: [], vaultFailures: [])
        }
        log.debug("sweep — purging \(purgedAssetIDs.count) expired draft(s)")

        var failures: [UUID] = []
        for assetID in purgedAssetIDs {
            do {
                try await vault.purgeSnapAsset(id: assetID)
            } catch {
                log.error("sweep — vault purge failed for \(assetID.uuidString): \(error)")
                failures.append(assetID)
            }
        }
        return SweepResult(purgedAssetIDs: purgedAssetIDs, vaultFailures: failures)
    }
}
