import Foundation
import HealthKit
import SwiftUI

private func mondayOfWeek(_ date: Date, calendar: Calendar = .current) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return cal.date(from: comps) ?? date
}

// MARK: - Compliance Model

enum ComplianceLevel {
    case green       // Within 20% of plan
    case over        // Overtraining: did significantly more than planned
    case under       // Undertraining: did the workout but significantly less
    case missed      // No matching workout type found at all
    case future      // Not yet evaluable

    var iconName: String {
        switch self {
        case .green: return "checkmark.circle.fill"
        case .over: return "arrow.up.circle.fill"
        case .under: return "arrow.down.circle.fill"
        case .missed: return "xmark.circle.fill"
        case .future: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .green: return .green
        case .over: return .yellow
        case .under: return .yellow
        case .missed: return .red
        case .future: return .gray
        }
    }
}

struct ComplianceResult {
    let level: ComplianceLevel
    let matchedWorkout: HKWorkout?
    let actualDurationMinutes: Double?
    let plannedDurationMinutes: Double?
    let deviationPercent: Double?
}

// MARK: - Pure Threshold Function (testable without HKWorkout)

/// Determines compliance level from actual vs planned values.
/// - Parameters:
///   - actual: The actual value (duration in minutes or distance in yards)
///   - planned: The planned value
/// - Returns: green if within 20%, yellow if overtraining (>20% over), red if undertraining (>20% under)
func complianceLevelFromValues(actual: Double, planned: Double) -> ComplianceLevel {
    guard planned > 0 else { return .green }
    let ratio = actual / planned
    if ratio >= 0.80 && ratio <= 1.20 { return .green }
    if ratio > 1.20 { return .over }   // Overtraining
    return .under                       // Undertraining
}

/// Legacy deviation-based function (kept for compatibility)
func complianceLevelFromDeviation(_ deviation: Double) -> ComplianceLevel {
    if deviation <= 0.20 { return .green }
    return .over  // Can't determine direction from absolute deviation alone
}

// MARK: - Yard Distance Parser

/// Parse "1,800yd" -> 1800.0, "2,000yd" -> 2000.0. Returns nil for non-yard formats.
func parseYardDistance(_ durationStr: String) -> Double? {
    let lowercased = durationStr.lowercased()
    guard lowercased.contains("yd") else { return nil }
    // Remove commas and "yd"
    let cleaned = lowercased
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: "yd", with: "")
        .trimmingCharacters(in: .whitespaces)
    return Double(cleaned)
}

// MARK: - Per-Workout Compliance

