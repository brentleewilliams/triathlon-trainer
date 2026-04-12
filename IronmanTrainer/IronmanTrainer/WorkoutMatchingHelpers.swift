import Foundation
import HealthKit

// MARK: - Standalone Workout Matching Helpers
// These pure functions encapsulate workout matching logic so it can be tested
// independently of SwiftUI views. Views may have their own copies of this logic
// for historical reasons; these canonical versions are the tested reference.

/// Parse a duration string into minutes.
/// - "60 min" -> 60, "1.5 hr" -> 90, "1:00" -> 60, "1,800yd" -> nil, "Rest" -> nil, "-" -> nil
func parseWorkoutDuration(_ durationStr: String) -> Int? {
    let lowercased = durationStr.lowercased()

    // Skip distance-based or rest days
    if lowercased.contains("yd") || lowercased.contains("rest") {
        return nil
    }

    // Handle H:MM format first (e.g., "1:00" -> 60 minutes, "1:45" -> 105 minutes)
    if let regex = try? NSRegularExpression(pattern: "^(\\d+):(\\d{2})", options: []) {
        if let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased)) {
            if let hoursRange = Range(match.range(at: 1), in: lowercased),
               let minutesRange = Range(match.range(at: 2), in: lowercased),
               let hours = Int(lowercased[hoursRange]),
               let minutes = Int(lowercased[minutesRange]) {
                return hours * 60 + minutes
            }
        }
    }

    // Handle "number min/hr" format (with or without space)
    if let regex = try? NSRegularExpression(pattern: "([\\d.]+)\\s*(min|hr)", options: []) {
        if let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased)) {
            if let numberRange = Range(match.range(at: 1), in: lowercased),
               let unitRange = Range(match.range(at: 2), in: lowercased),
               let value = Double(lowercased[numberRange]) {
                let unit = String(lowercased[unitRange])
                if unit == "hr" {
                    return Int(value * 60)
                } else if unit == "min" {
                    return Int(value)
                }
            }
        }
    }

    return nil
}

/// Extract the base workout type from a type string that may include emojis.
/// - "🚴 Bike" -> "Bike", "🏊 Swim" -> "Swim", "🏃 Run" -> "Run", "🏁 RACE DAY" -> "Run"
/// - "🏋️ Strength" -> "Strength", "🥾 Hike" -> "Hike"
func extractWorkoutTypeFromString(_ typeString: String) -> String {
    if typeString.contains("\u{1F6B4}") { return "Bike" }  // 🚴
    if typeString.contains("\u{1F3CA}") { return "Swim" }  // 🏊
    if typeString.contains("\u{1F3C3}") { return "Run" }   // 🏃
    if typeString.contains("\u{1F3C1}") { return "Run" }   // 🏁
    let lower = typeString.lowercased()
    if lower.contains("strength") { return "Strength" }
    if lower.contains("hike") || lower.contains("hiking") { return "Hike" }
    return typeString
}

/// Compute the calendar date for a workout given its day abbreviation and the week's start date.
/// - Parameters:
///   - day: Three-letter abbreviation ("Mon", "Tue", …, "Sun")
///   - weekStartDate: The Monday (or startDate) of the containing week
func dateForWorkoutDay(_ day: String, weekStartDate: Date) -> Date {
    let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    let dayIndex = dayOrder.firstIndex(of: day) ?? 0
    return Calendar.current.date(byAdding: .day, value: dayIndex, to: weekStartDate) ?? weekStartDate
}

/// Check if a planned workout type matches a HealthKit workout activity type.
func workoutTypeMatchesActivityType(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool {
    let planned = plannedType.lowercased()
    switch healthKitType {
    case .cycling:
        return planned.contains("bike") || planned.contains("cycling") || planned.contains("indoor cycling")
    case .swimming:
        return planned.contains("swim") || planned.contains("open water")
    case .running:
        return planned == "run" || planned.contains("run")
    case .walking:
        return planned == "walk" || planned.contains("walk")
    case .traditionalStrengthTraining, .functionalStrengthTraining:
        return planned.contains("strength") || planned.contains("weight")
    case .hiking:
        return planned.contains("hike") || planned.contains("hiking")
    case .rowing:
        return planned.contains("row") || planned.contains("rowing")
    case .paddleSports:
        return planned.contains("paddle") || planned.contains("kayak") || planned.contains("canoe")
    case .elliptical:
        return planned.contains("elliptical") || planned.contains("cross train") || planned.contains("crosstraining")
    case .stairClimbing:
        return planned.contains("stair") || planned.contains("step")
    case .yoga:
        return planned.contains("yoga")
    case .crossTraining:
        return planned.contains("cross") || planned.contains("crosstraining") || planned.contains("cross train")
    case .swimBikeRun:
        return planned.contains("brick") || planned.contains("race sim") || planned.contains("triathlon")
    default:
        return false
    }
}
