// NiftyData/Sources/Repositories/GraphRepository.swift
// GRDB SQLite. App Group container. WAL mode.
// SRS §7.2: intelligence graph — moments, vibe/acoustic tags, mood map, place history.
// NOTE: SQLCipher AES-256 encryption is deferred until a compatible SPM package is confirmed.
// GRDBSQLCipher was removed from GRDB.swift v7; KeychainBridge is retained for future wiring.

import Foundation
import GRDB
import NiftyCore
import os

private let log = Logger(subsystem: "com.hwcho99.niftymomnt", category: "GraphRepository")

public actor GraphRepository: GraphProtocol {
    private let config: AppConfig
    private let db: DatabaseQueue

    public init(config: AppConfig) {
        self.config = config
        self.db = GraphRepository.openDatabase(namespace: config.namespace)
    }

    // MARK: - GraphProtocol

    public func saveMoment(_ moment: Moment) async throws {
        log.debug("saveMoment — id=\(moment.id.uuidString) assets=\(moment.assets.count) label='\(moment.label)'")
        try await db.write { db in
            // Upsert each asset (including v0.2 ambient + palette fields)
            for asset in moment.assets {
                let vibesJSON = try JSONEncoder().encode(asset.vibeTags.map(\.rawValue))
                let vibesString = String(data: vibesJSON, encoding: .utf8) ?? "[]"
                let paletteJSON = asset.palette.flatMap { try? JSONEncoder().encode($0) }
                    .flatMap { String(data: $0, encoding: .utf8) }
                try db.execute(sql: """
                    INSERT INTO assets (id, type, captured_at, location_lat, location_lon,
                                        vibe_tags, ambient_weather, ambient_temp_c,
                                        ambient_sun_pos, palette_json, preset_name,
                                        duration_seconds, sequence_assembled_url)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        vibe_tags       = excluded.vibe_tags,
                        ambient_weather = excluded.ambient_weather,
                        ambient_temp_c  = excluded.ambient_temp_c,
                        ambient_sun_pos = excluded.ambient_sun_pos,
                        palette_json    = excluded.palette_json,
                        preset_name     = excluded.preset_name,
                        duration_seconds       = excluded.duration_seconds,
                        sequence_assembled_url = excluded.sequence_assembled_url
                    """,
                    arguments: [
                        asset.id.uuidString,
                        asset.type.rawValue,
                        asset.capturedAt.timeIntervalSince1970,
                        asset.location?.latitude,
                        asset.location?.longitude,
                        vibesString,
                        asset.ambient.weather?.rawValue,
                        asset.ambient.temperatureC,
                        asset.ambient.sunPosition?.rawValue,
                        paletteJSON,
                        asset.selectedPresetName,
                        asset.duration,
                        asset.sequenceAssembledURL?.absoluteString
                    ]
                )
            }

            // Upsert moment
            let vibesJSON = try JSONEncoder().encode(moment.dominantVibes.map(\.rawValue))
            let vibesString = String(data: vibesJSON, encoding: .utf8) ?? "[]"
            try db.execute(sql: """
                INSERT INTO moments (id, label, centroid_lat, centroid_lon,
                                     start_time, end_time, dominant_vibes, is_starred)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    label = excluded.label,
                    dominant_vibes = excluded.dominant_vibes,
                    is_starred = excluded.is_starred
                """,
                arguments: [
                    moment.id.uuidString,
                    moment.label,
                    moment.centroid.latitude,
                    moment.centroid.longitude,
                    moment.startTime.timeIntervalSince1970,
                    moment.endTime.timeIntervalSince1970,
                    vibesString,
                    moment.isStarred ? 1 : 0
                ]
            )

            // Insert moment_assets (ignore if already exists)
            for asset in moment.assets {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO moment_assets (moment_id, asset_id)
                    VALUES (?, ?)
                    """,
                    arguments: [moment.id.uuidString, asset.id.uuidString]
                )
            }
        }
        log.debug("saveMoment done — id=\(moment.id.uuidString)")
    }

    public func updateVibeTag(_ tag: VibeTag, for assetID: UUID) async throws {
        try await db.write { db in
            let row = try Row.fetchOne(db,
                sql: "SELECT vibe_tags FROM assets WHERE id = ?",
                arguments: [assetID.uuidString]
            )
            guard let existing = row?["vibe_tags"] as? String,
                  let data = existing.data(using: .utf8),
                  var tags = try? JSONDecoder().decode([String].self, from: data) else { return }

            if !tags.contains(tag.rawValue) {
                tags.append(tag.rawValue)
                let updated = String(data: (try? JSONEncoder().encode(tags)) ?? Data(), encoding: .utf8) ?? existing
                try db.execute(sql: "UPDATE assets SET vibe_tags = ? WHERE id = ?",
                               arguments: [updated, assetID.uuidString])
            }
        }
    }

    public func updatePreset(_ name: String, for assetID: UUID) async throws {
        try await db.write { db in
            try db.execute(sql: "UPDATE assets SET preset_name = ? WHERE id = ?",
                           arguments: [name, assetID.uuidString])
        }
    }

    public func fetchTodayMomentCount() async throws -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let startTS = startOfDay.timeIntervalSince1970
        return try await db.read { db in
            let row = try Row.fetchOne(db,
                sql: "SELECT COUNT(*) AS cnt FROM moments WHERE start_time >= ?",
                arguments: [startTS])
            return (row?["cnt"] as? Int) ?? 0
        }
    }

    public func fetchAcousticTags(for assetID: UUID) async throws -> [AcousticTag] {
        return try await db.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT tag, source, confidence FROM acoustic_tags WHERE asset_id = ?",
                arguments: [assetID.uuidString])
            return rows.compactMap { row -> AcousticTag? in
                guard let tagStr = row["tag"]    as? String, let tagType = AcousticTagType(rawValue: tagStr),
                      let srcStr = row["source"] as? String, let source  = AcousticSource(rawValue: srcStr),
                      let conf   = row["confidence"] as? Double else { return nil }
                return AcousticTag(tag: tagType, source: source, confidence: Float(conf))
            }
        }
    }

    public func updateAcousticTag(_ tag: AcousticTag, for assetID: UUID) async throws {
        try await db.write { db in
            try db.execute(sql: """
                INSERT INTO acoustic_tags (asset_id, tag, source, confidence)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(asset_id, tag) DO UPDATE SET
                    confidence = MAX(confidence, excluded.confidence)
                """,
                arguments: [
                    assetID.uuidString,
                    tag.tag.rawValue,
                    tag.source.rawValue,
                    tag.confidence
                ]
            )
        }
    }

    public func saveNudgeResponse(_ response: NudgeResponse) async throws {
        log.debug("saveNudgeResponse — nudgeID=\(response.nudgeID) type=\(response.responseType)")
        try await db.write { db in
            try db.execute(sql: """
                INSERT INTO nudge_responses (id, nudge_id, response_type, response_value, timestamp)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    response.nudgeID.uuidString,
                    response.responseType,
                    response.responseValue,
                    response.timestamp.timeIntervalSince1970
                ]
            )
        }
        log.debug("saveNudgeResponse done — nudgeID=\(response.nudgeID)")
    }

    public func mergeAcousticVibes(_ vibes: [VibeTag], for assetID: UUID) async throws {
        guard !vibes.isEmpty else { return }
        log.debug("mergeAcousticVibes — assetID=\(assetID.uuidString) vibes=[\(vibes.map(\.rawValue).joined(separator: ","))]")
        try await db.write { db in
            // 1. Look up the moment that contains this asset
            guard let momentID = try String.fetchOne(db, sql: """
                SELECT moment_id FROM moment_assets WHERE asset_id = ? LIMIT 1
                """, arguments: [assetID.uuidString])
            else {
                return  // asset not yet linked to a moment — skip
            }
            // 2. Read current dominant_vibes JSON
            let existing = (try String.fetchOne(db, sql: """
                SELECT dominant_vibes FROM moments WHERE id = ?
                """, arguments: [momentID])) ?? "[]"
            let existingTags = (try? JSONDecoder().decode([String].self,
                from: existing.data(using: .utf8) ?? Data())) ?? []
            // 3. Merge — append only tags not already present
            var merged = existingTags
            for v in vibes where !merged.contains(v.rawValue) {
                merged.append(v.rawValue)
            }
            guard merged.count > existingTags.count else { return }  // nothing new
            let mergedJSON = (try? String(data: JSONEncoder().encode(merged), encoding: .utf8)) ?? existing
            // 4. Update moment
            try db.execute(sql: """
                UPDATE moments SET dominant_vibes = ? WHERE id = ?
                """, arguments: [mergedJSON, momentID])
            log.debug("mergeAcousticVibes done — momentID=\(momentID) merged=\(merged)")
        }
    }

    public func saveMoodPoint(_ point: MoodPoint) async throws {
        log.debug("saveMoodPoint — momentID=\(point.momentID.uuidString)")
        try await db.write { db in
            let paletteJSON = (try? JSONEncoder().encode(point.palette.map { ["hex": $0.hex, "emotion": $0.emotion.rawValue] }))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            try db.execute(sql: """
                INSERT INTO mood_points (moment_id, lat, lon, mood, palette_json)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(moment_id) DO UPDATE SET
                    mood = excluded.mood,
                    palette_json = excluded.palette_json
                """,
                arguments: [
                    point.momentID.uuidString,
                    point.coordinate.latitude,
                    point.coordinate.longitude,
                    point.dominantMood.rawValue,
                    paletteJSON
                ]
            )
        }
        log.debug("saveMoodPoint done")
    }

    public func updatePlaceRecord(_ record: PlaceRecord) async throws {
        log.debug("updatePlaceRecord — name='\(record.placeName)'")
        try await db.write { db in
            let vibesJSON = (try? JSONEncoder().encode(record.dominantVibes.map(\.rawValue)))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            try db.execute(sql: """
                INSERT INTO place_history (id, place_name, lat, lon,
                                           visit_count, total_dwell_mins,
                                           first_visit, last_visit, dominant_vibes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    visit_count      = visit_count + 1,
                    last_visit       = excluded.last_visit,
                    total_dwell_mins = total_dwell_mins + excluded.total_dwell_mins,
                    dominant_vibes   = excluded.dominant_vibes
                """,
                arguments: [
                    record.id.uuidString,
                    record.placeName,
                    record.coordinate.latitude,
                    record.coordinate.longitude,
                    record.visitCount,
                    record.totalDwellMins,
                    record.firstVisit.timeIntervalSince1970,
                    record.lastVisit.timeIntervalSince1970,
                    vibesJSON
                ]
            )
        }
        log.debug("updatePlaceRecord done — '\(record.placeName)'")
    }

    public func deleteMoment(_ momentID: UUID) async throws {
        log.debug("deleteMoment — id=\(momentID.uuidString)")
        try await db.write { db in
            // Collect asset IDs before removing the join rows
            let assetRows = try Row.fetchAll(db,
                sql: "SELECT asset_id FROM moment_assets WHERE moment_id = ?",
                arguments: [momentID.uuidString])
            let assetIDs = assetRows.compactMap { $0["asset_id"] as? String }

            // Delete moment (cascades moment_assets via ON DELETE CASCADE)
            try db.execute(sql: "DELETE FROM moments WHERE id = ?",
                           arguments: [momentID.uuidString])

            // Delete orphaned asset rows
            for assetID in assetIDs {
                try db.execute(sql: "DELETE FROM assets WHERE id = ?", arguments: [assetID])
            }
        }
        log.debug("deleteMoment done — id=\(momentID.uuidString)")
    }

    public func saveDerivativeRecord(_ derivative: DerivativeAsset) async throws {
        // v0.7: derivative tracking
    }

    public func deleteDerivativeRecord(for assetID: UUID) async throws {
        // v0.7
    }

    public func fetchMoments(query: GraphQuery) async throws -> [Moment] {
        log.debug("fetchMoments — dateRange=\(String(describing: query.dateRange)) vibeFilter=\(query.vibeFilter.map(\.rawValue)) limit=\(String(describing: query.limit))")
        let moments = try await db.read { db in
            var conditions: [String] = []
            var arguments: [DatabaseValueConvertible] = []

            if let range = query.dateRange {
                conditions.append("m.start_time >= ? AND m.start_time <= ?")
                arguments.append(range.lowerBound.timeIntervalSince1970)
                arguments.append(range.upperBound.timeIntervalSince1970)
            }

            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            var sql = """
                SELECT m.id, m.label, m.centroid_lat, m.centroid_lon,
                       m.start_time, m.end_time, m.dominant_vibes, m.is_starred
                FROM moments m
                \(whereClause)
                ORDER BY m.start_time DESC
                """
            if let limit = query.limit {
                sql += " LIMIT \(limit)"
            }

            let momentRows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

            var moments: [Moment] = []
            for row in momentRows {
                guard let idStr = row["id"] as? String,
                      let momentID = UUID(uuidString: idStr) else { continue }

                // Fetch associated assets (including v0.2 ambient + palette columns, v0.8 is_private)
                let assetRows = try Row.fetchAll(db, sql: """
                    SELECT a.id, a.type, a.captured_at, a.location_lat, a.location_lon,
                           a.vibe_tags, a.ambient_weather, a.ambient_temp_c,
                           a.ambient_sun_pos, a.palette_json, a.preset_name, a.is_private,
                           a.duration_seconds, a.sequence_assembled_url
                    FROM assets a
                    JOIN moment_assets ma ON ma.asset_id = a.id
                    WHERE ma.moment_id = ?
                    ORDER BY a.captured_at ASC
                    """,
                    arguments: [idStr]
                )

                var assets: [Asset] = assetRows.compactMap { aRow -> Asset? in
                    guard let aIdStr = aRow["id"] as? String,
                          let aId = UUID(uuidString: aIdStr),
                          let typeStr = aRow["type"] as? String,
                          let assetType = AssetType(rawValue: typeStr),
                          let capturedAtRaw = aRow["captured_at"] as? Double else { return nil }

                    let assetIsPrivate = ((aRow["is_private"] as? Int64) ?? 0) != 0
                    // v0.8 filter: showPrivate=false → exclude private assets; showPrivate=true → only private
                    if query.showPrivate && !assetIsPrivate { return nil }
                    if !query.showPrivate && assetIsPrivate { return nil }

                    let location: GPSCoordinate? = (aRow["location_lat"] as? Double).flatMap { lat in
                        (aRow["location_lon"] as? Double).map { lon in GPSCoordinate(latitude: lat, longitude: lon) }
                    }
                    let vibeTags: [VibeTag] = {
                        guard let tagsStr = aRow["vibe_tags"] as? String,
                              let data = tagsStr.data(using: .utf8),
                              let rawTags = try? JSONDecoder().decode([String].self, from: data) else { return [] }
                        return rawTags.compactMap { VibeTag(rawValue: $0) }
                    }()
                    let ambient: AmbientMetadata = {
                        var a = AmbientMetadata()
                        if let w = aRow["ambient_weather"] as? String { a.weather = WeatherCondition(rawValue: w) }
                        if let t = aRow["ambient_temp_c"] as? Double { a.temperatureC = t }
                        if let s = aRow["ambient_sun_pos"] as? String { a.sunPosition = SunPosition(rawValue: s) }
                        return a
                    }()
                    let palette: ChromaticPalette? = {
                        guard let json = aRow["palette_json"] as? String,
                              let data = json.data(using: .utf8),
                              let decoded = try? JSONDecoder().decode(ChromaticPalette.self, from: data) else { return nil }
                        return decoded
                    }()

                    let assembledURL: URL? = (aRow["sequence_assembled_url"] as? String).flatMap(URL.init(string:))
                    return Asset(
                        id: aId,
                        type: assetType,
                        capturedAt: Date(timeIntervalSince1970: capturedAtRaw),
                        location: location,
                        vibeTags: vibeTags,
                        palette: palette,
                        ambient: ambient,
                        duration: aRow["duration_seconds"] as? Double,
                        selectedPresetName: aRow["preset_name"] as? String,
                        isPrivate: assetIsPrivate,
                        sequenceAssembledURL: assembledURL
                    )
                }

                // Skip moments with no visible assets after privacy filter
                guard !assets.isEmpty else { continue }

                // Batch-load acoustic tags for this moment's assets (single IN query, no N+1)
                if !assets.isEmpty {
                    let placeholders = assets.map { _ in "?" }.joined(separator: ", ")
                    let tagArgs: [DatabaseValueConvertible] = assets.map { $0.id.uuidString }
                    let tagRows = (try? Row.fetchAll(db,
                        sql: "SELECT asset_id, tag, source, confidence FROM acoustic_tags WHERE asset_id IN (\(placeholders))",
                        arguments: StatementArguments(tagArgs))) ?? []

                    var tagsMap: [String: [AcousticTag]] = [:]
                    for tRow in tagRows {
                        guard let aIDStr  = tRow["asset_id"]  as? String,
                              let tagStr  = tRow["tag"]        as? String,
                              let tagType = AcousticTagType(rawValue: tagStr),
                              let srcStr  = tRow["source"]     as? String,
                              let source  = AcousticSource(rawValue: srcStr),
                              let conf    = tRow["confidence"] as? Double else { continue }
                        tagsMap[aIDStr, default: []].append(
                            AcousticTag(tag: tagType, source: source, confidence: Float(conf))
                        )
                    }
                    for i in assets.indices {
                        assets[i].acousticTags = tagsMap[assets[i].id.uuidString] ?? []
                    }
                }

                let dominantVibes: [VibeTag] = {
                    guard let vibesStr = row["dominant_vibes"] as? String,
                          let data = vibesStr.data(using: .utf8),
                          let rawTags = try? JSONDecoder().decode([String].self, from: data) else { return [] }
                    return rawTags.compactMap { VibeTag(rawValue: $0) }
                }()

                if !query.vibeFilter.isEmpty {
                    let matchesFilter = dominantVibes.contains { query.vibeFilter.contains($0) }
                    guard matchesFilter else { continue }
                }

                let centroid = GPSCoordinate(
                    latitude: (row["centroid_lat"] as? Double) ?? 0,
                    longitude: (row["centroid_lon"] as? Double) ?? 0
                )

                let moment = Moment(
                    id: momentID,
                    label: (row["label"] as? String) ?? "",
                    assets: assets,
                    centroid: centroid,
                    startTime: Date(timeIntervalSince1970: (row["start_time"] as? Double) ?? 0),
                    endTime: Date(timeIntervalSince1970: (row["end_time"] as? Double) ?? 0),
                    dominantVibes: dominantVibes,
                    isStarred: ((row["is_starred"] as? Int64) ?? 0) != 0,
                    selectedPresetName: assets.first?.selectedPresetName
                )
                moments.append(moment)
            }
            return moments
        }
        log.debug("fetchMoments done — returned \(moments.count) moment(s)")
        return moments
    }

    // MARK: v0.8

    public func markAssetPrivate(assetID: UUID, isPrivate: Bool) async throws {
        log.debug("markAssetPrivate — assetID=\(assetID.uuidString) isPrivate=\(isPrivate)")
        try await db.write { db in
            try db.execute(
                sql: "UPDATE assets SET is_private = ? WHERE id = ?",
                arguments: [isPrivate ? 1 : 0, assetID.uuidString]
            )
        }
        log.debug("markAssetPrivate done")
    }

    public func fetchAssets(for momentID: UUID) async throws -> [Asset] {
        log.debug("fetchAssets — momentID=\(momentID.uuidString)")
        return try await db.read { db in
            let assetRows = try Row.fetchAll(db, sql: """
                SELECT a.id, a.type, a.captured_at, a.location_lat, a.location_lon,
                       a.vibe_tags, a.ambient_weather, a.ambient_temp_c,
                       a.ambient_sun_pos, a.palette_json, a.preset_name, a.is_private,
                       a.duration_seconds, a.sequence_assembled_url
                FROM assets a
                JOIN moment_assets ma ON ma.asset_id = a.id
                WHERE ma.moment_id = ?
                ORDER BY a.captured_at ASC
                """,
                arguments: [momentID.uuidString]
            )
            return assetRows.compactMap { aRow -> Asset? in
                guard let aIdStr = aRow["id"] as? String,
                      let aId = UUID(uuidString: aIdStr),
                      let typeStr = aRow["type"] as? String,
                      let assetType = AssetType(rawValue: typeStr),
                      let capturedAtRaw = aRow["captured_at"] as? Double else { return nil }

                let location: GPSCoordinate? = (aRow["location_lat"] as? Double).flatMap { lat in
                    (aRow["location_lon"] as? Double).map { lon in GPSCoordinate(latitude: lat, longitude: lon) }
                }
                let vibeTags: [VibeTag] = {
                    guard let tagsStr = aRow["vibe_tags"] as? String,
                          let data = tagsStr.data(using: .utf8),
                          let rawTags = try? JSONDecoder().decode([String].self, from: data) else { return [] }
                    return rawTags.compactMap { VibeTag(rawValue: $0) }
                }()
                let ambient: AmbientMetadata = {
                    var a = AmbientMetadata()
                    if let w = aRow["ambient_weather"] as? String { a.weather = WeatherCondition(rawValue: w) }
                    if let t = aRow["ambient_temp_c"] as? Double { a.temperatureC = t }
                    if let s = aRow["ambient_sun_pos"] as? String { a.sunPosition = SunPosition(rawValue: s) }
                    return a
                }()
                let palette: ChromaticPalette? = {
                    guard let json = aRow["palette_json"] as? String,
                          let data = json.data(using: .utf8),
                          let decoded = try? JSONDecoder().decode(ChromaticPalette.self, from: data) else { return nil }
                    return decoded
                }()
                let assembledURL: URL? = (aRow["sequence_assembled_url"] as? String).flatMap(URL.init(string:))
                return Asset(
                    id: aId,
                    type: assetType,
                    capturedAt: Date(timeIntervalSince1970: capturedAtRaw),
                    location: location,
                    vibeTags: vibeTags,
                    palette: palette,
                    ambient: ambient,
                    duration: aRow["duration_seconds"] as? Double,
                    selectedPresetName: aRow["preset_name"] as? String,
                    isPrivate: ((aRow["is_private"] as? Int64) ?? 0) != 0,
                    sequenceAssembledURL: assembledURL
                )
            }
        }
    }

    public func fetchPlaceHistory(limit: Int) async throws -> [PlaceRecord] {
        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, place_name, lat, lon, visit_count, total_dwell_mins,
                       first_visit, last_visit, dominant_vibes
                FROM place_history
                ORDER BY last_visit DESC
                LIMIT ?
                """, arguments: [limit])

            return rows.compactMap { row -> PlaceRecord? in
                guard let idStr = row["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = row["place_name"] as? String,
                      let lat = row["lat"] as? Double,
                      let lon = row["lon"] as? Double else { return nil }

                let vibes: [VibeTag] = {
                    guard let json = row["dominant_vibes"] as? String,
                          let data = json.data(using: .utf8),
                          let raw = try? JSONDecoder().decode([String].self, from: data) else { return [] }
                    return raw.compactMap { VibeTag(rawValue: $0) }
                }()

                return PlaceRecord(
                    id: id,
                    placeName: name,
                    coordinate: GPSCoordinate(latitude: lat, longitude: lon),
                    visitCount: (row["visit_count"] as? Int) ?? 1,
                    totalDwellMins: (row["total_dwell_mins"] as? Int) ?? 0,
                    firstVisit: Date(timeIntervalSince1970: (row["first_visit"] as? Double) ?? 0),
                    lastVisit: Date(timeIntervalSince1970: (row["last_visit"] as? Double) ?? 0),
                    dominantVibes: vibes
                )
            }
        }
    }

    public func fetchMoodMap(range: DateInterval) async throws -> [MoodPoint] {
        return []
    }

    // MARK: - L4C Records

    public func saveL4CRecord(_ record: L4CRecord) async throws {
        log.debug("saveL4CRecord — id=\(record.id.uuidString) frame=\(record.frameID)")
        try await db.write { db in
            let sourceIDsJSON = (try? JSONEncoder().encode(record.sourceAssetIDs.map(\.uuidString)))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            try db.execute(sql: """
                INSERT INTO l4c_records (id, source_ids, frame_id, border_color,
                                         captured_at, location_lat, location_lon, label)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    frame_id     = excluded.frame_id,
                    border_color = excluded.border_color,
                    label        = excluded.label
                """,
                arguments: [
                    record.id.uuidString,
                    sourceIDsJSON,
                    record.frameID,
                    record.borderColor.rawValue,
                    record.capturedAt.timeIntervalSince1970,
                    record.location?.latitude,
                    record.location?.longitude,
                    record.label
                ]
            )
        }
        log.debug("saveL4CRecord done — id=\(record.id.uuidString)")
    }

    public func fetchL4CRecords() async throws -> [L4CRecord] {
        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, source_ids, frame_id, border_color,
                       captured_at, location_lat, location_lon, label
                FROM l4c_records
                ORDER BY captured_at DESC
                """)
            return rows.compactMap { row -> L4CRecord? in
                guard let idStr = row["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let sourceJSON = row["source_ids"] as? String,
                      let sourceData = sourceJSON.data(using: .utf8),
                      let sourceStrs = try? JSONDecoder().decode([String].self, from: sourceData),
                      let frameID = row["frame_id"] as? String,
                      let borderRaw = row["border_color"] as? String,
                      let borderColor = L4CBorderColor(rawValue: borderRaw),
                      let capturedAtRaw = row["captured_at"] as? Double,
                      let label = row["label"] as? String
                else { return nil }

                let sourceIDs = sourceStrs.compactMap { UUID(uuidString: $0) }
                guard sourceIDs.count == 4 else { return nil }
                let location: GPSCoordinate? = (row["location_lat"] as? Double).flatMap { lat in
                    (row["location_lon"] as? Double).map { lon in GPSCoordinate(latitude: lat, longitude: lon) }
                }
                return L4CRecord(
                    id: id,
                    sourceAssetIDs: sourceIDs,
                    frameID: frameID,
                    borderColor: borderColor,
                    capturedAt: Date(timeIntervalSince1970: capturedAtRaw),
                    location: location,
                    label: label
                )
            }
        }
    }

    public func deleteL4CRecord(_ id: UUID) async throws -> [UUID] {
        log.debug("deleteL4CRecord — id=\(id.uuidString)")
        return try await db.write { db in
            // Fetch source IDs before deleting
            let row = try Row.fetchOne(db,
                sql: "SELECT source_ids FROM l4c_records WHERE id = ?",
                arguments: [id.uuidString])
            var sourceIDs: [UUID] = []
            if let json = row?["source_ids"] as? String,
               let data = json.data(using: .utf8),
               let strs = try? JSONDecoder().decode([String].self, from: data) {
                sourceIDs = strs.compactMap { UUID(uuidString: $0) }
            }
            try db.execute(sql: "DELETE FROM l4c_records WHERE id = ?", arguments: [id.uuidString])
            log.debug("deleteL4CRecord done — removed \(sourceIDs.count) source refs")
            return sourceIDs
        }
    }

    public func exportForCompanion() async throws -> GraphExport {
        let moments = try await fetchMoments(query: GraphQuery())
        let places = try await fetchPlaceHistory(limit: 100)
        return GraphExport(moments: moments, placeHistory: places, moodMap: [])
    }
}