/// Find the best matching HKWorkout for a planned workout and compute compliance.
func calculateCompliance(
    for planned: DayWorkout,
    on targetDate: Date,
    from hkWorkouts: [HKWorkout],
    today: Date = Date()
) -> ComplianceResult {
    let calendar = Calendar.current

    // Future day: no evaluation
    if calendar.startOfDay(for: targetDate) > calendar.startOfDay(for: today) {
        return ComplianceResult(level: .future, matchedWorkout: nil, actualDurationMinutes: nil, plannedDurationMinutes: nil, deviationPercent: nil)
    }

    // Rest days: not evaluated for compliance
    if planned.type.lowercased() == "rest" {
        return ComplianceResult(level: .future, matchedWorkout: nil, actualDurationMinutes: nil, plannedDurationMinutes: nil, deviationPercent: nil)
    }

    // Extract workout type and find matching HK workout on same day
    let workoutType = extractWorkoutTypeFromString(planned.type)
    let dayStart = calendar.startOfDay(for: targetDate)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

    let matched = hkWorkouts.first { hkWorkout in
        let hkDay = calendar.startOfDay(for: hkWorkout.startDate)
        return hkDay >= dayStart && hkDay < dayEnd
            && workoutTypeMatchesActivityType(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType)
    }

    guard let matchedWorkout = matched else {
        // Today with no workout yet: show as future (not red)
        if calendar.isDateInToday(targetDate) {
            return ComplianceResult(level: .future, matchedWorkout: nil, actualDurationMinutes: nil, plannedDurationMinutes: nil, deviationPercent: nil)
        }
        // Past day, no match: missed entirely
        return ComplianceResult(level: .missed, matchedWorkout: nil, actualDurationMinutes: nil, plannedDurationMinutes: nil, deviationPercent: nil)
    }

    let actualMinutes = matchedWorkout.duration / 60.0

    // Distance-based workout (e.g., swim yards)
    if let plannedYards = parseYardDistance(planned.duration) {
        if let actualDistance = matchedWorkout.totalDistance {
            let actualYards = actualDistance.doubleValue(for: .yard())
            let deviation = plannedYards > 0 ? abs(actualYards - plannedYards) / plannedYards : 0
            return ComplianceResult(
                level: complianceLevelFromValues(actual: actualYards, planned: plannedYards),
                matchedWorkout: matchedWorkout,
                actualDurationMinutes: actualMinutes,
                plannedDurationMinutes: nil,
                deviationPercent: deviation
            )
        }
        // No distance data: type-matched = green
        return ComplianceResult(level: .green, matchedWorkout: matchedWorkout, actualDurationMinutes: actualMinutes, plannedDurationMinutes: nil, deviationPercent: nil)
    }

    // Time-based workout
    if let plannedMinutes = parseWorkoutDuration(planned.duration) {
        let plannedDouble = Double(plannedMinutes)
        let deviation = plannedDouble > 0 ? abs(actualMinutes - plannedDouble) / plannedDouble : 0
        return ComplianceResult(
            level: complianceLevelFromValues(actual: actualMinutes, planned: plannedDouble),
            matchedWorkout: matchedWorkout,
            actualDurationMinutes: actualMinutes,
            plannedDurationMinutes: plannedDouble,
            deviationPercent: deviation
        )
    }

    // Cannot parse duration: type-matched = green
    return ComplianceResult(level: .green, matchedWorkout: matchedWorkout, actualDurationMinutes: actualMinutes, plannedDurationMinutes: nil, deviationPercent: nil)
}

// MARK: - Weekly Compliance (Duration-Weighted)

/// Calculate weekly compliance as a duration-weighted percentage. Returns nil if no workouts are evaluable yet.
func calculateWeekCompliance(
    week: TrainingWeek,
    hkWorkouts: [HKWorkout],
    today: Date = Date()
) -> Double? {
    let calendar = Calendar.current
    let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var totalPlannedMinutes = 0.0
    var totalActualMinutes = 0.0
    var hasEvaluableWorkout = false

    for workout in week.workouts {
        guard workout.type.lowercased() != "rest" else { continue }

        let dayIndex = dayOrder.firstIndex(of: workout.day) ?? 0
        let weekMonday = mondayOfWeek(week.startDate, calendar: calendar)
        let workoutDate = calendar.date(byAdding: .day, value: dayIndex, to: weekMonday) ?? week.startDate

        // Skip future days
        guard calendar.startOfDay(for: workoutDate) <= calendar.startOfDay(for: today) else { continue }
        // Skip today (not yet complete)
        guard !calendar.isDateInToday(workoutDate) else { continue }

        let compliance = calculateCompliance(for: workout, on: workoutDate, from: hkWorkouts, today: today)

        // Determine planned minutes for weighting
        let plannedMin: Double
        if let pm = compliance.plannedDurationMinutes {
            plannedMin = pm
        } else if let yards = parseYardDistance(workout.duration) {
            // Convert yards to estimated minutes (approx 30 yd/min)
            plannedMin = yards / 30.0
        } else {
            continue // Cannot weight this workout
        }

        totalPlannedMinutes += plannedMin
        if let actualMin = compliance.actualDurationMinutes {
            totalActualMinutes += min(actualMin, plannedMin * 1.5) // Cap at 150% to avoid skew
        }
        hasEvaluableWorkout = true
    }

    guard hasEvaluableWorkout, totalPlannedMinutes > 0 else { return nil }
    return min(100.0, (totalActualMinutes / totalPlannedMinutes) * 100.0)
}
