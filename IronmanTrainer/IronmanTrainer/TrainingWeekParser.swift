import Foundation

// MARK: - Training Week Parser
//
// Shared JSON-parsing logic extracted from LLMProxyService and PlanGenerationService.
// Both services previously contained near-identical private parsePlanJSON implementations.
// Any future plan-parsing changes should be made here only.

enum TrainingWeekParser {

    // MARK: - Public API

    /// Parse a JSON string (or markdown-fenced JSON string) into `[TrainingWeek]`.
    ///
    /// - Parameters:
    ///   - jsonString: Raw LLM output. May be wrapped in ` ```json ``` ` fences.
    ///   - raceDate: Used as the anchor when a week is missing explicit `startDate` /
    ///               `endDate` fields. Pass `nil` to anchor to today (suitable for
    ///               batch generation where the absolute race date is unknown at
    ///               parse time).
    /// - Returns: Sorted, Monday-anchored `[TrainingWeek]`.
    static func parse(_ jsonString: String, raceDate: Date? = nil) throws -> [TrainingWeek] {
        let cleaned = stripAndExtractJSONArray(from: jsonString)

        guard let data = cleaned.data(using: .utf8) else {
            throw PlanGenerationError.parseError("Could not convert response to data")
        }

        let rawWeeks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        guard let rawWeeks else {
            throw PlanGenerationError.parseError("Response is not a JSON array of weeks")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var weeks: [TrainingWeek] = []

        for rawWeek in rawWeeks {
            guard let weekNumber = rawWeek["weekNumber"] as? Int,
                  let phase = rawWeek["phase"] as? String,
                  let rawWorkouts = rawWeek["workouts"] as? [[String: Any]] else {
                continue
            }

            let (startDate, endDate) = parseDates(
                rawWeek: rawWeek,
                weekNumber: weekNumber,
                totalWeeks: rawWeeks.count,
                raceDate: raceDate,
                formatter: dateFormatter
            )

            var workouts = parseWorkouts(rawWorkouts)

            // Post-process: if all workouts landed on the same day (AI failure
            // mode), redistribute them Mon–Sun in order.
            let uniqueDays = Set(workouts.map { $0.day })
            if uniqueDays.count == 1 && workouts.count >= 5 {
                let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                workouts = workouts.enumerated().map { (i, w) in
                    DayWorkout(
                        day: dayOrder[min(i, 6)],
                        type: w.type,
                        duration: w.duration,
                        zone: w.zone,
                        status: w.status,
                        nutritionTarget: w.nutritionTarget,
                        notes: w.notes
                    )
                }
            }

            weeks.append(TrainingWeek(
                weekNumber: weekNumber,
                phase: phase,
                startDate: startDate,
                endDate: endDate,
                workouts: workouts
            ))
        }

        guard !weeks.isEmpty else {
            throw PlanGenerationError.parseError("No valid weeks parsed from response")
        }

        weeks.sort { $0.weekNumber < $1.weekNumber }

        // Snap each week to its own Mon–Sun. Do NOT re-anchor here — this
        // function may be called once per batch (e.g. weeks 1–5, 6–10, 11–14)
        // and re-anchoring would collapse every batch onto the same Monday.
        // Final re-anchoring to the onboarding week happens in
        // TrainingPlanManager when the full plan is loaded.
        return TrainingWeek.snapToMondaySunday(weeks)
    }

    /// Convenience overload that accepts `Data` (used by `LLMProxyService`).
    static func parse(_ data: Data, raceDate: Date? = nil) throws -> [TrainingWeek] {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw PlanGenerationError.parseError("Could not decode response as UTF-8")
        }
        return try parse(jsonString, raceDate: raceDate)
    }

    // MARK: - Private Helpers

    private static func stripAndExtractJSONArray(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the result doesn't start with '[', try to find the array
        if !cleaned.hasPrefix("[") {
            if let start = cleaned.range(of: "["),
               let end = cleaned.range(of: "]", options: .backwards) {
                cleaned = String(cleaned[start.lowerBound...end.upperBound])
            }
        }

        return cleaned
    }

    private static func parseDates(
        rawWeek: [String: Any],
        weekNumber: Int,
        totalWeeks: Int,
        raceDate: Date?,
        formatter: DateFormatter
    ) -> (startDate: Date, endDate: Date) {
        if let startStr = rawWeek["startDate"] as? String,
           let parsedStart = formatter.date(from: startStr) {
            let startDate = parsedStart
            let endDate: Date
            if let endStr = rawWeek["endDate"] as? String,
               let parsedEnd = formatter.date(from: endStr) {
                endDate = parsedEnd
            } else {
                endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
            }
            return (startDate, endDate)
        }

        // Fallback: calculate from the race date (or today for batch generation)
        let anchor = raceDate ?? Date()
        let weeksBeforeRace = totalWeeks - weekNumber
        let raceWeekStart = Calendar.current.date(
            byAdding: .day,
            value: -(Calendar.current.component(.weekday, from: anchor) - 2),
            to: anchor
        ) ?? anchor
        let startDate = Calendar.current.date(
            byAdding: .weekOfYear,
            value: -weeksBeforeRace,
            to: raceWeekStart
        ) ?? Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
        return (startDate, endDate)
    }

    private static func parseWorkouts(_ rawWorkouts: [[String: Any]]) -> [DayWorkout] {
        rawWorkouts.map { raw in
            DayWorkout(
                day: raw["day"] as? String ?? "Mon",
                type: raw["type"] as? String ?? "Rest",
                duration: raw["duration"] as? String ?? "-",
                zone: raw["zone"] as? String ?? "-",
                status: nil,
                nutritionTarget: raw["nutritionTarget"] as? String,
                notes: raw["notes"] as? String
            )
        }
    }
}
