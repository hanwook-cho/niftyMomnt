// NiftyData/Sources/Platform/SoundStampAdapter.swift
// Wraps AVAudioSession + SoundAnalysis.
// PRIVACY: buffer never written to disk. Max in-memory lifetime ~500ms.

import AVFoundation
import Combine
import Foundation
import NiftyCore
import SoundAnalysis

public actor SoundStampAdapter: SoundStampPipelineProtocol {
    nonisolated(unsafe) private let isActiveSubject = CurrentValueSubject<Bool, Never>(false)

    public init(config: AppConfig) {}

    public nonisolated var isActive: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    public func activatePreRoll() async throws {
        // TODO: AVAudioSession.sharedInstance() activate
        // TODO: start PCM 44.1kHz ring buffer (0.5s)
        isActiveSubject.send(true)
    }

    public func deactivatePreRoll() async {
        // TODO: stop buffer, deactivate AVAudioSession
        isActiveSubject.send(false)
    }

    public func analyzeAndTag(assetID: UUID) async throws -> [AcousticTag] {
        // TODO: capture 1.0s post-shutter, combine with 0.5s pre-roll
        // TODO: SNClassifySoundRequest on in-memory PCM buffer
        // TODO: release buffer immediately after classification
        // NEVER write to disk
        return []
    }
}
