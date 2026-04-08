  
**niftyMomnt**

Software Requirements Specification (SRS)

*Modular Clean Architecture · NiftyCore SDK · Multi-Variant iOS Platform*

Version 1.2 — updated April 2026 to include L4C / Photo Booth (v0.3.5)  |  Confidential

Platform: iOS 26.0+  |  Language: Swift 5.9+  |  Builds on PRD v1.6  |  Presentation layer: UI/UX Spec v1.7

Author: Han Wook Cho  |  hwcho99@gmail.com

**Document control — v1.2:** This revision is the canonical SRS for implementation work against **PRD v1.6** and **UI/UX Specification v1.7**. It supersedes `niftyMomnt_SRS_v1.1.docx.md`. v1.1 introduced platform minimums (iOS 26 / iPhone 15), PRD §15b.3 graph reference, and Film Archive naming; v1.2 is the formal release line for those product-spec versions.

# **1\. Introduction & Architectural Philosophy**

## **1.1 Purpose**

This Software Requirements Specification (SRS) defines the technical architecture, module boundaries, interface contracts, data models, and platform requirements for niftyMomnt and its companion apps. It is the primary reference for iOS engineers, and the authoritative source for all implementation decisions. It builds on **PRD v1.6** and **MRD v1.5**. SwiftUI presentation code must conform to the companion **UI/UX Specification v1.7** (screens, flows, tokens, and interaction design); the PRD remains authoritative for functional behavior and acceptance criteria.

Rationale, figures, and visual walkthroughs for Clean Architecture layers, multi-variant AppConfig, and data flow are in **`niftyMomnt_Architecture.html`** (Architecture Decision Record v1.1). That ADR is **non-normative** companion material; **this SRS remains the implementation contract** for modules, protocols, and NFRs.

## **1.2 Core Architectural Principle — Clean Architecture**

**The UI layer must be completely substitutable without modifying any business logic, data access, or AI processing code. Adding a new app variant is: new Xcode target \+ new UI layer \+ new AppConfig. Zero changes to NiftyCore.**

niftyMomnt is built on Clean Architecture adapted for iOS. All business logic lives in a local Swift Package — NiftyCore — that has zero knowledge of UIKit, SwiftUI, or any specific app target. The presentation layer is the only layer that knows about the UI framework. Every cross-layer dependency is expressed as a Swift protocol defined in the domain layer and implemented in the data layer.

## **1.3 The Dependency Rule**

Dependencies point inward only. Source code dependencies — imports, protocol conformances, type references — may only point from outer layers toward inner layers. The domain layer never imports anything from the presentation or data layers. The platform layer is never imported above the data layer.

| Layer | Contents | May import | Must never import |
| :---- | :---- | :---- | :---- |
| 1 — App Target | Xcode target, entry point, DI wiring, AppConfig | Presentation, Domain, Data, NiftyCore | Nothing — it owns everything |
| 2 — Presentation | SwiftUI Views, ViewModels, Coordinators | Domain (protocols only), NiftyCore models | Data layer implementations, iOS frameworks directly |
| 3 — Domain | Use cases, business logic, protocol definitions, domain models | Swift stdlib only | UIKit, SwiftUI, Foundation frameworks, AVFoundation, CoreML — zero platform imports |
| 4 — Data | Repository implementations, network clients, persistence | Domain, Foundation, platform frameworks | UIKit, SwiftUI, Presentation layer |
| 5 — Platform | AVFoundation, CoreML, CoreData, WeatherKit, WidgetKit, etc. | Apple SDKs | Everything above — platform frameworks are wrapped in Data layer adapters |

## **1.4 Multi-Variant Strategy**

niftyMomnt is designed as a multi-variant iOS platform from day one. All variants share NiftyCore. Each variant is a separate Xcode target with its own UI layer and AppConfig capability set. Feature flags in AppConfig control which engines are active, which asset types are enabled, and which AI modes are available — the core code is identical.

| Variant | Asset types | AI modes | UI style | Primary use case |
| :---- | :---- | :---- | :---- | :---- |
| niftyMomnt (full) | All 5 | Mode 0+1+2 | Full MZ aesthetic UI | Primary consumer app — MZ travelers |
| niftyMomnt Lite | Still \+ Clip only | Mode 0 only | Minimal, fast UI | Onboarding funnel — reduced friction entry point |
| Future variant A | Configurable | Configurable | Custom theme | TBD — defined via AppConfig at target creation |

# **2\. Package & Module Structure**

## **2.1 Repository Layout**

The monorepo is structured so that NiftyCore is a local Swift Package dependency shared by all app targets. No app target contains any business logic.

Below, the full tree uses **ASCII box-drawing** (`├──`, `└──`, `│`) in a monospace block so the hierarchy stays aligned in Markdown previews, IDEs, and exported Word/PDF.

```text
niftyMomnt/
├── NiftyCore/                          # Local Swift Package — all business logic
│   ├── Package.swift
│   ├── Sources/
│   │   ├── Domain/                     # Pure Swift — zero platform imports
│   │   │   ├── Models/                 # Moment, Asset, VibeTag, MoodPoint…
│   │   │   ├── UseCases/               # CaptureUseCase, IndexUseCase…
│   │   │   ├── Protocols/              # CaptureEngineProtocol, VaultProtocol…
│   │   │   └── AppConfig.swift         # Capability set, feature flags
│   │   ├── Engines/                    # Business logic implementations
│   │   │   ├── CaptureEngine.swift
│   │   │   ├── IndexingEngine.swift
│   │   │   ├── StoryEngine.swift
│   │   │   ├── NudgeEngine.swift
│   │   │   └── VoiceProseEngine.swift
│   │   └── Managers/                   # Cross-cutting services
│   │       ├── VaultManager.swift
│   │       ├── GraphManager.swift
│   │       └── LabClient.swift
│   └── Tests/

├── NiftyData/                          # Local Swift Package — data layer
│   ├── Sources/
│   │   ├── Repositories/               # NiftyCore protocol implementations
│   │   ├── Persistence/                # CoreData stack, SQLite graph
│   │   ├── Network/                    # LabNetworkClient, EnhancedAIClient
│   │   └── Platform/                   # AVFoundation, CoreML, WeatherKit adapters
│   └── Tests/

├── Apps/
│   ├── niftyMomnt/                     # Full app target
│   │   ├── niftyMomntApp.swift         # Entry point, DI wiring
│   │   ├── AppConfig+Full.swift
│   │   └── UI/                         # SwiftUI — full variant
│   ├── niftyMomntLite/                 # Lite app target
│   │   ├── niftyMomntLiteApp.swift
│   │   ├── AppConfig+Lite.swift
│   │   └── UI/                         # SwiftUI — Lite variant
│   └── Widgets/                        # WidgetKit extension (shared)

└── CompanionApps/
    ├── TripPlanner/
    ├── AnnualReview/
    ├── TravelPortfolio/
    └── SharedJourney/
```

