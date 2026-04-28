import Foundation

// MARK: - Coaching service protocol

protocol CoachingServiceProtocol {
    func sendCoachingMessage(
        userMessage: String,
        trainingContext: String,
        workoutHistory: String,
        zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)?,
        conversationHistory: [[String: Any]],
        imageData: Data?,
        planScope: String,
        traceContext: LangSmithTraceContext?
    ) async throws -> CoachingResponse
}

// MARK: - Race search protocol

protocol RaceSearchServiceProtocol {
    func searchRace(query: String) async throws -> RaceSearchResult
    func searchPrepRace(query: String) async throws -> PrepRaceSearchResult
}

// MARK: - LLMProxyService conformances

extension LLMProxyService: CoachingServiceProtocol {}
extension LLMProxyService: RaceSearchServiceProtocol {}

// MARK: - Shared LLM error type

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
            return "Invalid response from server"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .serverError:
            // Generic copy — each LLM-using feature (chat, race search, prep
            // race) wraps with its own context-specific error message at the
            // call site.
            return "Service temporarily unavailable. Please try again in a moment."
        }
    }
}
