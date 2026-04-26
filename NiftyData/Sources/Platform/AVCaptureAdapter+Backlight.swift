// NiftyData/Sources/Platform/AVCaptureAdapter+Backlight.swift
// Piqd v0.4 — backlight EV bias toggle (FR-SNAP §7.4 / UIUX §2.12).
//
// Spec calls for "+0.5 EV when the scene is strongly backlit". Automatic scene detection
// (foreground/background luminance ratio) is deferred — the v0.4 surface is a manual
// toggle that callers (Dev Settings) drive. The viewfinder already shows the metered
// output, so the user gets immediate visual feedback.
//
// Always sets `.continuousAutoExposure`. Disabling resets EV bias to 0.0; the device
// remains in continuousAutoExposure (we never knock it back to .locked).

import AVFoundation
import Foundation
import os

private let backlightLog = Logger(subsystem: "com.hwcho99.niftymomnt", category: "AVCaptureAdapter+Backlight")

extension AVCaptureAdapter {

    /// EV bias applied when backlight correction is on. Spec §7.4.
    public static let backlightEvBias: Float = 0.5

    /// Apply / clear the backlight EV bias on the active video device. Idempotent.
    public func setBacklightCorrection(enabled: Bool) {
        guard let device = activeVideoDevice else {
            backlightLog.warning("setBacklightCorrection — no active device")
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            let target: Float = enabled ? Self.backlightEvBias : 0.0
            let clamped = max(device.minExposureTargetBias, min(target, device.maxExposureTargetBias))
            device.setExposureTargetBias(clamped, completionHandler: nil)
            backlightLog.info("setBacklightCorrection enabled=\(enabled) bias=\(clamped)")
        } catch {
            backlightLog.error("setBacklightCorrection lockForConfiguration failed: \(String(describing: error))")
        }
    }
}
