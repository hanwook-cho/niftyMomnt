// Apps/niftyMomnt/niftyMomntApp.swift
// Composition root — all dependencies wired here per SRS §8.2.
// This is the only file that creates concrete implementations.

import BackgroundTasks
import NiftyCore
import NiftyData
import SwiftUI

@main
struct NiftyMomntApp: App {
    private let container: AppContainer
    // Captured separately so the backgroundTask closure can access it without hopping to MainActor.
    private let nudgeEngine: any NudgeEngineProtocol

    @MainActor
    init() {
        let config = AppConfig.v0_7

        // Platform adapters (NiftyData)
        let captureAdapter     = AVCaptureAdapter(config: config)
        let weatherAdapter     = OpenMeteoWeatherAdapter()
        let geocoderAdapter    = MapKitGeocoderAdapter()
        let indexingAdapter    = CoreMLIndexingAdapter(config: config, weather: weatherAdapter)
        let vaultRepo          = VaultRepository(config: config)
        let graphRepo          = GraphRepository(config: config)
        let soundStampAdapter  = SoundStampAdapter(config: config, graph: graphRepo)
        let labClient          = LabNetworkAdapter(config: config)
        let nudgeTrigger       = JournalSuggestionsAdapter(config: config)
        let compositingAdapter = CoreImageCompositingAdapter()

        // Fix adapter needs vault reference
        let fixAdapter = CoreImageFixAdapter(config: config, vault: vaultRepo)

        // Managers (NiftyCore actors)
        let vaultManager = VaultManager(vault: vaultRepo)
        let graphManager = GraphManager(graph: graphRepo)

        // Core engines (NiftyCore)
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
        let storyEngine = StoryEngine(
            config: config,
            vault: vaultRepo,
            graph: graphRepo,
            lab: labClient
        )
        let reelComposer = AVReelComposer(vault: vaultRepo)
        let voiceProseEngine = VoiceProseEngine(lab: labClient)
        let nudgeEngine = NudgeEngine(
            config: config,
            graph: graphRepo,
            lab: labClient,
            triggerSource: nudgeTrigger
        )

        // Use cases
        let captureUseCase = CaptureMomentUseCase(
            engine: captureEngine,
            vault: vaultManager,
            indexing: indexingEngine,
            graph: graphManager,
            geocoder: geocoderAdapter,
            nudge: nudgeEngine
        )
        let lifeFourCutsUseCase = LifeFourCutsUseCase(
            captureEngine: captureEngine,
            compositor: compositingAdapter,
            vault: vaultManager,
            graph: graphManager,
            geocoder: geocoderAdapter
        )
        let fixUseCase = FixAssetUseCase(
            fixRepo: fixAdapter,
            vault: vaultManager,
            graph: graphManager
        )
        let storyUseCase = AssembleReelUseCase(engine: storyEngine, composer: reelComposer)
        let shareUseCase = ShareMomentUseCase(vault: vaultManager, config: config)

        container = AppContainer(
            config: config,
            captureUseCase: captureUseCase,
            lifeFourCutsUseCase: lifeFourCutsUseCase,
            fixUseCase: fixUseCase,
            storyUseCase: storyUseCase,
            shareUseCase: shareUseCase,
            voiceProseEngine: voiceProseEngine,
            nudgeEngine: nudgeEngine,
            vaultManager: vaultManager,
            graphManager: graphManager,
            captureSession: captureAdapter.session,
            soundStampPipeline: soundStampAdapter
        )
        self.nudgeEngine = nudgeEngine

        // Forward resolved place name into AppContainer so CaptureHubView overlay can display it.
        captureUseCase.onPlaceResolved = { [weak container] name in
            container?.lastCapturedPlaceName = name
        }
        lifeFourCutsUseCase.onPlaceResolved = { [weak container] name in
            container?.lastCapturedPlaceName = name
        }

        NiftyMomntApp.registerBackgroundTasks(indexingEngine: indexingEngine)
        NiftyMomntApp.scheduleIndexBatch()
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        .backgroundTask(.appRefresh("com.hwcho99.niftyMomnt.refresh")) { [nudgeEngine] in
            await nudgeEngine.refresh()
        }
    }
}

// MARK: - BGTask registration

extension NiftyMomntApp {
    /// Called once at app launch to register BGProcessingTask handler.
    /// The task identifier must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static func registerBackgroundTasks(indexingEngine: IndexingEngine) {
        // using: .main — handler and expirationHandler are always called on the main queue.
        // BGTaskScheduler.shared.submit() requires the main thread; calling it from any other
        // context (e.g. Task.detached cooperative pool) causes _dispatch_assert_queue_fail.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.hwcho99.niftyMomnt.indexBatch",
            using: .main
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            // Actual indexing work runs detached (background priority, off main thread).
            let workItem = Task.detached(priority: .background) {
                // TODO: fetch unindexed asset IDs + data from vault, then call processBatch
                await indexingEngine.processBatch(assets: [])
            }
            // Completion and re-scheduling happen back on the main actor.
            Task { @MainActor in
                _ = await workItem.value
                processingTask.setTaskCompleted(success: true)
                NiftyMomntApp.scheduleIndexBatch()  // must be main thread
            }
            processingTask.expirationHandler = {
                // expirationHandler also called on main queue (using: .main)
                workItem.cancel()
                processingTask.setTaskCompleted(success: false)
            }
        }
    }

    static func scheduleIndexBatch() {
        let request = BGProcessingTaskRequest(identifier: "com.hwcho99.niftyMomnt.indexBatch")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }
}
