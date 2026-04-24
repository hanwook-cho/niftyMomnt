// Apps/Piqd/Piqd/PiqdApp.swift
// Composition root for Piqd. v0.1 wires the minimum path required for Snap Still capture:
// AVCaptureAdapter → CaptureEngine → CaptureMomentUseCase, plus VaultRepository/GraphRepository
// under the "piqd" namespace so app data lives at Documents/piqd/.
//
// Sound Stamp, nudges, story, sharing, Life 4 Cuts are intentionally absent — they land in
// later interim versions per Docs/Piqd/piqd_interim_version_plan.md.

import NiftyCore
import NiftyData
import SwiftUI

@main
struct PiqdApp: App {
    private let container: PiqdAppContainer

    @MainActor
    init() {
        // UI-test hook: when launched with PIQD_SEED_EMPTY_VAULT=1 (typically paired with
        // UI_TEST_MODE=1) clear the Piqd-scoped Documents/piqd/ tree before any repository
        // opens it. This gives XCUITest runs a deterministic empty-state start.
        if ProcessInfo.processInfo.environment["PIQD_SEED_EMPTY_VAULT"] == "1" {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let piqd = docs.appendingPathComponent("piqd", isDirectory: true)
            try? FileManager.default.removeItem(at: piqd)
        }

        // UI-test hooks for ModeStore. Cleared/seeded before ModeStore reads its defaults.
        let env = ProcessInfo.processInfo.environment
        if env["PIQD_RESET_LAST_MODE"] == "1" {
            let defaults = UserDefaults(suiteName: "piqd")
            defaults?.removeObject(forKey: "piqd.captureMode")
            defaults?.removeObject(forKey: "piqd.lastSnapFormat")
        }
        if let forced = env["PIQD_FORCE_LAST_MODE"],
           forced == "snap" || forced == "roll" {
            UserDefaults(suiteName: "piqd")?.set(forced, forKey: "piqd.captureMode")
        }

        let config = AppConfig.piqd_v0_3

        // Piqd v0.2 — dev knobs (loaded once at launch; XCUITest can seed via PIQD_DEV_*).
        let devSettings = DevSettingsStore()

        // Platform adapters
        let captureAdapter = AVCaptureAdapter(config: config)
        let indexingAdapter = CoreMLIndexingAdapter(config: config, weather: nil)
        let vaultRepo = VaultRepository(config: config)
        let graphRepo = GraphRepository(config: config)
        // Dev knob: dailyLimit is captured at launch. Changing the value in dev settings
        // takes effect on the next launch. (Live updates would need a Sendable bridge from
        // the @MainActor DevSettingsStore into the actor — out of scope for v0.2.)
        let rollCounter = RollCounterRepository(
            config: config,
            dailyLimit: devSettings.rollDailyLimit
        )
        // SoundStampAdapter is constructed but never activated — .soundStamp is not in
        // piqd_v0_1.features, so CaptureEngine.isSoundStampEnabled is false and the pipeline
        // stays idle. Passing it satisfies CaptureEngine's non-optional requirement.
        let soundStampAdapter = SoundStampAdapter(config: config, graph: graphRepo)

        // Managers
        let vaultManager = VaultManager(vault: vaultRepo, graph: graphRepo)
        let graphManager = GraphManager(graph: graphRepo)

        // Engines
        let captureEngine = CaptureEngine(
            config: config,
            captureAdapter: captureAdapter,
            soundStampPipeline: soundStampAdapter
        )
        let indexingEngine = IndexingEngine(
            config: config,
            adapter: indexingAdapter,
            graph: graphRepo
        )

        // Use case — geocoder/nudge omitted (not in v0.1 scope)
        let captureUseCase = CaptureMomentUseCase(
            engine: captureEngine,
            vault: vaultManager,
            indexing: indexingEngine,
            graph: graphManager
        )

        let modeStore = ModeStore()
        let imageEncoder: ImageEncoder = HEICEncoder()
        let captureActivity = CaptureActivityStore()

        // Piqd v0.3 — Sequence assembly chain. StoryEngine never calls `lab` from
        // `assembleSequence`, so a no-op LabClient keeps the signature satisfied without
        // pulling in networking.
        let sequenceAssembler = AVSequenceAssembler()
        let storyEngine = StoryEngine(
            config: config,
            vault: vaultRepo,
            graph: graphRepo,
            lab: PiqdNoopLabClient(),
            sequenceAssembler: sequenceAssembler
        )

        container = PiqdAppContainer(
            config: config,
            captureUseCase: captureUseCase,
            vaultManager: vaultManager,
            graphManager: graphManager,
            captureSession: captureAdapter.session,
            captureAdapter: captureAdapter,
            modeStore: modeStore,
            devSettings: devSettings,
            rollCounter: rollCounter,
            imageEncoder: imageEncoder,
            captureActivity: captureActivity,
            storyEngine: storyEngine,
            sequenceFrameCapturer: captureAdapter,
            makeSequenceTicker: { DispatchSourceTimerTicker() }
        )
    }

    var body: some Scene {
        WindowGroup {
            PiqdRootView(container: container)
        }
    }
}
