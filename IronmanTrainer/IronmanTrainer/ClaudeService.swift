import Foundation

// MARK: - Claude Service
class ClaudeService: NSObject, ObservableObject {
    static let shared = ClaudeService()

    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    private let baseURL = "https://api.anthropic.com/v1/messages"

    override init() {
        // Load API key from Secrets (Config.xcconfig)
        self.apiKey = Secrets.anthropicAPIKey
        super.init()
    }

    func sendMessage(userMessage: String, trainingContext: String, workoutHistory: String, zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)? = nil, conversationHistory: [[String: Any]] = [], imageData: Data? = nil) async throws -> String {
        let systemPrompt = buildSystemPrompt(context: trainingContext, history: workoutHistory, zoneBoundaries: zoneBoundaries)

        // Start LangSmith run
        let runID = LangSmithTracer.shared.startRun(systemPrompt: systemPrompt, userMessage: userMessage)

        // Build messages array with conversation history + current message
        var messages: [[String: Any]] = conversationHistory

        // Build current message content (multimodal if image attached)
        if let imageData = imageData {
            let base64 = imageData.base64EncodedString()
            var contentBlocks: [[String: Any]] = [
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": base64
                    ]
                ]
            ]
            contentBlocks.append([
                "type": "text",
                "text": userMessage
            ])
            messages.append(["role": "user", "content": contentBlocks])
        } else {
            messages.append(["role": "user", "content": userMessage])
        }

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": messages
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
                // End LangSmith run with response
                LangSmithTracer.shared.endRun(runID: runID, response: content)
                return content
            }
            throw ClaudeServiceError.invalidResponse
        case 401:
            throw ClaudeServiceError.invalidAPIKey
        case 429:
            throw ClaudeServiceError.rateLimitExceeded
        default:
            // Return more detailed error info
            if let errorData = String(data: data, encoding: .utf8) {
                print("API Error: \(httpResponse.statusCode) - \(errorData)")
            }
            throw ClaudeServiceError.serverError
        }
    }

    private func buildSystemPrompt(context: String, history: String, zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)? = nil) -> String {
        let z2 = zoneBoundaries?.z2 ?? 126
        let z3 = zoneBoundaries?.z3 ?? 144
        let z4 = zoneBoundaries?.z4 ?? 155
        let z5 = zoneBoundaries?.z5 ?? 167
        return """
        You are a personal triathlon coaching assistant for Brent, training for Ironman 70.3 Oregon (Jul 19, 2026, Salem OR).

        TRAINING PLAN: 17-week program (Mar 23 - Jul 19, 2026)
        ATHLETE: VO2 Max 57.8, 8-10 hrs/wk available
        HR ZONES: Z1 <\(z2)bpm (recovery) | Z2 \(z2)-\(z3)bpm (endurance) | Z3 \(z3)-\(z4)bpm (tempo) | Z4 \(z4)-\(z5)bpm (threshold) | Z5 \(z5)+bpm (VO2max)
        RACE GOAL: Sub-6:00 finish (Swim 38-42m | Bike 3:00-3:10 | Run 1:55-2:02)

        TRAINING CONTEXT:
        \(context)

        RECENT WORKOUTS:
        \(history)

        Give specific coaching advice based on Brent's training plan, zones, and race strategy.
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
            return "Invalid API key"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .serverError:
            return "Server error"
        }
    }
}

struct ClaudeResponse: Codable {
    struct Content: Codable {
        let text: String
    }

    let content: [Content]
}