// MARK: - Database setup

extension GraphRepository {
    private static func openDatabase(namespace: String?) -> DatabaseQueue {
        do {
            let dbURL = databaseURL(namespace: namespace)
            log.debug("GraphRepository — opening DB at: \(dbURL.path)")
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
            let queue = try DatabaseQueue(path: dbURL.path, configuration: config)
            try queue.write { db in
                try createSchema(db)
                try migrateSchema(db)
            }
            log.debug("GraphRepository — DB opened OK (file-backed)")
            return queue
        } catch {
            log.error("GraphRepository — file DB failed (\(error)), falling back to IN-MEMORY — data will NOT persist across launches!")
            let queue = try! DatabaseQueue()
            try! queue.write { db in
                try createSchema(db)
            }
            return queue
        }
    }

    /// DB path derived from `AppConfig.namespace`.
    /// - `nil` namespace → legacy niftyMomnt flat layout: `Documents/graph.sqlite`
    /// - non-nil namespace → scoped: `Documents/{ns}/graph.sqlite` (e.g. `Documents/piqd/graph.sqlite`)
    private static func databaseURL(namespace: String?) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base: URL
        if let ns = namespace {
            base = docs.appendingPathComponent(ns, isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } else {
            base = docs
        }
        let url = base.appendingPathComponent("graph.sqlite")
        log.debug("GraphRepository — DB path: \(url.path)")
        return url
    }

