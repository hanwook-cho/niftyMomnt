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

        let config = AppConfig.piqd_v0_6

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

        // Piqd v0.5 — drafts tray persistence. GRDB file lives at
        // `Documents/{ns}/drafts.sqlite` per `DraftsRepository`.
        let draftsRepository = DraftsRepository(config: config)
        let draftPurgeScheduler = DraftPurgeScheduler(
            drafts: draftsRepository,
            vault: vaultRepo
        )
        // Capture devSettings weakly via a closure — Debug builds honor the fake-now
        // offset; Release returns 0 unconditionally (`effectiveFakeNowOffset` gates).
        let draftsBindings = DraftsStoreBindings(
            repo: draftsRepository,
            nowOffsetProvider: { [weak devSettings] in
                devSettings?.effectiveFakeNowOffset ?? 0
            }
        )

        // Piqd v0.6 — identity, trusted circle, invite coordinator.
        let keychainStore = KeychainStore()
        // One-shot circle wipe trigger: deletes `circle.sqlite` + the Keychain
        // identity entry BEFORE the repo + service open them, so both come up
        // empty on this launch. Drain after firing.
        if devSettings.circleClearAll {
            try? keychainStore.delete(forKey: CryptoKitIdentityKeyService.primaryKey)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let circleDB = docs.appendingPathComponent(config.namespace ?? "", isDirectory: true)
                .appendingPathComponent("circle.sqlite")
            try? FileManager.default.removeItem(at: circleDB)
            devSettings.circleClearAll = false
        }
        let identityKeyService = CryptoKitIdentityKeyService(store: keychainStore)
        let trustedFriendsRepository = TrustedFriendsRepository(config: config)
        // XCUITest seed: pre-populate one friend so tests can exercise the
        // friends-list rendering + remove flow without driving the full
        // accept-an-invite path.
        if let name = env["PIQD_DEV_SEED_FRIEND_NAME"], !name.isEmpty {
            let pubKey = Data(repeating: 0xAB, count: 32)
            let friend = Friend(
                displayName: name,
                publicKey: pubKey,
                addedAt: Date(),
                lastActivityAt: nil
            )
            Task { try? await trustedFriendsRepository.insert(friend) }
        }
        let ownerProfile = OwnerProfile()
        let inviteCoordinator = InviteCoordinator(
            identity: identityKeyService,
            repo: trustedFriendsRepository,
            ownerSenderID: { ownerProfile.senderID },
            ownerDisplayName: { ownerProfile.displayName }
        )
        let incomingInviteState = IncomingInviteState(coordinator: inviteCoordinator)
        // Piqd v0.6 — Debug-only seed: hand a base64 invite payload to the state
        // as if the user just opened a `piqd://invite/<seed>` deep link. Lets
        // XCUITest exercise Accept/Decline without scanning a real QR.
        if let seed = devSettings.effectiveInviteTokenSeed,
           let url = URL(string: "piqd://invite/\(seed)") {
            incomingInviteState.queuedURL = url
        }

        // Piqd v0.6 — onboarding coordinator. Honors devSettings.onboardingForceShow
        // (set via launch arg `PIQD_DEV_ONBOARDING_RESET=1` or the dev settings
        // toggle). One-shot — drained after consumption so onboarding doesn't
        // re-show on every subsequent launch.
        let forceOnboardingShow = devSettings.onboardingForceShow
        // XCUITest-only bypass: pre-set the completion flag so the app boots
        // straight into capture without driving the four onboarding screens.
        // In `UI_TEST_MODE=1` we DEFAULT to bypassing onboarding so that all
        // pre-v0.6 UI tests continue to pass without per-test env changes.
        // `PIQD_DEV_ONBOARDING_RESET=1` overrides this to force the screens.
        let uiTestMode = env["UI_TEST_MODE"] == "1"
        let forceOnboardingComplete =
            env["PIQD_DEV_ONBOARDING_COMPLETE"] == "1" ||
            (uiTestMode && env["PIQD_DEV_ONBOARDING_RESET"] != "1")
        let onboardingCoordinator = OnboardingCoordinator(
            forceShow: forceOnboardingShow,
            forceComplete: forceOnboardingComplete
        )
        if forceOnboardingShow { devSettings.onboardingForceShow = false }

        // Piqd v0.6 — first-Roll storage warning gate (FR-STORAGE-08).
        // One-shot trigger via launch arg `PIQD_DEV_ROLL_WARNING_RESET=1` or
        // the dev settings toggle.
        let forceRollWarningShow = devSettings.firstRollWarningForceShow
        let firstRollWarningGate = FirstRollWarningGate(forceShow: forceRollWarningShow)
        if forceRollWarningShow { devSettings.firstRollWarningForceShow = false }

        container = PiqdAppContainer(
            config: config,
            captureUseCase: captureUseCase,
            vaultManager: vaultManager,
            vaultRepository: vaultRepo,
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
            makeSequenceTicker: { DispatchSourceTimerTicker() },
            motionMonitor: MotionMonitor(),
            subjectGuidance: SubjectGuidanceDetector(),
            vibeClassifier: StubVibeClassifier(),
            draftsRepository: draftsRepository,
            photoLibraryExporter: PhotoLibraryExporter(),
            shareHandoff: ShareHandoffCoordinator(),
            draftPurgeScheduler: draftPurgeScheduler,
            draftsBindings: draftsBindings,
            identityKeyService: identityKeyService,
            trustedFriendsRepository: trustedFriendsRepository,
            ownerProfile: ownerProfile,
            inviteCoordinator: inviteCoordinator,
            incomingInviteState: incomingInviteState,
            onboardingCoordinator: onboardingCoordinator,
            firstRollWarningGate: firstRollWarningGate
        )
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PiqdRootView(container: container)
                .task {
                    // Piqd v0.5 — hydrate drafts on cold launch + sweep before first render.
                    await container.draftsBindings.hydrate()
                    _ = try? await container.draftPurgeScheduler.sweep()
                    await container.draftsBindings.refreshFromRepo()
                    // Piqd v0.6 — warm the identity keypair so O3's QR is instantly
                    // available. Lazy-generates on first call; no-op afterward.
                    _ = try? await container.identityKeyService.currentKey()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        _ = try? await container.draftPurgeScheduler.sweep()
                        await container.draftsBindings.refreshFromRepo()
                    }
                }
                .onOpenURL { url in
                    // Piqd v0.6 — `piqd://invite/<token>` deep-link entry. Cold-launch
                    // URLs flow through the same handler via SwiftUI's bridging of
                    // UIScene's `openURLContexts`. Defers presentation if onboarding
                    // hasn't reached O3 yet — PiqdRootView drains the queue when the
                    // gate opens (see `.onChange` blocks there).
                    Task { @MainActor in
                        let onb = container.onboardingCoordinator
                        if onb.isComplete || onb.step == .invite {
                            await container.incomingInviteState.handle(url: url)
                        } else {
                            container.incomingInviteState.queuedURL = url
                        }
                    }
                }
        }
    }
}
