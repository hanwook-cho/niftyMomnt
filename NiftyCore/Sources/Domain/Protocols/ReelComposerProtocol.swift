// NiftyCore/Sources/Domain/Protocols/ReelComposerProtocol.swift
// Pure Swift — zero platform imports.

import Foundation

/// Assembles a sequence of scored assets into an exported video file.
/// The concrete implementation (AVReelComposer) lives in NiftyData.
public protocol ReelComposerProtocol: AnyObject, Sendable {
    /// Compose a reel from `reelAssets` and return the URL of the exported `.mov`.
    /// The caller is responsible for deleting the file when it is no longer needed.
    func compose(reelAssets: [ReelAsset], momentID: UUID) async throws -> URL
}
