// NiftyCore/Sources/Domain/Protocols/WeatherProtocol.swift
// Pure Swift — zero platform imports.

import Foundation

public protocol WeatherProtocol: AnyObject, Sendable {
    /// Fetch current weather conditions for a location at a given time.
    /// Returns condition + temperature in °C. Implementations may cache.
    func fetchConditions(
        at coordinate: GPSCoordinate,
        time: Date
    ) async throws -> (condition: WeatherCondition, temperatureC: Double)
}
