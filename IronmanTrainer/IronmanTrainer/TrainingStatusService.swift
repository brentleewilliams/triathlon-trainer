import Foundation
import HealthKit
import Combine

// MARK: - Models

enum TrainingDiscipline: String, CaseIterable, Codable {
    case swim, bike, run, combined
}

struct FitnessMetrics: Codable, Equatable {
    let discipline: TrainingDiscipline
    let ctl: Double
    let atl: Double
    var tsb: Double { ctl - atl }
    let lastSessionDaysAgo: Int?
    let weeklySessionCount: Int
}

struct DisciplineGap: Codable, Equatable {
    let discipline: TrainingDiscipline
    let daysSinceLastSession: Int
    let weeklySessionCount: Int
    let ctlVsHighest: Double

    var isMissing: Bool { daysSinceLastSession > 14 }
    var isUndertrained: Bool { ctlVsHighest < 0.30 && !isMissing }

    enum GapSeverity: String, Codable { case critical, warning, caution, none }
    var severity: GapSeverity {
        if isMissing { return .critical }
        if isUndertrained { return .warning }
        if daysSinceLastSession > 7 { return .caution }
        return .none
    }
}

// MARK: - Volume status (the new race-readiness metric)
//
// For each discipline, compares actual minutes done over the rolling
// 6-week window against expected minutes (plan when present, onboarding
// baseline otherwise). Weeks marked as taper in the plan are excluded
// from both numerator and denominator.

struct DisciplineVolumeStatus: Codable, Equatable {
    let discipline: TrainingDiscipline
    let actualMinutes: Int
    let plannedMinutes: Int
    let weeksConsidered: Int           // how many of the 6 weeks counted (taper + missing data excluded)
    let usedBaselineFallback: Bool     // true when ≥1 week used WeeklyVolumeStore baseline instead of plan

    /// Percent of planned volume completed. 100 = exactly on plan.
    /// When `plannedMinutes == 0` we can't compute a ratio, so report 100
    /// (you can't fall behind a plan that didn't ask for anything).
    var percent: Int {
        guard plannedMinutes > 0 else { return 100 }
        return Int((Double(actualMinutes) / Double(plannedMinutes)) * 100.0)
    }

    enum Severity: String, Codable { case onTrack, slipping, behind }
    var severity: Severity {
        let p = percent
        if p >= 90 { return .onTrack }
        if p >= 70 { return .slipping }
        return .behind
    }
}

struct HRVTrend: Codable, Equatable {
    let todaySDNN: Double?
    let sevenDayAvg: Double?
    let sixtyDayBaseline: Double?
    var percentFromBaseline: Double? {
        guard let t = todaySDNN, let b = sixtyDayBaseline, b > 0 else { return nil }
        return ((t - b) / b) * 100.0
    }
    enum Direction: String, Codable { case improving, stable, declining, insufficient }
    var direction: Direction {
        guard let pct = percentFromBaseline else { return .insufficient }
        if pct > 3 { return .improving }
        if pct < -5 { return .declining }
        return .stable
    }
}

struct DecouplingResult: Codable, Equatable {
    let workoutDate: Date
    let discipline: TrainingDiscipline
    let decouplingPercent: Double
    let durationMinutes: Double
    var isRaceReady: Bool { decouplingPercent < 5.0 }
}

enum IntensityPattern: String, Codable {
    case polarized
    case pyramidal
    case thresholdHeavy
    case mixed
    case insufficientData
}

struct LoadSpike: Codable, Equatable {
    let currentWeekHRSS: Double
    let priorWeekHRSS: Double
    var increasePercent: Double {
        guard priorWeekHRSS > 0 else { return 0 }
        return ((currentWeekHRSS - priorWeekHRSS) / priorWeekHRSS) * 100.0
    }
    var isSpiked: Bool { increasePercent > 15 }
    var isCritical: Bool { increasePercent > 25 }
}

struct CompositeReadiness: Codable, Equatable {
    let score: Int
    let tsbScore: Int
    let hrvScore: Int
    let loadSpikeScore: Int

