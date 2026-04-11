// NiftyData/Sources/Platform/CoreMLIndexingAdapter.swift
// Wraps Vision, SoundAnalysis, CoreImage. All inference on Neural Engine.

import AVFoundation
import CoreImage
import CoreML
import Foundation
import NiftyCore
import os
import SoundAnalysis
import Vision

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "CoreMLIndexing")

public final class CoreMLIndexingAdapter: IndexingProtocol, Sendable {
    private let config: AppConfig
    private let weather: (any WeatherProtocol)?

    public init(config: AppConfig, weather: (any WeatherProtocol)? = nil) {
        self.config = config
        self.weather = weather
    }

    // MARK: - Image Classification (v0.1)

    public func classifyImage(_ assetID: UUID, imageData: Data) async throws -> [VibeTag] {
        log.debug("classifyImage start — assetID=\(assetID.uuidString) imageData=\(imageData.count)B")

        guard let ciImage = CIImage(data: imageData) else {
            log.error("classifyImage — CIImage(data:) returned nil, cannot classify")
            return []
        }

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        let request = VNClassifyImageRequest()

        do {
            try handler.perform([request])
        } catch {
            log.error("classifyImage — VNImageRequestHandler.perform failed: \(error)")
            throw error
        }

        let allResults = request.results ?? []
        log.debug("classifyImage — Vision returned \(allResults.count) observations total")

        let topObservations = allResults
            .filter { $0.confidence > 0.3 }
            .prefix(10)

        // Log all top observations for tuning the identifier→VibeTag map
        for obs in topObservations {
            log.debug("  observation: '\(obs.identifier)' confidence=\(String(format: "%.2f", obs.confidence))")
        }

        var seen = Set<VibeTag>()
        var tags: [VibeTag] = []
        for obs in topObservations {
            if let tag = vibeTag(for: obs.identifier), !seen.contains(tag) {
                log.debug("  mapped '\(obs.identifier)' → .\(tag.rawValue)")
                seen.insert(tag)
                tags.append(tag)
            } else if vibeTag(for: obs.identifier) == nil {
                log.debug("  no mapping for '\(obs.identifier)' (conf=\(String(format: "%.2f", obs.confidence)))")
            }
            if tags.count == 3 { break }
        }

        log.debug("classifyImage done — final tags: [\(tags.map(\.rawValue).joined(separator: ", "))]")
        return tags
    }

    // MARK: - Audio Analysis (v0.5)

    public func analyzeAudio(_ assetID: UUID, audioData: Data) async throws -> [AcousticTag] {
        // TODO v0.5: SNClassifySoundRequest with audioData
        return []
    }

    public func analyzePCMBuffer(
        _ assetID: UUID,
        buffer: UnsafeBufferPointer<Float>,
        sampleRate: Double
    ) async throws -> [AcousticTag] {
        // Copy to [Float] (Sendable) before any async hop — AVAudioPCMBuffer is not Sendable.
        let samples = Array(buffer)
        return try await Task.detached(priority: .utility) {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: sampleRate,
                                       channels: 1,
                                       interleaved: false)
            guard let format,
                  let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                              frameCapacity: AVAudioFrameCount(samples.count)),
                  let dst = pcm.floatChannelData else { return [] }

            pcm.frameLength = AVAudioFrameCount(samples.count)
            dst[0].assign(from: samples, count: samples.count)

            let observer = PCMObserver()
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let analyzer = SNAudioStreamAnalyzer(format: format)
            try analyzer.add(request, withObserver: observer)
            analyzer.analyze(pcm, atAudioFramePosition: 0)
            analyzer.completeAnalysis()

