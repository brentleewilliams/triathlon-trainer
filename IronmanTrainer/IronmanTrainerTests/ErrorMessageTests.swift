import XCTest
@testable import Race1_Trainer

/// Guards against misleading or context-inappropriate error messages surfacing in the UI.
/// These tests caught the App Store rejection where ClaudeServiceError.serverError
/// contained onboarding race-search copy ("The search service is temporarily unavailable")
/// instead of a message appropriate for the chat coaching context.
final class ErrorMessageTests: XCTestCase {

    // MARK: - ClaudeServiceError descriptions

    func testServerError_doesNotMentionSearch() {
        let msg = ClaudeServiceError.serverError.localizedDescription ?? ""
        XCTAssertFalse(
            msg.lowercased().contains("search"),
            "serverError should not mention 'search' — it appears in chat, not the race-search onboarding flow. Got: \"\(msg)\""
        )
    }

    func testServerError_doesNotMentionRaceDetails() {
        let msg = ClaudeServiceError.serverError.localizedDescription ?? ""
        XCTAssertFalse(
            msg.lowercased().contains("race details"),
            "serverError should not contain race-search onboarding copy. Got: \"\(msg)\""
        )
    }

    func testServerError_isUserFriendly() {
        let msg = ClaudeServiceError.serverError.localizedDescription ?? ""
        XCTAssertFalse(msg.isEmpty, "serverError must have a user-facing description")
        // Should not expose raw HTTP status codes or internal identifiers
        XCTAssertFalse(msg.contains("500"), "serverError should not expose raw HTTP status codes")
        XCTAssertFalse(msg.contains("503"), "serverError should not expose raw HTTP status codes")
    }

    func testNetworkError_isUserFriendly() {
        let msg = ClaudeServiceError.networkError.localizedDescription ?? ""
        XCTAssertFalse(msg.isEmpty, "networkError must have a user-facing description")
    }

    func testRateLimitError_isUserFriendly() {
        let msg = ClaudeServiceError.rateLimitExceeded.localizedDescription ?? ""
        XCTAssertFalse(msg.isEmpty, "rateLimitExceeded must have a user-facing description")
    }

    func testInvalidAPIKey_isUserFriendly() {
        let msg = ClaudeServiceError.invalidAPIKey.localizedDescription ?? ""
        XCTAssertFalse(msg.isEmpty, "invalidAPIKey must have a user-facing description")
    }

    // MARK: - All cases covered

    func testAllErrorCasesHaveDescriptions() {
        let cases: [ClaudeServiceError] = [
            .invalidRequest, .networkError, .invalidResponse,
            .invalidAPIKey, .rateLimitExceeded, .serverError
        ]
        for error in cases {
            let msg = error.localizedDescription ?? ""
            XCTAssertFalse(
                msg.isEmpty,
                "\(error) has no localizedDescription — it will show blank in the UI"
            )
        }
    }
}
