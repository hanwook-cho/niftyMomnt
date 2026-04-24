// Apps/Piqd/Piqd/UI/Debug/DevSettingsStore.swift
// Piqd v0.2 — hidden developer-settings knobs surfaced via a 5-tap on the mode pill.
//
// These values exist to shorten test cycles: e.g. reducing the Roll daily limit from 24
// to 2 lets us verify the "Roll Full" overlay without taking 24 real photos. Settings
// persist across launches via UserDefaults("piqd.dev"). XCUITest may seed values at
// launch via `PIQD_DEV_<UPPER_SNAKE_KEY>=<value>` arguments; these are read once on init
// and written through so the persisted store stays consistent.

import Foundation
import NiftyCore
import Observation

@MainActor
@Observable
public final class DevSettingsStore {

    // MARK: - Knobs

    /// Daily cap on Roll-mode captures. Production default is 24; dev may shrink to
    /// exercise the "Roll Full" overlay quickly. Range clamp: 1…240.
    public var rollDailyLimit: Int {
        didSet { persist(\.rollDailyLimit, Self.keyRollDailyLimit, rollDailyLimit) }
    }

    /// Gate for the SwiftUI grain overlay in Roll mode. Disable when profiling preview FPS.
    public var grainOverlayEnabled: Bool {
        didSet { persist(\.grainOverlayEnabled, Self.keyGrainEnabled, grainOverlayEnabled) }
    }

    /// Soft-impact haptic during long-hold progress. Disable for quieter dev sessions.
    public var hapticEnabled: Bool {
        didSet { persist(\.hapticEnabled, Self.keyHapticEnabled, hapticEnabled) }
    }

    /// Seconds the user must hold the mode pill before the confirmation sheet appears.
    /// Production default 0.6s; range 0.05…2.0.
    public var longHoldDurationSeconds: Double {
        didSet { persist(\.longHoldDurationSeconds, Self.keyLongHold, longHoldDurationSeconds) }
    }

    // MARK: - Piqd v0.3 knobs (Snap Format Selector)

    /// Clip-mode recording ceiling. Production choices: 5 / 10 / 15 seconds; default 10.
    /// Any value outside {5, 10, 15} is clamped to the nearest allowed value at init time.
    public var clipMaxDurationSeconds: Int {
        didSet { persist(\.clipMaxDurationSeconds, Self.keyClipMaxDuration, clipMaxDurationSeconds) }
    }

    /// Sequence frame cadence in milliseconds. Production default 333; range 100…1000 so
    /// design can feel-test spacing without a rebuild.
    public var sequenceIntervalMs: Int {
        didSet { persist(\.sequenceIntervalMs, Self.keySequenceIntervalMs, sequenceIntervalMs) }
    }

    /// Number of frames a Sequence capture fires. Production default 6; range 3…12.
    public var sequenceFrameCount: Int {
        didSet { persist(\.sequenceFrameCount, Self.keySequenceFrameCount, sequenceFrameCount) }
    }

    /// Exercises the assembler-failure discard path: when true, `StoryEngine.assembleSequence`
    /// is wrapped in a throwing stub so `PiqdCaptureView` can verify no vault row lands (UI13).
    public var forceSequenceAssemblyFailure: Bool {
        didSet { persist(\.forceSequenceAssemblyFailure, Self.keyForceAsmFail, forceSequenceAssemblyFailure) }
    }

    /// Simulates non-MultiCam hardware so the Dual segment renders disabled without needing
    /// an older device in the sim farm (UI11 inverse).
    public var forceDualCamUnavailable: Bool {
        didSet { persist(\.forceDualCamUnavailable, Self.keyForceDualUnavail, forceDualCamUnavailable) }
    }

    /// Composite layout used for both Dual Still and Dual Video output. PIP is the
    /// default (rear full-frame, front inset top-right); topBottom and sideBySide
    /// produce 50/50 splits.
    public var dualLayout: DualLayout {
        didSet { defaults.set(dualLayout.rawValue, forKey: Self.keyDualLayout) }
    }

    // MARK: - Storage

    private let defaults: UserDefaults
    public static let suite = "piqd.dev"
    private static let keyRollDailyLimit = "rollDailyLimit"
    private static let keyGrainEnabled = "grainOverlayEnabled"
    private static let keyHapticEnabled = "hapticEnabled"
    private static let keyLongHold = "longHoldDurationSeconds"
    private static let keyClipMaxDuration = "clipMaxDurationSeconds"
    private static let keySequenceIntervalMs = "sequenceIntervalMs"
    private static let keySequenceFrameCount = "sequenceFrameCount"
    private static let keyForceAsmFail = "forceSequenceAssemblyFailure"
    private static let keyForceDualUnavail = "forceDualCamUnavailable"
    private static let keyDualLayout = "dualLayout"

    // MARK: - Init

