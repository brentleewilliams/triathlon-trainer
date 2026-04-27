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
