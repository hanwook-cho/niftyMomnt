// Apps/Piqd/Piqd/UI/Capture/CameraPreviewView.swift
// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer, identical pattern to niftyMomnt.
// Attaches to the AVCaptureSession owned by AVCaptureAdapter via PiqdAppContainer.

import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> _PiqdPreviewUIView {
        let view = _PiqdPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: _PiqdPreviewUIView, context: Context) {}
}

final class _PiqdPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }
}
