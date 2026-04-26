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
    // Piqd v0.4 — invisible level. Singleton sensor, started lazily by the view that
    // first subscribes (PiqdCaptureView's LevelIndicatorView).
    public let motionMonitor: MotionMonitor
    /// Piqd v0.4 — face-rect → "Step back for the full vibe" pipeline. Snap-only consumer
    /// (PiqdCaptureView gates on mode + format + recording state).
    public let subjectGuidance: SubjectGuidanceDetector
    /// Piqd v0.4 — `VibeClassifying` injection seam. Ships as `StubVibeClassifier`
    /// (always `.quiet`). Real CoreML scene classifier lands in a later version.
    public let vibeClassifier: any VibeClassifying

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
        makeSequenceTicker: @escaping @Sendable () -> any SequenceTicker,
        motionMonitor: MotionMonitor,
        subjectGuidance: SubjectGuidanceDetector,
        vibeClassifier: any VibeClassifying
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
        self.motionMonitor = motionMonitor
        self.subjectGuidance = subjectGuidance
        self.vibeClassifier = vibeClassifier
    }
}