    public init(defaults: UserDefaults = UserDefaults(suiteName: DevSettingsStore.suite) ?? .standard,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults

        // Defaults if nothing saved and no launch override.
        var rollLimit = (defaults.object(forKey: Self.keyRollDailyLimit) as? Int) ?? 24
        var grain     = (defaults.object(forKey: Self.keyGrainEnabled) as? Bool) ?? true
        var haptic    = (defaults.object(forKey: Self.keyHapticEnabled) as? Bool) ?? true
        var longHold  = (defaults.object(forKey: Self.keyLongHold) as? Double) ?? 0.6

        // Launch-time overrides: `PIQD_DEV_ROLL_DAILY_LIMIT=2` (env) or `-PIQD_DEV_ROLL_DAILY_LIMIT 2` (args).
        if let v = Self.readInt(environment: environment, launchArguments: launchArguments, key: "PIQD_DEV_ROLL_DAILY_LIMIT") {
            rollLimit = v
        }
        if let v = Self.readBool(environment: environment, launchArguments: launchArguments, key: "PIQD_DEV_GRAIN_ENABLED") {
            grain = v
        }
        if let v = Self.readBool(environment: environment, launchArguments: launchArguments, key: "PIQD_DEV_HAPTIC_ENABLED") {
            haptic = v
        }
        if let v = Self.readDouble(environment: environment, launchArguments: launchArguments, key: "PIQD_DEV_LONG_HOLD") {
            longHold = v
        }

        // Piqd v0.3 defaults + launch-arg overrides.
        var clipMax = (defaults.object(forKey: Self.keyClipMaxDuration) as? Int) ?? 10
        var seqIntervalMs = (defaults.object(forKey: Self.keySequenceIntervalMs) as? Int) ?? 333
        var seqFrameCount = (defaults.object(forKey: Self.keySequenceFrameCount) as? Int) ?? 6
        var forceAsmFail = (defaults.object(forKey: Self.keyForceAsmFail) as? Bool) ?? false
        var forceDualUnavail = (defaults.object(forKey: Self.keyForceDualUnavail) as? Bool) ?? false
        var dualLayoutRaw = (defaults.object(forKey: Self.keyDualLayout) as? String) ?? DualLayout.pip.rawValue

        if let v = Self.readInt(environment: environment, launchArguments: launchArguments, key: "PIQD_DEV_CLIP_MAX_DURATION") {
            clipMax = v
        }
        if let v = Self.readInt(environment: environment, launchArguments: launchArguments, key: "PIQD_DEV_SEQUENCE_INTERVAL_MS") {
            seqIntervalMs = v
        }
        if let v = Self.readInt(environment: environment, launchArguments: launchArguments, key: "PIQD_DEV_SEQUENCE_FRAME_COUNT") {
            seqFrameCount = v
        }
        if let v = Self.readBool(environment: environment, launchArguments: launchArguments, key: "PIQD_DEV_FORCE_SEQUENCE_ASSEMBLY_FAILURE") {
            forceAsmFail = v
        }
        if let v = Self.readBool(environment: environment, launchArguments: launchArguments, key: "PIQD_DEV_FORCE_DUAL_CAM_UNAVAILABLE") {
            forceDualUnavail = v
        }
        if let s = environment["PIQD_DEV_DUAL_LAYOUT"] ?? Self.argValue(launchArguments, flag: "-PIQD_DEV_DUAL_LAYOUT") {
            dualLayoutRaw = s
        }

        // Clamp.
        self.rollDailyLimit = max(1, min(240, rollLimit))
        self.grainOverlayEnabled = grain
        self.hapticEnabled = haptic
        self.longHoldDurationSeconds = max(0.05, min(2.0, longHold))
        // Clip ceiling — clamp to allowed choice set {5, 10, 15}.
        self.clipMaxDurationSeconds = [5, 10, 15].min(by: { abs($0 - clipMax) < abs($1 - clipMax) }) ?? 10
        self.sequenceIntervalMs = max(100, min(1000, seqIntervalMs))
        self.sequenceFrameCount = max(3, min(12, seqFrameCount))
        self.forceSequenceAssemblyFailure = forceAsmFail
        self.forceDualCamUnavailable = forceDualUnavail
        self.dualLayout = DualLayout(rawValue: dualLayoutRaw) ?? .pip
    }

    public func resetDefaults() {
        rollDailyLimit = 24
        grainOverlayEnabled = true
        hapticEnabled = true
        longHoldDurationSeconds = 0.6
        clipMaxDurationSeconds = 10
        sequenceIntervalMs = 333
        sequenceFrameCount = 6
        forceSequenceAssemblyFailure = false
        forceDualCamUnavailable = false
        dualLayout = .pip
    }

    // MARK: - Helpers

    private func persist<V>(_ keyPath: KeyPath<DevSettingsStore, V>, _ key: String, _ value: V) {
        defaults.set(value, forKey: key)
    }

    private static func readInt(environment: [String: String], launchArguments: [String], key: String) -> Int? {
        if let s = environment[key], let v = Int(s) { return v }
        if let s = argValue(launchArguments, flag: "-\(key)"), let v = Int(s) { return v }
        return nil
    }
    private static func readDouble(environment: [String: String], launchArguments: [String], key: String) -> Double? {
        if let s = environment[key], let v = Double(s) { return v }
        if let s = argValue(launchArguments, flag: "-\(key)"), let v = Double(s) { return v }
        return nil
    }
    private static func readBool(environment: [String: String], launchArguments: [String], key: String) -> Bool? {
        if let s = environment[key] { return parseBool(s) }
        if let s = argValue(launchArguments, flag: "-\(key)") { return parseBool(s) }
        return nil
    }
    private static func parseBool(_ s: String) -> Bool {
        switch s.lowercased() {
        case "1", "true", "yes", "on":  return true
        case "0", "false", "no", "off": return false
        default:                        return false
        }
    }
    private static func argValue(_ args: [String], flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }
}
