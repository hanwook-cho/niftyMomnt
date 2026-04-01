// NiftyCore/Sources/Domain/Protocols/SoundStampPipelineProtocol.swift

import Combine
import Foundation

public protocol SoundStampPipelineProtocol: AnyObject, Sendable {
    /// Start the always-on pre-roll buffer.
    /// Called on entry to Still mode when soundStamp feature is enabled.
    func activatePreRoll() async throws

    /// Stop pre-roll buffer and release microphone session.
    /// Called on mode switch, app background, or feature toggle-off.
    func deactivatePreRoll() async

    /// Capture the 1.0s post-shutter buffer, combine with 0.5s pre-roll,
    /// run acoustic classification, write tags to graph, release buffer.
    /// Returns acoustic tags written. Fire-and-forget safe.
    func analyzeAndTag(assetID: UUID) async throws -> [AcousticTag]

    /// Current activation state (for UI indicator binding).
    var isActive: AnyPublisher<Bool, Never> { get }
}
