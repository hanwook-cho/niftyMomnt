// Tests/Mocks/MockCaptureAdapter.swift

import Combine
import Foundation
@testable import NiftyCore

final class MockCaptureAdapter: CaptureEngineProtocol {
    private let stateSubject = CurrentValueSubject<CaptureState, Never>(.idle)
    private let telemetrySubject = PassthroughSubject<CaptureTelemetry, Never>()

    var captureState: AnyPublisher<CaptureState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var telemetry: AnyPublisher<CaptureTelemetry, Never> {
        telemetrySubject.eraseToAnyPublisher()
    }

    func startSession(mode: CaptureMode, config: AppConfig) async throws {}
    func stopSession() async {}
    func captureAsset() async throws -> Asset {
        Asset(type: .still, capturedAt: Date())
    }
    func switchMode(to mode: CaptureMode) async throws {}
    func applyPreset(_ preset: VibePreset) async {}
    func availableModes() -> [CaptureMode] { CaptureMode.allCases }
}
