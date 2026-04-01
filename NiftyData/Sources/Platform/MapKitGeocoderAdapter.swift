// NiftyData/Sources/Platform/MapKitGeocoderAdapter.swift

import CoreLocation
import Foundation
import NiftyCore

public final class MapKitGeocoderAdapter: Sendable {
    public init() {}

    public func reverseGeocode(coordinate: GPSCoordinate) async throws -> String {
        // TODO: CLGeocoder.reverseGeocodeLocation(). Falls back to formatted coordinates.
        return "\(coordinate.latitude), \(coordinate.longitude)"
    }
}