## **2.2 NiftyCore Package — Module Breakdown**

| Module | Responsibility | Key types | Platform imports |
| :---- | :---- | :---- | :---- |
| Domain/Models | All value types shared across the system | Moment, Asset, AssetType, VibeTag, AcousticTag, MoodPoint, PlaceRecord | None — Swift stdlib only |
| Domain/Protocols | Defines all cross-layer contracts as Swift protocols | CaptureEngineProtocol, VaultProtocol, GraphProtocol, LabClientProtocol, IndexingProtocol | None — Swift stdlib only |
| Domain/UseCases | Orchestrates protocols to implement a user-facing operation | CaptureMomentUseCase, AssembleReelUseCase, GenerateNudgeUseCase, ShareMomentUseCase | None — pure Swift |
| Domain/AppConfig | Capability set and feature flags per variant | AppConfig struct, CapabilitySet, AssetTypeSet, AIModeSet | None |
| Engines/Capture | Manages capture session lifecycle, mode switching, live telemetry | CaptureEngine, CaptureMode, CaptureState, TelemetryPublisher | None — delegates to CaptureEngineProtocol impl |
| Engines/Indexing | On-device classification, clustering, ambient harvesting | IndexingEngine, MomentCluster, VibeClassifier, ChromaticProfiler | None — delegates to IndexingProtocol impl |
| Engines/Story | Reel assembly, Film Archive / Moment organization, caption generation | StoryEngine, ReelAssembler, AssetScorer, CaptionGenerator | None |
| Engines/Nudge | Trigger evaluation, question generation, response handling | NudgeEngine, NudgeTrigger, NudgeCard, QuestionGenerator, ResponseProcessor | None |
| Managers/Vault | Encrypted asset storage lifecycle | VaultManager, VaultItem, VaultQuery | None — delegates to VaultProtocol impl |
| Managers/Graph | Intelligence graph read/write, App Group export | GraphManager, GraphQuery, GraphExporter | None |
| Managers/Lab | Cloud VLM session management, consent, purge verification | LabClient, LabSession, LabConsent, LabResult | None — delegates to LabClientProtocol |

# **3\. AppConfig — Variant Capability System**

## **3.1 Overview**

AppConfig is the mechanism by which different app variants share identical NiftyCore code while exposing different feature sets and UI surfaces. It is a value type injected at app startup. Every engine checks AppConfig before activating any capability. No capability is hard-coded — all are runtime-configurable through this single struct.

## **3.2 AppConfig Definition**

// NiftyCore/Sources/Domain/AppConfig.swift

public struct AppConfig {

    public let appVariant:     AppVariant

    public let assetTypes:     AssetTypeSet

    public let aiModes:        AIModeSet

    public let features:       FeatureSet

    public let sharing:        SharingConfig

    public let storage:        StorageConfig

}

public enum AppVariant: String {

    case full           // niftyMomnt — full feature, MZ UI

    case lite           // niftyMomnt Lite — reduced feature

    case custom(String) // Future variants

}

public struct AssetTypeSet: OptionSet {

    public static let still      \= AssetTypeSet(rawValue: 1 \<\< 0\)

    public static let live       \= AssetTypeSet(rawValue: 1 \<\< 1\)

    public static let clip       \= AssetTypeSet(rawValue: 1 \<\< 2\)

    public static let echo       \= AssetTypeSet(rawValue: 1 \<\< 3\)

    public static let atmosphere \= AssetTypeSet(rawValue: 1 \<\< 4\)

    public static let all: AssetTypeSet \= \[.still,.live,.clip,.echo,.atmosphere\]

    public static let basic: AssetTypeSet \= \[.still,.clip\]

}

public struct AIModeSet: OptionSet {

    public static let onDevice   \= AIModeSet(rawValue: 1 \<\< 0\) // Mode 0 — always on

    public static let enhancedAI \= AIModeSet(rawValue: 1 \<\< 1\) // Mode 1 — text only

    public static let lab        \= AIModeSet(rawValue: 1 \<\< 2\) // Mode 2 — encrypted visual

    public static let full: AIModeSet \= \[.onDevice,.enhancedAI,.lab\]

}

public struct FeatureSet: OptionSet {

    public static let rollMode        \= FeatureSet(rawValue: 1 \<\< 0\)

    public static let nudgeEngine     \= FeatureSet(rawValue: 1 \<\< 1\)

    public static let moodMap         \= FeatureSet(rawValue: 1 \<\< 2\)

    public static let liveActivity    \= FeatureSet(rawValue: 1 \<\< 3\)

    public static let journalSuggest  \= FeatureSet(rawValue: 1 \<\< 4\)

    public static let trustedSharing  \= FeatureSet(rawValue: 1 \<\< 5\)

    public static let communityFeed   \= FeatureSet(rawValue: 1 \<\< 6\)

    public static let widgetKit       \= FeatureSet(rawValue: 1 \<\< 7\)