    enum Level: String, Codable {
        case race, fresh, training, tired, overreached
    }
    var level: Level {
        switch score {
        case 80...: return .race
        case 60..<80: return .fresh
        case 40..<60: return .training
        case 20..<40: return .tired
        default: return .overreached
        }
    }
}

struct TrainingStatus: Codable, Equatable {
    let computedAt: Date
    let fitnessPerDiscipline: [FitnessMetrics]
    let disciplineGaps: [DisciplineGap]
    // Optional in storage: caches written before this field existed will decode
    // without it; compute() always populates a non-nil value.
    let disciplineVolumeStatuses: [DisciplineVolumeStatus]
    let hrvTrend: HRVTrend
    let recentDecoupling: [DecouplingResult]
    let intensityPattern: IntensityPattern
    let loadSpike: LoadSpike
    let readiness: CompositeReadiness

    enum CodingKeys: String, CodingKey {
        case computedAt, fitnessPerDiscipline, disciplineGaps, disciplineVolumeStatuses
        case hrvTrend, recentDecoupling, intensityPattern, loadSpike, readiness
    }

    init(
        computedAt: Date,
        fitnessPerDiscipline: [FitnessMetrics],
        disciplineGaps: [DisciplineGap],
        disciplineVolumeStatuses: [DisciplineVolumeStatus],
        hrvTrend: HRVTrend,
        recentDecoupling: [DecouplingResult],
        intensityPattern: IntensityPattern,
        loadSpike: LoadSpike,
        readiness: CompositeReadiness
    ) {
        self.computedAt = computedAt
        self.fitnessPerDiscipline = fitnessPerDiscipline
        self.disciplineGaps = disciplineGaps
        self.disciplineVolumeStatuses = disciplineVolumeStatuses
        self.hrvTrend = hrvTrend
        self.recentDecoupling = recentDecoupling
        self.intensityPattern = intensityPattern
        self.loadSpike = loadSpike
        self.readiness = readiness
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        computedAt              = try c.decode(Date.self,                          forKey: .computedAt)
        fitnessPerDiscipline    = try c.decode([FitnessMetrics].self,              forKey: .fitnessPerDiscipline)
        disciplineGaps          = try c.decode([DisciplineGap].self,               forKey: .disciplineGaps)
        disciplineVolumeStatuses = (try? c.decode([DisciplineVolumeStatus].self,   forKey: .disciplineVolumeStatuses)) ?? []
        hrvTrend                = try c.decode(HRVTrend.self,                      forKey: .hrvTrend)
        recentDecoupling        = try c.decode([DecouplingResult].self,            forKey: .recentDecoupling)
        intensityPattern        = try c.decode(IntensityPattern.self,              forKey: .intensityPattern)
        loadSpike               = try c.decode(LoadSpike.self,                     forKey: .loadSpike)
        readiness               = try c.decode(CompositeReadiness.self,            forKey: .readiness)
    }

    var combinedFitness: FitnessMetrics? { fitnessPerDiscipline.first { $0.discipline == .combined } }
    var combinedTSB: Double? { combinedFitness?.tsb }
    var criticalGaps: [DisciplineGap] { disciplineGaps.filter { $0.severity == .critical } }
    var warningGaps: [DisciplineGap] { disciplineGaps.filter { $0.severity == .warning } }

