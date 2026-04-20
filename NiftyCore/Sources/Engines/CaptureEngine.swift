// NiftyCore/Sources/Engines/CaptureEngine.swift
// @MainActor — capture state read from main thread for UI binding.
// Never imports AVFoundation — delegates to CaptureEngineProtocol adapter.

import Combine
import Foundation
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "CaptureEngine")

@MainActor
public final class CaptureEngine: CaptureEngineProtocol {
    private let config: AppConfig
    private let captureAdapter: any CaptureEngineProtocol
    private let soundStampPipeline: any SoundStampPipelineProtocol

    private let captureStateSubject = CurrentValueSubject<CaptureState, Never>(.idle)
    private let telemetrySubject = PassthroughSubject<CaptureTelemetry, Never>()

    public var captureState: AnyPublisher<CaptureState, Never> {
        captureStateSubject.eraseToAnyPublisher()
    }

    public var telemetry: AnyPublisher<CaptureTelemetry, Never> {
        telemetrySubject.eraseToAnyPublisher()
    }

    public init(
        config: AppConfig,
        captureAdapter: any CaptureEngineProtocol,
        soundStampPipeline: any SoundStampPipelineProtocol
    ) {
        self.config = config
        self.captureAdapter = captureAdapter
        self.soundStampPipeline = soundStampPipeline
    }

    /// Returns true when both the compile-time feature flag and the runtime user toggle are on.
    private var isSoundStampEnabled: Bool {
        config.features.contains(.soundStamp) &&
        UserDefaults.standard.bool(forKey: "nifty.soundStampEnabled")
    }

    public func startSession(mode: CaptureMode, config: AppConfig) async throws {
        try await captureAdapter.startSession(mode: mode, config: config)
        if mode == .still && isSoundStampEnabled {
            // Sound Stamp failure (e.g. audio engine conflict after session rebuild) must NOT
            // propagate — the camera is already running at this point. Log and continue.
            do {
                try await soundStampPipeline.activatePreRoll()
            } catch {
                log.warning("startSession — activatePreRoll failed, Sound Stamp disabled for this session: \(error)")
            }
        }
        captureStateSubject.send(.ready(mode: mode))
    }

    public func stopSession() async {
        await soundStampPipeline.deactivatePreRoll()
        await captureAdapter.stopSession()
        captureStateSubject.send(.idle)
    }

    public func startRecording(mode: CaptureMode) async throws {
        try await captureAdapter.startRecording(mode: mode)
        captureStateSubject.send(.capturing(mode: mode))
    }

    public func stopRecording() async throws -> Asset {
        let asset = try await captureAdapter.stopRecording()
        captureStateSubject.send(.processing)
        return asset
    }

    public func captureAsset() async throws -> Asset {
        captureStateSubject.send(.capturing(mode: currentMode()))
        let asset = try await captureAdapter.captureAsset()
        if currentMode() == .still && isSoundStampEnabled {
            Task.detached { [soundStampPipeline] in
                _ = try? await soundStampPipeline.analyzeAndTag(assetID: asset.id)
            }
        }
        captureStateSubject.send(.processing)
        return asset
    }

    public func reconfigureSession(to mode: CaptureMode, gestureTime: Double) async throws {
        let wasStill = currentMode() == .still
        let isStill = mode == .still
        if wasStill && !isStill {
            await soundStampPipeline.deactivatePreRoll()
        }
        try await captureAdapter.reconfigureSession(to: mode, gestureTime: gestureTime)
        if isStill && isSoundStampEnabled {
            do {
                try await soundStampPipeline.activatePreRoll()
            } catch {
                log.warning("reconfigureSession — activatePreRoll failed, Sound Stamp disabled for this session: \(error)")
            }
        }
        captureStateSubject.send(.ready(mode: mode))
    }

    public func switchCamera() async throws {
        try await captureAdapter.switchCamera()
    }

    public func focusAndLock(at point: CGPoint, frameSize: CGSize) async throws {
        try await captureAdapter.focusAndLock(at: point, frameSize: frameSize)
    }

    public func unlockFocusAndExposure() async {
        await captureAdapter.unlockFocusAndExposure()
    }

    public func applyPreset(_ preset: VibePreset) async {
        await captureAdapter.applyPreset(preset)
    }

    public func availableModes() -> [CaptureMode] {
        CaptureMode.allCases.filter { mode in
            switch mode {
            case .still:      return config.assetTypes.contains(.still)
            case .live:       return config.assetTypes.contains(.live)
            case .clip:       return config.assetTypes.contains(.clip)
            case .echo:       return config.assetTypes.contains(.echo)
            case .atmosphere: return config.assetTypes.contains(.atmosphere)
            case .photoBooth: return config.features.contains(.l4c)
            case .snap:       return config.features.contains(.snapMode)
            case .roll:       return config.features.contains(.rollMode)
            }
        }
    }

    public func latestSecondaryFrameData() -> Data? {
        return captureAdapter.latestSecondaryFrameData()
    }

    private func currentMode() -> CaptureMode {
        if case .ready(let mode) = captureStateSubject.value { return mode }
        if case .capturing(let mode) = captureStateSubject.value { return mode }
        return .still
    }
}