    public static let all: FeatureSet \= \[.rollMode,.nudgeEngine,.moodMap,

                                         .liveActivity,.journalSuggest,

                                         .trustedSharing,.widgetKit\]

}

## **3.3 Variant Configurations**

// Apps/niftyMomnt/AppConfig+Full.swift

extension AppConfig {

    static let full \= AppConfig(

        appVariant:  .full,

        assetTypes:  .all,

        aiModes:     .full,

        features:    .all,

        sharing:     SharingConfig(maxCircleSize: 10, labEnabled: true),

        storage:     StorageConfig(smartArchiveEnabled: true, iCloudSyncEnabled: true)

    )

}

// Apps/niftyMomntLite/AppConfig+Lite.swift

extension AppConfig {

    static let lite \= AppConfig(

        appVariant:  .lite,

        assetTypes:  .basic,   // Still \+ Clip only

        aiModes:     \[.onDevice\],

        features:    \[.rollMode, .widgetKit\],

        sharing:     SharingConfig(maxCircleSize: 5, labEnabled: false),

        storage:     StorageConfig(smartArchiveEnabled: false, iCloudSyncEnabled: false)

    )

}

## **3.4 Engine Capability Checking**

Every engine checks AppConfig before activating any capability. The config is injected at initialisation — never accessed as a global singleton. This makes engines fully testable in isolation with any capability set.

// NiftyCore/Sources/Engines/CaptureEngine.swift

public final class CaptureEngine {

    private let config: AppConfig

    private let captureAdapter: CaptureEngineProtocol

    public init(config: AppConfig, captureAdapter: CaptureEngineProtocol) {

        self.config \= config

        self.captureAdapter \= captureAdapter

    }

    public func availableModes() \-\> \[CaptureMode\] {

        CaptureMode.allCases.filter { mode in

            config.assetTypes.contains(mode.requiredAssetType)

        }

    }

}

# **4\. Domain Models**

## **4.1 Core Types**

All domain models are pure Swift value types (structs or enums). They carry no persistence annotations, no Codable conformances in the domain layer (those live in the data layer), and no UI-related properties. They are the lingua franca of the entire system.

### **Asset — the atomic capture unit**

public struct Asset: Identifiable, Equatable {

    public let id:          UUID

    public let type:        AssetType

    public let capturedAt:  Date

    public let location:    GPSCoordinate?

    public var vibeTags:    \[VibeTag\]

    public var acousticTags:\[AcousticTag\]

    public var palette:     ChromaticPalette?

    public var ambient:     AmbientMetadata

    public var transcript:  String?        // Echo only — on-device speech

    public var score:       AssetScore?    // Set by StoryEngine

    public var duration:    TimeInterval?  // Clip / Echo / Atmosphere

}

public enum AssetType: String, CaseIterable {

    case still, live, clip, echo, atmosphere

    /// Life Four Cuts composite strip — a single JPEG assembled from 4 source stills. **NEW v0.3.5**
    case l4c

    var requiredAssetType: AssetTypeSet {

        switch self {

        case .still:      return .still

        case .live:       return .live

        case .clip:       return .clip

        case .echo:       return .echo

        case .atmosphere: return .atmosphere

        case .l4c:        return .still   // booth captures use photo class

        }

    }

}

### **Moment — a cluster of related assets**

public struct Moment: Identifiable, Equatable {

    public let id:           UUID

    public var label:        String         // e.g. "Rainy Walk · Siena · Tuesday"

    public var assets:       \[Asset\]

    public var centroid:     GPSCoordinate

    public var startTime:    Date

    public var endTime:      Date

    public var dominantVibes:\[VibeTag\]      // Top 3 by frequency

    public var moodPoint:    MoodPoint?     // Set after nudge response

    public var isStarred:    Bool

    public var heroAssetID:  UUID?          // Highest-scored Still or Live

}

### **AmbientMetadata — harvested at capture time**

public struct AmbientMetadata: Equatable {

    public var weather:       WeatherCondition?  // WeatherKit

    public var temperatureC:  Double?

    public var elevationM:    Double?            // Core Location barometric

    public var sunPosition:   SunPosition?       // Golden/blue hour computed

    public var nowPlayingTrack:  String?         // MusicKit / Spotify SDK

    public var nowPlayingArtist: String?

}

### **AppConfig-related types (continued)**

public struct GPSCoordinate: Equatable {

    public let latitude:  Double

    public let longitude: Double

    public let altitude:  Double?

}

public struct ChromaticPalette: Equatable {

    public let colors: \[HSLColor\]    // Up to 5 dominant colors

}

public struct AssetScore: Equatable {

    public let motionInterest:   Double  // 0.0–1.0

    public let vibeCoherence:    Double

    public let chromaticHarmony: Double

    public let uniqueness:       Double

    public var composite:        Double { (motionInterest \+ vibeCoherence

                                         \+ chromaticHarmony \+ uniqueness) / 4 }

}

## **4.2 Intelligence Graph Models**

public struct PlaceRecord: Identifiable, Equatable {

    public let id:              UUID

    public let placeName:       String

    public let coordinate:      GPSCoordinate

    public var visitCount:      Int

    public var totalDwellMins:  Int

    public var firstVisit:      Date

    public var lastVisit:       Date

    public var dominantVibes:   \[VibeTag\]

}

public struct MoodPoint: Equatable {

    public let momentID:     UUID

    public let coordinate:   GPSCoordinate

    public let dominantMood: MoodTag

    public let palette:      \[EmotionColor\]  // 4–5 color+label pairs

}

public struct NudgeResponse: Equatable {

    public let momentID:      UUID

    public let questionText:  String

    public let responseType:  NudgeResponseType  // .chip, .voice, .text

    public let responseValue: String

    public let timestamp:     Date

}

## **4.3 L4C Domain Models** *(NEW v0.3.5)*

