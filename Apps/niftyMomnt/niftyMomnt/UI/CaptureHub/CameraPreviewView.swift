// Apps/niftyMomnt/UI/CaptureHub/CameraPreviewView.swift
// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer.
// Attaches to the shared AVCaptureSession from AppContainer so the preview
// renders the live camera feed without owning the session itself.

import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> _VideoPreviewUIView {
        let view = _VideoPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: _VideoPreviewUIView, context: Context) {
        // Session changes (e.g. front/back switch) are handled by reconfiguring
        // the session's inputs directly; the preview layer follows automatically.
    }
}

// MARK: - Backing UIView

/// UIView subclass whose backing layer is AVCaptureVideoPreviewLayer.
/// This is the correct pattern for preview layers — overriding `layerClass` lets
/// the layer be sized automatically by Auto Layout / UIView bounds changes.
final class _VideoPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct FocusLockGestureView: UIViewRepresentable {
    let onLongPress: (CGPoint, CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        recognizer.minimumPressDuration = 0.6
        recognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onLongPress = onLongPress
    }

    final class Coordinator: NSObject {
        var onLongPress: (CGPoint, CGSize) -> Void

        init(onLongPress: @escaping (CGPoint, CGSize) -> Void) {
            self.onLongPress = onLongPress
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let view = recognizer.view else { return }
            onLongPress(recognizer.location(in: view), view.bounds.size)
        }
    }
}
