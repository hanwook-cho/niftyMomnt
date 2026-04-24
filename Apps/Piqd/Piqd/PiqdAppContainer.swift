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
    /// Concrete adapter — exposed so views can call imperative methods that aren't part of
    /// the CaptureEngineProtocol surface (e.g. attaching a preview layer under the dual-video
    /// no-connection topology).
    public let captureAdapter: AVCaptureAdapter
    // Piqd v0.2 additions
    public let modeStore: ModeStore
    public let devSettings: DevSettingsStore
    public let rollCounter: RollCounterRepository
    public let imageEncoder: ImageEncoder
    // Piqd v0.3 — single source of truth for "capture in flight" (Sequence/Clip/Dual).
    public let captureActivity: CaptureActivityStore
    // Piqd v0.3 — Sequence wiring. `sequenceFrameCapturer` is the AVCaptureAdapter re-exposed
    // via its SequenceFrameCapturer conformance; `makeSequenceTicker` returns a fresh
    // DispatchSourceTimerTicker per Sequence (tickers are single-use). `storyEngine.assembleSequence`
    // composes the captured frames into a looping MP4.
    public let storyEngine: StoryEngine
    public let sequenceFrameCapturer: any SequenceFrameCapturer
    public let makeSequenceTicker: @Sendable () -> any SequenceTicker

    public init(
        config: AppConfig,
        captureUseCase: CaptureMomentUseCase,
        vaultManager: VaultManager,
        graphManager: GraphManager,
        captureSession: AVCaptureSession,
        captureAdapter: AVCaptureAdapter,
        modeStore: ModeStore,
        devSettings: DevSettingsStore,
        rollCounter: RollCounterRepository,
        imageEncoder: ImageEncoder,
        captureActivity: CaptureActivityStore,
        storyEngine: StoryEngine,
        sequenceFrameCapturer: any SequenceFrameCapturer,
        makeSequenceTicker: @escaping @Sendable () -> any SequenceTicker
    ) {
        self.config = config
        self.captureUseCase = captureUseCase
        self.vaultManager = vaultManager
        self.graphManager = graphManager
        self.captureSession = captureSession
        self.captureAdapter = captureAdapter
        self.modeStore = modeStore
        self.devSettings = devSettings
        self.rollCounter = rollCounter
        self.imageEncoder = imageEncoder
        self.captureActivity = captureActivity
        self.storyEngine = storyEngine
        self.sequenceFrameCapturer = sequenceFrameCapturer
        self.makeSequenceTicker = makeSequenceTicker
    }
}
