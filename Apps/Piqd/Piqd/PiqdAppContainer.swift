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
    /// Concrete repository — exposed so Piqd-only views (drafts tray) can call
    /// methods like `snapAssetURL(id:type:)` that aren't part of `VaultProtocol`.
    public let vaultRepository: VaultRepository
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
    /// Piqd v0.5 — drafts tray persistence. GRDB-backed `DraftsRepository` in production;
    /// `InMemoryDraftsRepository` for UI-test seams.
    public let draftsRepository: any DraftsRepositoryProtocol
    /// Piqd v0.5 — iOS Photos save target.
    public let photoLibraryExporter: any PhotoLibraryExporterProtocol
    /// Piqd v0.5 — interim "send →" sheet wrapper. Replaced by Trusted Circle in v0.6.
    public let shareHandoff: ShareHandoffCoordinator
    /// Piqd v0.5 — foreground-only purge sweep. Triggered on app launch, on
    /// `willEnterForegroundNotification`, and (when extended) on the active timer.
    public let draftPurgeScheduler: DraftPurgeScheduler
    /// Piqd v0.5 — @Observable bridge that drives badge + tray UI.
    public let draftsBindings: DraftsStoreBindings

    public init(
        config: AppConfig,
        captureUseCase: CaptureMomentUseCase,
        vaultManager: VaultManager,
        vaultRepository: VaultRepository,
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
        vibeClassifier: any VibeClassifying,
        draftsRepository: any DraftsRepositoryProtocol,
        photoLibraryExporter: any PhotoLibraryExporterProtocol,
        shareHandoff: ShareHandoffCoordinator,
        draftPurgeScheduler: DraftPurgeScheduler,
        draftsBindings: DraftsStoreBindings
    ) {
        self.config = config
        self.captureUseCase = captureUseCase
        self.vaultManager = vaultManager
        self.vaultRepository = vaultRepository
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
        self.draftsRepository = draftsRepository
        self.photoLibraryExporter = photoLibraryExporter
        self.shareHandoff = shareHandoff
        self.draftPurgeScheduler = draftPurgeScheduler
        self.draftsBindings = draftsBindings
    }
}
