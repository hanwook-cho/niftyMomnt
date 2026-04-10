// Apps/niftyMomnt/AppContainer.swift
// Holds all resolved dependencies for injection into the view hierarchy.

import AVFoundation
import Combine
import NiftyCore
import Observation
import SwiftUI

@MainActor @Observable
public final class AppContainer {
    public let config: AppConfig
    public let captureUseCase: CaptureMomentUseCase
    public let lifeFourCutsUseCase: LifeFourCutsUseCase
    public let fixUseCase: FixAssetUseCase
    public let storyUseCase: AssembleReelUseCase
    public let shareUseCase: ShareMomentUseCase
    public let nudgeEngine: any NudgeEngineProtocol
    public let vaultManager: VaultManager
    public let graphManager: GraphManager
    /// The AVCaptureSession owned by AVCaptureAdapter. Views attach preview layers to this.
    public let captureSession: AVCaptureSession
    /// Set by CaptureMomentUseCase after geocoding completes. Read by CaptureHubView overlay.
    public var lastCapturedPlaceName: String = ""
    /// True while SoundStamp pre-roll buffer is active (Still mode + feature enabled).
    public var isSoundStampActive: Bool = false

    private let soundStampPipeline: (any SoundStampPipelineProtocol)?
    private var soundStampCancellable: AnyCancellable?

    public init(
        config: AppConfig,
        captureUseCase: CaptureMomentUseCase,
        lifeFourCutsUseCase: LifeFourCutsUseCase,
        fixUseCase: FixAssetUseCase,
        storyUseCase: AssembleReelUseCase,
        shareUseCase: ShareMomentUseCase,
        nudgeEngine: any NudgeEngineProtocol,
        vaultManager: VaultManager,
        graphManager: GraphManager,
        captureSession: AVCaptureSession,
        soundStampPipeline: (any SoundStampPipelineProtocol)? = nil
    ) {
        self.config = config
        self.captureUseCase = captureUseCase
        self.lifeFourCutsUseCase = lifeFourCutsUseCase
        self.fixUseCase = fixUseCase
        self.storyUseCase = storyUseCase
        self.shareUseCase = shareUseCase
        self.nudgeEngine = nudgeEngine
        self.vaultManager = vaultManager
        self.graphManager = graphManager
        self.captureSession = captureSession
        self.soundStampPipeline = soundStampPipeline

        soundStampCancellable = soundStampPipeline?.isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in self?.isSoundStampActive = active }
    }

    /// Called by CaptureHubView when the Sound Stamp Settings toggle changes at runtime.
    /// Activates pre-roll when enabled in Still mode; deactivates otherwise.
    public func applySoundStampToggle(enabled: Bool, currentMode: CaptureMode) {
        guard let pipeline = soundStampPipeline else { return }
        Task {
            if enabled && currentMode == .still {
                try? await pipeline.activatePreRoll()
            } else {
                await pipeline.deactivatePreRoll()
            }
        }
    }
}
