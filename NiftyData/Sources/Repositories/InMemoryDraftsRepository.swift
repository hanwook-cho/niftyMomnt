// NiftyData/Sources/Repositories/InMemoryDraftsRepository.swift
// Piqd v0.5 — zero-IO `DraftsRepositoryProtocol` for unit tests and the dev-mode
// "fake capture" UI test seam.

import Foundation
import NiftyCore

public actor InMemoryDraftsRepository: DraftsRepositoryProtocol {

    private var items: [DraftItem] = []

    public init() {}

    @discardableResult
    public func insert(_ item: DraftItem) -> Bool {
        guard item.mode == .snap else { return false }
        guard !items.contains(where: { $0.assetID == item.assetID }) else { return false }
        items.append(item)
        return true
    }

    public func all() -> [DraftItem] {
        items.sorted { $0.capturedAt < $1.capturedAt }
    }

    @discardableResult
    public func purgeExpired(now: Date) -> [UUID] {
        var purged: [UUID] = []
        items.removeAll { item in
            if item.expiresAt <= now {
                purged.append(item.assetID)
                return true
            }
            return false
        }
        return purged
    }

    public func remove(assetID: UUID) {
        items.removeAll { $0.assetID == assetID }
    }
}