### **L4CRecord**
```swift
public struct L4CRecord: Identifiable, Equatable, Sendable {
    public let id: UUID                    // equals composite asset ID
    public let sourceAssetIDs: [UUID]      // exactly 4, in capture order
    public let frameID: String             // "none" or bundle PNG asset name
    public let borderColor: L4CBorderColor
    public let capturedAt: Date
    public let location: GPSCoordinate?
    public let label: String               // place name or date fallback
}
```

### **L4CBorderColor**
```swift
public enum L4CBorderColor: String, CaseIterable, Sendable {
    case white, black, pastelPink, skyBlue
}
```

### **FeaturedFrame**
```swift
public struct FeaturedFrame: Identifiable, Equatable, Sendable {
    public let id: String             // matches PNG asset name; "none" = no frame
    public let displayName: String
    public let previewColorHex: String
    public static let allCases: [FeaturedFrame] = [.none, .minimalistBlack, .springBlossom, .retroNeon]
}
```

### **L4CStampConfig**
```swift
public struct L4CStampConfig: Sendable {
    public let dateText: String
    public let locationText: String
    public let showAppLogo: Bool    // default true
}
```

# **5\. Protocol Contracts — Cross-Layer Boundaries**

## **5.1 Overview**

Every dependency that crosses a layer boundary is expressed as a Swift protocol defined in the domain layer. The data layer provides concrete implementations. The presentation layer and engines depend only on the protocols — never on implementations. This is what makes each layer independently testable and swappable.

## **5.2 CaptureEngineProtocol**

// NiftyCore/Sources/Domain/Protocols/CaptureEngineProtocol.swift

public protocol CaptureEngineProtocol: AnyObject {

    var captureState: AnyPublisher\<CaptureState, Never\> { get }

    var telemetry:    AnyPublisher\<CaptureTelemetry, Never\> { get }

    func startSession(mode: CaptureMode, config: AppConfig) async throws

    func stopSession() async

    func captureAsset() async throws \-\> Asset

    func switchMode(to mode: CaptureMode) async throws

    func applyPreset(\_ preset: VibePreset) async

}

public enum CaptureMode: CaseIterable {

    case still, live, clip, echo, atmosphere

    /// Photo Booth mode — triggers BoothCaptureView; ghost label "BOOTH"; session class change deferred to START tap. **NEW v0.3.5**
    case photoBooth

    var requiredAssetType: AssetTypeSet { /\* see Section 4 \*/ }

}

public struct CaptureTelemetry {

    public let mode:         CaptureMode

    public let elapsed:      TimeInterval   // 0.0 → ceiling

    public let ceiling:      TimeInterval   // Configured max

    public let isWarning:    Bool           // elapsed \>= ceiling \- 5.0

    public let audioLevel:   Float?         // Echo only: 0.0–1.0

}

## **5.3 VaultProtocol**

public protocol VaultProtocol: AnyObject {

    func save(\_ asset: Asset, data: Data) async throws

    func load(\_ assetID: UUID) async throws \-\> (Asset, Data)

    func delete(\_ assetID: UUID) async throws

    func query(\_ query: VaultQuery) async throws \-\> \[Asset\]

    func exportToPhotoLibrary(\_ assetID: UUID) async throws

    var storageUsedBytes: AnyPublisher\<Int64, Never\> { get }

}

## **5.4 GraphProtocol**

public protocol GraphProtocol: AnyObject {

    // Write — NiftyCore only

    func saveMoment(\_ moment: Moment) async throws

    func updateVibeTag(\_ tag: VibeTag, for assetID: UUID) async throws

    func saveNudgeResponse(\_ response: NudgeResponse) async throws

    func saveMoodPoint(\_ point: MoodPoint) async throws

    func updatePlaceRecord(\_ record: PlaceRecord) async throws

    // Read — NiftyCore \+ companion apps via SDK

    func fetchMoments(query: GraphQuery) async throws \-\> \[Moment\]

    func fetchPlaceHistory(limit: Int) async throws \-\> \[PlaceRecord\]

    func fetchMoodMap(range: DateInterval) async throws \-\> \[MoodPoint\]

    func exportForCompanion() async throws \-\> GraphExport

    // L4C — NEW v0.3.5

    func saveL4CRecord(_ record: L4CRecord) async throws

    func fetchL4CRecords() async throws \-\> \[L4CRecord\]

    func deleteL4CRecord(_ id: UUID) async throws \-\> \[UUID\]   // returns source asset IDs

}

## **5.5 IndexingProtocol**

public protocol IndexingProtocol: AnyObject {

    func classifyImage(\_ assetID: UUID, imageData: Data) async throws \-\> \[VibeTag\]

    func analyzeAudio(\_ assetID: UUID, audioData: Data) async throws \-\> \[AcousticTag\]

    func extractPalette(\_ assetID: UUID, imageData: Data) async throws \-\> ChromaticPalette

    func harvestAmbientMetadata(at location: GPSCoordinate?,

                                at time: Date) async throws \-\> AmbientMetadata

    func clusterMoments(assets: \[Asset\]) async throws \-\> \[Moment\]

}

## **5.6 LabClientProtocol**

public protocol LabClientProtocol: AnyObject {

    // Mode 1 — text-only Enhanced AI

    func generateCaption(for moment: Moment,

                         tone: CaptionTone) async throws \-\> \[CaptionCandidate\]

    func transformProse(\_ transcript: String,

                        styles: \[ProseStyle\]) async throws \-\> \[ProseVariant\]

    func generateNudgeQuestion(for moment: Moment,

                               trigger: NudgeTrigger) async throws \-\> NudgeCard

    // Mode 2 — encrypted visual Lab

    func requestLabSession(assets: \[UUID\],

                           consent: LabConsent) async throws \-\> LabSession

    func processLabSession(\_ session: LabSession) async throws \-\> LabResult

    func verifyPurge(sessionID: UUID) async throws \-\> PurgeConfirmation

}

## **5.7 NudgeEngineProtocol**

public protocol NudgeEngineProtocol: AnyObject {

