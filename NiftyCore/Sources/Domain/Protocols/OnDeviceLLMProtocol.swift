// NiftyCore/Sources/Domain/Protocols/OnDeviceLLMProtocol.swift
// Zero platform imports — pure Swift domain protocol.
//
// Concrete implementation: NiftyData/FoundationModelAdapter (iOS 26+ only).
// Anything that needs on-device LLM inference depends on this protocol so NiftyCore
// remains decoupled from the FoundationModels system framework.

import Foundation

/// Describes a single on-device LLM inference capability.
public protocol OnDeviceLLMProtocol: AnyObject, Sendable {
    /// `true` when the underlying model is reachable on the current device / OS version.
    /// Callers must check this before calling `respond(to:)` and gracefully degrade when false.
    var isAvailable: Bool { get }

    /// Sends `prompt` to the on-device model and returns the model's text response.
    ///
    /// - Throws: `OnDeviceLLMError.unavailable` if `isAvailable == false`.
    /// - Throws: `OnDeviceLLMError.requiresiOS26` on iOS < 26.
    /// - Throws: Any inference error propagated from the underlying framework.
    func respond(to prompt: String) async throws -> String
}

// MARK: - Errors

public enum OnDeviceLLMError: Error, LocalizedError {
    /// On-device LLM is not available on this device or OS version.
    case unavailable
    /// The caller is on iOS < 26 where FoundationModels is not available.
    case requiresiOS26

    public var errorDescription: String? {
        switch self {
        case .unavailable:    return "On-device LLM is not available on this device."
        case .requiresiOS26:  return "AI captions require iOS 26 or later."
        }
    }
}
