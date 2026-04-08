// NiftyData/Sources/Platform/WeatherKitAdapter.swift
// Open-Meteo free weather API — no API key required.
// Replaces WeatherKit (requires paid Apple Developer membership).
// Docs: https://open-meteo.com/en/docs
// Endpoint: /v1/forecast?latitude=&longitude=&current=temperature_2m,weather_code&timezone=auto

import Foundation
import NiftyCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "OpenMeteoWeather")

public final class OpenMeteoWeatherAdapter: WeatherProtocol {
    private let session: URLSession
    /// Simple in-process cache: coordinate bucket (0.1° grid) → (result, fetchedAt).
    /// NSCache is internally thread-safe; nonisolated(unsafe) suppresses the Sendable warning.
    nonisolated(unsafe) private let cache = NSCache<NSString, CacheEntry>()

    public init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 50
    }

    public func fetchConditions(
        at coordinate: GPSCoordinate,
        time: Date
    ) async throws -> (condition: WeatherCondition, temperatureC: Double) {
        let key = cacheKey(for: coordinate)

        // Return cached result if < 30 minutes old
        if let entry = cache.object(forKey: key as NSString),
           Date().timeIntervalSince(entry.fetchedAt) < 1800 {
            log.debug("fetchConditions — cache hit for \(key)")
            return (entry.condition, entry.temperatureC)
        }

        let url = buildURL(latitude: coordinate.latitude, longitude: coordinate.longitude)
        log.debug("fetchConditions — fetching \(url.absoluteString)")

        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            log.error("fetchConditions — non-2xx response")
            throw WeatherFetchError.badResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let condition = wmoToCondition(decoded.current.weather_code)
        let tempC = decoded.current.temperature_2m

        log.debug("fetchConditions — wmo=\(decoded.current.weather_code) → .\(condition.rawValue) temp=\(tempC)°C")

        let entry = CacheEntry(condition: condition, temperatureC: tempC, fetchedAt: Date())
        cache.setObject(entry, forKey: key as NSString)

        return (condition, tempC)
    }

    // MARK: - Private

    private func buildURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components.url!
    }

    /// Bucket coordinates to 0.1° grid for cache key (≈11km resolution — fine for weather).
    private func cacheKey(for coordinate: GPSCoordinate) -> String {
        let lat = (coordinate.latitude * 10).rounded() / 10
        let lon = (coordinate.longitude * 10).rounded() / 10
        return "\(lat),\(lon)"
    }

    /// WMO weather interpretation codes → WeatherCondition
    /// Reference: https://open-meteo.com/en/docs (WMO Weather interpretation codes)
    private func wmoToCondition(_ code: Int) -> WeatherCondition {
        switch code {
        case 0, 1:          return .clear
        case 2, 3:          return .cloudy
        case 45, 48:        return .fog
        case 51...67:       return .rain
        case 71...77:       return .snow
        case 80...82:       return .rain
        case 85, 86:        return .snow
        case 95...99:       return .thunder
        default:            return .clear
        }
    }
}

// MARK: - Response models

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather

    struct CurrentWeather: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }
}

// MARK: - Cache entry

private final class CacheEntry: NSObject {
    let condition: WeatherCondition
    let temperatureC: Double
    let fetchedAt: Date

    init(condition: WeatherCondition, temperatureC: Double, fetchedAt: Date) {
        self.condition = condition
        self.temperatureC = temperatureC
        self.fetchedAt = fetchedAt
    }
}

// MARK: - Error

private enum WeatherFetchError: Error {
    case badResponse
}
