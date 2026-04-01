// Tests/Mocks/MockSoundStampPipeline.swift

import Combine
import Foundation
@testable import NiftyCore

actor MockSoundStampPipeline: SoundStampPipelineProtocol {
    private(set) var preRollActivated = false
    nonisolated(unsafe) private let isActiveSubject = CurrentValueSubject<Bool, Never>(false)

    nonisolated var isActive: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    func activatePreRoll() async throws {
        preRollActivated = true
        isActiveSubject.send(true)
    }

    func deactivatePreRoll() async {
        isActiveSubject.send(false)
    }

    func analyzeAndTag(assetID: UUID) async throws -> [AcousticTag] {
        return []
    }
}
