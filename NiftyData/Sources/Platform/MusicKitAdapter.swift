// NiftyData/Sources/Platform/MusicKitAdapter.swift

import Foundation
import MusicKit
import NiftyCore

public final class MusicKitAdapter: Sendable {
    public init() {}

    public func currentTrack() async -> (track: String, artist: String)? {
        // TODO: MusicKit.MusicPlayer.Queue.currentEntry
        return nil
    }
}