    func contextString(brief: Bool = false) -> String {
        let combined = combinedFitness
        let tsb = combined?.tsb ?? 0
        let ctl = combined?.ctl ?? 0
        let atl = combined?.atl ?? 0
        let score = readiness.score
        let level = readiness.level.rawValue.capitalized

        if brief {
            var lines: [String] = []
            let hrvPctStr: String
            if let pct = hrvTrend.percentFromBaseline {
                hrvPctStr = String(format: "%+.0f%%", pct)
            } else {
                hrvPctStr = "n/a"
            }
            lines.append(String(format: "READINESS: %d/100 (%@) — Form: %+.0f, HRV: %@ above baseline", score, level, tsb, hrvPctStr))
            if !criticalGaps.isEmpty {
                let gapDesc = criticalGaps.map { "\($0.discipline.rawValue.capitalized) (\($0.daysSinceLastSession)d gap)" }.joined(separator: ", ")
                lines.append("⚠️ DISCIPLINE GAPS: \(gapDesc)")
            }
            return lines.joined(separator: "\n")
        }

        var out = "====== TRAINING STATUS ======\n"
        out += String(format: "Overall — CTL: %.0f | ATL: %.0f | Form (TSB): %+.0f\n", ctl, atl, tsb)
        out += String(format: "Readiness: %d/100 (%@)\n", score, level)

        if let today = hrvTrend.todaySDNN, let pct = hrvTrend.percentFromBaseline {
            out += String(format: "HRV: %.0f ms today, %+.0f%% vs 60-day baseline (%@)\n", today, pct, hrvTrend.direction.rawValue)
        } else {
            out += "HRV: insufficient data\n"
        }

        if !criticalGaps.isEmpty {
            let gapDesc = criticalGaps.map { "\($0.discipline.rawValue.capitalized) (\($0.daysSinceLastSession)d gap)" }.joined(separator: ", ")
            out += "⚠️ DISCIPLINE GAPS: \(gapDesc) — athlete has not trained these in 14+ days\n"
        }

        for disc in [TrainingDiscipline.swim, .bike, .run] {
            guard let m = fitnessPerDiscipline.first(where: { $0.discipline == disc }) else { continue }
            let lastStr = m.lastSessionDaysAgo.map { "\($0)d ago" } ?? "never"
            out += String(format: "  %@ — CTL: %.0f | ATL: %.0f | TSB: %+.0f | Last: %@ | This week: %dx\n",
                          disc.rawValue.capitalized, m.ctl, m.atl, m.tsb, lastStr, m.weeklySessionCount)
        }

        out += "Intensity pattern (14d): \(intensityPattern.rawValue)\n"

        if let lastDec = recentDecoupling.first {
            let readyStr = lastDec.isRaceReady ? "✅ race-ready" : "❌ needs base work"
            let discLabel = lastDec.discipline.rawValue
            out += String(format: "Aerobic decoupling (last %@ ≥60min): %.1f%% (%@)\n", discLabel, lastDec.decouplingPercent, readyStr)
        }

        return out
    }
}

// MARK: - TrainingStatusService

@MainActor
final class TrainingStatusService: ObservableObject {

    @Published var status: TrainingStatus?
    @Published var isComputing = false
    @Published var hasEverComputed = false

    private let healthKit: HealthKitManager?
    private static let cacheKey = "trainingStatus_v1"
    private static let cacheTTL: TimeInterval = 6 * 60 * 60
    private var cancellables = Set<AnyCancellable>()
    // Set to true the first time the HK workouts publisher fires after init,
    // guaranteeing we've actually received synced data from HealthKit.
    private var healthKitDidSync = false

