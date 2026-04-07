import Foundation
import FirebaseAuth

// MARK: - Template Params

struct TemplateParams: Codable {
    var raceCategory: String
    var raceSubtype: String
    var goalTier: String
    var customGoalText: String?
    var schedulePattern: String
    var includeStrength: Bool
}

// MARK: - Template Plan Result

struct TemplatePlanResult {
    var weeks: [TrainingWeek]
    var method: String
    var warnings: [String]
}

// MARK: - LLM Proxy Service

/// Routes all LLM requests through the Firebase Cloud Function proxy.
/// Replaces direct OpenAI/Anthropic calls — the proxy handles model selection,
/// API keys, and server-side prompt injection protection.
class LLMProxyService {
    static let shared = LLMProxyService()

    private let baseURL = "https://us-central1-brents-trainer.cloudfunctions.net"
    private var proxyURL: URL { URL(string: "\(baseURL)/llmProxy")! }

    private init() {}

    // MARK: - 1. Coaching Chat (Streaming)

    /// Sends a coaching message and returns the full accumulated response.
    func sendCoachingMessage(
        userMessage: String,
        trainingContext: String,
        workoutHistory: String,
        zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)? = nil,
        conversationHistory: [[String: Any]] = [],
        imageData: Data? = nil
    ) async throws -> String {
        return try await streamCoachingMessage(
            userMessage: userMessage,
            trainingContext: trainingContext,
            workoutHistory: workoutHistory,
            zoneBoundaries: zoneBoundaries,
            conversationHistory: conversationHistory,
            imageData: imageData,
            onToken: { _ in }
        )
    }

    /// Streams a coaching message, calling `onToken` for each incremental token.
    /// Returns the full accumulated response when complete.
    func streamCoachingMessage(
        userMessage: String,
        trainingContext: String,
        workoutHistory: String,
        zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)? = nil,
        conversationHistory: [[String: Any]] = [],
        imageData: Data? = nil,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        var body: [String: Any] = [
            "type": "coaching",
            "userMessage": userMessage,
            "trainingContext": trainingContext,
            "workoutHistory": workoutHistory,
            "conversationHistory": conversationHistory
        ]

        if let zones = zoneBoundaries {
            body["zoneBoundaries"] = [
                "z2": zones.z2,
                "z3": zones.z3,
                "z4": zones.z4,
                "z5": zones.z5
            ]
        }

        if let imageData = imageData {
            body["imageData"] = imageData.base64EncodedString()
        }

        let request = try await buildRequest(body: body, timeout: 120)

        // Use streaming via URLSession.bytes
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validateHTTPResponse(response)

        var accumulated = ""
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let raw = String(line.dropFirst(6))
                if raw == "[DONE]" { break }
                // Server JSON-encodes each token chunk — decode it
                if let data = raw.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(String.self, from: data) {
                    accumulated += decoded
                    onToken(decoded)
                } else {
                    // Fallback: use raw value
                    accumulated += raw
                    onToken(raw)
                }
            }
        }

        return accumulated
    }

    // MARK: - 2. Race Search (Onboarding)

    func searchRace(query: String) async throws -> RaceSearchResult {
        let sanitized = sanitizeQuery(query)

        let body: [String: Any] = [
            "type": "raceSearch",
            "query": sanitized
        ]

        let data = try await performRequest(body: body, timeout: 30)

        // Proxy returns { result: "<json string>" } — extract the inner result
        let resultString = try extractResultString(from: data)
        guard let resultData = resultString.data(using: .utf8) else {
            throw ClaudeServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateStr) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateStr)"
            )
        }

        return try decoder.decode(RaceSearchResult.self, from: resultData)
    }

    // MARK: - 3. Prep Race Search

    func searchPrepRace(query: String) async throws -> PrepRaceSearchResult {
        let sanitized = sanitizeQuery(query)

        let body: [String: Any] = [
            "type": "prepRaceSearch",
            "query": sanitized
        ]

        let responseData = try await performRequest(body: body, timeout: 15)

        // Proxy returns { result: "<json string>" } — extract the inner result
        let resultString = try extractResultString(from: responseData)
        guard let resultData = resultString.data(using: .utf8) else {
            throw ClaudeServiceError.invalidResponse
        }

        struct RawResult: Decodable {
            let name: String
            let date: String
            let distance: String
        }

        let raw = try JSONDecoder().decode(RawResult.self, from: resultData)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: raw.date) else {
            throw ClaudeServiceError.invalidResponse
        }

        return PrepRaceSearchResult(name: raw.name, date: date, distance: raw.distance)
    }

    // MARK: - 4. Plan Generation

    func generatePlan(input: PlanGenerationInput) async throws -> [TrainingWeek] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let inputData = try encoder.encode(input)
        guard let inputDict = try JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
            throw ClaudeServiceError.invalidRequest
        }

        let body: [String: Any] = [
            "type": "planGeneration",
            "input": inputDict
        ]

        // Plan generation can take a while (two LLM passes on the server)
        let data = try await performRequest(body: body, timeout: 300)

        // Proxy returns { result: ... } — result may be a JSON object/array or a string
        let planData = try extractResultData(from: data)
        return try parsePlanJSON(planData)
    }

    // MARK: - 5. Plan Generation (Batch)

    func generatePlanBatch(input: PlanGenerationInput, weekStart: Int, weekEnd: Int, totalWeeks: Int) async throws -> [TrainingWeek] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let inputData = try encoder.encode(input)
        guard let inputDict = try JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
            throw ClaudeServiceError.invalidRequest
        }

        let body: [String: Any] = [
            "type": "planGenerationBatch",
            "input": inputDict,
            "weekStart": weekStart,
            "weekEnd": weekEnd,
            "totalWeeks": totalWeeks
        ]

        let data = try await performRequest(body: body, timeout: 180)
        let planData = try extractResultData(from: data)
        return try parsePlanJSON(planData)
    }

    // MARK: - 6. Plan Generation (Template-Based)

    func generatePlanFromTemplate(input: PlanGenerationInput, templateParams: TemplateParams) async throws -> TemplatePlanResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let inputData = try encoder.encode(input)
        guard let inputDict = try JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
            throw ClaudeServiceError.invalidRequest
        }

        let paramsData = try encoder.encode(templateParams)
        guard let paramsDict = try JSONSerialization.jsonObject(with: paramsData) as? [String: Any] else {
            throw ClaudeServiceError.invalidRequest
        }

        let body: [String: Any] = [
            "type": "planFromTemplate",
            "input": inputDict,
            "templateParams": paramsDict
        ]

        let data = try await performRequest(body: body, timeout: 120)

        // Parse outer response for result, method, and warnings
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeServiceError.invalidResponse
        }

        let method = json["method"] as? String ?? "unknown"
        let warnings = json["warnings"] as? [String] ?? []

        // Extract result and parse into TrainingWeeks
        let planData = try extractResultData(from: data)
        let weeks = try parsePlanJSON(planData)

        return TemplatePlanResult(weeks: weeks, method: method, warnings: warnings)
    }

    // MARK: - Request Infrastructure

    private func buildRequest(body: [String: Any], timeout: TimeInterval) async throws -> URLRequest {
        let token = try await getFirebaseIDToken()

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw ClaudeServiceError.invalidRequest
        }

        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        request.httpBody = jsonData
        return request
    }

    /// Performs a non-streaming request and returns the response body as Data.
    private func performRequest(body: [String: Any], timeout: TimeInterval) async throws -> Data {
        let request = try await buildRequest(body: body, timeout: timeout)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)
        return data
    }

    // MARK: - Auth

    private func getFirebaseIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw ClaudeServiceError.invalidAPIKey
        }
        return try await user.getIDToken()
    }

    // MARK: - Response Validation

    private func validateHTTPResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeServiceError.networkError
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw ClaudeServiceError.invalidAPIKey
        case 429:
            throw ClaudeServiceError.rateLimitExceeded
        default:
            if let data = data, let errorBody = String(data: data, encoding: .utf8) {
                print("[LLM PROXY] Error HTTP \(httpResponse.statusCode): \(errorBody)")
            }
            throw ClaudeServiceError.serverError
        }
    }

    // MARK: - Proxy Response Parsing

    /// Extracts the `result` field from the proxy response as a String.
    /// The proxy returns `{ "result": "<LLM output string>" }`.
    private func extractResultString(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeServiceError.invalidResponse
        }
        if let result = json["result"] as? String {
            return stripMarkdownFences(result)
        }
        // If result is already a JSON object/array, serialize it back to string
        if let result = json["result"] {
            let resultData = try JSONSerialization.data(withJSONObject: result)
            return String(data: resultData, encoding: .utf8) ?? ""
        }
        throw ClaudeServiceError.invalidResponse
    }

    /// Strips markdown code fences (```json ... ```) that LLMs sometimes wrap around JSON.
    private func stripMarkdownFences(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts the `result` field from the proxy response as Data (for JSON object/array results).
    private func extractResultData(from data: Data) throws -> Data {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] else {
            throw ClaudeServiceError.invalidResponse
        }
        // If result is already a parsed JSON object/array, re-serialize
        if let resultObj = result as? [[String: Any]] {
            return try JSONSerialization.data(withJSONObject: resultObj)
        }
        if let resultObj = result as? [String: Any] {
            return try JSONSerialization.data(withJSONObject: resultObj)
        }
        // If result is a string (raw JSON text), return as data
        if let resultStr = result as? String, let strData = resultStr.data(using: .utf8) {
            return strData
        }
        throw ClaudeServiceError.invalidResponse
    }

    // MARK: - Input Sanitization (defense in depth)

    private func sanitizeQuery(_ query: String) -> String {
        String(query
            .unicodeScalars
            .filter { $0.properties.isPatternWhitespace || (!$0.properties.isNoncharacterCodePoint && $0.value >= 0x20) }
            .prefix(200)
            .map { Character($0) })
    }

    // MARK: - Plan JSON Parsing

    /// Parses the plan JSON returned by the proxy into `[TrainingWeek]`.
    /// Adapted from `PlanGenerationService.parsePlanJSON`.
    private func parsePlanJSON(_ data: Data) throws -> [TrainingWeek] {
        // The proxy may return raw JSON or wrap it — handle both
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw PlanGenerationError.parseError("Could not decode response as UTF-8")
        }

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

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw PlanGenerationError.parseError("Could not convert response to data")
        }

        let rawWeeks = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
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

            // Parse dates
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
                // Calculate from week number working backwards
                let totalWeeks = rawWeeks.count
                let weeksBeforeRace = totalWeeks - weekNumber
                let raceWeekStart = Calendar.current.date(byAdding: .day, value: -(Calendar.current.component(.weekday, from: Date()) - 2), to: Date()) ?? Date()
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
}
