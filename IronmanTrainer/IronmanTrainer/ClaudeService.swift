import Foundation
import os.Logger

class ClaudeService: NSObject, ObservableObject {
    static let shared = ClaudeService()

    private let apiKey: String
    private let model = "claude-3-5-sonnet-20241022"
    private let baseURL = "https://api.anthropic.com/v1/messages"

    private let logger = Logger(subsystem: "com.ironmantrainer", category: "ClaudeService")

    override init() {
        // Load API key from environment variables (set via Config.xcconfig)
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            self.apiKey = key
        } else {
            self.apiKey = ""
            logger.error("ANTHROPIC_API_KEY not found in environment. Set it in Config.xcconfig")
        }
        super.init()
    }

    func sendMessage(userMessage: String, trainingContext: String, workoutHistory: String) async throws -> String {
        let systemPrompt = buildSystemPrompt(context: trainingContext, history: workoutHistory)

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": userMessage
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw ClaudeServiceError.invalidRequest
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeServiceError.networkError
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let responseBody = try decoder.decode(ClaudeResponse.self, from: data)
            if let content = responseBody.content.first?.text {
                return content
            }
            throw ClaudeServiceError.invalidResponse
        case 401:
            logger.error("Invalid API key")
            throw ClaudeServiceError.invalidAPIKey
        case 429:
            logger.error("Rate limited")
            throw ClaudeServiceError.rateLimitExceeded
        default:
            logger.error("HTTP \(httpResponse.statusCode)")
            throw ClaudeServiceError.serverError
        }
    }

    private func buildSystemPrompt(context: String, history: String) -> String {
        """
        You are a personal triathlon coaching assistant for Brent, training for Ironman 70.3 Oregon (Jul 19, 2026, Salem OR).

        TRAINING PLAN CONTEXT:
        - 17-week program (Mar 23 - Jul 19, 2026)
        - 5 phases: Volume Rebalance → Build 1 → Build 2/Race Specificity → Peak & Sharpen → Taper & Race
        - Current phase and weekly volume adjusts throughout plan

        ATHLETE PROFILE:
        - VO2 Max: 57.8 mL/kg/min (Mar 2026)
        - Resting HR: ~61 bpm | Max HR: 180 bpm
        - Swim (pool): 2:10/100yd | OWS: 2:24/100yd
        - Bike (no power): 16.8 mph avg (Boise race), trainer + outdoor
        - Run (Denver): Easy 9:00/mi, 10K 8:15/mi

        TRAINING ZONES (HR-based):
        - Z1: <126 bpm (recovery)
        - Z2: 126-144 bpm (easy, long rides/runs)
        - Z3: 144-155 bpm (tempo, race-pace)
        - Z4: 155-167 bpm (hard intervals, bike)
        - Z5: 167-180 bpm (all-out sprints, swim only)

        RACE TARGETS FOR OREGON:
        - Swim: 38-42:00 (benefiting from downstream current)
        - Bike: 3:00-3:10 (pacing Z3-4, steady HR 135-145)
        - Run: 1:55-2:02 (Mi 1-2: 9:00-9:15 | Mi 3-9: 8:45-9:00 | Mi 10+: 8:15-8:30)
        - Total: Sub-6:00 race finish

        NUTRITION PROTOCOL:
        - Gut training progression: 50-100g carbs/hr by race week
        - Bike: 80-100g carbs/hr via bottles + gels. Salt cap every 20min.
        - Run: Gel every 30min, water every station, salt every 30min
        - NO protein bars during racing (slows digestion, zero energy)
        - Pure carbs only: gels, sports drink, maltodextrin/fructose

        KEY LESSON FROM BOISE 70.3 (Jul 2025):
        - Finished 6:49:48, walked final miles due to severe underfueling (~150g carbs over 7hrs)
        - Heat collapse at 93°F triggered by low glycogen → loss of thermoregulation
        - Needed 400-500g carbs but only had ~150g
        - Oregon is cooler (78-85°F) = massive advantage
        - Proper nutrition + Denver altitude advantage = sub-6 is achievable

        RECENT WORKOUT HISTORY (Last 4 Weeks):
        {history}

        THIS WEEK'S TRAINING PLAN:
        {context}

        COACHING APPROACH:
        1. Reference the training plan and specific phase details
        2. Use Brent's metrics (zones, pacing) in your advice
        3. Explain the WHY behind training decisions
        4. Provide specific nutrition/fueling guidance based on race analysis
        5. Be concise but detailed
        6. Focus on preparation for Oregon's cooler climate and shaded run course

        When answering:
        - Be specific to Brent's plan, zones, and targets
        - Connect to Boise 70.3 lessons (especially fueling)
        - Emphasize Oregon's advantages: cooler, shaded run, downstream swim
        - Give actionable advice for daily training or race week prep
        """
    }
}

enum ClaudeServiceError: LocalizedError {
    case invalidRequest
    case networkError
    case invalidResponse
    case invalidAPIKey
    case rateLimitExceeded
    case serverError

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid request format"
        case .networkError:
            return "Network connection failed"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .invalidAPIKey:
            return "Invalid API key. Check your credentials."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Try again later."
        case .serverError:
            return "Claude API server error"
        }
    }
}

struct ClaudeResponse: Codable {
    struct Content: Codable {
        let text: String
    }

    let content: [Content]
}
