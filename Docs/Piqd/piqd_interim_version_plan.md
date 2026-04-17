# Piqd — Interim Version Plan
# v0.1 → v1.0 Feature Ladder

_Reference: piqd_PRD_v1.1.md · piqd_SRS_v1.0.md · piqd_UIUX_Spec_v1.0.md · piqd_UIUX_Requirements_v1.1.md_
_Base SDK: NiftyCore (from niftyMomnt SRS v1.2) · NiftyData platform adapters_
_Last updated: 2026-04-17 · all versions planned, none started_

---

## Purpose

Piqd is a new iOS app built on the existing NiftyCore SDK. This plan breaks v1.0 into ten thin, independently-verifiable interim versions, each validating one architectural or feature risk before the next layer is added. Every version ships with an automated test suite (XCTest / XCUITest) plus a scripted on-device checklist for anything the simulator cannot exercise (dual-camera, P2P LAN, iCloud E2EE, APNs).

Full task and checklist detail for each version lives in its own file — see `piqd_interim_v0.X_plan.md`. This file is the summary and dependency map.

---

## Legend

| Symbol | Meaning |
|--------|---------|
| ⬜ | Not Started |
| 🔄 | In Progress |
| ✅ | Complete |

---

## Version Summary

| Version | Verification goal | Detail | Status |
|---------|-------------------|--------|--------|
| [v0.1](piqd_interim_v0.1_plan.md) | Piqd Xcode target wired to NiftyCore; `AppConfig.piqd` active; Snap Still capture → local encrypted vault → device verification | [v0.1 plan](piqd_interim_v0.1_plan.md) | ⬜ |
| v0.2 | Mode system: long-hold pill + confirmation sheet → switch <150ms; grain overlay in Roll; mode persists; Roll 24-shot counter; per-mode aspect ratio default | _pending_ | ⬜ |
| v0.3 | Snap format selector (Still→Sequence→Clip→Dual); 6-frame Sequence at 333ms ±20ms; hold-to-Clip; Dual via MultiCamSession; shutter morph | _pending_ | ⬜ |
| v0.4 | Pre-shutter: zoom pill (0.5/1/2× + pinch), camera flip, invisible level, subject guidance, backlight correction, vibe hint glyph; Layer 0/1 chrome auto-retreat | _pending_ | ⬜ |
| v0.5 | Drafts tray 24h expiry (amber<1h, red<15min); iOS share sheet hand-off; "save" to Photos; per-mode vault lifecycle | _pending_ | ⬜ |
| v0.6 | Trusted Circle: Curve25519 keypair in Keychain; QR + deep-link invite; max 10 friends; onboarding O0–O4; first-Roll storage warning | _pending_ | ⬜ |
| v0.7 | Snap P2P sharing: MPC LAN + WebRTC STUN/TURN + APNs pending; ephemeral lifecycle; inbox; asset view; reaction chips; 2-exchange thread | _pending_ | ⬜ |
| v0.8 | Roll unlock ritual: 9 PM / 24h trigger; StoryEngine assembly; encrypted `RollPackage` per-recipient; CloudKit delivery; friend-side decrypt → Film Archive | _pending_ | ⬜ |
| v0.9 | Film sims (kodakWarm / fujiCool / ilfordMono); grain overlay ≥30fps; light leak; ambient metadata; Film Archive Moment view + "Save all"; vault auto-purge; Settings | _pending_ | ⬜ |
| v1.0 | Success metrics instrumented; crash-free ≥99.5%; shutter p95 <100ms, Sequence p95 <2s, mode switch p95 <150ms; App Store submission ready | _pending_ | ⬜ |

---

## Dependency Rationale

- **v0.1–v0.2** prove architecture wiring (new target + NiftyCore + mode-bifurcated Vault) before any aesthetic or sharing work — fastest failure mode to uncover.
- **v0.3–v0.4** land all capture formats and viewfinder chrome before sharing, so sharing stages test against real asset variety.
- **v0.5** (Drafts Tray) is deliberately ahead of P2P: exercises post-capture queue + iOS Photos handoff without network complexity.
- **v0.6** (Circle + Curve25519 keys) gates v0.7 and v0.8 — both depend on key exchange.
- **v0.7** before v0.8 because Snap P2P is lower-stakes if flaky; Roll unlock is the emotional core and deserves a stable base.
- **v0.9** ships aesthetic/metadata last because it's largely additive polish — should not block structural validation, and tuning needs real captures from prior stages.
- **v1.0** is a hardening pass, not new features.

