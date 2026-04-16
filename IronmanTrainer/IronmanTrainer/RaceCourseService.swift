import Foundation
import CoreLocation

// MARK: - Athlete Data (for pacing)

/// Minimal slice of athlete state needed by `getPacingStrategy`. Keeps the
/// service decoupled from `UserProfile` / `HealthKitManager`.
struct AthleteData {
    var thresholds: PerformanceThresholds
    var environment: AthleteEnvironment?
}

// MARK: - Race Course Service
//
// v1 responsibilities:
//  - Load a bundled `RaceCourseProfile` (currently Ironman 70.3 Oregon).
//  - Emit phase-dependent system-prompt context (always / +5wk / +2wk tiers).
//  - Compute altitude delta + acclimation notes.
//  - Produce a pacing plan using effort descriptors by default; inject
//    numeric targets only when `PerformanceThresholds` is populated.
//  - Persist `AthleteEnvironment` via UserDefaults (small-surface helper).
//
// v2 will extend `loadCourseProfile` to consult Firestore cache + a
// `courseResearch` Cloud Function. The seam is marked below.

@MainActor
final class RaceCourseService: ObservableObject {
    static let shared = RaceCourseService()

    // MARK: Published

    /// The currently active course profile (if loaded).
    @Published private(set) var currentProfile: RaceCourseProfile?
    /// The athlete's training environment (inferred or user-edited).
    @Published var athleteEnvironment: AthleteEnvironment

    // MARK: Storage keys

    private enum Keys {
        static let environment = "raceCourse.athleteEnvironment"
        static let inferredOnce = "raceCourse.environmentInferredOnce"
    }

