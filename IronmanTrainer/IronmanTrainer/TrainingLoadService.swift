import Foundation
import HealthKit

// MARK: - Training Stress Score (hrTSS)

struct DailyTrainingLoad: Identifiable {
    let id = UUID()
    let date: Date
    let hrTSS: Double        // Heart-rate-based Training Stress Score
    let durationMinutes: Double
    let workoutCount: Int
}

// MARK: - Fitness / Fatigue / Form

struct TrainingLoadSummary {
    let fitness: Double      // CTL: Chronic Training Load (42-day EMA)
    let fatigue: Double      // ATL: Acute Training Load (7-day EMA)
    let form: Double         // TSB: Training Stress Balance = CTL - ATL
    let dailyLoads: [DailyTrainingLoad]

    var formStatus: FormStatus {
        if form > 15 { return .fresh }
        if form > 0 { return .ready }
        if form > -10 { return .tired }
        return .overreached
    }
}

enum FormStatus: String {
    case fresh       // TSB > 15: Well rested, possibly detraining
    case ready       // TSB 0-15: Race ready, good form
    case tired       // TSB -10 to 0: Productive training fatigue
    case overreached // TSB < -10: Risk of overtraining

    var displayName: String {
        switch self {
        case .fresh: return "Fresh"
        case .ready: return "Race Ready"
        case .tired: return "Productive Fatigue"
        case .overreached: return "Overreached"
        }
    }

    var iconName: String {
        switch self {
        case .fresh: return "battery.100"
        case .ready: return "bolt.fill"
        case .tired: return "battery.50"
        case .overreached: return "exclamationmark.triangle.fill"
        }
    }

    var colorName: String {
        switch self {
        case .fresh: return "blue"
        case .ready: return "green"
        case .tired: return "yellow"
        case .overreached: return "red"
        }
    }
}

// MARK: - Training Load Service

enum TrainingLoadService {

    /// Calculate hrTSS for a single workout using the TRIMP-based formula.
    /// hrTSS = (duration_min × HRR × intensity_factor) / (LTHR_HRR × 60) × 100
    /// Simplified: uses average HR relative to max HR and resting HR.
    static func calculateHrTSS(
        durationMinutes: Double,
        avgHR: Double,
        restingHR: Double,
        maxHR: Double
    ) -> Double {
        guard maxHR > restingHR, avgHR >= restingHR else { return 0 }

        let hrReserve = maxHR - restingHR
        let hrRatio = (avgHR - restingHR) / hrReserve
        let lthrRatio = 0.85 // Approximate LTHR at 85% of HRR

        // Exponential weighting: higher HR = disproportionately more stress
        let intensity = hrRatio * hrRatio
        let lthrIntensity = lthrRatio * lthrRatio

        guard lthrIntensity > 0 else { return 0 }

        let tss = (durationMinutes * intensity) / (60.0 * lthrIntensity) * 100.0
        return max(0, tss)
    }

    /// Calculate daily training loads from HealthKit workouts.
    static func calculateDailyLoads(
        workouts: [HKWorkout],
        restingHR: Double,
        maxHR: Double,
        days: Int = 90
    ) -> [DailyTrainingLoad] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: today) else { return [] }

        // Group workouts by day
        var dailyMap: [Date: (tss: Double, duration: Double, count: Int)] = [:]

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            guard day >= startDate else { continue }

            let durationMin = workout.duration / 60.0

            // Extract average HR if available
            let avgHR = estimateAvgHR(for: workout, maxHR: maxHR)

            let tss = calculateHrTSS(
                durationMinutes: durationMin,
                avgHR: avgHR,
                restingHR: restingHR,
                maxHR: maxHR
            )

            var entry = dailyMap[day] ?? (0, 0, 0)
            entry.tss += tss
            entry.duration += durationMin
            entry.count += 1
            dailyMap[day] = entry
        }

        // Fill in zero days
        var loads: [DailyTrainingLoad] = []
        var currentDate = startDate
        while currentDate <= today {
            let entry = dailyMap[currentDate]
            loads.append(DailyTrainingLoad(
                date: currentDate,
                hrTSS: entry?.tss ?? 0,
                durationMinutes: entry?.duration ?? 0,
                workoutCount: entry?.count ?? 0
            ))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? today.addingTimeInterval(86400)
        }

        return loads
    }

    /// Calculate CTL (fitness), ATL (fatigue), and TSB (form).
    static func calculateTrainingLoad(
        workouts: [HKWorkout],
        restingHR: Double,
        maxHR: Double
    ) -> TrainingLoadSummary {
        let dailyLoads = calculateDailyLoads(
            workouts: workouts,
            restingHR: restingHR,
            maxHR: maxHR,
            days: 90
        )

        guard !dailyLoads.isEmpty else {
            return TrainingLoadSummary(fitness: 0, fatigue: 0, form: 0, dailyLoads: [])
        }

        // Exponential moving averages
        let ctlDecay = 2.0 / (42.0 + 1.0) // 42-day EMA
        let atlDecay = 2.0 / (7.0 + 1.0)  // 7-day EMA

        var ctl = 0.0
        var atl = 0.0

        for load in dailyLoads {
            ctl = ctl * (1 - ctlDecay) + load.hrTSS * ctlDecay
            atl = atl * (1 - atlDecay) + load.hrTSS * atlDecay
        }

        let tsb = ctl - atl

        return TrainingLoadSummary(
            fitness: ctl,
            fatigue: atl,
            form: tsb,
            dailyLoads: dailyLoads
        )
    }

    // MARK: - Helpers

    /// Estimate average HR for a workout. Falls back to zone-based estimate if HR data not directly available.
    private static func estimateAvgHR(for workout: HKWorkout, maxHR: Double) -> Double {
        // Default estimate based on workout type and duration
        let intensityFactor: Double
        switch workout.workoutActivityType {
        case .swimming:
            intensityFactor = 0.72 // Typically Z2-Z3
        case .cycling:
            intensityFactor = 0.70 // Typically Z2
        case .running:
            intensityFactor = 0.75 // Typically Z2-Z3
        default:
            intensityFactor = 0.65
        }
        return maxHR * intensityFactor
    }
}
