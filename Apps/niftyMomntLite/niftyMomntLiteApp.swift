// Apps/niftyMomntLite/niftyMomntLiteApp.swift
// Lite variant composition root.
// Add this as a separate Xcode target — no NiftyCore changes required.

import BackgroundTasks
import NiftyCore
import NiftyData
import SwiftUI

@main
struct NiftyMomntLiteApp: App {
    private let container: AppContainer
    private let nudgeEngine: any NudgeEngineProtocol

    @MainActor
    init() {
        let config = AppConfig.lite

        let captureAdapter    = AVCaptureAdapter(config: config)
        let soundStampAdapter = SoundStampAdapter(config: config)
        let vaultRepo         = VaultRepository(config: config)
        let graphRepo         = GraphRepository(config: config)
        let labClient         = LabNetworkAdapter(config: config)
        let nudgeTrigger      = JournalSuggestionsAdapter(config: config)
        let indexingAdapter   = CoreMLIndexingAdapter(config: config)
        let fixAdapter        = CoreImageFixAdapter(config: config, vault: vaultRepo)

        let vaultManager = VaultManager(vault: vaultRepo)
        let graphManager = GraphManager(graph: graphRepo)

        let captureEngine = CaptureEngine(config: config, captureAdapter: captureAdapter, soundStampPipeline: soundStampAdapter)
        let indexingEngine = IndexingEngine(config: config, adapter: indexingAdapter, graph: graphRepo)
        let storyEngine = StoryEngine(config: config, vault: vaultRepo, graph: graphRepo, lab: labClient)
        let nudgeEngine = NudgeEngine(config: config, graph: graphRepo, lab: labClient, triggerSource: nudgeTrigger)

        let captureUseCase = CaptureMomentUseCase(engine: captureEngine, vault: vaultManager, indexing: indexingEngine)
        let fixUseCase = FixAssetUseCase(fixRepo: fixAdapter, vault: vaultManager, graph: graphManager)
        let storyUseCase = AssembleReelUseCase(engine: storyEngine)
        let shareUseCase = ShareMomentUseCase(vault: vaultManager, config: config)

        container = AppContainer(
            config: config,
            captureUseCase: captureUseCase,
            fixUseCase: fixUseCase,
            storyUseCase: storyUseCase,
            shareUseCase: shareUseCase,
            nudgeEngine: nudgeEngine,
            vaultManager: vaultManager,
            graphManager: graphManager
        )
        self.nudgeEngine = nudgeEngine

        NiftyMomntLiteApp.registerBackgroundTasks(indexingEngine: indexingEngine)
        NiftyMomntLiteApp.scheduleIndexBatch()
    }

    var body: some Scene {
        WindowGroup {
            LiteRootView(container: container)
        }
        .backgroundTask(.appRefresh("com.hwcho99.niftyMomntLite.refresh")) { [nudgeEngine] in
            await nudgeEngine.refresh()
        }
    }
}

// MARK: - BGTask registration

extension NiftyMomntLiteApp {
    static func registerBackgroundTasks(indexingEngine: IndexingEngine) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.hwcho99.niftyMomntLite.indexBatch",
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
        let request = BGProcessingTaskRequest(identifier: "com.hwcho99.niftyMomntLite.indexBatch")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }
}