    // MARK: Init

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.environment) {
            do {
                self.athleteEnvironment = try JSONDecoder().decode(AthleteEnvironment.self, from: data)
            } catch {
                print("[RaceCourseService] Failed to decode stored AthleteEnvironment: \(error). Falling back to defaults.")
                self.athleteEnvironment = AthleteEnvironment.defaultInferred()
            }
        } else {
            self.athleteEnvironment = AthleteEnvironment.defaultInferred()
        }
    }

    // MARK: - Profile Loading

    /// Loads the course profile for `raceId`. v1 consults the bundled
    /// profile table only. v2 will fall back to Firestore cache → Cloud
    /// Function research.
    func loadCourseProfile(for raceId: String) -> RaceCourseProfile? {
        if let bundled = BundledCourseProfiles.all[raceId] {
            currentProfile = bundled
            return bundled
        }
        // TODO(v2): Firestore cache lookup at raceCourses/{raceId},
        // then POST /llmProxy { type: "courseResearch", ... } on miss.
        return nil
    }

    /// Convenience for the single v1 race.
    func loadDefaultProfile() -> RaceCourseProfile? {
        loadCourseProfile(for: BundledCourseProfiles.ironman703Oregon2026.raceId)
    }

    // MARK: - Phase Context (§4.5)

    /// Returns the phase-dependent course context block for the system
    /// prompt. Size scales with proximity to race day:
    ///  - Always: race name/date/venue, altitude delta, course shape.
    ///  - +5wk (≤5 weeks to race): heat acclimation + race-pace notes.
    ///  - +2wk (≤2 weeks to race): travel, weather, pacing-by-discipline.
    func getPhaseContext(weeksToRace: Int, profile: RaceCourseProfile? = nil) -> String {
        guard let profile = profile ?? currentProfile else { return "" }
        var blocks: [String] = []

        // ---- Always ----
        let altitude = getAltitudeAdjustment(
            trainingElevation: athleteEnvironment.trainingElevationFeet,
            raceElevation: profile.venueElevationFeet
        )
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeZone = TimeZone.current
        var always = "RACE COURSE CONTEXT (always):\n"
        always += "- Race: \(profile.raceName), \(df.string(from: profile.raceDate))\n"
        always += "- Venue: \(profile.venue) (\(profile.venueElevationFeet)ft)\n"
        always += "- Course shape: \(profile.terrain.rawValue), \(profile.totalDistanceDescription), "
        always += "\(profile.totalElevationGainFeet)ft total elevation gain\n"
        always += "- Athlete training at \(athleteEnvironment.trainingElevationFeet)ft "
        always += "(\(athleteEnvironment.trainingClimate))\n"
        always += "- Altitude delta: \(altitude.summary)\n"
        blocks.append(always)

        // ---- +5wk tier ----
        if weeksToRace <= 5 {
            var mid = "RACE PREP (≤5 weeks):\n"
            mid += "- Expected race-day weather: \(profile.expectedWeather.tempLowF)-"
            mid += "\(profile.expectedWeather.tempHighF)°F, \(profile.expectedWeather.conditionsSummary)\n"
            mid += "- Heat acclimation: starting ~3 weeks out, suggest 20-30 min heat exposure "
            mid += "(sauna, hot bath post-workout, midday training).\n"
            mid += "- Race-pace sessions: calibrate to HR zones + effort descriptors. "
            mid += "Altitude-adjusted targets: \(altitude.acclimationRecommendation).\n"
            mid += "- Terrain-specific emphasis: \(terrainEmphasis(profile.terrain)).\n"
            blocks.append(mid)
        }

        // ---- +2wk tier ----
        if weeksToRace <= 2 {
            var hot = "RACE WEEK (≤2 weeks):\n"
            hot += "- Travel: athlete at \(athleteEnvironment.trainingElevationFeet)ft → "
            hot += "race at \(profile.venueElevationFeet)ft. "
            hot += "Arrive 2 days early to adjust; expect feeling oxygen-rich — don't go out too fast.\n"
            hot += "- Taper: course is \(profile.terrain.rawValue) — keep intensity brief, volume low.\n"
            hot += "- Pacing strategy: use effort descriptors unless athlete has shared thresholds. "
            hot += "Swim: draft when possible. Bike: hold Z2 steady through rolling sections. "
            hot += "Run: start conservative Z2 — altitude fitness gives a cushion to negative split.\n"
            blocks.append(hot)
        }

        return blocks.joined(separator: "\n")
    }

    private func terrainEmphasis(_ terrain: TerrainProfile) -> String {
        switch terrain {
        case .flat:
            return "sustained power at threshold, not climbing strength"
        case .rolling:
            return "sustained power at threshold with short surges over rollers"
        case .hilly:
            return "climbing repeats and extended tempo on grade"
        case .mountainous:
            return "long sustained climbs + descent skills"
        }
    }

    // MARK: - Altitude Adjustment

    /// Computes altitude delta and returns HR + pace adjustment estimates
    /// plus acclimation recommendations.
    ///
    /// Rules of thumb (v1, validated against §4.4.1–4.4.3 coaching examples):
    ///  - Each 1,000ft of descent to race day ≈ 3 bpm lower HR at the same effort.
    ///  - Each 1,000ft of descent to race day ≈ 6 sec/mi faster run pace.
    ///  - Zero when delta < 500ft either direction.
    ///  - Ascent (training lower than race) means HR *higher* at race → flip signs.
    nonisolated func getAltitudeAdjustment(trainingElevation: Int, raceElevation: Int) -> AltitudeContext {
        let delta = trainingElevation - raceElevation
        let absDelta = abs(delta)

        // Small deltas: no meaningful adjustment.
        if absDelta < 500 {
            return AltitudeContext(
                deltaFeet: delta,
                hrAdjustmentBpm: 0,
                paceAdvantageSecPerMile: 0,
                acclimationRecommendation: "No meaningful altitude change — train and race at similar effort.",
                summary: "Race elevation matches training — no altitude adjustment needed."
            )
        }

        // Descending to race day (training higher): advantage.
        if delta > 0 {
            let hrBpm = Int((Double(delta) / 1000.0) * 3.0)
            let paceSec = Int((Double(delta) / 1000.0) * 6.0)
            let rec = "At race elevation, HR at the same effort will be roughly \(hrBpm) bpm lower — " +
                "treat altitude HR readings as 'expected at altitude'. Plan to feel fast on race day."
            let summary = "Training at +\(delta)ft vs race — ~\(hrBpm) bpm lower HR, " +
                "~\(paceSec) sec/mi faster run pace at race elevation. Advantage."
            return AltitudeContext(
                deltaFeet: delta,
                hrAdjustmentBpm: hrBpm,
                paceAdvantageSecPerMile: paceSec,
                acclimationRecommendation: rec,
                summary: summary
            )
        }

        // Ascending to race day (training lower): disadvantage.
        let ascentFeet = -delta
        let hrBpm = -Int((Double(ascentFeet) / 1000.0) * 3.0)
        let paceSec = -Int((Double(ascentFeet) / 1000.0) * 6.0)
        let rec = "Race is at altitude (\(ascentFeet)ft higher). HR at effort will be ~\(abs(hrBpm)) bpm " +
            "higher; pace will feel ~\(abs(paceSec)) sec/mi slower. Arrive early if possible and " +
            "accept slower early-race pacing."
        let summary = "Race is +\(ascentFeet)ft above training — expect ~\(abs(hrBpm)) bpm higher HR " +
            "and ~\(abs(paceSec)) sec/mi slower run pace. Acclimate if arrival allows."
        return AltitudeContext(
            deltaFeet: delta,
            hrAdjustmentBpm: hrBpm,
            paceAdvantageSecPerMile: paceSec,
            acclimationRecommendation: rec,
            summary: summary
        )
    }

    // MARK: - Pacing Strategy

    /// Produces a pacing plan. v1 defaults to effort descriptors; numeric
    /// targets only appear when the athlete has provided thresholds
    /// (§4.4.5 opportunistic capture).
    func getPacingStrategy(profile: RaceCourseProfile, athleteData: AthleteData) -> PacingPlan {
        let t = athleteData.thresholds
        let hasNumbers = t.hasAnyValue

        // Swim
        let swimNumeric: String? = {
            guard let css = t.cssSecondsPer100yd else { return nil }
            return "~\(Self.formatMinSecPace(seconds: css))/100yd"
        }()
        let swim = PacingTarget(
            discipline: .swim,
            effortDescriptor: "Steady Z2, draft when possible",
            numericTarget: swimNumeric,
            note: "Conserve legs for the bike — no hero pulls."
        )

        // Bike
        let bikeNumeric: String? = {
            guard let ftp = t.ftpWatts else { return nil }
            let low = Int(Double(ftp) * 0.72)
            let high = Int(Double(ftp) * 0.78)
            return "\(low)-\(high)W (72-78% FTP)"
        }()
        let terrainNote: String
        switch profile.terrain {
        case .flat: terrainNote = "Hold steady watts; aero matters more than climbing."
        case .rolling: terrainNote = "Ride rollers steady — don't surge over short climbs."
        case .hilly: terrainNote = "Pace climbs at Z3 ceiling, recover on descents."
        case .mountainous: terrainNote = "Sustained tempo up climbs; eat on descents."
        }
        let bike = PacingTarget(
            discipline: .bike,
            effortDescriptor: "Z2 steady with controlled rollers",
            numericTarget: bikeNumeric,
            note: terrainNote
        )

        // Run
        let runNumeric: String? = {
            guard let pace = t.thresholdPaceSecondsPerMile else { return nil }
            let target = pace + 60 // ~Z2 for a half-marathon off the bike
            return "~\(Self.formatMinSecPace(seconds: target))/mi"
        }()
        let run = PacingTarget(
            discipline: .run,
            effortDescriptor: "Start conservative Z2, build in back half",
            numericTarget: runNumeric,
            note: "Negative-split if legs allow — altitude fitness is your cushion."
        )

        let summary = hasNumbers
            ? "Pacing with athlete-provided thresholds — targets are anchors, not limits."
            : "Effort-descriptor pacing (no thresholds captured). Ask athlete if specific numbers are desired."

        return PacingPlan(
            raceId: profile.raceId,
            targets: [swim, bike, run],
            hasNumericTargets: hasNumbers,
            strategySummary: summary
        )
    }

    /// Formats an integer duration in seconds as `m:ss`. Used for pace strings
    /// (both per-mile and per-100yd — caller appends the unit). Pure function,
    /// so `nonisolated` to allow use from any actor context (incl. tests).
    nonisolated static func formatMinSecPace(seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Environment Persistence

    func saveEnvironment(_ env: AthleteEnvironment) {
        athleteEnvironment = env
        do {
            let data = try JSONEncoder().encode(env)
            UserDefaults.standard.set(data, forKey: Keys.environment)
        } catch {
            print("[RaceCourseService] Failed to encode AthleteEnvironment: \(error)")
        }
    }

    /// True when `inferEnvironmentIfNeeded` has already run at least once.
    var hasInferredEnvironment: Bool {
        UserDefaults.standard.bool(forKey: Keys.inferredOnce)
    }

    /// Infers `AthleteEnvironment` from `CLLocation` on first launch. If
    /// permission is denied, the stored defaults remain and the user can
    /// override via Settings.
    func inferEnvironmentIfNeeded(location: CLLocation?, adminArea: String?) {
        guard !hasInferredEnvironment else { return }
        var env = athleteEnvironment
        if let loc = location {
            let metersToFeet = 3.28084
            env.trainingElevationFeet = Int((loc.altitude * metersToFeet).rounded())
        }
        env.trainingClimate = Self.climateClassification(adminArea: adminArea)
        saveEnvironment(env)
        UserDefaults.standard.set(true, forKey: Keys.inferredOnce)
    }

    /// Köppen-style heuristic on US admin area → one of the climate picker options.
    /// Pure function, so `nonisolated` to allow use from any actor context.
    nonisolated static func climateClassification(adminArea: String?) -> String {
        guard let area = adminArea?.lowercased() else { return "temperate marine" }
        // Arid desert (hottest, driest)
        let aridDesert: Set<String> = ["arizona", "nevada", "new mexico"]
        if aridDesert.contains(area) { return "arid desert" }
        // Semi-arid / dry heat (mountain west)
        let semiArid: Set<String> = ["colorado", "utah", "wyoming", "montana", "idaho"]
        if semiArid.contains(area) { return "semi-arid, dry heat" }
        // Humid subtropical
        let humidSub: Set<String> = [
            "florida", "louisiana", "texas", "georgia", "alabama", "mississippi",
            "south carolina", "north carolina", "arkansas", "tennessee"
        ]
        if humidSub.contains(area) { return "humid subtropical" }
        // Temperate marine (PNW + coastal NorCal)
        let temperateMarine: Set<String> = ["oregon", "washington"]
        if temperateMarine.contains(area) { return "temperate marine" }
        // Tropical (HI + southernmost FL treated via humid subtropical)
        if area == "hawaii" { return "tropical" }
        // Continental (Midwest, Northeast, interior West)
        let continental: Set<String> = [
            "minnesota", "wisconsin", "michigan", "illinois", "indiana", "ohio",
            "iowa", "missouri", "kansas", "nebraska", "south dakota", "north dakota",
            "pennsylvania", "new york", "new jersey", "connecticut", "massachusetts",
            "rhode island", "vermont", "new hampshire", "maine", "west virginia",
            "virginia", "kentucky", "oklahoma", "maryland", "delaware"
        ]
        if continental.contains(area) { return "continental" }
        // Default
        return "temperate marine"
    }
}
