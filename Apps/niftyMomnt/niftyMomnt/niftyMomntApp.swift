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
        let config = AppConfig.v0_4

        // Platform adapters (NiftyData)
        let captureAdapter     = AVCaptureAdapter(config: config)
        let soundStampAdapter  = SoundStampAdapter(config: config)
        let weatherAdapter     = OpenMeteoWeatherAdapter()
        let geocoderAdapter    = MapKitGeocoderAdapter()
        let indexingAdapter    = CoreMLIndexingAdapter(config: config, weather: weatherAdapter)
        let vaultRepo          = VaultRepository(config: config)
        let graphRepo          = GraphRepository(config: config)
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
            geocoder: geocoderAdapter
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
        let storyUseCase = AssembleReelUseCase(engine: storyEngine)
        let shareUseCase = ShareMomentUseCase(vault: vaultManager, config: config)

        container = AppContainer(
            config: config,
            captureUseCase: captureUseCase,
            lifeFourCutsUseCase: lifeFourCutsUseCase,
            fixUseCase: fixUseCase,
            storyUseCase: storyUseCase,
            shareUseCase: shareUseCase,
            nudgeEngine: nudgeEngine,
            vaultManager: vaultManager,
            graphManager: graphManager,
            captureSession: captureAdapter.session
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
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.hwcho99.niftyMomnt.indexBatch",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            Task {
                // TODO: fetch unindexed asset IDs + data from vault, then call processBatch
                await indexingEngine.processBatch(assets: [])
                processingTask.setTaskCompleted(success: true)
            }
            processingTask.expirationHandler = {
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