    init(healthKit: HealthKitManager? = nil) {
        self.healthKit = healthKit
        self.status = Self.loadCached()

        // Recompute when HK workouts arrive after init.
        // The initial compute() in ContentView.onAppear races against syncWorkouts()
        // and can read an empty array, pinning a bad result in cache. Subscribing
        // here makes sure we recompute as soon as workouts actually populate.
        healthKit?.$workouts
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.healthKitDidSync = true
                    await self?.compute()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public entry point

    func compute() async {
        isComputing = true
        defer { isComputing = false }

        let workouts = healthKit?.workouts ?? []
        let maxHR = Double(healthKit?.maxHeartRate ?? 182)
        let zoneCache = healthKit?.workoutZones ?? [:]
        let calendar = Calendar.current
        let now = Date()

        // Build 60-day daily HRSS buckets per discipline
        let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let recentWorkouts = workouts.filter { $0.startDate >= sixtyDaysAgo }

        // Map workout type → discipline
        func discipline(for workout: HKWorkout) -> TrainingDiscipline? {
            switch workout.workoutActivityType {
            case .swimming: return .swim
            case .cycling: return .bike
            case .running: return .run
            default: return nil
            }
        }

        // Build daily HRSS arrays (index 0 = 59 days ago, index 59 = today)
        var dailyHRSS: [TrainingDiscipline: [Double]] = [
            .swim: Array(repeating: 0, count: 60),
            .bike: Array(repeating: 0, count: 60),
            .run: Array(repeating: 0, count: 60),
            .combined: Array(repeating: 0, count: 60)
        ]

        for workout in recentWorkouts {
            guard let disc = discipline(for: workout) else { continue }
            let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: workout.startDate), to: calendar.startOfDay(for: now)).day ?? 0
            let idx = 59 - daysAgo
            guard idx >= 0 && idx < 60 else { continue }

            let durationHours = workout.duration / 3600.0
            // Use average HR from workout metadata if available, else fall back to 75% maxHR
            let avgHR: Double
            if let hrQuantity = workout.statistics(for: HKQuantityType.quantityType(forIdentifier: .heartRate)!)?.averageQuantity() {
                avgHR = hrQuantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
            } else {
                avgHR = maxHR * 0.75
            }

            let hrss = Self.computeHRSS(durationHours: durationHours, avgHR: avgHR, maxHR: maxHR)
            dailyHRSS[disc]?[idx] += hrss
            dailyHRSS[.combined]?[idx] += hrss
        }

        // Compute CTL/ATL per discipline
        let ctlLambda = 2.0 / 43.0
        let atlLambda = 2.0 / 8.0

