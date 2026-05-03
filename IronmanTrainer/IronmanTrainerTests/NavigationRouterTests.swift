import XCTest
@testable import Race1_Trainer

@MainActor
final class NavigationRouterTests: XCTestCase {

    var router: NavigationRouter!

    override func setUp() {
        super.setUp()
        router = NavigationRouter()
        // Reset all state
        router.showCheckIn = false
        router.showChat = false
        router.showSettings = false
        router.showCalendar = false
        router.showLogWorkout = false
        router.chatSeed = ""
    }

    func testOpenCheckIn_setsShowCheckIn() {
        router.openCheckIn()
        XCTAssertTrue(router.showCheckIn)
        XCTAssertFalse(router.showChat)
        XCTAssertFalse(router.showSettings)
    }

    func testOpenChat_setsShowChat() {
        router.openChat()
        XCTAssertTrue(router.showChat)
        XCTAssertEqual(router.chatSeed, "")
    }

    func testOpenChat_withSeed_storesSeed() {
        router.openChat(seed: "Help me with my swim")
        XCTAssertTrue(router.showChat)
        XCTAssertEqual(router.chatSeed, "Help me with my swim")
    }

    func testOpenChat_emptySeed_leavesNoSeed() {
        router.openChat(seed: "")
        XCTAssertTrue(router.showChat)
        XCTAssertEqual(router.chatSeed, "")
    }

    func testOpenSettings_setsShowSettings() {
        router.openSettings()
        XCTAssertTrue(router.showSettings)
        XCTAssertFalse(router.showChat)
    }

    func testOpenCalendar_setsShowCalendar() {
        router.openCalendar()
        XCTAssertTrue(router.showCalendar)
        XCTAssertFalse(router.showSettings)
    }

    func testOpenLogWorkout_setsShowLogWorkout() {
        router.openLogWorkout()
        XCTAssertTrue(router.showLogWorkout)
        XCTAssertFalse(router.showCalendar)
    }

    func testOpenMultiple_eachFlagIsIndependent() {
        router.openSettings()
        router.openCalendar()
        XCTAssertTrue(router.showSettings)
        XCTAssertTrue(router.showCalendar)
        XCTAssertFalse(router.showChat)
        XCTAssertFalse(router.showCheckIn)
        XCTAssertFalse(router.showLogWorkout)
    }

    func testChatSeed_canBeCleared() {
        router.openChat(seed: "test nudge")
        XCTAssertEqual(router.chatSeed, "test nudge")
        router.chatSeed = ""
        XCTAssertEqual(router.chatSeed, "")
    }
}
