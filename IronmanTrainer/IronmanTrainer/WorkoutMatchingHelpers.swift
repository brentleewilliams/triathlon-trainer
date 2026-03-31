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
func extractWorkoutTypeFromString(_ typeString: String) -> String {
    if typeString.contains("\u{1F6B4}") { return "Bike" }  // 🚴
    if typeString.contains("\u{1F3CA}") { return "Swim" }  // 🏊
    if typeString.contains("\u{1F3C3}") { return "Run" }   // 🏃
    if typeString.contains("\u{1F3C1}") { return "Run" }   // 🏁
    return typeString
}

/// Check if a planned workout type matches a HealthKit workout activity type.
func workoutTypeMatchesActivityType(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool {
    let planned = plannedType.lowercased()
    switch healthKitType {
    case .cycling:
        return planned == "bike"
    case .swimming:
        return planned == "swim"
    case .running:
        return planned == "run"
    case .walking:
        return planned == "walk"
    default:
        return false
    }
}