    var pendingNudge: AnyPublisher\<NudgeCard?, Never\> { get }

    func evaluateTriggers(for moment: Moment) async

    func submitResponse(\_ response: NudgeResponse) async throws

    func dismiss(nudgeID: UUID)

    func snooze(nudgeID: UUID, until: Date)

}

# **6\. Engine Specifications**

## **6.1 CaptureEngine**

### **Responsibilities**

* Owns the capture session lifecycle — start, stop, mode switch.

* Publishes real-time CaptureState and CaptureTelemetry via Combine publishers.

* Implements the mode navigation logic (swipe model, ghost label trigger, available modes filtered by AppConfig).

* Orchestrates asset assembly for complex types (Atmosphere \= Still frame \+ Echo recording composed into a single Asset).

* Never imports AVFoundation — all camera/microphone access is delegated to the CaptureEngineProtocol implementation in NiftyData.

### **State machine**

| State | Entry condition | Exit condition | Published telemetry |
| :---- | :---- | :---- | :---- |
| idle | App launch / session end | startSession() called | None |
| ready | Session started successfully | captureAsset() or switchMode() | Current mode, available modes |
| capturing | captureAsset() called | Asset complete or error | CaptureTelemetry: elapsed, ceiling, isWarning, audioLevel |
| processing | Raw capture complete | Asset saved to vault | None — async background |
| error | Any recoverable failure | Error cleared / session restarted | CaptureError type |

## **6.2 IndexingEngine**

### **Responsibilities**

* Runs entirely on-device, triggered when device is charging and screen is off.

* Processes unindexed assets from the vault in FIFO order.

* Calls IndexingProtocol methods for image classification, audio analysis, chromatic profiling, and ambient metadata harvesting.

* Produces Moment clusters from processed assets using the GPS \+ time \+ vibe-similarity algorithm.

* Writes all results back to the graph via GraphProtocol — the indexing engine never directly writes to persistence.

### **Processing pipeline per asset**

| \# | Step | Input | Output to graph |
| :---- | :---- | :---- | :---- |
| 1 | Image classification (Still, Live, Clip, Atmosphere) | Image data from vault | Place tags, vibe tags, aesthetic tags |
| 2 | Acoustic analysis (Echo, Clip audio, Atmosphere audio) | Audio data from vault | Acoustic tags (Windy, Crowded, Music, Rain, Ocean, Quiet) |
| 3 | Chromatic profiling (all visual types) | Image data from vault | ChromaticPalette — up to 5 HSL colors |
| 4 | Ambient metadata harvest | GPS coordinate, capture timestamp | AmbientMetadata (weather, elevation, sun position, Now Playing) |
| 5 | Speech transcription (Echo assets) | Audio data from vault | transcript string on Asset |
| 6 | Moment clustering (batch, runs after 3+ assets indexed) | All indexed assets in rolling 90-min / 200m window | Moment records with label, centroid, dominantVibes |

## **6.3 StoryEngine**

### **Responsibilities**

* Scores all assets using the AssetScorer (motion interest, vibe coherence, chromatic harmony, uniqueness).

* Assembles Reel candidate lists using time-based or vibe-based sequencing heuristics.

* If LabResult is available for the Moment, uses the narrative graph for cinematic sequencing instead of heuristics.

* Generates caption candidates using the LabClientProtocol (Mode 0 on-device or Mode 1 Enhanced AI).

* Manages Film Archive–style Moment organization: assigns hero asset, generates Moment label via reverse geocoding \+ dominant vibe.

### **AssetScorer weights**

| Factor | Weight | Derivation |
| :---- | :---- | :---- |
| Motion interest | 0.30 | Clips with significant subject motion score 0.8–1.0. Stills and Lives score 0.3–0.6 based on composition analysis. |
| Vibe coherence | 0.30 | Score \= overlap between asset vibe tags and Moment dominant vibes / total Moment vibe count. |
| Chromatic harmony | 0.20 | HSL distance between asset palette and Moment cluster palette centroid. Closer \= higher score. |
| Uniqueness | 0.20 | 1.0 minus average cosine similarity to all other assets in cluster. Penalises near-duplicates from burst sequences. |

## **6.4 NudgeEngine**

### **Trigger evaluation algorithm**

The NudgeEngine runs a trigger evaluation pass whenever: (a) the app is foregrounded, (b) a JournalingSuggestions callback fires, or (c) a CoreMotion activity-cessation event is received. It evaluates all trigger signals, applies the minimum-quiet-period gate, and — if two or more signals are present — selects the highest-priority question template and assembles a NudgeCard.

func evaluateTriggers(for moment: Moment) async {

    guard canShowNudge() else { return }  // cool-down, daily cap

    let signals \= await collectSignals(for: moment)

    guard signals.count \>= 2 else { return }

    let trigger \= selectPrimaryTrigger(from: signals)

    let card: NudgeCard

    if config.aiModes.contains(.enhancedAI) {

        card \= try await labClient.generateNudgeQuestion(for: moment,

                                                          trigger: trigger)

    } else {

        card \= templateEngine.buildCard(trigger: trigger, moment: moment)

    }

    pendingNudgeSubject.send(card)

}

### **NudgeCard structure**

public struct NudgeCard: Identifiable {

    public let id:           UUID

    public let momentID:     UUID

    public let heroAssetID:  UUID?

    public let question:     String

    public let chips:        \[NudgeChip\]      // 2–3 quick replies

    public let trigger:      NudgeTrigger

    public let expiresAt:    Date              // 24h from generation

}

public struct NudgeChip: Identifiable {

    public let id:    UUID

    public let label: String   // e.g. "It got quieter"

    public let value: String   // stored as NudgeResponse.responseValue

}

## **6.5 LifeFourCutsUseCase** *(NEW v0.3.5)*

### **Responsibilities**

- `captureOneShot() async throws -> (Asset, Data)`: captures one still via `CaptureEngineProtocol.captureAsset()`, reads JPEG from temp dir, returns asset + data. Called 4 times in the capture loop managed by BoothCaptureView's ViewModel.