        var fitnessMetrics: [FitnessMetrics] = []
        for disc in TrainingDiscipline.allCases {
            let daily = dailyHRSS[disc] ?? Array(repeating: 0, count: 60)
            let ctl = Self.computeEWA(dailyValues: daily, lambda: ctlLambda)
            let atl = Self.computeEWA(dailyValues: daily, lambda: atlLambda)

            // Last session days ago and weekly session count
            var lastDaysAgo: Int? = nil
            var weeklyCount = 0
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now

            let discWorkouts: [HKWorkout]
            if disc == .combined {
                discWorkouts = recentWorkouts.filter { discipline(for: $0) != nil }
            } else {
                discWorkouts = recentWorkouts.filter { discipline(for: $0) == disc }
            }

            if let latest = discWorkouts.sorted(by: { $0.startDate > $1.startDate }).first {
                lastDaysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: latest.startDate), to: calendar.startOfDay(for: now)).day
            }
            weeklyCount = discWorkouts.filter { $0.startDate >= sevenDaysAgo }.count

            fitnessMetrics.append(FitnessMetrics(
                discipline: disc,
                ctl: ctl,
                atl: atl,
                lastSessionDaysAgo: lastDaysAgo,
                weeklySessionCount: weeklyCount
            ))
        }

        // Discipline gaps (swim/bike/run only)
        let highestCTL = fitnessMetrics
            .filter { $0.discipline != .combined }
            .map { $0.ctl }
            .max() ?? 1.0

        var disciplineGaps: [DisciplineGap] = []
        for disc in [TrainingDiscipline.swim, .bike, .run] {
            guard let metrics = fitnessMetrics.first(where: { $0.discipline == disc }) else { continue }
            let daysAgo = metrics.lastSessionDaysAgo ?? 999
            let ctlRatio = highestCTL > 0 ? metrics.ctl / highestCTL : 0
            disciplineGaps.append(DisciplineGap(
                discipline: disc,
                daysSinceLastSession: daysAgo,
                weeklySessionCount: metrics.weeklySessionCount,
                ctlVsHighest: ctlRatio
            ))
        }

        // HRV trend
        let hrvSamples = await healthKit?.fetchHRVSamples(days: 60) ?? []
        let hrvTrend = Self.buildHRVTrend(samples: hrvSamples, now: now)

        // Aerobic decoupling (last 5 runs/bikes ≥ 60 min)
        let longWorkouts = recentWorkouts
            .filter {
                let disc = discipline(for: $0)
                return (disc == .run || disc == .bike) && $0.duration >= 3600
            }
            .sorted(by: { $0.startDate > $1.startDate })
            .prefix(5)

        var decouplingResults: [DecouplingResult] = []
        for workout in longWorkouts {
            let hrSamples = await healthKit?.fetchHRSamples(for: workout) ?? []
            let distSamples = await healthKit?.fetchDistanceSamples(for: workout) ?? []
            guard hrSamples.count >= 40, distSamples.count >= 20 else { continue }
            if let result = Self.computeDecoupling(workout: workout, hrSamples: hrSamples, distSamples: distSamples, discipline: discipline(for: workout) ?? .run) {
                decouplingResults.append(result)
            }
        }

        // Intensity pattern from zone cache
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let recentZoneWorkouts = recentWorkouts.filter { $0.startDate >= fourteenDaysAgo }
        var zoneTotals: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
        for workout in recentZoneWorkouts {
            if let zones = zoneCache[workout.uuid] {
                for (zone, pct) in zones {
                    zoneTotals[zone, default: 0] += pct
                }
            }
        }
        let intensityPattern = Self.computeIntensityPattern(zoneTotals: zoneTotals)

        // Load spike (current week vs prior week HRSS)
        let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let startOfPriorWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek) ?? now

        let currentWeekHRSS = dailyHRSS[.combined]?.suffix(7).reduce(0, +) ?? 0
        let priorWeekHRSS: Double = {
            var total = 0.0
            for workout in recentWorkouts {
                guard workout.startDate >= startOfPriorWeek && workout.startDate < startOfThisWeek else { continue }
                guard discipline(for: workout) != nil else { continue }
                let durationHours = workout.duration / 3600.0
                let avgHR: Double
                if let hrQ = workout.statistics(for: HKQuantityType.quantityType(forIdentifier: .heartRate)!)?.averageQuantity() {
                    avgHR = hrQ.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                } else {
                    avgHR = maxHR * 0.75
                }
                total += Self.computeHRSS(durationHours: durationHours, avgHR: avgHR, maxHR: maxHR)
            }
            return total
        }()

        let loadSpike = Self.computeLoadSpike(currentWeekHRSS: currentWeekHRSS, priorWeekHRSS: priorWeekHRSS)

        // Composite readiness
        let combinedMetrics = fitnessMetrics.first { $0.discipline == .combined }
        let tsb = combinedMetrics?.tsb ?? 0
        let readiness = Self.computeReadiness(tsb: tsb, hrvTrend: hrvTrend, loadSpike: loadSpike)

        // Volume status — compares actual minutes vs planned (or onboarding
        // baseline) over the last 6 weeks, skipping taper weeks.
        let planWeeks = AuthService.shared.savedPlan ?? []
        let baselines = WeeklyVolumeStore.loadMinutes()
        let volumeStatuses = Self.computeVolumeStatuses(
            workouts: recentWorkouts,
            planWeeks: planWeeks,
            baselineMinutes: (swim: baselines.swim, bike: baselines.bike, run: baselines.run),
            now: now,
            calendar: calendar,
            disciplineFor: discipline
        )

        let newStatus = TrainingStatus(
            computedAt: now,
            fitnessPerDiscipline: fitnessMetrics,
            disciplineGaps: disciplineGaps,
            disciplineVolumeStatuses: volumeStatuses,
            hrvTrend: hrvTrend,
            recentDecoupling: decouplingResults,
            intensityPattern: intensityPattern,
            loadSpike: loadSpike,
            readiness: readiness
        )

        // Guard: if workouts are empty AND HealthKit hasn't confirmed a sync yet,
        // this is the cold-start race where compute() fired before syncWorkouts()
        // finished. Skip updating the UI — the HK observer will trigger a fresh
        // compute once real data is available, so the readiness circles stay in
        // their loading (gray) state instead of flashing red.
        guard !recentWorkouts.isEmpty || healthKitDidSync else { return }

        self.status = newStatus
        hasEverComputed = true

        if !recentWorkouts.isEmpty {
            Self.saveCache(newStatus)
            let swimPct = newStatus.disciplineVolumeStatuses.first { $0.discipline == .swim }?.percent ?? 0
            let bikePct = newStatus.disciplineVolumeStatuses.first { $0.discipline == .bike }?.percent ?? 0
            let runPct  = newStatus.disciplineVolumeStatuses.first { $0.discipline == .run  }?.percent ?? 0
            AppGroupConstants.syncReadinessToWidget(
                score: newStatus.readiness.score,
                swimPercent: swimPct,
                bikePercent: bikePct,
                runPercent: runPct
            )
        }
    }

    // MARK: - Static helpers (internal for tests)

    /// Compute per-discipline volume status over the last 6 weeks (42 days).
    ///
    /// Algorithm:
    /// - Anchor the window on the Monday of the week that's 5 weeks ago
    ///   (so the window is exactly 6 ISO weeks ending with the current one).
    /// - For each of the 6 weeks: if the matching plan week's phase is "Taper",
    ///   skip the week entirely (both planned and actual are excluded).
    /// - Otherwise: planned minutes per discipline = sum of `parseWorkoutDuration`
    ///   over plan workouts whose `day` matches that week. If no plan exists
    ///   for that week (pre-plan), fall back to the user's onboarding baseline
    ///   (`baselineMinutes`).
    /// - Actual minutes = sum of HK workout durations of that discipline within
    ///   the week's Mon..Sun range.
    static func computeVolumeStatuses(
        workouts: [HKWorkout],
        planWeeks: [TrainingWeek],
        baselineMinutes: (swim: Int, bike: Int, run: Int),
        now: Date,
        calendar: Calendar = Calendar.current,
        disciplineFor: (HKWorkout) -> TrainingDiscipline?
    ) -> [DisciplineVolumeStatus] {
        var cal = calendar
        cal.firstWeekday = 2  // Monday

        // Find the Monday of the current ISO week.
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        guard let thisMonday = cal.date(from: comps) else { return [] }

        // Build six week windows ending with the current week.
        var weekRanges: [(monday: Date, sunday: Date, planWeek: TrainingWeek?)] = []
        for offset in (-5...0) {
            guard let monday = cal.date(byAdding: .weekOfYear, value: offset, to: thisMonday),
                  let sunday = cal.date(byAdding: .day, value: 7, to: monday) else { continue }
            // Plan week match: any plan week whose Monday equals this Monday.
            let planWeek = planWeeks.first { pw in
                cal.isDate(mondayOfISOWeek(for: pw.startDate, calendar: cal),
                           inSameDayAs: monday)
            }
            weekRanges.append((monday, sunday, planWeek))
        }

        let disciplines: [(TrainingDiscipline, Int)] = [
            (.swim, baselineMinutes.swim),
            (.bike, baselineMinutes.bike),
            (.run,  baselineMinutes.run)
        ]

        var results: [DisciplineVolumeStatus] = []
        for (disc, baseline) in disciplines {
            var totalPlanned = 0
            var totalActual  = 0
            var weeksCounted = 0
            var usedFallback = false

            for range in weekRanges {
                // Skip taper weeks: don't count for or against.
                if let pw = range.planWeek, pw.phase.lowercased().contains("taper") {
                    continue
                }

                // Planned minutes for this week.
                let plannedThisWeek: Int
                if let pw = range.planWeek {
                    plannedThisWeek = plannedMinutes(for: disc, in: pw)
                } else {
                    plannedThisWeek = baseline
                    usedFallback = true
                }

                // Actual minutes from HK in this Mon..Sun range.
                let actualThisWeek = workouts
                    .filter { $0.startDate >= range.monday && $0.startDate < range.sunday }
                    .filter { disciplineFor($0) == disc }
                    .reduce(0) { $0 + Int($1.duration / 60.0) }

                totalPlanned += plannedThisWeek
                totalActual  += actualThisWeek
                weeksCounted += 1
            }

            results.append(DisciplineVolumeStatus(
                discipline: disc,
                actualMinutes: totalActual,
                plannedMinutes: totalPlanned,
                weeksConsidered: weeksCounted,
                usedBaselineFallback: usedFallback
            ))
        }

        return results
    }

    /// Sum planned minutes of a given discipline in a TrainingWeek by parsing
    /// each workout's `duration` field (e.g. "1:30", "45 min", "2:00").
    static func plannedMinutes(for discipline: TrainingDiscipline, in week: TrainingWeek) -> Int {
        week.workouts.reduce(0) { acc, workout in
            // Map planned workout `type` string to discipline.
            let t = workout.type.lowercased()
            let matches: Bool
            switch discipline {
            case .swim:     matches = t.contains("swim")
            case .bike:     matches = t.contains("bike") || t.contains("cycl") || t.contains("brick")
            case .run:      matches = t.contains("run")  || t.contains("brick")
            case .combined: matches = true
            }
            guard matches else { return acc }
            return acc + (parseWorkoutDuration(workout.duration) ?? 0)
        }
    }

    /// Monday of the ISO week containing `date`.
    static func mondayOfISOWeek(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? date
    }

    static func computeHRSS(durationHours: Double, avgHR: Double, maxHR: Double) -> Double {
        guard durationHours > 0, maxHR > 0 else { return 0 }
        let lthr = maxHR * 0.89
        return durationHours * pow(avgHR / lthr, 2) * 100.0
    }

    static func computeEWA(dailyValues: [Double], lambda: Double) -> Double {
        guard !dailyValues.isEmpty else { return 0 }
        var ewa = 0.0
        var initialized = false
        for value in dailyValues {
            if !initialized {
                if value > 0 {
                    ewa = value
                    initialized = true
                }
            } else {
                ewa = lambda * value + (1 - lambda) * ewa
            }
        }
        return ewa
    }

    static func computeIntensityPattern(zoneTotals: [String: Double]) -> IntensityPattern {
        let total = zoneTotals.values.reduce(0, +)
        guard total > 0 else { return .insufficientData }
        let z1 = (zoneTotals["Z1"] ?? 0) / total * 100
        let z2 = (zoneTotals["Z2"] ?? 0) / total * 100
        let z3 = (zoneTotals["Z3"] ?? 0) / total * 100
        let z4 = (zoneTotals["Z4"] ?? 0) / total * 100
        let easyPct = z1 + z2
        let threshPct = z3 + z4
        if easyPct >= 78 && z3 < 10 { return .polarized }
        if threshPct > 30 { return .thresholdHeavy }
        if easyPct >= 60 { return .pyramidal }
        return .mixed
    }

    static func computeLoadSpike(currentWeekHRSS: Double, priorWeekHRSS: Double) -> LoadSpike {
        LoadSpike(currentWeekHRSS: currentWeekHRSS, priorWeekHRSS: priorWeekHRSS)
    }

    static func computeReadiness(tsb: Double, hrvTrend: HRVTrend, loadSpike: LoadSpike) -> CompositeReadiness {
        let tsbScore: Int
        switch tsb {
        case 10..<20: tsbScore = 40
        case 5..<10: tsbScore = 32
        case 20..<30: tsbScore = 30
        case 0..<5: tsbScore = 22
        case 30..<40: tsbScore = 20
        case -10..<0: tsbScore = 12
        case -20..<(-10): tsbScore = 6
        default: tsbScore = 0
        }

        let hrvScore: Int
        if let pct = hrvTrend.percentFromBaseline {
            switch pct {
            case 5...: hrvScore = 30
            case 0..<5: hrvScore = 22
            case -5..<0: hrvScore = 14
            case -10..<(-5): hrvScore = 7
            default: hrvScore = 0
            }
        } else {
            hrvScore = 15
        }

        let loadSpikeScore: Int
        if loadSpike.isCritical {
            loadSpikeScore = 0
        } else if loadSpike.isSpiked {
            loadSpikeScore = 15
        } else {
            loadSpikeScore = 30
        }

        let total = tsbScore + hrvScore + loadSpikeScore
        return CompositeReadiness(score: total, tsbScore: tsbScore, hrvScore: hrvScore, loadSpikeScore: loadSpikeScore)
    }

    // MARK: - Private helpers

    private static func buildHRVTrend(samples: [HKQuantitySample], now: Date) -> HRVTrend {
        guard !samples.isEmpty else {
            return HRVTrend(todaySDNN: nil, sevenDayAvg: nil, sixtyDayBaseline: nil)
        }
        let cal = Calendar.current
        let sdnnUnit = HKUnit.secondUnit(with: .milli)
        let todayStart = cal.startOfDay(for: now)
        let sevenAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now

        let todaySamples = samples.filter { $0.startDate >= todayStart }
        let sevenDaySamples = samples.filter { $0.startDate >= sevenAgo }

        let todaySDNN: Double? = todaySamples.isEmpty ? nil :
            todaySamples.map { $0.quantity.doubleValue(for: sdnnUnit) }.reduce(0, +) / Double(todaySamples.count)

        let sevenDayAvg: Double? = sevenDaySamples.isEmpty ? nil :
            sevenDaySamples.map { $0.quantity.doubleValue(for: sdnnUnit) }.reduce(0, +) / Double(sevenDaySamples.count)

        let baseline: Double? = samples.isEmpty ? nil :
            samples.map { $0.quantity.doubleValue(for: sdnnUnit) }.reduce(0, +) / Double(samples.count)

        return HRVTrend(todaySDNN: todaySDNN, sevenDayAvg: sevenDayAvg, sixtyDayBaseline: baseline)
    }

    private static func computeDecoupling(workout: HKWorkout, hrSamples: [HKQuantitySample], distSamples: [HKQuantitySample], discipline: TrainingDiscipline) -> DecouplingResult? {
        let midpoint = workout.startDate.addingTimeInterval(workout.duration / 2)
        let hrUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let distUnit = HKUnit.meter()

        let firstHR = hrSamples.filter { $0.startDate < midpoint }.map { $0.quantity.doubleValue(for: hrUnit) }
        let secondHR = hrSamples.filter { $0.startDate >= midpoint }.map { $0.quantity.doubleValue(for: hrUnit) }
        let firstDist = distSamples.filter { $0.startDate < midpoint }.map { $0.quantity.doubleValue(for: distUnit) }
        let secondDist = distSamples.filter { $0.startDate >= midpoint }.map { $0.quantity.doubleValue(for: distUnit) }

        guard !firstHR.isEmpty, !secondHR.isEmpty, !firstDist.isEmpty, !secondDist.isEmpty else { return nil }

        let avgHR1 = firstHR.reduce(0, +) / Double(firstHR.count)
        let avgHR2 = secondHR.reduce(0, +) / Double(secondHR.count)
        let totalDist1 = firstDist.reduce(0, +)
        let totalDist2 = secondDist.reduce(0, +)
        let halfDuration = workout.duration / 2

        guard avgHR1 > 0, avgHR2 > 0, halfDuration > 0 else { return nil }

        let ef1 = (totalDist1 / halfDuration) / avgHR1
        let ef2 = (totalDist2 / halfDuration) / avgHR2

        guard ef1 > 0 else { return nil }

        let decouplingPct = (ef1 - ef2) / ef1 * 100.0
        return DecouplingResult(
            workoutDate: workout.startDate,
            discipline: discipline,
            decouplingPercent: decouplingPct,
            durationMinutes: workout.duration / 60.0
        )
    }

    // MARK: - Cache

    private static func loadCached() -> TrainingStatus? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(TrainingStatus.self, from: data) else { return nil }
        guard Date().timeIntervalSince(cached.computedAt) < cacheTTL else { return nil }
        return cached
    }

    private static func saveCache(_ status: TrainingStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
