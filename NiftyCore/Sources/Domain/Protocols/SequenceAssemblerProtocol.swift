// NiftyCore/Sources/Domain/Protocols/SequenceAssemblerProtocol.swift
// Pure-Swift seam between StoryEngine and the AVFoundation-backed implementation in NiftyData.
// Kept out of StoryEngine's direct dependency graph so NiftyCore remains platform-agnostic.

import Foundation

public protocol SequenceAssemblerProtocol: Sendable {
    /// Compose `frameURLs` (HEIC, in capture order) into a looping 9:16 H.264 MP4 at
    /// `outputURL`. Throws on I/O or encoder failure; callers are expected to delete the
    /// partial output file. Returns the assembled URL + measured duration in seconds.
    func assemble(
        frameURLs: [URL],
        outputURL: URL,
        frameDurationSeconds: Double
    ) async throws -> (url: URL, durationSeconds: Double)
}