    private static func createSchema(_ db: Database) throws {
        // assets — one row per captured asset (v0.1 columns)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS assets (
                id           TEXT PRIMARY KEY NOT NULL,
                type         TEXT NOT NULL,
                captured_at  REAL NOT NULL,
                location_lat REAL,
                location_lon REAL,
                vibe_tags    TEXT NOT NULL DEFAULT '[]'
            )
            """)

        // moments — one row per clustered moment
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS moments (
                id             TEXT PRIMARY KEY NOT NULL,
                label          TEXT NOT NULL,
                centroid_lat   REAL NOT NULL,
                centroid_lon   REAL NOT NULL,
                start_time     REAL NOT NULL,
                end_time       REAL NOT NULL,
                dominant_vibes TEXT NOT NULL DEFAULT '[]',
                is_starred     INTEGER NOT NULL DEFAULT 0
            )
            """)

        // moment_assets — join table
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS moment_assets (
                moment_id TEXT NOT NULL REFERENCES moments(id) ON DELETE CASCADE,
                asset_id  TEXT NOT NULL REFERENCES assets(id)  ON DELETE CASCADE,
                PRIMARY KEY (moment_id, asset_id)
            )
            """)

        // place_history — v0.2
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS place_history (
                id               TEXT PRIMARY KEY NOT NULL,
                place_name       TEXT NOT NULL,
                lat              REAL NOT NULL,
                lon              REAL NOT NULL,
                visit_count      INTEGER NOT NULL DEFAULT 1,
                total_dwell_mins INTEGER NOT NULL DEFAULT 0,
                first_visit      REAL NOT NULL,
                last_visit       REAL NOT NULL,
                dominant_vibes   TEXT NOT NULL DEFAULT '[]'
            )
            """)

        // mood_points — v0.2
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS mood_points (
                moment_id    TEXT PRIMARY KEY NOT NULL REFERENCES moments(id) ON DELETE CASCADE,
                lat          REAL NOT NULL,
                lon          REAL NOT NULL,
                mood         TEXT NOT NULL,
                palette_json TEXT NOT NULL DEFAULT '[]'
            )
            """)

        // l4c_records — v0.3.5
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS l4c_records (
                id           TEXT PRIMARY KEY NOT NULL,
                source_ids   TEXT NOT NULL,
                frame_id     TEXT NOT NULL DEFAULT 'none',
                border_color TEXT NOT NULL DEFAULT 'white',
                captured_at  REAL NOT NULL,
                location_lat REAL,
                location_lon REAL,
                label        TEXT NOT NULL DEFAULT ''
            )
            """)

        // acoustic_tags — v0.5: SoundStamp results, one row per (asset, tag)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS acoustic_tags (
                asset_id   TEXT NOT NULL,
                tag        TEXT NOT NULL,
                source     TEXT NOT NULL DEFAULT 'soundStamp',
                confidence REAL NOT NULL DEFAULT 0.0,
                PRIMARY KEY (asset_id, tag)
            )
            """)

        // nudge_responses — v0.6: user responses to post-capture nudge cards
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS nudge_responses (
                id             TEXT PRIMARY KEY NOT NULL,
                nudge_id       TEXT NOT NULL,
                response_type  TEXT NOT NULL,
                response_value TEXT NOT NULL,
                timestamp      REAL NOT NULL
            )
            """)

        // Indexes
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_moments_start_time ON moments(start_time DESC)
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_place_history_last_visit ON place_history(last_visit DESC)
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_l4c_captured_at ON l4c_records(captured_at DESC)
            """)
    }

    /// Add v0.2 columns to the `assets` table for existing installs.
    /// SQLite's ALTER TABLE ADD COLUMN fails if the column already exists — errors are swallowed.
    private static func migrateSchema(_ db: Database) throws {
        let migrations = [
            // v0.2 asset columns
            "ALTER TABLE assets ADD COLUMN ambient_weather TEXT",
            "ALTER TABLE assets ADD COLUMN ambient_temp_c  REAL",
            "ALTER TABLE assets ADD COLUMN ambient_sun_pos TEXT",
            "ALTER TABLE assets ADD COLUMN palette_json    TEXT",
            // v0.4: user-selected preset name
            "ALTER TABLE assets ADD COLUMN preset_name TEXT",
            // v0.8: private vault flag (0 = public, 1 = private)
            "ALTER TABLE assets ADD COLUMN is_private INTEGER NOT NULL DEFAULT 0",
            // Piqd v0.3 (m_v0_3_asset_type_extension): persist Clip/Dual duration +
            // Sequence assembled-strip URL. assets.type is plain TEXT with no CHECK
            // constraint, so the new .sequence / .clip / .dual values insert without a
            // schema widening step.
            "ALTER TABLE assets ADD COLUMN duration_seconds REAL",
            "ALTER TABLE assets ADD COLUMN sequence_assembled_url TEXT",
        ]
        for sql in migrations {
            try? db.execute(sql: sql) // swallows "duplicate column" on existing DBs
        }
        // v0.3.5: l4c_records table — created by createSchema via IF NOT EXISTS, no migration needed
    }
}

// MARK: - ChromaticPalette Codable

extension ChromaticPalette: Codable {
    private enum CodingKeys: String, CodingKey { case colors }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let colors = try container.decode([HSLColor].self, forKey: .colors)
        self.init(colors: colors)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(colors, forKey: .colors)
    }
}

extension HSLColor: Codable {
    private enum CodingKeys: String, CodingKey { case hue, saturation, lightness }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hue = try c.decode(Double.self, forKey: .hue)
        let saturation = try c.decode(Double.self, forKey: .saturation)
        let lightness = try c.decode(Double.self, forKey: .lightness)
        self.init(hue: hue, saturation: saturation, lightness: lightness)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hue, forKey: .hue)
        try c.encode(saturation, forKey: .saturation)
        try c.encode(lightness, forKey: .lightness)
    }
}

// MARK: - KeychainBridge

/// Minimal Keychain helper scoped to the graph database key.
/// Generates a random 32-byte key on first launch and stores it in the Keychain.
private enum KeychainBridge {
    static func graphDatabaseKey() throws -> String {
        let service = "com.hwcho99.niftymomnt.graphKey"
        let account = "graphDatabaseKey"

        if let existing = try? keychainLoad(service: service, account: account) {
            return existing
        }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        guard status == errSecSuccess else {
            throw DatabaseError(message: "SecRandomCopyBytes failed: \(status)")
        }
        let key = keyBytes.map { String(format: "%02x", $0) }.joined()
        try keychainStore(service: service, account: account, value: key)
        return key
    }

    private static func keychainLoad(service: String, account: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw DatabaseError(message: "Keychain load failed: \(status)")
        }
        return value
    }

    private static func keychainStore(service: String, account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DatabaseError(message: "Keychain store failed: \(status)")
        }
    }
}
