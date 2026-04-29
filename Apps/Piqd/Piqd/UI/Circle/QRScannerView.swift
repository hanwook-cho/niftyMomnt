// Apps/Piqd/Piqd/UI/Circle/QRScannerView.swift
// Piqd v0.6 — single-shot QR scanner. Wraps an `AVCaptureSession` +
// `AVCaptureMetadataOutput` inside a UIViewRepresentable. Owns its own
// session lifecycle so it never contends with the main camera engine
// (`AVCaptureAdapter`); the scanner stops + releases on `dismantleUIView`.
//
// Emits the first matched `piqd://invite/<token>` URL via `onScanned` and
// then halts metadata emission — the caller is expected to dismiss the
// presenting sheet on receipt.

import SwiftUI
import AVFoundation
import NiftyCore

public struct QRScannerView: UIViewRepresentable {

    public typealias UIViewType = ScannerUIView

    public var onScanned: (URL) -> Void

    public init(onScanned: @escaping (URL) -> Void) {
        self.onScanned = onScanned
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    public func makeUIView(context: Context) -> ScannerUIView {
        let view = ScannerUIView()
        view.coordinator = context.coordinator
        view.start()
        return view
    }

    public func updateUIView(_ uiView: ScannerUIView, context: Context) { /* no-op */ }

    public static func dismantleUIView(_ uiView: ScannerUIView, coordinator: Coordinator) {
        uiView.stop()
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onScanned: (URL) -> Void
        private var emitted = false

        init(onScanned: @escaping (URL) -> Void) {
            self.onScanned = onScanned
        }

        public func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !emitted else { return }
            for obj in metadataObjects {
                guard
                    let qr = obj as? AVMetadataMachineReadableCodeObject,
                    let raw = qr.stringValue,
                    let url = URL(string: raw),
                    url.scheme == InviteCoordinator.urlScheme,
                    url.host == InviteCoordinator.urlHost
                else { continue }

                emitted = true
                output.setMetadataObjectsDelegate(nil, queue: nil)
                onScanned(url)
                return
            }
        }
    }

    // MARK: - Hosting view

    public final class ScannerUIView: UIView {
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private let sessionQueue = DispatchQueue(label: "com.piqd.qrscanner.session")
        weak var coordinator: Coordinator?

        public override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
        }

        required init?(coder: NSCoder) { fatalError("not implemented") }

        public override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }

        func start() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureAndRun()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard granted else { return }
                    DispatchQueue.main.async { self?.configureAndRun() }
                }
            case .denied, .restricted:
                return  // caller surfaces a "Settings" affordance; no auto-prompt re-fire
            @unknown default:
                return
            }
        }

        func stop() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if self.session.isRunning {
                    self.session.stopRunning()
                }
            }
        }

        private func configureAndRun() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.configure()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }

        private func configure() {
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.sessionPreset = .high

            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.bounds
                self.layer.addSublayer(layer)
                self.previewLayer = layer
            }
        }
    }
}