- `buildAndSave(shots: [(Asset, Data)], frame: FeaturedFrame, borderColor: L4CBorderColor, config: L4CStampConfig) async throws -> L4CRecord`: saves 4 source stills (hidden flag), geocodes location, composites strip via `CompositingAdapterProtocol`, saves composite as `.l4c` asset to vault, saves `L4CRecord` to graph via `GraphProtocol.saveL4CRecord(_:)`, posts `niftyMomentCaptured` notification.

- `recomposite(photos: [Data], frame: FeaturedFrame, borderColor: L4CBorderColor) async throws -> Data`: no-persist preview recomposite for live preview in `StripPreviewSheet`. Returns composited JPEG `Data` without saving to vault or graph.

### **CompositingAdapterProtocol**

```swift
public protocol CompositingAdapterProtocol: AnyObject {
    func compositeStrip(
        photos: [Data],
        frame: FeaturedFrame,
        borderColor: L4CBorderColor,
        stampConfig: L4CStampConfig
    ) async throws -> Data   // returns 1080×1920 JPEG
}
```

Implemented by `CoreImageCompositingAdapter` in `NiftyData/Platform/`. Canvas 1080×1920, slot geometry per PRD v1.7 §3.10.3. CoreText stamp. Featured Frame PNG composited on top.

# **7\. Data Layer Specifications**

## **7.1 VaultRepository — Encrypted Asset Storage**

| Attribute | Specification |
| :---- | :---- |
| Encryption | AES-256-GCM. Key derived from device biometric auth via SecKeyCreateRandomKey stored in iOS Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly. |
| Storage backend | FileManager-managed directory within the app sandbox. Asset binary data stored as encrypted files; metadata stored in CoreData with NSPersistentCloudKitContainer (optional iCloud sync for metadata only). |
| Asset file naming | UUID-based filenames with type extension: {uuid}.still.enc, {uuid}.clip.enc, {uuid}.echo.enc. No human-readable names in the file system. |
| Query interface | VaultQuery is a value type with filter, sort, and pagination parameters. Implemented as NSFetchRequest under the hood — never exposed to the domain layer. |
| Smart archive | Background task triggered on app backgrounding. Compresses Stills older than threshold (configurable in AppConfig) to JPEG 80% quality. Original encrypted file replaced. Metadata preserved unchanged. |

## **7.2 GraphRepository — Intelligence Graph**

| Attribute | Specification |
| :---- | :---- |
| Database | SQLite via SQLCipher for at-rest encryption. Database file located in the iOS App Group shared container (com.niftymomnt.group) — accessible to all companion apps with the same Team ID. |
| Schema version | Integer schema\_version column in a metadata table. Incremented on any schema change. Companion apps check version on launch and show update prompt if version is ahead of their supported range. |
| Write access | NiftyCore only. The SQLite WAL (Write-Ahead Logging) mode is enabled. NiftyCore holds the exclusive writer connection. Companion apps open read-only connections. |
| Tables | moments, vibe\_tags, acoustic\_tags, ambient\_metadata, nudge\_responses, mood\_map, place\_history, asset\_scores — as defined in PRD v1.6 §15b.3 (Intelligence Graph Schema). |
| GraphExport | A versioned JSON snapshot of the graph exported to the App Group container on demand. Used by companion apps that prefer JSON over SQLite. Maximum export size governed by AppConfig.storage. |

## **7.2a L4C Database Schema** *(NEW v0.3.5)*

The `l4c_records` table is added to the GraphRepository SQLite database alongside the existing intelligence graph tables.

```sql
CREATE TABLE l4c_records (
    id           TEXT PRIMARY KEY,
    source_ids   TEXT NOT NULL,   -- JSON array of 4 UUIDs
    frame_id     TEXT NOT NULL,
    border_color TEXT NOT NULL,
    captured_at  REAL NOT NULL,
    location_lat REAL,
    location_lon REAL,
    label        TEXT NOT NULL
);
CREATE INDEX idx_l4c_captured_at ON l4c_records(captured_at DESC);
```

Source stills are stored as normal `.still` assets in the vault with a `hidden: true` metadata flag. The `l4c_records.source_ids` JSON array references these hidden asset IDs. On delete of an L4CRecord, the `deleteL4CRecord(_:)` method returns the source asset IDs for cascade deletion from the vault.

## **7.3 Platform Adapters**

All iOS framework interactions are isolated in adapter classes in NiftyData/Platform/. These implement the protocols defined in NiftyCore/Domain/Protocols/. The domain and engine layers never import Apple frameworks directly.

| Adapter | Implements | Wraps |
| :---- | :---- | :---- |
| AVCaptureAdapter | CaptureEngineProtocol | AVFoundation: AVCaptureSession, AVCaptureDevice, AVAssetWriter, AVAudioRecorder. Handles all camera/microphone lifecycle. Publishes CaptureState and CaptureTelemetry. |
| CoreMLIndexingAdapter | IndexingProtocol (classification, audio, palette) | Vision.VNClassifyImageRequest, SoundAnalysis.SNClassifySoundRequest, CoreImage for palette extraction. All inference runs on Neural Engine. |
| SpeechAdapter | IndexingProtocol (transcript) | Speech.SFSpeechRecognizer with SFSpeechRecognitionRequest. On-device recognition model (no network). Produces transcript string for Echo assets. |
| WeatherKitAdapter | IndexingProtocol (ambient harvest) | WeatherKit.WeatherService. Fetches current conditions at GPS coordinate. 30-minute cache. Returns WeatherCondition? — nil on cache miss after 6h. |
| MapKitGeocoderAdapter | IndexingProtocol (ambient harvest) | MapKit.CLGeocoder.reverseGeocodeLocation(). Returns neighborhood/city string. Falls back to formatted coordinates on cache miss. |
| MusicKitAdapter | IndexingProtocol (ambient harvest) | MusicKit.MusicPlayer.Queue.currentEntry. Reads currently playing track. Fallback: SpotifyiOS SDK if authorized. Returns nil gracefully if nothing playing. |
| JournalSuggestionsAdapter | NudgeEngineProtocol (trigger source) | JournalingSuggestions framework. Delivers JSuggestion clusters to NudgeEngine as trigger signals. User authorization via JSAuthorizationStatus. |
| LabNetworkAdapter | LabClientProtocol (Mode 1 \+ Mode 2\) | URLSession with TLS 1.3 and certificate pinning. Handles both text-only Enhanced AI calls and encrypted-asset Lab sessions. Implements purge verification. |
| CoreImageCompositingAdapter *(NEW v0.3.5)* | CompositingAdapterProtocol | CGContext-based strip compositor. Canvas 1080×1920, slot geometry per PRD v1.7 §3.10.3. CoreText stamp (wordmark + date/location). Featured Frame PNG composited on top via CIImage blending. |

