// NiftyCore/Sources/Domain/Models/CaptureActivityStore.swift
// Piqd v0.3 — single source of truth for "is a capture currently in flight?". Consumed by:
//   • ModePill — dims itself + rejects long-hold while capturing (FR-MODE-09)
//   • FormatSelectorView — swipe-up / long-press-from-Still ignored while capturing
//   • ShutterButtonView — drives arc-fill animation for Clip / Dual recordings
//
// Kept deliberately narrow: a balanced Bool toggle with an associated reason for logging.
// Mismatched begin/end calls trip a DEBUG assertion — a leaked "still capturing" state would
// silently brick the mode pill.

import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "CaptureActivity")

public enum CaptureActivityReason: String, Sendable {
    case sequence
    case clip
    case dual
}

@MainActor
@available(iOS 17.0, macOS 14.0, *)
@Observable
public final class CaptureActivityStore {

    public private(set) var isCapturing: Bool = false
    public private(set) var reason: CaptureActivityReason?

    public init() {}

    public func beginCapture(reason: CaptureActivityReason) {
        if isCapturing {
            // Balanced begin/end is a hard invariant — nested captures indicate a caller bug.
            assertionFailure("beginCapture called while already capturing (was=\(self.reason?.rawValue ?? "nil"), new=\(reason.rawValue))")
            log.error("beginCapture called while already capturing — ignoring nested call")
            return
        }
        self.isCapturing = true
        self.reason = reason
        log.debug("beginCapture reason=\(reason.rawValue)")
    }

    public func endCapture() {
        if !isCapturing {
            assertionFailure("endCapture called with no active capture")
            log.error("endCapture called with no active capture — ignoring")
            return
        }
        log.debug("endCapture reason=\(self.reason?.rawValue ?? "?")")
        self.isCapturing = false
        self.reason = nil
    }
}
