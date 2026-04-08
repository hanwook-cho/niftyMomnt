// NiftyCore/Sources/Domain/Protocols/GeocoderProtocol.swift
// Pure Swift — zero platform imports.

import Foundation

public protocol GeocoderProtocol: AnyObject, Sendable {
    /// Reverse-geocode a GPS coordinate into a human-readable PlaceRecord.
    /// Implementations must handle rate-limiting and fall back gracefully.
    func reverseGeocode(_ coordinate: GPSCoordinate) async throws -> PlaceRecord
}