# **8\. Dependency Injection & Composition Root**

## **8.1 Overview**

All dependencies are injected at the composition root — the app entry point. No engine or use case creates its own dependencies. No singletons in NiftyCore. This makes every component independently testable: swap in a mock implementation conforming to the protocol and the engine has no knowledge of the change.

## **8.2 Composition Root Pattern**

// Apps/niftyMomnt/niftyMomntApp.swift

@main

struct NiftyMomntApp: App {

    private let container: AppContainer

    init() {

        let config \= AppConfig.full

        // Platform adapters (NiftyData)

        let captureAdapter   \= AVCaptureAdapter(config: config)

        let indexingAdapter  \= CoreMLIndexingAdapter(config: config)

        let vaultRepo        \= VaultRepository(config: config)

        let graphRepo        \= GraphRepository(config: config)

        let labClient        \= LabNetworkAdapter(config: config)

        let nudgeTrigger     \= JournalSuggestionsAdapter(config: config)

        // Core engines (NiftyCore) — injected with protocol implementations

        let captureEngine    \= CaptureEngine(config: config,

                                             captureAdapter: captureAdapter)

        let indexingEngine   \= IndexingEngine(config: config,

                                              adapter: indexingAdapter,

                                              graph: graphRepo)

        let storyEngine      \= StoryEngine(config: config,

                                           vault: vaultRepo,

                                           graph: graphRepo,

                                           lab: labClient)

        let nudgeEngine      \= NudgeEngine(config: config,

                                           graph: graphRepo,

                                           lab: labClient,

                                           triggerSource: nudgeTrigger)

        let vaultManager     \= VaultManager(vault: vaultRepo)

        let graphManager     \= GraphManager(graph: graphRepo)

        // Use cases — injected with engines

        let captureUseCase   \= CaptureMomentUseCase(

                                   engine: captureEngine,

                                   vault: vaultManager,

                                   indexing: indexingEngine)

        let storyUseCase     \= AssembleReelUseCase(engine: storyEngine)

        let shareUseCase     \= ShareMomentUseCase(

                                   vault: vaultManager,

                                   config: config)

        container \= AppContainer(

            config: config,

            captureUseCase: captureUseCase,

            storyUseCase: storyUseCase,

            shareUseCase: shareUseCase,

            nudgeEngine: nudgeEngine,

            vaultManager: vaultManager,

            graphManager: graphManager

        )

    }

    var body: some Scene {

        WindowGroup {

            RootView(container: container)

        }

    }

}

## **8.3 Testing Strategy**

Because every dependency is injected via protocol, unit tests never touch real hardware, file systems, or networks. Each engine can be tested with lightweight mock implementations.

// Tests/NiftyCore/CaptureEngineTests.swift

final class CaptureEngineTests: XCTestCase {

    var engine: CaptureEngine\!

    var mockAdapter: MockCaptureAdapter\!

    override func setUp() {

        mockAdapter \= MockCaptureAdapter()

        engine \= CaptureEngine(config: .lite,   // test with Lite config

                               captureAdapter: mockAdapter)

    }

    func test\_availableModes\_lite\_excludesEchoAndAtmosphere() {

        let modes \= engine.availableModes()

        XCTAssertFalse(modes.contains(.echo))

        XCTAssertFalse(modes.contains(.atmosphere))

        XCTAssertTrue(modes.contains(.still))

        XCTAssertTrue(modes.contains(.clip))

    }

}

# **9\. Concurrency Model**

## **9.1 Overview**

niftyMomnt uses Swift Concurrency (async/await, actors, structured concurrency) exclusively. No manual GCD dispatch queues, no OperationQueue. Combine is used only for reactive UI binding — all async work uses async/await.

## **9.2 Actor Isolation**

| Component | Isolation | Rationale |
| :---- | :---- | :---- |
| CaptureEngine | @MainActor — capture state must be read from main thread for UI binding | AVCaptureSession callbacks come on background threads; bridge to main via await. |
| IndexingEngine | actor IndexingEngine — serialises background indexing operations | Prevents concurrent writes to the graph from overlapping indexing passes. |
| VaultManager | actor VaultManager — serialises all vault reads and writes | Prevents torn writes during concurrent save \+ smart archive operations. |
| GraphManager | actor GraphManager — serialises all graph mutations | SQLite WAL mode handles concurrent reads but mutations must be serialised. |
| NudgeEngine | @MainActor — nudge cards published to UI | NudgeCard publisher subscribed by ViewModel on main thread. |
| StoryEngine | Nonisolated — stateless scoring and assembly | Asset scoring and Reel assembly are pure functional operations with no shared mutable state. |

## **9.3 Background Task Strategy**

* **IndexingEngine:** Registered as a BGProcessingTask (requires charging \+ idle). Triggered by BGTaskScheduler. Maximum runtime: 60 seconds per pass. Processes up to 50 assets per pass, then reschedules.

* **Smart archive:** Registered as a BGAppRefreshTask. Runs when device is charging. Compresses eligible assets in batches of 10\.

