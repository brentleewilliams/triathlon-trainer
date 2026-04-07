import Foundation
import HealthKit

// MARK: - Weekly Volume Result

struct WeeklyVolumeResult {
    let plannedMinutes: Double
    let actualMinutes: Double
    let deviationPercent: Double
    let byDiscipline: [String: DisciplineVolume]

    var isUnderTraining: Bool { deviationPercent < -20 }
    var isOverTraining: Bool { deviationPercent > 20 }
    var isOnTrack: Bool { abs(deviationPercent) <= 20 }

    var statusMessage: String {
        let pct = Int(abs(deviationPercent))
        if isOnTrack {
            return "On track this week"
        } else if isUnderTraining {
            return "You're \(pct)% under plan this week"
        } else {
            return "You're \(pct)% over plan this week"
        }
    }

    var statusIcon: String {
        if isOnTrack { return "checkmark.circle.fill" }
        if isUnderTraining { return "arrow.down.circle.fill" }
        return "arrow.up.circle.fill"
    }

    var statusColor: String {
        if isOnTrack { return "green" }
        if abs(deviationPercent) <= 50 { return "yellow" }
        return "red"
    }
}

struct DisciplineVolume {
    let discipline: String
    let plannedMinutes: Double
    let actualMinutes: Double

    var deviationPercent: Double {
        guard plannedMinutes > 0 else { return 0 }
        return ((actualMinutes - plannedMinutes) / plannedMinutes) * 100
    }
}

// MARK: - Weekly Volume Service

enum WeeklyVolumeService {

    static func calculateWeeklyVolume(
        week: TrainingWeek,
        hkWorkouts: [HKWorkout],
        today: Date = Date()
    ) -> WeeklyVolumeResult {
        let calendar = Calendar.current
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        var totalPlannedMin = 0.0
        var totalActualMin = 0.0
        var disciplineMap: [String: (planned: Double, actual: Double)] = [
            "Swim": (0, 0),
            "Bike": (0, 0),
            "Run": (0, 0)
        ]

        for workout in week.workouts {
            guard workout.type.lowercased() != "rest" else { continue }

            let dayIndex = dayOrder.firstIndex(of: workout.day) ?? 0
            let workoutDate = calendar.date(byAdding: .day, value: dayIndex, to: week.startDate) ?? week.startDate

            // Only count days up to today (not future)
            guard calendar.startOfDay(for: workoutDate) <= calendar.startOfDay(for: today) else { continue }

            let discipline = extractDiscipline(from: workout.type)
            let plannedMin = parseWorkoutMinutes(workout.duration)
            totalPlannedMin += plannedMin

            var entry = disciplineMap[discipline] ?? (0, 0)
            entry.planned += plannedMin
            disciplineMap[discipline] = entry
        }

        // Sum actual HealthKit workouts for the week
        let weekStart = calendar.startOfDay(for: week.startDate)
        let weekEnd: Date
        if let end = calendar.date(byAdding: .day, value: 7, to: weekStart) {
            weekEnd = min(end, calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: today) ?? today))
        } else {
            weekEnd = weekStart
        }

        for hkWorkout in hkWorkouts {
            let hkDate = calendar.startOfDay(for: hkWorkout.startDate)
            guard hkDate >= weekStart && hkDate < weekEnd else { continue }

            let actualMin = hkWorkout.duration / 60.0
            totalActualMin += actualMin

            let discipline = hkDiscipline(for: hkWorkout.workoutActivityType)
            var entry = disciplineMap[discipline] ?? (0, 0)
            entry.actual += actualMin
            disciplineMap[discipline] = entry
        }

        let deviation: Double
        if totalPlannedMin > 0 {
            deviation = ((totalActualMin - totalPlannedMin) / totalPlannedMin) * 100
        } else {
            deviation = 0
        }

        let byDiscipline = disciplineMap.mapValues { entry in
            DisciplineVolume(discipline: "", plannedMinutes: entry.planned, actualMinutes: entry.actual)
        }

        return WeeklyVolumeResult(
            plannedMinutes: totalPlannedMin,
            actualMinutes: totalActualMin,
            deviationPercent: deviation,
            byDiscipline: byDiscipline
        )
    }

    // MARK: - Helpers

    private static func extractDiscipline(from type: String) -> String {
        let lower = type.lowercased()
        if lower.contains("swim") || lower.contains("\u{1F3CA}") { return "Swim" }
        if lower.contains("bike") || lower.contains("cycling") || lower.contains("\u{1F6B4}") { return "Bike" }
        if lower.contains("run") || lower.contains("\u{1F3C3}") || lower.contains("\u{1F3C1}") { return "Run" }
        if lower.contains("brick") || lower.contains("race sim") { return "Bike" } // Bricks counted under bike
        return "Other"
    }

    private static func hkDiscipline(for activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .swimming: return "Swim"
        case .cycling: return "Bike"
        case .running: return "Run"
        default: return "Other"
        }
    }

    private static func parseWorkoutMinutes(_ duration: String) -> Double {
        let lowercased = duration.lowercased()

        // Skip yard-based (swim distance)
        if lowercased.contains("yd") {
            // Estimate swim time from yards: ~2 min per 100 yards
            let cleaned = lowercased
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "yd", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let yards = Double(cleaned) {
                return yards / 50.0 // ~50 yards per minute
            }
            return 30 // fallback
        }

        // H:MM format
        if let regex = try? NSRegularExpression(pattern: "^(\\d+):(\\d{2})", options: []) {
            if let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)) {
                if let hRange = Range(match.range(at: 1), in: lowercased),
                   let mRange = Range(match.range(at: 2), in: lowercased),
                   let h = Int(lowercased[hRange]),
                   let m = Int(lowercased[mRange]) {
                    return Double(h * 60 + m)
                }
            }
        }

        // "X min" format
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*min", options: []) {
            if let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               let range = Range(match.range(at: 1), in: lowercased),
               let minutes = Int(lowercased[range]) {
                return Double(minutes)
            }
        }

        // "X.X hrs" or "X hrs" format
        if let regex = try? NSRegularExpression(pattern: "([\\d.]+)\\s*hr", options: []) {
            if let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               let range = Range(match.range(at: 1), in: lowercased),
               let hours = Double(lowercased[range]) {
                return hours * 60
            }
        }

        return 0
    }
}
