// NiftyCore/Sources/Domain/Models/ClipQualityConfig.swift
// Video clip quality ceiling for Piqd Snap Mode Clip format.
// SRS §2.3.

import Foundation

public struct ClipQualityConfig: Equatable, Sendable {
    public enum Resolution: String, Sendable { case hd1080, uhd4K }

    public let maxResolution: Resolution
    public let maxFrameRate: Int
    /// Gates 120fps to Pro devices when `true`.
    public let proOnlyHighFPS: Bool

    public init(maxResolution: Resolution, maxFrameRate: Int, proOnlyHighFPS: Bool) {
        self.maxResolution = maxResolution
        self.maxFrameRate = maxFrameRate
        self.proOnlyHighFPS = proOnlyHighFPS
    }
}
