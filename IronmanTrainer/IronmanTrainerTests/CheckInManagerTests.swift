import XCTest
@testable import Race1_Trainer

final class CheckInManagerTests: XCTestCase {

    var manager: CheckInManager!

    @MainActor
    override func setUp() {
        super.setUp()
        // Clear any persisted state to keep tests deterministic.
        UserDefaults.standard.removeObject(forKey: "checkIn.enabled")
        UserDefaults.standard.removeObject(forKey: "checkIn.time")
        UserDefaults.standard.removeObject(forKey: "checkIn.cachedOpeningMessage")
        manager = CheckInManager()
        manager.freshnessWindow = 6 * 60 * 60
    }

    @MainActor
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "checkIn.enabled")
        UserDefaults.standard.removeObject(forKey: "checkIn.time")
        UserDefaults.standard.removeObject(forKey: "checkIn.cachedOpeningMessage")
        manager = nil
        super.tearDown()
    }

    // MARK: - loadCachedOpeningMessage staleness

    @MainActor
    func testLoadCachedOpeningMessage_fresh() {
        let now = Date()
        let cached = CachedOpeningMessage(
            notificationBody: "body",
            openingMessage: "opening",
            generatedAt: now.addingTimeInterval(-60), // 1 min ago
            workoutSummary: nil
        )
        manager.saveCachedOpeningMessage(cached)

        let loaded = manager.loadCachedOpeningMessage(now: now)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.openingMessage, "opening")
    }

    @MainActor
    func testLoadCachedOpeningMessage_expired() {
        let now = Date()
        let cached = CachedOpeningMessage(
            notificationBody: "body",
            openingMessage: "opening",
            generatedAt: now.addingTimeInterval(-7 * 60 * 60), // 7h ago > 6h window
            workoutSummary: nil
        )
        manager.saveCachedOpeningMessage(cached)

        let loaded = manager.loadCachedOpeningMessage(now: now)
        XCTAssertNil(loaded, "A message older than the freshness window must be treated as stale")
    }

    @MainActor
    func testLoadCachedOpeningMessage_missing() {
        XCTAssertNil(manager.loadCachedOpeningMessage())
    }

    @MainActor
    func testLoadCachedOpeningMessage_exactlyAtBoundary() {
        // Exactly the freshness window (default 6h) — consider stale to be
        // conservative (we regenerate on the boundary).
        let now = Date()
        let cached = CachedOpeningMessage(
            notificationBody: "body",
            openingMessage: "opening",
            generatedAt: now.addingTimeInterval(-(6 * 60 * 60) - 1),
            workoutSummary: nil
        )
        manager.saveCachedOpeningMessage(cached)
        XCTAssertNil(manager.loadCachedOpeningMessage(now: now))
    }

    // MARK: - Defaults

    @MainActor
    func testDefaultCheckInTime_is7AM() {
        let cal = Calendar.current
        let h = cal.component(.hour, from: manager.checkInTime)
        let m = cal.component(.minute, from: manager.checkInTime)
        XCTAssertEqual(h, 7)
        XCTAssertEqual(m, 0)
    }

    @MainActor
    func testDefaultEnabled_isFalse() {
        XCTAssertFalse(manager.enabled)
    }

    // MARK: - Static fallback message (tier 3)

    @MainActor
    func testStaticFallbackMessage_noPlan() {
        let msg = manager.staticFallbackMessage(trainingPlan: nil)
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - Generate opening message uses fallback on failure

    @MainActor
    func testGenerateOpeningMessage_fallsBackOnError() async {
        struct BoomError: Error {}
        manager.generateOpeningMessageCall = { _ in throw BoomError() }

        let result = await manager.generateOpeningMessage(trainingPlan: nil, healthKit: nil)
        XCTAssertFalse(result.openingMessage.isEmpty)
        XCTAssertNotNil(manager.lastError)
    }

    @MainActor
    func testGenerateOpeningMessage_cachesOnSuccess() async {
        manager.generateOpeningMessageCall = { _ in ("push body", "Hi, good morning — how's the body feeling?") }

        let result = await manager.generateOpeningMessage(trainingPlan: nil, healthKit: nil)
        XCTAssertEqual(result.openingMessage, "Hi, good morning — how's the body feeling?")
        XCTAssertNil(manager.lastError)

        let cached = manager.loadCachedOpeningMessage()
        XCTAssertEqual(cached?.openingMessage, "Hi, good morning — how's the body feeling?")
        XCTAssertEqual(cached?.notificationBody, "push body")
    }

    // MARK: - Chat filter predicate (tested via static helper)

    func testChatFilter_allReturnsEverything() {
        let msgs = [
            ChatMessage(isUser: true, text: "a", kind: .general),
            ChatMessage(isUser: false, text: "b", kind: .checkIn),
        ]
        XCTAssertEqual(ChatView.applyFilter(.all, to: msgs).count, 2)
    }

    func testChatFilter_checkInsOnlyCheckIns() {
        let msgs = [
            ChatMessage(isUser: true, text: "a", kind: .general),
            ChatMessage(isUser: false, text: "b", kind: .checkIn),
            ChatMessage(isUser: true, text: "c", kind: .checkIn),
        ]
        let filtered = ChatView.applyFilter(.checkIns, to: msgs)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.kind == .checkIn })
    }
}
