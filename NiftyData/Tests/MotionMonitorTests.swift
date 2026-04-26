// NiftyData/Tests/MotionMonitorTests.swift
// Piqd v0.4 — exercises the rate-mode + publish/replay surface. CMMotionManager itself
// is not driven here (no deviceMotion delivery in XCTest hosts); we use the `emit(_:)`
// seam to drive samples and assert the contract that `LevelIndicatorView` depends on.

import XCTest
import NiftyCore
@testable import NiftyData

final class MotionMonitorTests: XCTestCase {

    func test_defaultRate_isIdle() {
        let m = MotionMonitor()
        XCTAssertEqual(m.currentRate(), .idle)
    }

    func test_setRecordingTrue_switchesToRecordingRate() {
        let m = MotionMonitor()
        m.setRecording(true)
        XCTAssertEqual(m.currentRate(), .recording)
        m.setRecording(false)
        XCTAssertEqual(m.currentRate(), .idle)
    }

    func test_updateRate_intervals() {
        XCTAssertEqual(MotionMonitor.UpdateRate.idle.intervalSeconds,      1.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(MotionMonitor.UpdateRate.recording.intervalSeconds, 1.0 / 5.0,  accuracy: 1e-9)
    }

    func test_emit_updatesLatestSample() {
        let m = MotionMonitor()
        let s = MotionSample(rollDegrees: 5.5, timestamp: Date())
        m.emit(s)
        XCTAssertEqual(m.currentSample(), s)
    }

    func test_samples_replaysLatestToNewSubscribers() async {
        let m = MotionMonitor()
        let seed = MotionSample(rollDegrees: 7.0, timestamp: Date())
        m.emit(seed)
        var iterator = m.samples.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, seed)
    }

    func test_samples_deliversEmissionsAfterSubscribe() async {
        let m = MotionMonitor()
        let stream = m.samples
        let task = Task { () -> [Double] in
            var out: [Double] = []
            for await s in stream {
                out.append(s.rollDegrees)
                if out.count == 3 { break }
            }
            return out
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        m.emit(MotionSample(rollDegrees: -1.0, timestamp: Date()))
        m.emit(MotionSample(rollDegrees:  4.0, timestamp: Date()))
        m.emit(MotionSample(rollDegrees:  9.0, timestamp: Date()))
        let observed = await task.value
        XCTAssertEqual(observed, [-1.0, 4.0, 9.0])
    }

    func test_setRecording_idempotentWhenRateUnchanged() {
        let m = MotionMonitor()
        m.setRecording(false) // already idle
        XCTAssertEqual(m.currentRate(), .idle)
        m.setRecording(true)
        m.setRecording(true)  // already recording
        XCTAssertEqual(m.currentRate(), .recording)
    }
}
