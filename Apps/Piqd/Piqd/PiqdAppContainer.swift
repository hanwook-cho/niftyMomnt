// Apps/Piqd/Piqd/PiqdAppContainer.swift
// Resolved dependencies passed down the Piqd view hierarchy. Kept deliberately thin for v0.1;
// subsequent versions extend this with story, sharing, nudges, etc.

import AVFoundation
import NiftyCore
import NiftyData
import Observation

@MainActor @Observable
public final class PiqdAppContainer {
    public let config: AppConfig
    public let captureUseCase: CaptureMomentUseCase
    public let vaultManager: VaultManager
    public let graphManager: GraphManager
    public let captureSession: AVCaptureSession

    public init(
        config: AppConfig,
        captureUseCase: CaptureMomentUseCase,
        vaultManager: VaultManager,
        graphManager: GraphManager,
        captureSession: AVCaptureSession
    ) {
        self.config = config
        self.captureUseCase = captureUseCase
        self.vaultManager = vaultManager
        self.graphManager = graphManager
        self.captureSession = captureSession
    }
}
