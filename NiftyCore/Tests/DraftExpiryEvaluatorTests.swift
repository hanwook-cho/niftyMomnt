// NiftyCore/Tests/DraftExpiryEvaluatorTests.swift
// Piqd v0.5 — pure threshold logic for the drafts tray.
// Locks the four FR-SNAP-DRAFT-05 thresholds + the badge urgency derivation.

import XCTest
@testable import NiftyCore

final class DraftExpiryEvaluatorTests: XCTestCase {

    // Anchor `capturedAt` at a fixed instant; we vary `now` against it.
    private let captured = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - Per-row state

    func test_freshlyCaptured_isHidden() {
        // 0h elapsed → 24h remaining → above 3h → hidden
        let now = captured.addingTimeInterval(60) // 1 minute later
        let state = DraftExpiryEvaluator.evaluate(capturedAt: captured, now: now)
        XCTAssertEqual(state, .hidden(remaining: 24 * 3600 - 60))
    }

    func test_atThreeHoursRemaining_isNormal_boundaryInclusive() {
        // PRD: >3h → hidden, 1h ≤ x ≤ 3h → normal. So exactly 3h is .normal.
        let now = captured.addingTimeInterval(21 * 3600) // 21h elapsed → 3h left
        let state = DraftExpiryEvaluator.evaluate(capturedAt: captured, now: now)
        XCTAssertEqual(state, .normal(remaining: 3 * 3600))
    }

    func test_justAboveThreeHours_isHidden() {
        // 3h + 1s remaining → .hidden
        let now = captured.addingTimeInterval(21 * 3600 - 1)
        let state = DraftExpiryEvaluator.evaluate(capturedAt: captured, now: now)
        XCTAssertEqual(state, .hidden(remaining: 3 * 3600 + 1))
    }

    func test_atOneHourRemaining_isAmber_boundaryExclusive() {
        // remaining == 1h exactly → .amber (spec says <1h is amber; we use < here so
        // exactly 1h is .normal). Verify both sides.
        let now = captured.addingTimeInterval(23 * 3600)
        XCTAssertEqual(DraftExpiryEvaluator.evaluate(capturedAt: captured, now: now),
                       .normal(remaining: 3600))

        let nowJustBelow = captured.addingTimeInterval(23 * 3600 + 1)
        XCTAssertEqual(DraftExpiryEvaluator.evaluate(capturedAt: captured, now: nowJustBelow),
                       .amber(remaining: 3600 - 1))
    }

    func test_atFifteenMinutesRemaining_isAmber_boundaryExclusive() {
        // remaining == 15min exactly → .amber (spec says <15min is red).
        let now = captured.addingTimeInterval(24 * 3600 - 15 * 60)
        XCTAssertEqual(DraftExpiryEvaluator.evaluate(capturedAt: captured, now: now),
                       .amber(remaining: 15 * 60))

        let nowJustBelow = captured.addingTimeInterval(24 * 3600 - 15 * 60 + 1)
        XCTAssertEqual(DraftExpiryEvaluator.evaluate(capturedAt: captured, now: nowJustBelow),
                       .red(remaining: 15 * 60 - 1))
    }

    func test_oneSecondAfterCeiling_isExpired() {
        let now = captured.addingTimeInterval(24 * 3600 + 1)
        XCTAssertEqual(DraftExpiryEvaluator.evaluate(capturedAt: captured, now: now), .expired)
    }

    func test_exactlyAtCeiling_isExpired_boundaryInclusive() {
        // remaining <= 0 → .expired (zero-second window doesn't keep the row alive)
        let now = captured.addingTimeInterval(24 * 3600)
        XCTAssertEqual(DraftExpiryEvaluator.evaluate(capturedAt: captured, now: now), .expired)
    }

    func test_customCeilingRespected() {
        // 1h ceiling, 30min elapsed → 30min remaining → .amber
        let now = captured.addingTimeInterval(30 * 60)
        let state = DraftExpiryEvaluator.evaluate(capturedAt: captured, now: now, hardCeilingHours: 1)
        XCTAssertEqual(state, .amber(remaining: 30 * 60))
    }

    // MARK: - Badge state aggregation

    func test_badge_emptyList_isHidden() {
        XCTAssertEqual(DraftExpiryEvaluator.badgeState(items: [], now: captured), .hidden)
    }

    func test_badge_allFreshItems_isNormal() {
        let items = [
            DraftItem(assetID: UUID(), assetType: .still,    capturedAt: captured),
            DraftItem(assetID: UUID(), assetType: .sequence, capturedAt: captured),
        ]
        let now = captured.addingTimeInterval(60)
        XCTAssertEqual(DraftExpiryEvaluator.badgeState(items: items, now: now), .normal(count: 2))
    }

    func test_badge_anyItemUnderOneHour_promotesToUrgent() {
        // One fresh, one at 30min remaining → urgent.
        let urgent = DraftItem(assetID: UUID(), assetType: .still,
                               capturedAt: captured.addingTimeInterval(-(23 * 3600 + 30 * 60)))
        let fresh  = DraftItem(assetID: UUID(), assetType: .clip,
                               capturedAt: captured)
        let state = DraftExpiryEvaluator.badgeState(items: [urgent, fresh], now: captured)
        XCTAssertEqual(state, .urgent(count: 2))
    }

    func test_badge_excludesExpiredFromCount() {
        // Expired items don't appear in the badge — caller will purge separately.
        let stale = DraftItem(assetID: UUID(), assetType: .still,
                              capturedAt: captured.addingTimeInterval(-25 * 3600))
        let alive = DraftItem(assetID: UUID(), assetType: .clip, capturedAt: captured)
        XCTAssertEqual(DraftExpiryEvaluator.badgeState(items: [stale, alive], now: captured),
                       .normal(count: 1))
    }

    func test_badge_allExpired_isHidden() {
        let stale = DraftItem(assetID: UUID(), assetType: .still,
                              capturedAt: captured.addingTimeInterval(-25 * 3600))
        XCTAssertEqual(DraftExpiryEvaluator.badgeState(items: [stale], now: captured), .hidden)
    }

    // MARK: - DraftItem invariants

    func test_draftItem_expiresAt_matchesCeiling() {
        let item = DraftItem(assetID: UUID(), assetType: .still, capturedAt: captured)
        XCTAssertEqual(item.expiresAt, captured.addingTimeInterval(24 * 3600))
    }

    func test_draftItem_defaultsToSnapModeAndTwentyFourHourCeiling() {
        let item = DraftItem(assetID: UUID(), assetType: .still, capturedAt: captured)
        XCTAssertEqual(item.mode, .snap)
        XCTAssertEqual(item.hardCeilingHours, 24)
    }
}
