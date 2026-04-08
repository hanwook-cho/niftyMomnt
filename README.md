# niftyMomnt

A capture-first iOS camera journal. Shoot first, reflect later — niftyMomnt wraps every photo and clip in ambient context (location, weather, music, time of day) and organises them into a dark, editorial film archive.

---

## Architecture

```
niftyMomnt/
├── NiftyCore/          # Domain layer — zero platform imports
│   ├── Sources/
│   │   ├── Domain/
│   │   │   ├── Models/         Moment, Asset, VibeTag, AppConfig …
│   │   │   ├── Protocols/      CaptureEngineProtocol, VaultProtocol …
│   │   │   └── UseCases/       CaptureMomentUseCase, FixAssetUseCase …
│   │   ├── Engines/            CaptureEngine, IndexingEngine, StoryEngine …
│   │   └── Managers/           VaultManager, GraphManager
│   └── Tests/
│
├── NiftyData/          # Platform adapters — AVFoundation, CoreML, CloudKit …
│   └── Sources/
│       ├── Platform/   AVCaptureAdapter, SoundStampAdapter, CoreMLIndexingAdapter …
│       ├── Repositories/       VaultRepository, GraphRepository
│       └── Network/            LabNetworkAdapter
│
└── Apps/
    ├── niftyMomnt/     # Full-feature app
    └── niftyMomntLite/ # Lite variant (basic capture, no Sound Stamp / Photo Fix)
```

**NiftyCore** is a pure Swift package with no platform imports — all AVFoundation, CoreML, CloudKit, and other OS frameworks live in **NiftyData** behind protocol adapters. The **Apps** layer wires everything together through `AppContainer` and renders the UI in SwiftUI.

---

## Key Features

| Feature | Description |
|---|---|
| **Capture Hub** | Full-screen viewfinder with four zones: glass top bar (flash, timer, film counter, live photo), live preview, preset bar with peek swatches, and shutter row |
| **Film Archive** | Dark editorial journal grouped by week — roll cards with thumbnail strips, preset accent colours, and vibe tags |
| **Vibe Presets** | Five film presets (Film Roll, Amalfi, Tokyo Neon, Nordic, Disposable) with per-preset accent colour applied across the UI |
| **Sound Stamp** | Ambient audio fingerprint captured at shutter press and used to tag the vibe of each moment |
| **Roll Mode** | Film-roll constraint — 17 shots per roll, strip counter in Zone A |
| **Photo Fix** | On-device AI enhancement via CoreImage / CoreML pipeline |
| **Vault** | Face ID–gated private archive |
| **Multi-variant** | `.full` config (all features) and `.lite` config (basic assetTypes only) share the same codebase |

---

## Requirements

- Xcode 16+
- iOS 18+ deployment target (iOS 26 Liquid Glass materials used)
- Physical iPhone recommended — AVCaptureSession does not run on Simulator

---

## Getting Started

```bash
git clone https://github.com/hanwook-cho/niftyMomnt.git
cd niftyMomnt
open niftyMomnt.xcworkspace
```

Select the **niftyMomnt** scheme, choose a physical device, and build.

> Swift Package dependencies (NiftyCore, NiftyData) are resolved automatically by Xcode from the workspace.

---

## UI Spec

Design documents live in [`Docs/`](Docs/). The current production spec is **v1.8**.

| File | Description |
|---|---|
| `niftyMomnt_UIUX_Spec_v1.8.html` | Full UI/UX specification (current) |
| `niftyMomnt_SRS_v1_0_Definitive.docx.pdf` | Software Requirements Specification |
| `niftyMomnt_PRD_v1_5.html` | Product Requirements v1.5 that needs to be updated to v1.6 |
| `niftyMomnt_PRD_v1.6_Delta.html` | Product Requirements changes from v1.5 (`niftyMomnt_PRD_v1_5.html`) to v1.6  Document |

---

## License

Private repository. All rights reserved.
