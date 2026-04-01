// NiftyData/Sources/Platform/SpeechAdapter.swift
// On-device speech recognition for Echo assets.

import Foundation
import NiftyCore
import Speech

public final class SpeechAdapter: Sendable {
    public init() {}

    public func transcribe(audioData: Data) async throws -> String {
        // TODO: SFSpeechRecognizer with on-device recognition
        return ""
    }
}
