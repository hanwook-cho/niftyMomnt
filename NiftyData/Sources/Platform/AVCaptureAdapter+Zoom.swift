// NiftyData/Sources/Platform/AVCaptureAdapter+Zoom.swift
// Piqd v0.4 — public zoom surface used by the zoom pill (discrete jumps) and the pinch
// gesture (continuous ramp).
//
// IMPORTANT: as of iOS 26, `.builtInDualWideCamera` and `.builtInTripleCamera` no longer
// auto-expose ultra-wide as a sub-1.0 `videoZoomFactor` — every constituent device
// reports `min=1.0`. The "0.5×" label in iPhone Camera UI is purely a UI convention
// for "swap input to .builtInUltraWideCamera, set its zoom to 1.0".
//
// So the pill works by **swapping the active input device per zoom level**:
//   • `.ultraWide` → `.builtInUltraWideCamera` @ 1.0
//   • `.wide`      → `.builtInWideAngleCamera`  @ 1.0
//   • `.telephoto` → `.builtInTelephotoCamera`  @ 1.0 (Pro models only)
//
// Pinch ramps `videoZoomFactor` within the currently-active physical lens — no auto
// cross-lens fluid zoom. Matches Apple's pre-iOS 13 Camera app and most third-party
// cameras. ~150ms input swap per pill tap; pinch is instant.

import AVFoundation
import CoreGraphics
import Foundation
import NiftyCore
import os

private let zoomLog = Logger(subsystem: "com.hwcho99.niftymomnt", category: "AVCaptureAdapter+Zoom")

extension AVCaptureAdapter {

    /// Pill tap — maps the segment to a physical lens + zoom factor:
    ///   • `.ultraWide` → `.builtInUltraWideCamera` @ 1.0 (optical UW)
    ///   • `.wide`      → `.builtInWideAngleCamera`  @ 1.0 (optical wide)
    ///   • `.telephoto` → `.builtInWideAngleCamera`  @ 2.0 (digital crop on wide;
    ///                     mirrors Apple's "2×" pill which sensor-crops the 48MP wide
    ///                     instead of jumping to the optical tele which is 3×–5× on
    ///                     modern Pro models and has poor close-focus).
    /// ~150ms per lens swap; pure zoom factor changes are instant.
    public func setZoom(_ level: ZoomLevel) async throws {
        guard let current = activeVideoDevice else { return }
        let position: AVCaptureDevice.Position = current.position == .front ? .front : .back
        guard position == .back || level == .wide else { return }

        // Resolve target lens + zoom factor.
        let targetType: AVCaptureDevice.DeviceType
        let targetFactor: CGFloat
        switch level {
        case .ultraWide:
            targetType = .builtInUltraWideCamera
            targetFactor = 1.0
        case .wide:
            targetType = .builtInWideAngleCamera
            targetFactor = 1.0
        case .telephoto:
            // Digital 2× crop on the WIDE lens — not the optical telephoto. Wide's
            // sensor handles 2× crop with full quality and matches Apple's UX.
            targetType = .builtInWideAngleCamera
            targetFactor = 2.0
        }

        guard let target = AVCaptureDevice.default(targetType, for: .video, position: position) else {
            zoomLog.warning("setZoom — no device for type=\(targetType.rawValue) position=\(String(describing: position))")
            return
        }

        if current.deviceType == target.deviceType {
            // Same lens — just adjust zoom factor (smooth ramp for visible transition).
            try rampZoom(factor: targetFactor, on: current, rate: 6.0)
            return
        }
        try await swapBackInput(to: target)
        if let newDevice = activeVideoDevice {
            try? applyZoom(factor: targetFactor, on: newDevice)
        }
    }

    /// Pinch — continuous digital zoom on the currently-active physical lens. Clamped
    /// to the device's min/max range. Cheap; safe to call per-frame.
    public func setZoomContinuous(_ factor: Double) throws {
        guard let device = activeVideoDevice else { return }
        try applyZoom(factor: factor, on: device)
    }

