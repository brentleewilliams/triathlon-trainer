import XCTest
@testable import Race1_Trainer

final class FeatureFlagsTests: XCTestCase {

    private let udKey = "shareWorkoutDataWithCoach"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: udKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: udKey)
        super.tearDown()
    }

    // MARK: - FeatureFlags.includeHealthKitInAIContext

    func testIncludeHKInAIContext_defaultsToTrue_whenKeyAbsent() {
        XCTAssertTrue(FeatureFlags.includeHealthKitInAIContext)
    }

    func testIncludeHKInAIContext_returnsFalse_whenKeySetFalse() {
        UserDefaults.standard.set(false, forKey: udKey)
        XCTAssertFalse(FeatureFlags.includeHealthKitInAIContext)
    }

    func testIncludeHKInAIContext_returnsTrue_whenKeySetTrue() {
        UserDefaults.standard.set(true, forKey: udKey)
        XCTAssertTrue(FeatureFlags.includeHealthKitInAIContext)
    }

    func testIncludeHKInAIContext_toggleOffThenOn_reflectsLatestValue() {
        UserDefaults.standard.set(false, forKey: udKey)
        XCTAssertFalse(FeatureFlags.includeHealthKitInAIContext)
        UserDefaults.standard.set(true, forKey: udKey)
        XCTAssertTrue(FeatureFlags.includeHealthKitInAIContext)
    }

    // MARK: - ChatView.applyFilter

    func testApplyFilter_all_returnsAllMessages() {
        let messages = [
            ChatMessage(isUser: true, text: "hi", kind: .general),
            ChatMessage(isUser: false, text: "hey", kind: .checkIn),
        ]
        let result = ChatView.applyFilter(.all, to: messages)
        XCTAssertEqual(result.count, 2)
    }

    func testApplyFilter_checkIns_returnsOnlyCheckInMessages() {
        let messages = [
            ChatMessage(isUser: true, text: "general", kind: .general),
            ChatMessage(isUser: false, text: "check-in reply", kind: .checkIn),
            ChatMessage(isUser: true, text: "another general", kind: .general),
        ]
        let result = ChatView.applyFilter(.checkIns, to: messages)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.text, "check-in reply")
    }

    func testApplyFilter_checkIns_emptyWhenNoCheckIns() {
        let messages = [
            ChatMessage(isUser: true, text: "a", kind: .general),
            ChatMessage(isUser: false, text: "b", kind: .general),
        ]
        let result = ChatView.applyFilter(.checkIns, to: messages)
        XCTAssertTrue(result.isEmpty)
    }

    func testApplyFilter_all_emptyInput_returnsEmpty() {
        XCTAssertTrue(ChatView.applyFilter(.all, to: []).isEmpty)
    }
}
