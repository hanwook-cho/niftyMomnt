// NiftyCore/Sources/Domain/Models/AspectRatio.swift
// Piqd v0.2 — per-mode aspect ratio for viewfinder letterboxing and post-capture crop.
// Snap defaults to 9:16, Roll defaults to 4:3. Capture always runs at the sensor's native
// 4:3; the final image is center-cropped to the requested ratio before encoding.

import Foundation
import CoreGraphics

public enum AspectRatio: String, CaseIterable, Sendable {
    case nineSixteen = "9:16"
    case fourThree   = "4:3"
    case oneOne      = "1:1"

    /// width / height
    public var ratio: CGFloat {
        switch self {
        case .nineSixteen: return 9.0 / 16.0
        case .fourThree:   return 4.0 / 3.0
        case .oneOne:      return 1.0
        }
    }

    /// Default ratio for a Piqd capture mode. Non-Piqd modes fall back to 4:3.
    public static func defaultFor(_ mode: CaptureMode) -> AspectRatio {
        switch mode {
        case .snap: return .nineSixteen
        case .roll: return .fourThree
        default:    return .fourThree
        }
    }

    /// Rect to crop from a source image of `size` to produce this aspect ratio,
    /// centered. Returns the full rect if the ratios are already equal within rounding.
    public func centerCropRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let targetRatio = ratio
        let sourceRatio = size.width / size.height
        if abs(sourceRatio - targetRatio) < 0.001 {
            return CGRect(origin: .zero, size: size)
        }
        if sourceRatio > targetRatio {
            // Source is wider — crop left/right.
            let newWidth = size.height * targetRatio
            let x = (size.width - newWidth) / 2.0
            return CGRect(x: x, y: 0, width: newWidth, height: size.height)
        } else {
            // Source is taller — crop top/bottom.
            let newHeight = size.width / targetRatio
            let y = (size.height - newHeight) / 2.0
            return CGRect(x: 0, y: y, width: size.width, height: newHeight)
        }
    }
}
