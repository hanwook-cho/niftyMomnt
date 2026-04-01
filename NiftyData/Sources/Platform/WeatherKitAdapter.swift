// NiftyData/Sources/Platform/WeatherKitAdapter.swift
// WeatherKit.WeatherService. 30-minute cache.

import Foundation
import NiftyCore
import WeatherKit

public final class WeatherKitAdapter: Sendable {
    public init() {}

    public func fetchWeather(at location: GPSCoordinate, time: Date) async throws -> AmbientMetadata {
        // TODO: WeatherService.shared.weather(for:)
        return AmbientMetadata()
    }
}