            var best: [AcousticTagType: AcousticTag] = [:]
            for result in observer.results {
                for c in result.classifications {
                    guard Float(c.confidence) >= 0.35,
                          let tagType = SoundStampAdapter.mapAudioSetIdentifier(c.identifier)
                    else { continue }
                    let conf = Float(c.confidence)
                    if best[tagType] == nil || conf > best[tagType]!.confidence {
                        best[tagType] = AcousticTag(tag: tagType, source: .soundStamp, confidence: conf)
                    }
                }
            }
            return best.values.sorted { $0.confidence > $1.confidence }
        }.value
    }

    // MARK: - Chromatic Palette (v0.2)

    /// Extracts up to 5 dominant colors using CIAreaAverage across 5 image regions.
    /// Regions: full image + 4 quadrants. Near-duplicate HSL values are deduplicated.
    public func extractPalette(_ assetID: UUID, imageData: Data) async throws -> ChromaticPalette {
        log.debug("extractPalette start — assetID=\(assetID.uuidString) dataSize=\(imageData.count)B")

        guard let ciImage = CIImage(data: imageData) else {
            log.error("extractPalette — CIImage(data:) returned nil")
            return ChromaticPalette(colors: [])
        }

        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else {
            return ChromaticPalette(colors: [])
        }

        // Define 5 non-overlapping + 1 full region
        let halfW = extent.width / 2
        let halfH = extent.height / 2
        let regions: [CGRect] = [
            extent,                                                          // full
            CGRect(x: extent.minX, y: extent.minY, width: halfW, height: halfH),         // bottom-left
            CGRect(x: extent.minX + halfW, y: extent.minY, width: halfW, height: halfH), // bottom-right
            CGRect(x: extent.minX, y: extent.minY + halfH, width: halfW, height: halfH), // top-left
            CGRect(x: extent.minX + halfW, y: extent.minY + halfH, width: halfW, height: halfH), // top-right
        ]

        let ciContext = CIContext()
        var colors: [HSLColor] = []

        for region in regions {
            guard let hsl = averageColor(ciImage: ciImage, region: region, context: ciContext) else { continue }
            // Deduplicate: skip if within 15° hue + 0.15 saturation of an existing color
            let isDuplicate = colors.contains { existing in
                abs(existing.hue - hsl.hue) < 15 && abs(existing.saturation - hsl.saturation) < 0.15
            }
            if !isDuplicate {
                colors.append(hsl)
            }
            if colors.count == 5 { break }
        }

        log.debug("extractPalette done — \(colors.count) color(s) extracted")
        return ChromaticPalette(colors: colors)
    }

    // MARK: - Ambient Metadata (v0.2)

    public func harvestAmbientMetadata(at location: GPSCoordinate?, at time: Date) async throws -> AmbientMetadata {
        var ambient = AmbientMetadata()
        ambient.sunPosition = sunPosition(for: time)

        guard let location, let weather else {
            return ambient
        }

        do {
            let (condition, tempC) = try await weather.fetchConditions(at: location, time: time)
            ambient.weather = condition
            ambient.temperatureC = tempC
            log.debug("harvestAmbientMetadata — .\(condition.rawValue) \(String(format: "%.1f", tempC))°C sun=\(ambient.sunPosition?.rawValue ?? "nil")")
        } catch {
            log.error("harvestAmbientMetadata — weather fetch failed: \(error)")
        }

        return ambient
    }

    // MARK: - Moment Clustering (v0.8)

    public func clusterMoments(assets: [Asset]) async throws -> [Moment] {
        // TODO v0.8: 90-min / 200m clustering window
        return []
    }
}

// MARK: - Palette helpers

private extension CoreMLIndexingAdapter {
    /// Returns the average color of `region` within `ciImage` as an HSLColor, or nil on failure.
    func averageColor(ciImage: CIImage, region: CGRect, context: CIContext) -> HSLColor? {
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ciImage,
                                                 kCIInputExtentKey: CIVector(cgRect: region)]),
              let output = filter.outputImage else { return nil }

        // Render the 1×1 result into a 4-byte RGBA buffer
        var rgba = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(rgba[0]) / 255
        let g = Double(rgba[1]) / 255
        let b = Double(rgba[2]) / 255
        return rgbToHSL(r: r, g: g, b: b)
    }

    /// Standard RGB → HSL conversion. Returns hue in 0–360, sat/lightness in 0–1.
    func rgbToHSL(r: Double, g: Double, b: Double) -> HSLColor {
        let cMax = max(r, g, b)
        let cMin = min(r, g, b)
        let delta = cMax - cMin

        let lightness = (cMax + cMin) / 2

        let saturation: Double
        if delta == 0 {
            saturation = 0
        } else {
            saturation = delta / (1 - abs(2 * lightness - 1))
        }

        let hue: Double
        if delta == 0 {
            hue = 0
        } else if cMax == r {
            hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if cMax == g {
            hue = 60 * (((b - r) / delta) + 2)
        } else {
            hue = 60 * (((r - g) / delta) + 4)
        }

        return HSLColor(
            hue: (hue + 360).truncatingRemainder(dividingBy: 360),
            saturation: min(1, max(0, saturation)),
            lightness: min(1, max(0, lightness))
        )
    }

    /// Returns the sun position bucket for a given Date, using local calendar hour.
    func sunPosition(for date: Date) -> SunPosition {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<7:   return .sunrise
        case 7..<11:  return .morning
        case 11..<14: return .midday
        case 14..<17: return .afternoon
        case 17..<20: return .sunset
        default:      return .night
        }
    }
}

// MARK: - Vision identifier → VibeTag mapping

