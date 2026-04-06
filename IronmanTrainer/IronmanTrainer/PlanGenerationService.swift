import Foundation

// MARK: - Plan Generation Input

struct PlanGenerationInput: Codable {
    var race: Race
    var profile: UserProfile
    var swimLevel: SkillLevel?
    var bikeLevel: SkillLevel?
    var runLevel: SkillLevel?
    var fitnessHours: String
    var fitnessSchedule: String
    var fitnessInjuries: String
    var fitnessEquipment: String
    var hkSummary: String? // pre-built HK summary string (not the raw profile)
    var chatSummary: String? // pre-built chat summary

    /// Storage key for saving/loading from UserDefaults
    private static let storageKey = "plan_generation_input"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> PlanGenerationInput? {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(PlanGenerationInput.self, from: data)
    }
}

// MARK: - Plan Generation Service

class PlanGenerationService {
    static let shared = PlanGenerationService()

    private let apiKey: String
    private let model = "gpt-4.1-mini"
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let maxRetries = 3

    private init() {
        self.apiKey = Secrets.openAIAPIKey
    }

    // MARK: - Public API

    func generateFullPlan(input: PlanGenerationInput) async throws -> [TrainingWeek] {
        // Pass 1: Generate summary
        let summaryJSON = try await withRetry { [self] in
            try await generatePlanSummary(input: input)
        }

        // Pass 2: Expand with details
        let detailedJSON = try await withRetry { [self] in
            try await expandPlanDetails(summary: summaryJSON, input: input)
        }

        // Parse into domain objects
        return try parsePlanJSON(detailedJSON, raceDate: input.race.date)
    }

    // MARK: - Pass 1: Summary

    private func generatePlanSummary(input: PlanGenerationInput) async throws -> String {
        let weeksUntilRace = max(1, Calendar.current.dateComponents([.weekOfYear], from: Date(), to: input.race.date).weekOfYear ?? 12)
        let startDate = Calendar.current.startOfDay(for: Date())

        let goalString: String = {
            switch input.race.userGoal {
            case .timeTarget(let t):
                let h = Int(t) / 3600
                let m = (Int(t) % 3600) / 60
                return "Finish in \(h)h \(String(format: "%02d", m))m"
            case .justComplete:
                return "Complete the race (no specific time target)"
            }
        }()

        let distancesStr = input.race.distances.map { "\($0.key): \($0.value) mi" }.joined(separator: ", ")

        let skillsStr: String = {
            var parts: [String] = []
            if let s = input.swimLevel { parts.append("Swim: \(s.rawValue)") }
            if let b = input.bikeLevel { parts.append("Bike: \(b.rawValue)") }
            if let r = input.runLevel { parts.append("Run: \(r.rawValue)") }
            return parts.isEmpty ? "Not specified" : parts.joined(separator: ", ")
        }()

        let systemPrompt = """
        You are an expert endurance coach creating a personalized training plan.

        Generate a structured training plan as a JSON array of weeks.

        RACE: \(input.race.name) on \(Formatters.fullDate.string(from: input.race.date))
        LOCATION: \(input.race.location)
        TYPE: \(input.race.type.rawValue)
        DISTANCES: \(distancesStr)
        COURSE: \(input.race.courseType)
        \(input.race.elevationGainM.map { "ELEVATION GAIN: \(Int($0))m" } ?? "")
        \(input.race.elevationAtVenueM.map { "VENUE ELEVATION: \(Int($0))m" } ?? "")
        \(input.race.historicalWeather.map { "TYPICAL WEATHER: \($0)" } ?? "")

        ATHLETE: \(input.profile.name)
        \(input.profile.biologicalSex.map { "Sex: \($0)" } ?? "")
        \(input.profile.weightKg.map { "Weight: \(String(format: "%.1f", $0)) kg" } ?? "")
        \(input.profile.restingHR.map { "Resting HR: \($0) bpm" } ?? "")
        \(input.profile.vo2Max.map { "VO2 Max: \(String(format: "%.1f", $0))" } ?? "")
        SKILL LEVELS: \(skillsStr)

        GOAL: \(goalString)
        WEEKS AVAILABLE: \(weeksUntilRace)
        PLAN START DATE: \(Formatters.fullDate.string(from: startDate))

        TRAINING CONSTRAINTS:
        - Available hours/week: \(input.fitnessHours.isEmpty ? "Not specified" : input.fitnessHours)
        - Schedule: \(input.fitnessSchedule.isEmpty ? "Not specified" : input.fitnessSchedule)
        - Injuries/limitations: \(input.fitnessInjuries.isEmpty ? "None" : input.fitnessInjuries)
        - Equipment: \(input.fitnessEquipment.isEmpty ? "Not specified" : input.fitnessEquipment)

        \(input.hkSummary.map { "RECENT TRAINING HISTORY:\n\($0)" } ?? "")

        \(PrepRacesManager.shared.contextString().map { "\($0)\nPrep race day AND the day before must be Rest days." } ?? "")

        RULES:
        - Each week has exactly 7 days (Mon-Sun)
        - Include at least 1 rest day per week
        - Workout types use emoji prefixes: "\u{1F3CA} Swim", "\u{1F6B4} Bike", "\u{1F3C3} Run", "\u{1F6B4}+\u{1F3C3} Brick", "\u{1F4AA} Strength", "Rest"
        - Duration format: "45min", "1:00", "1,600yd" (for swim), "-" for rest
        - Zone format: "Z1"-"Z5", "Z2-Z3", "-" for rest
        - Include recovery weeks every 3-4 weeks
        - Max 10% weekly volume increase
        - Phase names: "Base" (first ~30%), "Build" (next ~35%), "Peak" (next ~20%), "Taper" (last ~15%), "Race Week" (final)
        - Start dates should be Mondays, ending on Sundays

        Return ONLY a JSON array matching this schema, no other text:
        [{"weekNumber": 1, "phase": "Base", "startDate": "YYYY-MM-DD", "endDate": "YYYY-MM-DD", "workouts": [{"day": "Mon", "type": "Rest", "duration": "-", "zone": "-"}, ...7 days]}]
        """

        return try await callOpenAI(systemPrompt: systemPrompt, userMessage: "Generate my \(weeksUntilRace)-week training plan.")
    }

