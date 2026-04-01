// Apps/niftyMomnt/AppContainer.swift
// Holds all resolved dependencies for injection into the view hierarchy.

import AVFoundation
import NiftyCore
import Observation
import SwiftUI

@MainActor @Observable
public final class AppContainer {
    public let config: AppConfig
    public let captureUseCase: CaptureMomentUseCase
    public let fixUseCase: FixAssetUseCase
    public let storyUseCase: AssembleReelUseCase
    public let shareUseCase: ShareMomentUseCase
    public let nudgeEngine: any NudgeEngineProtocol
    public let vaultManager: VaultManager
    public let graphManager: GraphManager
    /// The AVCaptureSession owned by AVCaptureAdapter. Views attach preview layers to this.
    public let captureSession: AVCaptureSession

    public init(
        config: AppConfig,
        captureUseCase: CaptureMomentUseCase,
        fixUseCase: FixAssetUseCase,
        storyUseCase: AssembleReelUseCase,
        shareUseCase: ShareMomentUseCase,
        nudgeEngine: any NudgeEngineProtocol,
        vaultManager: VaultManager,
        graphManager: GraphManager,
        captureSession: AVCaptureSession
    ) {
        self.config = config
        self.captureUseCase = captureUseCase
        self.fixUseCase = fixUseCase
        self.storyUseCase = storyUseCase
        self.shareUseCase = shareUseCase
        self.nudgeEngine = nudgeEngine
        self.vaultManager = vaultManager
        self.graphManager = graphManager
        self.captureSession = captureSession
    }
}
