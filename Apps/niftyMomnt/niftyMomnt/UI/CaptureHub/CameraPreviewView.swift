// Apps/niftyMomnt/UI/CaptureHub/CameraPreviewView.swift
// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer.
// Attaches to the shared AVCaptureSession from AppContainer so the preview
// renders the live camera feed without owning the session itself.

import AVFoundation
import SwiftUI

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
