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
    func captureAsset() async throws -> Asset
    func switchMode(to mode: CaptureMode) async throws
    func applyPreset(_ preset: VibePreset) async
    func availableModes() -> [CaptureMode]
}
