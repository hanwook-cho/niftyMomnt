// NiftyCore/Sources/Domain/Protocols/CaptureEngineProtocol.swift
// Zero platform imports — Combine allowed for reactive binding.

import Combine
import Foundation

@MainActor
public protocol CaptureEngineProtocol: AnyObject {
    var captureState: AnyPublisher<CaptureState, Never> { get }
    var telemetry: AnyPublisher<CaptureTelemetry, Never> { get }
    func startSession(mode: CaptureMode, config: AppConfig) async throws
    func stopSession() async
    /// Captures a still or Live Photo frame. Use for .still and .live modes.
    func captureAsset() async throws -> Asset
    /// Starts recording video to a temp file. Use for .clip, .echo, .atmosphere modes.
    func startRecording(mode: CaptureMode) async throws
    /// Stops recording and returns the Asset (with duration). Temp file at tmpdir/{id}.mov.
    func stopRecording() async throws -> Asset
    func switchMode(to mode: CaptureMode, gestureTime: Double) async throws
    func switchCamera() async throws
    func focusAndLock(at point: CGPoint, frameSize: CGSize) async throws
    func unlockFocusAndExposure() async
    func applyPreset(_ preset: VibePreset) async
    func availableModes() -> [CaptureMode]
}