---

## Test Automation Strategy

Automation coverage target: every interim version runs green in CI before on-device sign-off.

| Layer | Harness | What it covers |
|-------|---------|----------------|
| NiftyCore / NiftyData unit | XCTest | Domain models (`SequenceStrip`, `EphemeralPolicy`, `RollPackage`), use cases, engine contracts — pure Swift, runs on every build |
| Repository integration | XCTest (in-memory GRDB + temp dir) | Vault per-mode separation, ephemeral purge scheduler, 9 PM trigger math (DST, timezone, 24h-from-first), `rollCircle` immutability |
| Performance | XCTest `measure` blocks | Shutter latency p95 <100ms, Sequence interval jitter ±20ms, assembly time <2s, mode switch <150ms, grain ≥30fps |
| UI flows | XCUITest | Mode switch long-hold + confirmation sheet, format selector cycling, drafts tray timer thresholds (injected clock), zoom pill, aspect ratio toggle, onboarding happy path |
| Loopback integration | XCTest on paired simulators | P2P over LAN (two simulators on same network), CloudKit private container (two Apple IDs), APNs via sandbox |
| Device checklist (manual, scripted) | Written per-version | Dual-camera sync, real-world low-light grain, iCloud upload under poor connectivity, APNs receipt timing, screenshot-detection. Minimal and front-loaded to the version that introduces the capability |

### Automation Conventions

- Each interim plan file has a `## Verification Checklist` with an `Automated` column (Y / N / partial). Target ≥80% automated per version.
- All new domain types ship with unit tests in `NiftyCore/Tests` in the same PR as the production type.
- Every platform adapter has a protocol-level unit test against a mock; the concrete adapter gets one smoke integration test.
- Performance gates are enforced via XCTest baselines — a regression >10% fails the build.
- XCUITest uses a `UI_TEST_MODE` launch argument that injects a deterministic clock, disables network, and seeds fixture vault contents.

---

## Shared Scaffolding (applied from v0.1)

These land in v0.1 and remain stable across subsequent versions:

- `Apps/Piqd/` — new Xcode target, separate bundle ID `com.piqd.app`, separate app icon.
- `AppConfig.piqd` — see SRS §2.1. Sub-features are gated per version via `FeatureSet` flags layered on top (e.g. `piqd.v0_1 = piqd ∖ {snapMode, sequenceCapture, p2pSharing, iCloudRollPackage}`).
- `piqdRootView` — root switcher between Onboarding (v0.6+) and Capture (v0.1+).
- Separate GRDB schema namespace so Piqd and niftyMomnt can coexist on the same device during development without collision.
- CI workflow `ci-piqd.yml` running unit + UI tests on every PR touching `Apps/Piqd/`, `NiftyCore/`, or `NiftyData/`.

---

## Open Items Carried Forward

Tracked from SRS §11. Each must be resolved no later than the version listed:

| # | Item | Blocks | Target version |
|---|------|--------|----------------|
| 1 | App Store name clearance for "Piqd" | App Store submission | pre-v1.0 |
| 2 | iCloud container provisioning + entitlement | v0.8 | pre-v0.8 |
| 3 | Curve25519 Keychain storage impl | v0.6 | v0.6 |
| 4 | WebRTC STUN/TURN server selection + cost model | v0.7 | v0.7 |
| 5 | Moving Still quality threshold (Live Photo motion minimum) | v2.0 (deferred) | — |
| 6 | Film simulation CIFilter tuning | v0.9 | v0.9 |
| 7 | UX validation of 333ms / 6-frame Sequence | v0.3 | pre-v0.3 |
| 8 | 24 shots/day Roll cap validation | v0.2 | pre-v0.2 |
| 9 | Grain overlay intensity calibration | v0.9 | v0.9 |
| 10 | APNs sandbox cert + push server | v0.7 | pre-v0.7 |

---

*— End of summary — Full detail per version in `piqd_interim_v0.X_plan.md` —*
