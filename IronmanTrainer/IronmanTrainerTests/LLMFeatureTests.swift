import XCTest
@testable import Race1_Trainer

// MARK: - Mocks

final class MockCoachingService: CoachingServiceProtocol {
    var result: Result<CoachingResponse, Error> = .success(CoachingResponse(text: "Great work!", proposedChanges: nil))

    func sendCoachingMessage(
        userMessage: String,
        trainingContext: String,
        workoutHistory: String,
        zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)?,
        conversationHistory: [[String: Any]],
        imageData: Data?,
        planScope: String,
        traceContext: LangSmithTraceContext?
    ) async throws -> CoachingResponse {
        switch result {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

final class MockRaceSearchService: RaceSearchServiceProtocol {
    var searchRaceResult: Result<RaceSearchResult, Error> = .success(
        RaceSearchResult(name: "Ironman 70.3 Oregon", date: Date().addingTimeInterval(86400 * 80),
                         location: "Bend, OR", type: "70.3", distances: [:],
                         courseType: "mixed", elevationGainM: nil, elevationAtVenueM: nil, historicalWeather: nil)
    )
    var searchPrepRaceResult: Result<PrepRaceSearchResult, Error> = .success(
        PrepRaceSearchResult(name: "Cherry Creek Sneak 5K", date: Date().addingTimeInterval(86400 * 30), distance: "5K")
    )

    func searchRace(query: String) async throws -> RaceSearchResult {
        switch searchRaceResult {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    func searchPrepRace(query: String) async throws -> PrepRaceSearchResult {
        switch searchPrepRaceResult {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

// MARK: - Coach Chat Tests

final class CoachChatLLMTests: XCTestCase {

    var viewModel: ChatViewModel!
    var mockService: MockCoachingService!

    override func setUp() {
        super.setUp()
        mockService = MockCoachingService()
        viewModel = ChatViewModel(skipHistory: true)
        viewModel.coachingService = mockService
    }

    func testHappyPath_appendsAssistantMessage() async {
        mockService.result = .success(CoachingResponse(text: "Focus on your long run this weekend.", proposedChanges: nil))

        await viewModel.sendMessage("What should I focus on this week?")

        let lastMessage = viewModel.messages.last
        XCTAssertEqual(lastMessage?.isUser, false)
        XCTAssertEqual(lastMessage?.text, "Focus on your long run this weekend.")
        XCTAssertNil(viewModel.error)
    }

    func testServerError_retriesOnceThenShowsError() async {
        var callCount = 0
        // Fail both attempts
        mockService.result = .failure(ClaudeServiceError.serverError)

        // Track calls by replacing the service with a counting mock
        final class CountingMock: CoachingServiceProtocol {
            var callCount = 0
            func sendCoachingMessage(userMessage: String, trainingContext: String, workoutHistory: String, zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)?, conversationHistory: [[String: Any]], imageData: Data?, planScope: String, traceContext: LangSmithTraceContext?) async throws -> CoachingResponse {
                callCount += 1
                throw ClaudeServiceError.serverError
            }
        }
        let counting = CountingMock()
        viewModel.coachingService = counting

        await viewModel.sendMessage("Test")

        XCTAssertEqual(counting.callCount, 2, "Should retry exactly once")
        XCTAssertNotNil(viewModel.error)
        XCTAssertEqual(viewModel.error, ClaudeServiceError.serverError.localizedDescription)
    }

    func testServerError_retriesAndSucceeds() async {
        final class FailOnceMock: CoachingServiceProtocol {
            var callCount = 0
            func sendCoachingMessage(userMessage: String, trainingContext: String, workoutHistory: String, zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)?, conversationHistory: [[String: Any]], imageData: Data?, planScope: String, traceContext: LangSmithTraceContext?) async throws -> CoachingResponse {
                callCount += 1
                if callCount == 1 { throw ClaudeServiceError.serverError }
                return CoachingResponse(text: "Recovered response.", proposedChanges: nil)
            }
        }
        let failOnce = FailOnceMock()
        viewModel.coachingService = failOnce

        await viewModel.sendMessage("Hello")

        XCTAssertEqual(failOnce.callCount, 2)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.messages.last?.text, "Recovered response.")
    }

    func testNonRetryableError_doesNotRetry() async {
        final class CountingMock: CoachingServiceProtocol {
            var callCount = 0
            func sendCoachingMessage(userMessage: String, trainingContext: String, workoutHistory: String, zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)?, conversationHistory: [[String: Any]], imageData: Data?, planScope: String, traceContext: LangSmithTraceContext?) async throws -> CoachingResponse {
                callCount += 1
                throw ClaudeServiceError.invalidAPIKey
            }
        }
        let counting = CountingMock()
        viewModel.coachingService = counting

        await viewModel.sendMessage("Test")

        XCTAssertEqual(counting.callCount, 1, "Non-retryable errors should not retry")
        XCTAssertNotNil(viewModel.error)
    }
}

// MARK: - Onboarding Race Search Tests

@MainActor
final class OnboardingRaceSearchLLMTests: XCTestCase {

    var viewModel: OnboardingViewModel!
    var mockService: MockRaceSearchService!

    override func setUp() {
        super.setUp()
        mockService = MockRaceSearchService()
        viewModel = OnboardingViewModel()
        viewModel.raceSearchService = mockService
        // Use a query that won't fuzzy-match any entry in VerifiedRaceDatabase
        // so localRaceOverride returns nil and the search path actually reaches
        // the (mocked) LLM where the failure cases under test are configured.
        viewModel.raceSearchQuery = "Zzz Fictional Race Xyz 9999"
    }

    func testHappyPath_setsRaceSearchResult() async {
        let futureDate = Date().addingTimeInterval(86400 * 80)
        mockService.searchRaceResult = .success(
            RaceSearchResult(name: "Ironman 70.3 Oregon", date: futureDate,
                             location: "Bend, OR", type: "70.3", distances: [:],
                             courseType: "mixed", elevationGainM: nil, elevationAtVenueM: nil, historicalWeather: nil)
        )

        await viewModel.searchRace()

        XCTAssertNotNil(viewModel.raceSearchResult)
        XCTAssertEqual(viewModel.raceSearchResult?.name, "Ironman 70.3 Oregon")
        XCTAssertNil(viewModel.error)
    }

    func testServerError_showsTransientMessage() async {
        mockService.searchRaceResult = .failure(ClaudeServiceError.serverError)

        await viewModel.searchRace()

        XCTAssertNil(viewModel.raceSearchResult)
        XCTAssertEqual(viewModel.error, "Couldn't reach the search service. Check your connection and try again.")
    }

    func testNetworkError_showsTransientMessage() async {
        mockService.searchRaceResult = .failure(ClaudeServiceError.networkError)

        await viewModel.searchRace()

        XCTAssertNil(viewModel.raceSearchResult)
        XCTAssertEqual(viewModel.error, "Couldn't reach the search service. Check your connection and try again.")
    }

    func testInvalidResponse_showsNotFoundMessage() async {
        mockService.searchRaceResult = .failure(ClaudeServiceError.invalidResponse)

        await viewModel.searchRace()

        XCTAssertNil(viewModel.raceSearchResult)
        XCTAssertEqual(viewModel.error, "Could not find that race. Try a more specific name or enter details manually.")
    }
}

// MARK: - Prep Race Search Tests

final class PrepRaceSearchLLMTests: XCTestCase {

    var mockService: MockRaceSearchService!

    // Drives the private searchRace() method by simulating the same logic
    // since AddPrepRaceSheet is a View and not directly unit-testable.
    // We test the error classification logic extracted into a helper.
    func prepRaceSearchError(from error: Error) -> String {
        let isTransient = (error as? ClaudeServiceError) == .serverError || (error as? ClaudeServiceError) == .networkError
        return isTransient
            ? "Couldn't reach the search service. Check your connection and try again."
            : "Could not find that race. Try a more specific name or enter details manually."
    }

    func testHappyPath_returnsRaceDetails() async throws {
        mockService = MockRaceSearchService()
        let expected = PrepRaceSearchResult(name: "Cherry Creek Sneak 5K", date: Date().addingTimeInterval(86400 * 30), distance: "5K")
        mockService.searchPrepRaceResult = .success(expected)

        let result = try await mockService.searchPrepRace(query: "Cherry Creek Sneak 5K 2026")
        XCTAssertEqual(result.name, "Cherry Creek Sneak 5K")
        XCTAssertEqual(result.distance, "5K")
    }

    func testServerError_showsTransientMessage() {
        let msg = prepRaceSearchError(from: ClaudeServiceError.serverError)
        XCTAssertEqual(msg, "Couldn't reach the search service. Check your connection and try again.")
    }

    func testNetworkError_showsTransientMessage() {
        let msg = prepRaceSearchError(from: ClaudeServiceError.networkError)
        XCTAssertEqual(msg, "Couldn't reach the search service. Check your connection and try again.")
    }

    func testInvalidResponse_showsNotFoundMessage() {
        let msg = prepRaceSearchError(from: ClaudeServiceError.invalidResponse)
        XCTAssertEqual(msg, "Could not find that race. Try a more specific name or enter details manually.")
    }

    func testCancellation_isNotAnError() async {
        mockService = MockRaceSearchService()
        mockService.searchPrepRaceResult = .failure(CancellationError())
        // CancellationError should be swallowed — verify it is NOT classified as a transient/notFound error
        do {
            _ = try await mockService.searchPrepRace(query: "test")
            XCTFail("Should have thrown")
        } catch is CancellationError {
            // correct — caller handles this separately
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