    /// Discrete levels the zoom pill should render for the active camera position.
    /// Front returns `[.wide]`. Back returns whichever physical lenses are registered
    /// on this device (UW + W + Tele on Pro, UW + W on most non-Pro, W only on older).
    public func availableZoomLevels() -> [ZoomLevel] {
        guard let device = activeVideoDevice else { return [.wide] }
        let position: AVCaptureDevice.Position = device.position == .front ? .front : .back
        return AVCaptureAdapter.availablePhysicalLensLevels(position: position)
    }

    /// Empty in the lens-swap model — no continuous lens transitions during pinch.
    public func lensSwitchOverFactors() -> [Double] { [] }

    /// Current `videoZoomFactor` on the active device, or 1.0 if none.
    public func currentZoomFactor() -> Double {
        guard let device = activeVideoDevice else { return 1.0 }
        return Double(device.videoZoomFactor)
    }

    /// Current camera position (front / back). UI uses this for FR-SNAP-ZOOM-04 (front
    /// pinch is capped at 2× digital crop). Returns `.back` if no device is active.
    public func currentCameraPosition() -> CameraPosition {
        activeVideoDevice?.position == .front ? .front : .back
    }

    /// The pill segment that best describes the current lens + zoom factor. UI uses
    /// this to keep the highlighted segment in sync after taps and pinches.
    public func currentZoomLevel() -> ZoomLevel {
        guard let device = activeVideoDevice else { return .wide }
        switch device.deviceType {
        case .builtInUltraWideCamera: return .ultraWide
        case .builtInTelephotoCamera: return .telephoto
        default:
            // Wide lens — distinguish 1× vs 2× by current zoom factor.
            return device.videoZoomFactor >= 1.99 ? .telephoto : .wide
        }
    }

    // MARK: - Pure helpers (testable)

    /// Map a `ZoomLevel` pill segment to the physical `AVCaptureDevice` for that lens.
    /// Front camera always returns the front wide-angle (the only front lens on every
    /// shipping iPhone). Returns `nil` if the requested lens isn't on this device.
    public nonisolated static func physicalLens(
        for level: ZoomLevel,
        position: AVCaptureDevice.Position
    ) -> AVCaptureDevice? {
        if position == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        switch level {
        case .ultraWide: return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        case .wide:      return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        // .telephoto is a digital 2× crop on the wide lens (not the optical tele) —
        // see `setZoom` for the rationale. Returns the same device as `.wide`.
        case .telephoto: return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
    }

    /// Levels the pill should render for `position`, computed by checking which physical
    /// lens devices the system has registered. Pure — easy to unit-test by mocking the
    /// `AVCaptureDevice.default` lookups isn't possible, so this is exercised in
    /// device-checklist verification rather than XCTest.
    public nonisolated static func availablePhysicalLensLevels(position: AVCaptureDevice.Position) -> [ZoomLevel] {
        if position == .front { return [.wide] }
        var levels: [ZoomLevel] = []
        if AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil {
            levels.append(.ultraWide)
        }
        // Wide is the floor — every iPhone has one.
        levels.append(.wide)
        // 2× pill is a digital crop on wide. Available whenever the wide lens supports
        // zoom factor ≥ 2.0, which is true on every iPhone shipped in the last decade.
        if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           wide.maxAvailableVideoZoomFactor >= 2.0 {
            levels.append(.telephoto)
        }
        return levels
    }

    // MARK: - Private

    private func applyZoom(factor: Double, on device: AVCaptureDevice) throws {
        let clamped = max(device.minAvailableVideoZoomFactor,
                          min(CGFloat(factor), device.maxAvailableVideoZoomFactor))
        guard abs(device.videoZoomFactor - clamped) > 0.001 else { return }
        try device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
    }

    /// Smooth animated zoom — used for pill taps within the same lens (e.g. wide 1× → 2×).
    /// `rate` is in stops per second; `6.0` lands a 1×→2× ramp in ~170ms which feels
    /// snappy without being jarring (matches Apple Camera).
    private func rampZoom(factor: Double, on device: AVCaptureDevice, rate: Float) throws {
        let clamped = max(device.minAvailableVideoZoomFactor,
                          min(CGFloat(factor), device.maxAvailableVideoZoomFactor))
        guard abs(device.videoZoomFactor - clamped) > 0.001 else { return }
        try device.lockForConfiguration()
        device.ramp(toVideoZoomFactor: clamped, withRate: rate)
        device.unlockForConfiguration()
    }
}