private extension CoreMLIndexingAdapter {
    /// Maps a VNClassifyImageRequest observation identifier to a VibeTag.
    ///
    /// Apple's taxonomy uses concrete noun identifiers, not aesthetic keywords.
    /// Observed examples: "structure", "wood_processed", "cord", "machine",
    /// "consumer_electronics", "outdoor_nature", "sky", "person", "food_drink".
    /// Priority order matters — first match wins. Tune using the "no mapping for"
    /// debug log lines emitted for every unmatched observation.
    func vibeTag(for identifier: String) -> VibeTag? {
        let id = identifier.lowercased()

        // ── Golden ── warm, bright, sunset/sunrise, golden-hour light
        if id.contains("sunset")    || id.contains("sunrise")  || id.contains("golden")
        || id.contains("warm_light") || id.contains("sunlight") || id.contains("yellow")
        || id.contains("autumn")    || id.contains("fall")     || id.contains("orange")
        || id.contains("amber")     || id.contains("candlelight") {
            return .golden
        }

        // ── Moody ── dark, dramatic, night, stormy, overcast
        if id.contains("night")     || id.contains("dark")      || id.contains("dramatic")
        || id.contains("storm")     || id.contains("overcast")  || id.contains("mist")
        || id.contains("rain")      || id.contains("gloomy")    || id.contains("dusk") {
            return .moody
        }

        // ── Serene ── outdoor nature, green, calm, botanical
        if id.contains("nature")    || id.contains("forest")    || id.contains("mountain")
        || id.contains("field")     || id.contains("meadow")    || id.contains("garden")
        || id.contains("plant")     || id.contains("leaf")      || id.contains("grass")
        || id.contains("tree")      || id.contains("outdoor")   || id.contains("flower")
        || id.contains("floral")    || id.contains("landscape") || id.contains("park")
        || id.contains("trail")     || id.contains("hiking")    || id.contains("wildlife")
        || id.contains("beach")     || id.contains("coast")     || id.contains("lake") {
            return .serene
        }

        // ── Electric ── urban, city, technology, screens, vivid light
        if id.contains("neon")      || id.contains("city")      || id.contains("urban")
        || id.contains("street")    || id.contains("nightlife") || id.contains("crowd")
        || id.contains("vibrant")   || id.contains("colorful")  || id.contains("signage")
        || id.contains("consumer_electronics") || id.contains("electronic")
        || id.contains("technology") || id.contains("screen")    || id.contains("light_effect")
        || id.contains("festival")  || id.contains("concert")   || id.contains("performer") {
            return .electric
        }

        // ── Nostalgic ── vintage, retro, aged, historic, film-era
        if id.contains("vintage")   || id.contains("retro")     || id.contains("aged")
        || id.contains("classic")   || id.contains("historic")  || id.contains("antique")
        || id.contains("monument")  || id.contains("ruin")      || id.contains("heritage") {
            return .nostalgic
        }

        // ── Cozy ── indoor, home, food, warm materials (wood, textile, furniture)
        if id.contains("indoor")    || id.contains("interior")  || id.contains("home")
        || id.contains("food")      || id.contains("drink")     || id.contains("cafe")
        || id.contains("coffee")    || id.contains("candle")    || id.contains("kitchen")
        || id.contains("wood")      || id.contains("textile")   || id.contains("furniture")
        || id.contains("table")     || id.contains("chair")     || id.contains("sofa")
        || id.contains("bedroom")   || id.contains("living")    || id.contains("fireplace")
        || id.contains("book")      || id.contains("library")   || id.contains("bakery") {
            return .cozy
        }

        // ── Dreamy ── sky, clouds, water, soft/hazy light, snow
        if id.contains("sky")       || id.contains("cloud")     || id.contains("pastel")
        || id.contains("haze")      || id.contains("snow")      || id.contains("fog")
        || id.contains("water")     || id.contains("ocean")     || id.contains("sea")
        || id.contains("river")     || id.contains("reflection") || id.contains("mist")
        || id.contains("ethereal")  || id.contains("dreamy") {
            return .dreamy
        }

        // ── Raw ── structural, industrial, machinery, wires, concrete, minimal
        if id.contains("structure") || id.contains("machine")   || id.contains("cord")
        || id.contains("metal")     || id.contains("wire")      || id.contains("cable")
        || id.contains("concrete")  || id.contains("industrial") || id.contains("shadow")
        || id.contains("abstract")  || id.contains("minimal")   || id.contains("monochrome")
        || id.contains("black_and_white")      || id.contains("architecture")
        || id.contains("building")  || id.contains("bridge")    || id.contains("wall")
        || id.contains("fence")     || id.contains("stone")     || id.contains("graffiti")
        || id.contains("tool")      || id.contains("hardware") {
            return .raw
        }

        return nil
    }
}

// MARK: - SNResultsObserving bridge (batch path)

private final class PCMObserver: NSObject, SNResultsObserving {
    var results: [SNClassificationResult] = []
    func request(_ request: SNRequest, didProduce result: SNResult) {
        if let r = result as? SNClassificationResult { results.append(r) }
    }
    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}
