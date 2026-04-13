// NiftyData/Sources/Platform/FoundationModelAdapter.swift
// On-device LLM via Apple's FoundationModels framework (iOS 26+).
//
// On iOS < 26:  `isAvailable` returns false; `respond(to:)` throws `OnDeviceLLMError.requiresiOS26`.
// On iOS 26+:  Uses `LanguageModelSession` for on-device inference with no data leaving the device.

import Foundation
import NiftyCore
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "FoundationModelAdapter")

public final class FoundationModelAdapter: OnDeviceLLMProtocol, Sendable {

    public init() {
        if #available(iOS 26, *) {
            log.info("FoundationModelAdapter — initialized; iOS 26+ detected, on-device LLM available")
        } else {
            log.info("FoundationModelAdapter — initialized; iOS < 26, on-device LLM unavailable")
        }
    }

    // MARK: - OnDeviceLLMProtocol

    public var isAvailable: Bool {
        if #available(iOS 26, *) {
            return true
        }
        return false
    }

    /// Sends `prompt` to Apple's on-device language model and returns the response text.
    ///
    /// **Privacy:** Inference runs entirely on-device. No data is transmitted.
    /// **Availability:** Requires iOS 26+. Throws `OnDeviceLLMError.requiresiOS26` on older OS.
    public func respond(to prompt: String) async throws -> String {
        guard isAvailable else {
            log.warning("FoundationModelAdapter.respond — iOS 26+ required; throwing requiresiOS26")
            throw OnDeviceLLMError.requiresiOS26
        }

        if #available(iOS 26, *) {
#if canImport(FoundationModels)
            log.debug("FoundationModelAdapter.respond — prompt.count=\(prompt.count) chars")
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let text = response.content
            log.info("FoundationModelAdapter.respond — response.count=\(text.count) chars")
            return text
#else
            log.error("FoundationModelAdapter.respond — FoundationModels not importable at compile time (SDK too old)")
            throw OnDeviceLLMError.unavailable
#endif
        } else {
            // Defensive — `isAvailable` already returns false below iOS 26.
            throw OnDeviceLLMError.requiresiOS26
        }
    }
}
