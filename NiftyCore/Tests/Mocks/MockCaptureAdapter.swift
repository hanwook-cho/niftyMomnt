// Tests/Mocks/MockCaptureAdapter.swift

import Combine
import CoreGraphics
import Foundation
@testable import NiftyCore

@MainActor
final class MockCaptureAdapter: CaptureEngineProtocol {
    nonisolated(unsafe) private let stateSubject = CurrentValueSubject<CaptureState, Never>(.idle)
    nonisolated(unsafe) private let telemetrySubject = PassthroughSubject<CaptureTelemetry, Never>()

    nonisolated var captureState: AnyPublisher<CaptureState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    nonisolated var telemetry: AnyPublisher<CaptureTelemetry, Never> {
        telemetrySubject.eraseToAnyPublisher()
    }

    func startSession(mode: CaptureMode, config: AppConfig) async throws {}
    func stopSession() async {}
    func captureAsset() async throws -> Asset {
        Asset(type: .still, capturedAt: Date())
    }
    func startRecording(mode: CaptureMode) async throws {}
    func stopRecording() async throws -> Asset {
        Asset(type: .clip, capturedAt: Date())
    }
    func reconfigureSession(to mode: CaptureMode, gestureTime: Double) async throws {}
    func configure(for format: CaptureFormat,
                   dualKind: DualMediaKind,
                   dualLayout: DualLayout,
                   gestureTime: Double) async throws {}
    func switchCamera() async throws {}
    func focusAndLock(at point: CGPoint, frameSize: CGSize) async throws {}
    func unlockFocusAndExposure() async {}
    func applyPreset(_ preset: VibePreset) async {}
    func availableModes() -> [CaptureMode] { CaptureMode.allCases }
    func latestSecondaryFrameData() -> Data? { nil }
}
