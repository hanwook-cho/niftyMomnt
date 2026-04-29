// Apps/Piqd/PiqdTests/FirstRollWarningGateTests.swift
// Piqd v0.6 — `FirstRollWarningGate` logic. Pure UserDefaults gate; no UI.

import XCTest
import NiftyCore
@testable import Piqd

@MainActor
final class FirstRollWarningGateTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "piqd.tests.firstRollWarning"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_snapMode_neverPresentsWarning() {
        let gate = FirstRollWarningGate(defaults: defaults)
        let intercepted = gate.interceptShutterTap(mode: .snap)
        XCTAssertFalse(intercepted)
        XCTAssertFalse(gate.isPresented)
        XCTAssertFalse(gate.hasShown)
    }

    func test_rollMode_firstTap_presentsWarning_andConsumesTap() {
        let gate = FirstRollWarningGate(defaults: defaults)
        let intercepted = gate.interceptShutterTap(mode: .roll)
        XCTAssertTrue(intercepted, "first Roll tap must be consumed")
        XCTAssertTrue(gate.isPresented)
        XCTAssertFalse(gate.hasShown, "flag persists only after acknowledge()")
    }

    func test_rollMode_afterAcknowledge_doesNotRePresent() {
        let gate = FirstRollWarningGate(defaults: defaults)
        _ = gate.interceptShutterTap(mode: .roll)
        gate.acknowledge()
        XCTAssertTrue(gate.hasShown)
        XCTAssertFalse(gate.isPresented)

        let interceptedAgain = gate.interceptShutterTap(mode: .roll)
        XCTAssertFalse(interceptedAgain, "subsequent Roll taps proceed to capture")
        XCTAssertFalse(gate.isPresented)
    }

    func test_acknowledge_persistsAcrossNewGateInstances() {
        let gate1 = FirstRollWarningGate(defaults: defaults)
        _ = gate1.interceptShutterTap(mode: .roll)
        gate1.acknowledge()

        // Cold-launch parity — fresh instance, same defaults.
        let gate2 = FirstRollWarningGate(defaults: defaults)
        XCTAssertTrue(gate2.hasShown)
        let intercepted = gate2.interceptShutterTap(mode: .roll)
        XCTAssertFalse(intercepted)
    }

    func test_forceShow_resetsPersistedFlag() {
        let gate1 = FirstRollWarningGate(defaults: defaults)
        _ = gate1.interceptShutterTap(mode: .roll)
        gate1.acknowledge()
        XCTAssertTrue(gate1.hasShown)

        let gate2 = FirstRollWarningGate(defaults: defaults, forceShow: true)
        XCTAssertFalse(gate2.hasShown)
        let intercepted = gate2.interceptShutterTap(mode: .roll)
        XCTAssertTrue(intercepted)
    }
}
