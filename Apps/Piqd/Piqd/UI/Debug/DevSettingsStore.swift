// Apps/Piqd/Piqd/UI/Debug/DevSettingsStore.swift
// Piqd v0.2 — hidden developer-settings knobs surfaced via a 5-tap on the mode pill.
//
// These values exist to shorten test cycles: e.g. reducing the Roll daily limit from 24
// to 2 lets us verify the "Roll Full" overlay without taking 24 real photos. Settings
// persist across launches via UserDefaults("piqd.dev"). XCUITest may seed values at
// launch via `PIQD_DEV_<UPPER_SNAKE_KEY>=<value>` arguments; these are read once on init
// and written through so the persisted store stays consistent.

import Foundation
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

    // MARK: - Storage

    private let defaults: UserDefaults
    public static let suite = "piqd.dev"
    private static let keyRollDailyLimit = "rollDailyLimit"
    private static let keyGrainEnabled = "grainOverlayEnabled"
    private static let keyHapticEnabled = "hapticEnabled"
    private static let keyLongHold = "longHoldDurationSeconds"

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

        // Clamp.
        self.rollDailyLimit = max(1, min(240, rollLimit))
        self.grainOverlayEnabled = grain
        self.hapticEnabled = haptic
        self.longHoldDurationSeconds = max(0.05, min(2.0, longHold))
    }

    public func resetDefaults() {
        rollDailyLimit = 24
        grainOverlayEnabled = true
        hapticEnabled = true
        longHoldDurationSeconds = 0.6
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
