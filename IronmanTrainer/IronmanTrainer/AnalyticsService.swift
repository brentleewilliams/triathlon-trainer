import Foundation

// TODO: Add FirebaseAnalytics product to the existing firebase-ios-sdk SPM dependency,
//       then replace the print fallback with: Analytics.logEvent(name, parameters: params)

/// Typed analytics events for plan generation tracking.
/// Uses Firebase Analytics when available, falls back to console logging.
enum PlanAnalytics {

    static func planGenerationStarted(
        method: String,
        raceCategory: String,
        raceSubtype: String,
        goalTier: String,
        schedulePattern: String,
        weeksAvailable: Int,
        includeStrength: Bool
    ) {
        logEvent("plan_generation_started", params: [
            "method": method,
            "race_category": raceCategory,
            "race_subtype": raceSubtype,
            "goal_tier": goalTier,
            "schedule_pattern": schedulePattern,
            "weeks_available": weeksAvailable,
            "include_strength": includeStrength
        ])
    }

    static func planGenerationCompleted(
        method: String,
        raceCategory: String,
        raceSubtype: String,
        goalTier: String,
        durationSeconds: Double,
        weeksGenerated: Int
    ) {
        logEvent("plan_generation_completed", params: [
            "method": method,
            "race_category": raceCategory,
            "race_subtype": raceSubtype,
            "goal_tier": goalTier,
            "duration_seconds": durationSeconds,
            "weeks_generated": weeksGenerated
        ])
    }

    static func planGenerationFailed(
        method: String,
        raceCategory: String,
        goalTier: String,
        errorType: String,
        fallbackTriggered: Bool
    ) {
        logEvent("plan_generation_failed", params: [
            "method": method,
            "race_category": raceCategory,
            "goal_tier": goalTier,
            "error_type": errorType,
            "fallback_triggered": fallbackTriggered
        ])
    }

    static func goalClassified(
        inputTier: String,
        outputTier: String,
        raceCategory: String,
        raceSubtype: String
    ) {
        logEvent("goal_classified", params: [
            "input_tier": inputTier,
            "output_tier": outputTier,
            "race_category": raceCategory,
            "race_subtype": raceSubtype
        ])
    }

    static func schedulePatternSelected(pattern: String, raceCategory: String) {
        logEvent("schedule_pattern_selected", params: [
            "pattern": pattern,
            "race_category": raceCategory
        ])
    }

    static func planApproved(method: String, raceCategory: String, goalTier: String, weeksCount: Int) {
        logEvent("plan_approved", params: [
            "method": method,
            "race_category": raceCategory,
            "goal_tier": goalTier,
            "weeks_count": weeksCount
        ])
    }

    static func planFallbackTriggered(reason: String, raceTypeRaw: String) {
        logEvent("plan_fallback_triggered", params: [
            "reason": reason,
            "race_type_raw": raceTypeRaw
        ])
    }

    // MARK: - Private

    private static func logEvent(_ name: String, params: [String: Any]) {
        // TODO: Once FirebaseAnalytics SPM product is added, replace with:
        //   Analytics.logEvent(name, parameters: params)
        print("[Analytics] \(name): \(params)")
    }
}
