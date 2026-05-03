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

// MARK: - Plan generation service protocol

protocol PlanGenerationServiceProtocol {
    func generatePlan(
        raceDate: Date,
        raceType: String,
        weeklyHours: Double,
        experienceLevel: String,
        userProfile: [String: Any]
    ) async throws -> [TrainingWeek]
}

// MARK: - Auth service protocol

protocol AuthServiceProtocol: AnyObject {
    var isAuthenticated: Bool { get }
    var currentUserID: String? { get }
    var onboardingComplete: Bool { get }
    // NOTE: AuthService.signOut() is declared `throws`, so the non-throwing
    // requirement here does not match. Wire up conformance once the signature
    // is reconciled (either make the protocol require `throws`, or make
    // AuthService.signOut() non-throwing).
    func signOut()
}

// MARK: - Database service protocol

protocol DatabaseServiceProtocol: AnyObject {
    func saveUserProfile(_ profile: [String: Any], uid: String) async throws
    func getUserProfile(uid: String) async throws -> [String: Any]?
    func saveTrainingPlan(weeks: [TrainingWeek], metadata: [String: Any], uid: String) async throws
    func getTrainingPlan(uid: String) async throws -> (weeks: [TrainingWeek], metadata: [String: Any])?
}

// MARK: - AuthService conformance
// NOTE: AuthService.signOut() throws, but AuthServiceProtocol.signOut() does
// not. Conformance is omitted until the signatures are aligned.
// extension AuthService: AuthServiceProtocol {}

// MARK: - FirestoreService conformance
// NOTE: FirestoreService uses typed models (UserProfile, PlanMetadata) rather
// than [String: Any] dictionaries. Conformance is omitted until
// DatabaseServiceProtocol is updated to match the concrete method signatures,
// or FirestoreService gains adaptor methods for the generic [String: Any] form.
// extension FirestoreService: DatabaseServiceProtocol {}

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
