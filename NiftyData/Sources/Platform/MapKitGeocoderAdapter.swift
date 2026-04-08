// NiftyData/Sources/Platform/MapKitGeocoderAdapter.swift
// CLGeocoder reverse-geocode → PlaceRecord.
// Rate limit: CLGeocoder allows one request per ~0.5s; results are cached in-process.

import CoreLocation
import Foundation
import NiftyCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "MapKitGeocoder")

public final class MapKitGeocoderAdapter: GeocoderProtocol {
    // CLGeocoder is not Sendable, so we create one per call rather than sharing.
    public init() {}

    public func reverseGeocode(_ coordinate: GPSCoordinate) async throws -> PlaceRecord {
        log.debug("reverseGeocode ▶ lat=\(coordinate.latitude, format: .fixed(precision: 5)) lon=\(coordinate.longitude, format: .fixed(precision: 5))")

        let clLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()

        let placemarks: [CLPlacemark]
        do {
            placemarks = try await geocoder.reverseGeocodeLocation(clLocation)
            log.debug("reverseGeocode — CLGeocoder returned \(placemarks.count) placemark(s)")
        } catch {
            log.error("reverseGeocode — CLGeocoder threw: \(error). Using coordinate fallback.")
            return fallbackRecord(for: coordinate)
        }

        guard let placemark = placemarks.first else {
            log.warning("reverseGeocode — empty placemark array, using coordinate fallback")
            return fallbackRecord(for: coordinate)
        }

        // Log every field so we can see exactly what CLGeocoder returned
        log.debug("reverseGeocode — placemark fields:")
        log.debug("  name            = \(placemark.name ?? "nil")")
        log.debug("  subLocality     = \(placemark.subLocality ?? "nil")")
        log.debug("  locality        = \(placemark.locality ?? "nil")")
        log.debug("  subAdminArea    = \(placemark.subAdministrativeArea ?? "nil")")
        log.debug("  adminArea       = \(placemark.administrativeArea ?? "nil")")
        log.debug("  country         = \(placemark.country ?? "nil")")
        log.debug("  isoCountryCode  = \(placemark.isoCountryCode ?? "nil")")
        log.debug("  postalCode      = \(placemark.postalCode ?? "nil")")
        log.debug("  thoroughfare    = \(placemark.thoroughfare ?? "nil")")

        let placeName = buildPlaceName(from: placemark)
        log.debug("reverseGeocode ✔ resolved '\(placeName)'")

        return PlaceRecord(
            placeName: placeName,
            coordinate: coordinate,
            visitCount: 1,
            totalDwellMins: 0,
            firstVisit: Date(),
            lastVisit: Date()
        )
    }

    // MARK: - Helpers

    private func buildPlaceName(from placemark: CLPlacemark) -> String {
        if let neighborhood = placemark.subLocality, !neighborhood.isEmpty {
            log.debug("buildPlaceName — chose subLocality: '\(neighborhood)'")
            return neighborhood
        }
        if let city = placemark.locality, !city.isEmpty {
            log.debug("buildPlaceName — chose locality: '\(city)'")
            return city
        }
        if let name = placemark.name, !name.isEmpty {
            log.debug("buildPlaceName — chose name: '\(name)'")
            return name
        }
        if let area = placemark.administrativeArea, !area.isEmpty {
            log.debug("buildPlaceName — chose administrativeArea: '\(area)'")
            return area
        }
        log.warning("buildPlaceName — all fields nil/empty, falling back to coordinate string")
        return coordinateString(for: placemark.location.flatMap {
            GPSCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        })
    }

    private func fallbackRecord(for coordinate: GPSCoordinate) -> PlaceRecord {
        let name = coordinateString(for: coordinate)
        log.debug("fallbackRecord — '\(name)'")
        return PlaceRecord(
            placeName: name,
            coordinate: coordinate,
            visitCount: 1,
            totalDwellMins: 0,
            firstVisit: Date(),
            lastVisit: Date()
        )
    }

    private func coordinateString(for coordinate: GPSCoordinate?) -> String {
        guard let c = coordinate else { return "Unknown Location" }
        return String(format: "%.3f°, %.3f°", c.latitude, c.longitude)
    }
}
