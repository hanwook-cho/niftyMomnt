// NiftyData/Tests/StubVibeClassifierTests.swift
// Piqd v0.4 — confirms the stub conforms to VibeClassifying and behaves as documented.

import XCTest
import NiftyCore
@testable import NiftyData

final class StubVibeClassifierTests: XCTestCase {

    func test_defaultSignalIsQuiet() {
        let c = StubVibeClassifier()
        XCTAssertEqual(c.currentSignal(), .quiet)
    }

    func test_emit_updatesCurrentSignal() {
        let c = StubVibeClassifier()
        c.emit(.social)
        XCTAssertEqual(c.currentSignal(), .social)
    }

    func test_signalsStream_replaysCurrentToNewSubscribers() async {
        let c = StubVibeClassifier()
        c.emit(.social)
        var iterator = c.signals.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, .social)
    }

    func test_signalsStream_yieldsEmissionsAfterSubscribe() async {
        let c = StubVibeClassifier()
        let stream = c.signals
        let task = Task { () -> [VibeSignal] in
            var out: [VibeSignal] = []
            for await s in stream {
                out.append(s)
                if out.count == 3 { break }
            }
            return out
        }
        // Allow subscriber to observe initial replay.
        try? await Task.sleep(nanoseconds: 10_000_000)
        c.emit(.neutral)
        c.emit(.social)
        let observed = await task.value
        XCTAssertEqual(observed, [.quiet, .neutral, .social])
    }

    func test_startStop_areIdempotent() {
        let c = StubVibeClassifier()
        c.start()
        c.start()
        c.stop()
        c.stop()
        XCTAssertEqual(c.currentSignal(), .quiet)
    }
}
