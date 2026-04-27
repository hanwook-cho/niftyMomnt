// Apps/Piqd/Piqd/UI/Capture/SilentLoopingPlayerView.swift
// Piqd v0.5 — silent looping MP4 player for the drafts tray Sequence row
// (FR-SNAP-DRAFT-04). Wraps `AVPlayerLayer` + `AVPlayerLooper` so the
// 6-frame Sequence MP4 plays back as a tight ~2s loop without stutter at the
// boundary.
//
// Lifecycle: SwiftUI mounts via `.onAppear` and unmounts via `.onDisappear`.
// The view dismantle path stops playback and tears down the queue player so
// scrolling the tray doesn't leak N concurrent AVPlayer instances.

import AVFoundation
import SwiftUI
import UIKit

struct SilentLoopingPlayerView: UIViewRepresentable {

    let url: URL

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.attach(url: url)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.attach(url: url)
    }

    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: ()) {
        uiView.tearDown()
    }

    /// `UIView` host that owns the `AVQueuePlayer` + `AVPlayerLooper`. Sized by
    /// AutoLayout from the SwiftUI side; layer geometry is synced in
    /// `layoutSubviews()`.
    final class PlayerLayerView: UIView {
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var attachedURL: URL?
        private let playerLayer = AVPlayerLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
            backgroundColor = .black
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }

        func attach(url: URL) {
            // Idempotent: re-attaching the same URL is a no-op.
            if attachedURL == url { return }
            tearDown()

            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true                           // FR-SNAP-DRAFT-04
            player.actionAtItemEnd = .advance
            self.looper = AVPlayerLooper(player: player, templateItem: item)
            self.queuePlayer = player
            self.playerLayer.player = player
            self.attachedURL = url
            player.play()
        }

        func tearDown() {
            queuePlayer?.pause()
            queuePlayer?.removeAllItems()
            queuePlayer = nil
            looper = nil
            playerLayer.player = nil
            attachedURL = nil
        }
    }
}
