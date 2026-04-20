// NowProvider.swift
// Clock abstraction so tests and dev-tools can control "now" without swizzling Date().
// Introduced in Piqd v0.2 for RollCounterRepository day-boundary logic and the 5-tap
// dev-menu discovery gesture on the mode pill.

import Foundation

public protocol NowProvider: Sendable {
    func now() -> Date
}

public struct SystemNowProvider: NowProvider {
    public init() {}
    public func now() -> Date { Date() }
}

/// Test/dev helper. Returns a fixed Date until `advance(by:)` or `set(_:)` is called.
public final class MockNowProvider: NowProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ initial: Date = Date(timeIntervalSince1970: 0)) {
        self.current = initial
    }

    public func now() -> Date {
        lock.withLock { current }
    }

    public func set(_ date: Date) {
        lock.withLock { current = date }
    }

    public func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}
