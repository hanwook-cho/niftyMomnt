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
    // Piqd v0.2 additions
    public let modeStore: ModeStore
    public let devSettings: DevSettingsStore
    public let rollCounter: RollCounterRepository
    public let imageEncoder: ImageEncoder
    // Piqd v0.3 — single source of truth for "capture in flight" (Sequence/Clip/Dual).
    public let captureActivity: CaptureActivityStore

    public init(
        config: AppConfig,
        captureUseCase: CaptureMomentUseCase,
        vaultManager: VaultManager,
        graphManager: GraphManager,
        captureSession: AVCaptureSession,
        modeStore: ModeStore,
        devSettings: DevSettingsStore,
        rollCounter: RollCounterRepository,
        imageEncoder: ImageEncoder,
        captureActivity: CaptureActivityStore
    ) {
        self.config = config
        self.captureUseCase = captureUseCase
        self.vaultManager = vaultManager
        self.graphManager = graphManager
        self.captureSession = captureSession
        self.modeStore = modeStore
        self.devSettings = devSettings
        self.rollCounter = rollCounter
        self.imageEncoder = imageEncoder
        self.captureActivity = captureActivity
    }
}
