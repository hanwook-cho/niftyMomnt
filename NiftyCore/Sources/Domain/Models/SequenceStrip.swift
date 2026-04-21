// NiftyCore/Sources/Domain/Models/SequenceStrip.swift
// Piqd v0.3 — domain model for the 6-frame Sequence asset (SRS §3.2).
// Emitted by `StoryEngine.assembleSequence` when all 6 HEIC frames have been stitched into
// a silent looping 9:16 H.264 MP4. `shareReady` flips to true once the MP4 is closed on disk;
// before that the Sequence row exists in the vault but cannot be surfaced for P2P share.

import Foundation

public struct SequenceStrip: Equatable, Sendable {
    public let id: UUID
    public let frameURLs: [URL]
    public let assembledVideoURL: URL
    public let durationSeconds: Double
    public let shareReady: Bool

    public init(
        id: UUID = UUID(),
        frameURLs: [URL],
        assembledVideoURL: URL,
        durationSeconds: Double,
        shareReady: Bool
    ) {
        self.id = id
        self.frameURLs = frameURLs
        self.assembledVideoURL = assembledVideoURL
        self.durationSeconds = durationSeconds
        self.shareReady = shareReady
    }
}
