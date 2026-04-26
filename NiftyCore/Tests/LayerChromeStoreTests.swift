// NiftyCore/Tests/LayerChromeStoreTests.swift
// Piqd v0.4 — exhaustive transition coverage for the layer-chrome state machine.

import XCTest
@testable import NiftyCore

final class LayerChromeStoreTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore(interval: TimeInterval = 3.0) -> (LayerChromeStore, MockNowProvider) {
        let clock = MockNowProvider(t0)
        let store = LayerChromeStore(now: clock, idleInterval: interval)
        return (store, clock)
    }

    // MARK: - Initial state

    func test_initialState_isRest() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.state, .rest)
        XCTAssertNil(store.lastInteractionAt)
    }

    // MARK: - tap()

    func test_tap_fromRest_revealsAndStartsIdleClock() {
        let (store, clock) = makeStore()
        store.tap()
        XCTAssertEqual(store.state, .revealed)
        XCTAssertEqual(store.lastInteractionAt, clock.now())
    }

    func test_tap_fromRevealed_returnsToRestAndClearsClock() {
        let (store, _) = makeStore()
        store.tap()
        store.tap()
        XCTAssertEqual(store.state, .rest)
        XCTAssertNil(store.lastInteractionAt)
    }

    func test_tap_fromFormatSelector_isIgnored() {
        let (store, _) = makeStore()
        store.enterFormatSelector()
        store.tap()
        XCTAssertEqual(store.state, .formatSelector)
    }

    // MARK: - interact()

    func test_interact_fromRevealed_resetsIdleClock() {
        let (store, clock) = makeStore()
        store.tap()                       // -> revealed at t0
        clock.advance(by: 1.5)            // 1.5s elapsed
        store.interact()                  // resets to t0 + 1.5
        XCTAssertEqual(store.lastInteractionAt, clock.now())
    }

    func test_interact_fromRest_isNoOp() {
        let (store, _) = makeStore()
        store.interact()
        XCTAssertEqual(store.state, .rest)
        XCTAssertNil(store.lastInteractionAt)
    }

    func test_interact_fromFormatSelector_isNoOp() {
        let (store, _) = makeStore()
        store.enterFormatSelector()
        store.interact()
        XCTAssertEqual(store.state, .formatSelector)
        XCTAssertNil(store.lastInteractionAt)
    }

    // MARK: - Format selector entry/exit

    func test_enterFormatSelector_pausesIdleClock() {
        let (store, _) = makeStore()
        store.tap()                       // revealed
        store.enterFormatSelector()
        XCTAssertEqual(store.state, .formatSelector)
        XCTAssertNil(store.lastInteractionAt)
    }

    func test_exitFormatSelector_returnsToRevealedWithFreshClock() {
        let (store, clock) = makeStore()
        store.tap()                       // revealed at t0
        clock.advance(by: 2.0)            // 2.0s passed (but we entered selector)
        store.enterFormatSelector()
        clock.advance(by: 5.0)            // selector open for 5s
        store.exitFormatSelector()
        XCTAssertEqual(store.state, .revealed)
        XCTAssertEqual(store.lastInteractionAt, clock.now())
    }

    // MARK: - shouldRetreat / retreat

    func test_shouldRetreat_falseBeforeIdleInterval() {
        let (store, clock) = makeStore(interval: 3.0)
        store.tap()
        clock.advance(by: 2.99)
        XCTAssertFalse(store.shouldRetreat(at: clock.now()))
    }

    func test_shouldRetreat_trueAtIdleInterval() {
        let (store, clock) = makeStore(interval: 3.0)
        store.tap()
        clock.advance(by: 3.0)
        XCTAssertTrue(store.shouldRetreat(at: clock.now()))
    }

    func test_shouldRetreat_falseDuringFormatSelector() {
        let (store, clock) = makeStore(interval: 3.0)
        store.tap()
        store.enterFormatSelector()
        clock.advance(by: 100)
        XCTAssertFalse(store.shouldRetreat(at: clock.now()))
    }

    func test_shouldRetreat_falseAtRest() {
        let (store, clock) = makeStore()
        clock.advance(by: 100)
        XCTAssertFalse(store.shouldRetreat(at: clock.now()))
    }

    func test_retreat_revealedGoesToRest() {
        let (store, _) = makeStore()
        store.tap()
        store.retreat()
        XCTAssertEqual(store.state, .rest)
        XCTAssertNil(store.lastInteractionAt)
    }

    func test_retreat_outsideRevealedIsNoOp() {
        let (store, _) = makeStore()
        store.retreat()
        XCTAssertEqual(store.state, .rest)

        store.enterFormatSelector()
        store.retreat()
        XCTAssertEqual(store.state, .formatSelector)
    }

    // MARK: - Combined / regression

    func test_interactDuringRevealed_extendsIdleWindow() {
        // Plan §6.1.4 — tapping a Layer 1 control mid-window resets the 3s clock.
        let (store, clock) = makeStore(interval: 3.0)
        store.tap()                       // revealed at t0
        clock.advance(by: 2.5)
        store.interact()                  // reset
        clock.advance(by: 2.5)            // total 5s from tap, only 2.5s since interact
        XCTAssertFalse(store.shouldRetreat(at: clock.now()))
        clock.advance(by: 0.6)            // 3.1s since interact
        XCTAssertTrue(store.shouldRetreat(at: clock.now()))
    }

    func test_layer2RoundTrip_resetsIdleWindowFromExit() {
        // Plan §6.1.5 — opening + closing Layer 2 resets the 3s window from dismiss time.
        let (store, clock) = makeStore(interval: 3.0)
        store.tap()                       // revealed at t0
        clock.advance(by: 2.5)
        store.enterFormatSelector()
        clock.advance(by: 10)             // selector idle long
        XCTAssertFalse(store.shouldRetreat(at: clock.now()))
        store.exitFormatSelector()        // back to revealed, clock reset to now
        clock.advance(by: 2.99)
        XCTAssertFalse(store.shouldRetreat(at: clock.now()))
        clock.advance(by: 0.02)
        XCTAssertTrue(store.shouldRetreat(at: clock.now()))
    }
}
