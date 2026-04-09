import Foundation

// MARK: - Analytics
//
// Firebase Analytics is not yet linked to this target due to binary dependency
// resolution issues with the SPM build. All calls fall back to console logging.
// To wire it up properly later:
//   1. In Xcode target > General > Frameworks, add FirebaseAnalytics
//   2. Also add FirebaseInstallations and GoogleAppMeasurement (required transitive deps)
//   3. Replace the print() calls below with Analytics.logEvent / Analytics.setUserID

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

    static func setUser(id: String) {
        // No-op until FirebaseAnalytics is properly linked
        print("[Analytics] setUser: \(id)")
    }

    // MARK: - Private

    private static func logEvent(_ name: String, params: [String: Any]) {
        print("[Analytics] \(name): \(params)")
    }
}