* **Graph export:** Triggered on app backgrounding via scenePhase observer. Exports updated GraphExport JSON to App Group container. Maximum 2s — lightweight operation given graph is \<50MB.

* **Lab session:** Runs as a user-initiated Task with structured cancellation. If the app is backgrounded during a Lab session, the session is cancelled and the user is notified on next foreground.

# **10\. Security & Privacy Architecture**

## **10.1 Encryption Stack**

| Asset / data | Encryption | Key management |
| :---- | :---- | :---- |
| Raw assets (vault) | AES-256-GCM. Each asset encrypted with a unique per-asset data encryption key (DEK). | DEK wrapped with the master key. Master key stored in iOS Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly. Never transmitted. |
| Intelligence graph | SQLCipher AES-256. Single database-level encryption key. | Database key stored in iOS Keychain, shared within App Group via kSecAttrAccessGroup. Accessible only to same-Team-ID apps. |
| Lab session (transit) | TLS 1.3 \+ certificate pinning. Assets additionally AES-256-GCM encrypted on-device before transmission. | Session encryption key derived ephemerally from Diffie-Hellman exchange. Never stored. |
| Enhanced AI (transit) | TLS 1.3 \+ certificate pinning. Only plaintext metadata transmitted — no encryption of content necessary as no sensitive assets are sent. | Standard TLS certificate pinned to niftyMomnt server CA. |
| iCloud backup (optional) | NSFileProtectionCompleteUnlessOpen for vault files. CloudKit uses Apple's end-to-end encryption for private database. | Apple manages CloudKit keys in user's iCloud keychain. niftyMomnt has no server-side key access. |

## **10.2 Privacy Framework Requirements**

| Framework | Permission required | Usage description (Info.plist) |
| :---- | :---- | :---- |
| Camera | NSCameraUsageDescription | niftyMomnt uses your camera to capture moments. |
| Microphone | NSMicrophoneUsageDescription | niftyMomnt records ambient sound for Echo and Atmosphere moments. |
| Location (when in use) | NSLocationWhenInUseUsageDescription | niftyMomnt uses your location to tag moments and organize your Film Archive. |
| Photo Library (add only) | NSPhotoLibraryAddUsageDescription | niftyMomnt saves Live Photos to your photo library when you export them. |
| Speech Recognition | NSSpeechRecognitionUsageDescription | niftyMomnt transcribes your voice notes on-device to create text. |
| Apple Music (MusicKit) | NSAppleMusicUsageDescription | niftyMomnt remembers what you were listening to when you capture a moment. |
| Health (motion — optional) | NSMotionUsageDescription | niftyMomnt uses motion data to suggest reflection prompts after a walk or activity. |
| Journaling Suggestions | JSAuthorizationStatus system prompt | niftyMomnt uses iOS Journaling Suggestions to prompt reflection at the right moment. |

# **11\. Non-Functional Requirements**

## **11.1 Performance Targets**

| Requirement | Target | Minimum supported device | Measurement |
| :---- | :---- | :---- | :---- |
| Cold app launch → capture-ready | \< 1.5 seconds | iPhone 15 | XCTest application launch metric |
| Capture → preview latency (Still) | \< 300ms | iPhone 15 | CACurrentMediaTime() diff at shutter → preview render |
| Mode switch animation | \< 150ms | iPhone 15 | Gesture recognition → ghost label first frame |
| Film Archive load (5,000 assets) | \< 2 seconds | iPhone 15 | Time to first Moment card rendered |
| On-device indexing per asset | \< 3 seconds (background) | iPhone 15 | Capture timestamp → vibe tags written to graph |
| Reel assembly (15 assets) | \< 20 seconds | iPhone 15 | User trigger → preview-ready Reel |
| Graph export to App Group | \< 2 seconds | iPhone 15 | graphManager.exportForCompanion() duration |
| App memory (active capture) | \< 200 MB | iPhone 15 | Instruments Memory profiler during Clip recording |

## **11.2 Code Quality Requirements**

* **Test coverage:** NiftyCore domain layer: minimum 85% line coverage. Engine logic: minimum 80%. Platform adapters in NiftyData: minimum 60% (hardware-dependent code excluded from coverage requirement).

* **SwiftLint:** All targets must pass SwiftLint with the project .swiftlint.yml configuration. Zero errors permitted in CI. Warnings addressed within the same sprint.

* **No direct framework imports above data layer:** CI check validates that no source file in NiftyCore/Sources imports UIKit, SwiftUI, AVFoundation, CoreML, or any Apple platform framework. Violation blocks merge.

* **Protocol-first new features:** Any new cross-layer capability must be introduced as a protocol in Domain/Protocols/ before any implementation is written. Protocol reviewed and approved before implementation sprint begins.

## **11.3 Supported Devices & OS**

| Requirement | Specification | Notes |
| :---- | :---- | :---- |
| Minimum iOS | iOS 26.0 | Per PRD v1.6 §13.4 — updated AI Intelligence frameworks, AVCaptureMultiCamSession, Journaling Suggestions API, computational photography APIs |
| Minimum device | iPhone 15 | Per PRD v1.6 §13.4 — Neural Engine and on-device ML targets at shipping minimum |
| Primary test devices | iPhone 15 Pro, iPhone 15, iPhone 16 family | Cover A16+ range; lowest supported SKU is iPhone 15 |
| Swift version | Swift 5.9+ | Team may adopt Swift 6 when toolchain aligns with iOS 26 SDK |
| Xcode version | Xcode shipping iOS 26 SDK | Use the Xcode version Apple pairs with the iOS 26 SDK for App Store submission |
| iPadOS | Not supported v1.0 | Per PRD v1.6 §13.4; evaluate at v2.0 milestone |

*— End of Document — niftyMomnt SRS v1.2 (updated April 2026, includes L4C v0.3.5) · PRD v1.7 · UI/UX v1.8 —*