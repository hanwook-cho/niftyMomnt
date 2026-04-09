// NiftyCore/Sources/Domain/Protocols/CompositingAdapterProtocol.swift
// Zero platform imports — CoreImage work lives in the NiftyData conforming type.

import Foundation

public protocol CompositingAdapterProtocol: AnyObject, Sendable {
    /// Composites 4 JPEG photos into a single 9:16 strip with optional Featured Frame overlay.
    /// - Parameters:
    ///   - photos: Exactly 4 JPEG `Data` values in capture order.
    ///   - borderColor: Background/border colour.
    ///   - frameAssetName: Bundle PNG asset name, or `nil` for plain border.
    ///   - stamp: Date, location, and logo config rendered at the bottom of the strip.
    /// - Returns: JPEG data for the composite strip (1080 × 1920px).
    func compositeStrip(
        photos: [Data],
        photoShape: L4CPhotoShape,
        borderColor: L4CBorderColor,
        frameAssetName: String?,
        stamp: L4CStampConfig
    ) async throws -> Data
}