    // MARK: - Pass 2: Detail Expansion

    private func expandPlanDetails(summary: String, input: PlanGenerationInput) async throws -> String {
        let systemPrompt = """
        You are an expert endurance coach. You previously generated a training plan summary.
        Now add detailed notes and nutrition targets to each workout.

        For each workout in the JSON array:
        1. Add a "notes" field with specific drill sets, pacing targets, technique cues, or workout structure
        2. Add a "nutritionTarget" field for workouts >= 60 min:
           - Bike 60-75min: "60g carbs/hr: 1 gel + sport drink per 30min"
           - Bike >75min: "60-80g carbs/hr: 2 gels + 1 bottle sport drink/hr"
           - Run >=60min: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink"
           - Brick: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"
           - Swim or <60min: null
        3. For swim workouts, include warm-up, drill sets, main set, and cool-down in notes
        4. For rest days, notes and nutritionTarget should be null

        ATHLETE CONTEXT:
        - Swim skill: \(input.swimLevel?.rawValue ?? "Not specified")
        - Bike skill: \(input.bikeLevel?.rawValue ?? "Not specified")
        - Run skill: \(input.runLevel?.rawValue ?? "Not specified")
        - Equipment: \(input.fitnessEquipment.isEmpty ? "Standard" : input.fitnessEquipment)

        Return ONLY the updated JSON array with the added fields. Keep all existing fields unchanged.
        """

        return try await callOpenAI(systemPrompt: systemPrompt, userMessage: "Add detailed notes and nutrition targets to this plan:\n\(summary)")
    }

    // MARK: - OpenAI API Call

    private func callOpenAI(systemPrompt: String, userMessage: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw PlanGenerationError.missingAPIKey
        }

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "temperature": 0.7,
            "messages": messages
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw PlanGenerationError.invalidRequest
        }

        guard let url = URL(string: baseURL) else {
            throw PlanGenerationError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlanGenerationError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("[PLAN GEN] API error: HTTP \(httpResponse.statusCode) - \(errorBody)")
            }
            throw PlanGenerationError.serverError(httpResponse.statusCode)
        }

        let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = responseJSON?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PlanGenerationError.invalidResponse
        }

        return content
    }

    // MARK: - JSON Parsing

    private func parsePlanJSON(_ jsonString: String, raceDate: Date) throws -> [TrainingWeek] {
        // Strip markdown fences if present
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it doesn't start with [, try to find the array
        if !cleaned.hasPrefix("[") {
            if let start = cleaned.range(of: "["),
               let end = cleaned.range(of: "]", options: .backwards) {
                cleaned = String(cleaned[start.lowerBound...end.upperBound])
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw PlanGenerationError.parseError("Could not convert response to data")
        }

        // Decode raw structure first
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

            // Parse dates - use provided or calculate from week number
            let startDate: Date
            let endDate: Date
            if let startStr = rawWeek["startDate"] as? String,
               let parsedStart = dateFormatter.date(from: startStr) {
                startDate = parsedStart
                if let endStr = rawWeek["endDate"] as? String,
                   let parsedEnd = dateFormatter.date(from: endStr) {
                    endDate = parsedEnd
                } else {
                    endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
                }
            } else {
                // Calculate from race date working backwards
                let totalWeeks = rawWeeks.count
                let weeksBeforeRace = totalWeeks - weekNumber
                let raceWeekStart = Calendar.current.date(byAdding: .day, value: -(Calendar.current.component(.weekday, from: raceDate) - 2), to: raceDate) ?? raceDate
                startDate = Calendar.current.date(byAdding: .weekOfYear, value: -weeksBeforeRace, to: raceWeekStart) ?? Date()
                endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
            }

            var workouts: [DayWorkout] = []
            for rawWorkout in rawWorkouts {
                let day = rawWorkout["day"] as? String ?? "Mon"
                let type = rawWorkout["type"] as? String ?? "Rest"
                let duration = rawWorkout["duration"] as? String ?? "-"
                let zone = rawWorkout["zone"] as? String ?? "-"
                let notes = rawWorkout["notes"] as? String
                let nutritionTarget = rawWorkout["nutritionTarget"] as? String

                workouts.append(DayWorkout(
                    day: day,
                    type: type,
                    duration: duration,
                    zone: zone,
                    status: nil,
                    nutritionTarget: nutritionTarget,
                    notes: notes
                ))
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
        return weeks
    }

    // MARK: - Retry Logic

    private func withRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                print("[PLAN GEN] Attempt \(attempt + 1) failed: \(error.localizedDescription)")
                if attempt < maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000 // 1s, 2s, 4s
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw lastError ?? PlanGenerationError.unknownError
    }
}

// MARK: - Errors

enum PlanGenerationError: LocalizedError {
    case missingAPIKey
    case invalidRequest
    case networkError
    case serverError(Int)
    case invalidResponse
    case parseError(String)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "OpenAI API key not configured."
        case .invalidRequest: return "Failed to build API request."
        case .networkError: return "Network error. Check your connection."
        case .serverError(let code): return "Server error (HTTP \(code)). Please try again."
        case .invalidResponse: return "Invalid response from AI service."
        case .parseError(let msg): return "Failed to parse training plan: \(msg)"
        case .unknownError: return "An unexpected error occurred."
        }
    }
}
