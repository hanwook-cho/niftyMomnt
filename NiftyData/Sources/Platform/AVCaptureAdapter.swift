// NiftyData/Sources/Platform/AVCaptureAdapter.swift
// Wraps AVFoundation. Implements CaptureEngineProtocol.
// This is the only file that imports AVFoundation for capture.

import AVFoundation
import Combine
import Foundation
import NiftyCore

public final class AVCaptureAdapter: CaptureEngineProtocol {
    private let config: AppConfig
    private let stateSubject = CurrentValueSubject<CaptureState, Never>(.idle)
    private let telemetrySubject = PassthroughSubject<CaptureTelemetry, Never>()

    /// Shared session. The UI layer attaches an AVCaptureVideoPreviewLayer to this.
    public let session = AVCaptureSession()
    private var isSessionConfigured = false

    public init(config: AppConfig) {
        self.config = config
    }

    public var captureState: AnyPublisher<CaptureState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    public var telemetry: AnyPublisher<CaptureTelemetry, Never> {
        telemetrySubject.eraseToAnyPublisher()
    }

    // MARK: - Session lifecycle

    public func startSession(mode: CaptureMode, config: AppConfig) async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            stateSubject.send(.error(.unauthorized))
            throw CaptureError.unauthorized
        }
        if !isSessionConfigured {
            try configureVideoInput(for: mode)
            isSessionConfigured = true
        }
        // startRunning() is synchronous and blocking — must not run on the main thread.
        let s = session
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                s.startRunning()
                if s.isRunning {
                    cont.resume()
                } else {
                    cont.resume(throwing: CaptureError.sessionFailed)
                }
            }
        }
        stateSubject.send(.ready(mode: mode))
    }

    public func stopSession() async {
        isSessionConfigured = false
        let s = session
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                if s.isRunning { s.stopRunning() }
                cont.resume()
            }
        }
        stateSubject.send(.idle)
    }

    public func captureAsset() async throws -> Asset {
        // TODO: capture photo/video via AVCapturePhotoOutput / AVAssetWriter
        throw CaptureError.captureFailed
    }

    public func switchMode(to mode: CaptureMode) async throws {
        // TODO: reconfigure session inputs/outputs for new mode
    }

    public func applyPreset(_ preset: VibePreset) async {
        // TODO: apply LUT / color space settings
    }

    public func availableModes() -> [CaptureMode] {
        CaptureMode.allCases
    }

    // MARK: - Private helpers

    /// Configures the session with the back wide-angle camera input.
    /// Must be called once before startRunning(). Not thread-isolated — caller holds
    /// the MainActor lock; AVCaptureSession.beginConfiguration/commitConfiguration
    /// is safe to call from any thread but we do it synchronously here before
    /// the background startRunning() dispatch.
    private func configureVideoInput(for mode: CaptureMode) throws {
        session.beginConfiguration()
        session.sessionPreset = (mode == .clip || mode == .echo || mode == .atmosphere) ? .high : .photo

        // Remove stale inputs
        session.inputs.forEach { session.removeInput($0) }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            throw CaptureError.sessionFailed
        }
        session.addInput(input)
        session.commitConfiguration()
    }
}
