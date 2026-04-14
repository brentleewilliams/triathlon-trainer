import Foundation

// MARK: - Race Course Profile (v1)
//
// Minimal data models for Race Course Intelligence. See PRD §4.3.1–4.3.2
// and §4.4.5. Keep this file tight — all course-related data types live
// here so the call sites only need a single import.

// MARK: - Terrain

enum TerrainProfile: String, Codable, CaseIterable {
    case flat
    case rolling
    case hilly
    case mountainous
}

// MARK: - Data Source

enum DataSource: String, Codable {
    case llmResearch
    case userEntered
    case bundled
}

// MARK: - Expected Weather

struct ExpectedWeather: Codable, Equatable {
    let tempHighF: Int
    let tempLowF: Int
    let conditionsSummary: String
}

// MARK: - Race Course Profile

struct RaceCourseProfile: Codable, Equatable {
    let raceId: String
    let raceName: String
    let venue: String
    let raceDate: Date

    // Race shape
    let raceType: RaceType
    let totalDistanceDescription: String

    // Terrain
    let terrain: TerrainProfile
    let totalElevationGainFeet: Int
    let venueElevationFeet: Int

    // Expected weather on race day (historical for that date/location)
    let expectedWeather: ExpectedWeather

    // Metadata
    let dataSource: DataSource
    let lastRefreshed: Date
}

// MARK: - Athlete Environment

/// The athlete's training context. Inferred on first launch via CoreLocation
/// (elevation + reverse-geocode climate) and editable in Settings.
struct AthleteEnvironment: Codable, Equatable {
    var trainingElevationFeet: Int
    var trainingClimate: String
    var poolAccess: Bool
    var openWaterAccess: Bool
    var trainerAccess: Bool

    static let defaultClimateOptions: [String] = [
        "semi-arid, dry heat",
        "humid subtropical",
        "temperate marine",
        "arid desert",
        "continental",
        "tropical"
    ]

    static func defaultInferred() -> AthleteEnvironment {
        AthleteEnvironment(
            trainingElevationFeet: 0,
            trainingClimate: "temperate marine",
            poolAccess: true,
            openWaterAccess: false,
            trainerAccess: true
        )
    }
}

// MARK: - Performance Thresholds (§4.4.5)

enum ThresholdSource: String, Codable {
    case userEntered
    case inferredFromHistory
}

struct PerformanceThresholds: Codable, Equatable {
    var ftpWatts: Int?
    var thresholdPaceSecondsPerMile: Int?
    var cssSecondsPer100yd: Int?
    var capturedAt: Date?
    var source: ThresholdSource

    static let empty = PerformanceThresholds(
        ftpWatts: nil,
        thresholdPaceSecondsPerMile: nil,
        cssSecondsPer100yd: nil,
        capturedAt: nil,
        source: .userEntered
    )

    var hasAnyValue: Bool {
        ftpWatts != nil || thresholdPaceSecondsPerMile != nil || cssSecondsPer100yd != nil
    }
}

// MARK: - Altitude Context

/// Result of comparing training elevation vs race elevation. Returned by
/// `RaceCourseService.getAltitudeAdjustment(...)`.
struct AltitudeContext: Equatable {
    /// Positive means training is higher than race (descending for race day).
    let deltaFeet: Int
    /// Approximate HR adjustment at race-day elevation vs training. Positive
    /// means HR will be *lower* at race elevation for the same effort.
    let hrAdjustmentBpm: Int
    /// Expected pace advantage in seconds per mile (run). Positive means
    /// faster at race-day elevation. Zero for small deltas.
    let paceAdvantageSecPerMile: Int
    /// Human-facing acclimation recommendation.
    let acclimationRecommendation: String
    /// Short summary suitable for the system prompt.
    let summary: String
}

// MARK: - Pacing Plan

enum PacingDiscipline: String, Codable {
    case swim
    case bike
    case run
}

/// Per-discipline pacing target. v1 returns effort-descriptor pacing by
/// default; specific watt/pace numbers are only populated when
/// `PerformanceThresholds` has data.
struct PacingTarget: Codable, Equatable {
    let discipline: PacingDiscipline
    /// Plain-language effort descriptor ("Z2 steady", "strong but sustainable").
    let effortDescriptor: String
    /// Specific numeric target when available ("160-170W", "8:30/mi").
    let numericTarget: String?
    /// Short coaching note.
    let note: String?
}

struct PacingPlan: Codable, Equatable {
    let raceId: String
    let targets: [PacingTarget]
    /// True when any numeric target was populated from PerformanceThresholds.
    let hasNumericTargets: Bool
    /// One-line overall strategy.
    let strategySummary: String
}
