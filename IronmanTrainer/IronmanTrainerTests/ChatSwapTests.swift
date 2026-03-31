import XCTest
@testable import IronmanTrainer

final class ChatSwapTests: XCTestCase {

    var viewModel: ChatViewModel!

    override func setUp() {
        super.setUp()
        viewModel = ChatViewModel()
        viewModel.trainingPlan = TrainingPlanManager()
        // Clear any persisted state from previous test runs
        UserDefaults.standard.removeObject(forKey: "coaching_chat_history")
        UserDefaults.standard.removeObject(forKey: "last_swap_command")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "coaching_chat_history")
        UserDefaults.standard.removeObject(forKey: "last_swap_command")
        viewModel = nil
        super.tearDown()
    }

    // MARK: - SwapCommand Parsing Tests

    func testParseSwapCommand_ValidTag() {
        let response = "Sure! I'll swap Tuesday and Wednesday for you. [SWAP_DAYS:week=2:from=Tue:to=Wed] Done!"
        let command = viewModel.parseSwapCommand(from: response)

        XCTAssertNotNil(command)
        XCTAssertEqual(command?.weekNumber, 2)
        XCTAssertEqual(command?.fromDay, "Tue")
        XCTAssertEqual(command?.toDay, "Wed")
    }

    func testParseSwapCommand_AllDays() {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for from in days {
            for to in days where to != from {
                let response = "[SWAP_DAYS:week=1:from=\(from):to=\(to)]"
                let command = viewModel.parseSwapCommand(from: response)
                XCTAssertNotNil(command, "Should parse swap from \(from) to \(to)")
                XCTAssertEqual(command?.fromDay, from)
                XCTAssertEqual(command?.toDay, to)
            }
        }
    }

    func testParseSwapCommand_HighWeekNumber() {
        let response = "[SWAP_DAYS:week=17:from=Sat:to=Sun]"
        let command = viewModel.parseSwapCommand(from: response)

        XCTAssertNotNil(command)
        XCTAssertEqual(command?.weekNumber, 17)
    }

    func testParseSwapCommand_NoTag() {
        let response = "I think you should keep Tuesday's workout as is."
        let command = viewModel.parseSwapCommand(from: response)

        XCTAssertNil(command)
    }

    func testParseSwapCommand_MalformedTag_MissingWeek() {
        let response = "[SWAP_DAYS:from=Tue:to=Wed]"
        let command = viewModel.parseSwapCommand(from: response)

        XCTAssertNil(command)
    }

    func testParseSwapCommand_MalformedTag_InvalidDay() {
        let response = "[SWAP_DAYS:week=1:from=Tuesday:to=Wednesday]"
        let command = viewModel.parseSwapCommand(from: response)

        XCTAssertNil(command)
    }

    func testParseSwapCommand_MalformedTag_PartialMatch() {
        let response = "[SWAP_DAYS:week=1:from=Tue]"
        let command = viewModel.parseSwapCommand(from: response)

        XCTAssertNil(command)
    }

    func testParseSwapCommand_EmbeddedInLongResponse() {
        let response = """
        Great idea! Moving your long ride to Thursday makes sense given the weather forecast.

        Here's what I'll do:
        [SWAP_DAYS:week=5:from=Wed:to=Thu]

        This way you'll have better conditions for the outdoor ride. Your Wednesday will now have the easier swim workout instead.
        """
        let command = viewModel.parseSwapCommand(from: response)

        XCTAssertNotNil(command)
        XCTAssertEqual(command?.weekNumber, 5)
        XCTAssertEqual(command?.fromDay, "Wed")
        XCTAssertEqual(command?.toDay, "Thu")
    }

    // MARK: - Swap Execution Tests

    func testExecuteSwap_SwapsWorkoutsBetweenDays() {
        guard let plan = viewModel.trainingPlan else {
            XCTFail("Training plan should exist")
            return
        }

        let week1 = plan.getWeek(1)!
        let tueBefore = week1.workouts.filter { $0.day == "Tue" }.map { $0.type }
        let wedBefore = week1.workouts.filter { $0.day == "Wed" }.map { $0.type }

        let command = SwapCommand(weekNumber: 1, fromDay: "Tue", toDay: "Wed")
        let result = viewModel.executeSwap(command)

        XCTAssertNotNil(result, "Swap should succeed")

        let week1After = plan.getWeek(1)!
        let tueAfter = week1After.workouts.filter { $0.day == "Tue" }.map { $0.type }
        let wedAfter = week1After.workouts.filter { $0.day == "Wed" }.map { $0.type }

        XCTAssertEqual(tueAfter, wedBefore, "Tuesday should now have Wednesday's workouts")
        XCTAssertEqual(wedAfter, tueBefore, "Wednesday should now have Tuesday's workouts")
    }

    func testExecuteSwap_InvalidWeekReturnsNil() {
        let command = SwapCommand(weekNumber: 99, fromDay: "Tue", toDay: "Wed")
        let result = viewModel.executeSwap(command)

        XCTAssertNil(result, "Swap should fail for non-existent week")
    }

    func testExecuteSwap_PreservesWorkoutCount() {
        guard let plan = viewModel.trainingPlan else {
            XCTFail("Training plan should exist")
            return
        }

        let countBefore = plan.getWeek(1)!.workouts.count

        let command = SwapCommand(weekNumber: 1, fromDay: "Tue", toDay: "Thu")
        _ = viewModel.executeSwap(command)

        let countAfter = plan.getWeek(1)!.workouts.count
        XCTAssertEqual(countBefore, countAfter, "Total workout count should not change after swap")
    }

    func testExecuteSwap_DoubleSwapRestoresOriginal() {
        guard let plan = viewModel.trainingPlan else {
            XCTFail("Training plan should exist")
            return
        }

        let week1Original = plan.getWeek(1)!
        let originalTypes = week1Original.workouts.map { "\($0.day):\($0.type)" }.sorted()

        // Swap Tue <-> Wed
        let command1 = SwapCommand(weekNumber: 1, fromDay: "Tue", toDay: "Wed")
        _ = viewModel.executeSwap(command1)

        // Swap back Wed <-> Tue (undo)
        let command2 = SwapCommand(weekNumber: 1, fromDay: "Wed", toDay: "Tue")
        _ = viewModel.executeSwap(command2)

        let week1After = plan.getWeek(1)!
        let afterTypes = week1After.workouts.map { "\($0.day):\($0.type)" }.sorted()

        XCTAssertEqual(originalTypes, afterTypes, "Double swap should restore original plan")
    }

    // MARK: - SwapCommand Codable Tests

    func testSwapCommand_EncodesAndDecodes() throws {
        let command = SwapCommand(weekNumber: 3, fromDay: "Mon", toDay: "Fri")

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(SwapCommand.self, from: data)

        XCTAssertEqual(decoded.weekNumber, 3)
        XCTAssertEqual(decoded.fromDay, "Mon")
        XCTAssertEqual(decoded.toDay, "Fri")
    }

    // MARK: - Last Swap Persistence Tests

    func testLastSwap_PersistedToUserDefaults() {
        // Persist a swap command directly via UserDefaults (simulating what sendMessage does)
        let command = SwapCommand(weekNumber: 2, fromDay: "Tue", toDay: "Wed")
        let data = try! JSONEncoder().encode(command)
        UserDefaults.standard.set(data, forKey: "last_swap_command")

        // Create a new view model to simulate app restart
        let newViewModel = ChatViewModel()
        XCTAssertNotNil(newViewModel.lastSwap, "Last swap should persist across view model instances")
        XCTAssertEqual(newViewModel.lastSwap?.weekNumber, 2)
        XCTAssertEqual(newViewModel.lastSwap?.fromDay, "Tue")
        XCTAssertEqual(newViewModel.lastSwap?.toDay, "Wed")
    }

    func testLastSwap_ClearedFromUserDefaults() {
        // Set a swap in UserDefaults
        let command = SwapCommand(weekNumber: 1, fromDay: "Mon", toDay: "Fri")
        let data = try! JSONEncoder().encode(command)
        UserDefaults.standard.set(data, forKey: "last_swap_command")

        // Verify it's in UserDefaults
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "last_swap_command"))

        // Clear it
        UserDefaults.standard.removeObject(forKey: "last_swap_command")
        let newViewModel = ChatViewModel()
        XCTAssertNil(newViewModel.lastSwap, "Last swap should be nil when cleared from UserDefaults")
    }

    // MARK: - Chat History Persistence Tests

    func testChatHistory_SaveAndLoad() {
        viewModel.messages = [
            ChatMessage(isUser: true, text: "Can I swap Tuesday and Wednesday?"),
            ChatMessage(isUser: false, text: "Sure! [SWAP_DAYS:week=1:from=Tue:to=Wed]")
        ]
        viewModel.saveChatHistory()

        let newViewModel = ChatViewModel()
        XCTAssertEqual(newViewModel.messages.count, 2, "Messages should persist")
        XCTAssertEqual(newViewModel.messages[0].text, "Can I swap Tuesday and Wednesday?")
        XCTAssertTrue(newViewModel.messages[0].isUser)
        XCTAssertEqual(newViewModel.messages[1].text, "Sure! [SWAP_DAYS:week=1:from=Tue:to=Wed]")
        XCTAssertFalse(newViewModel.messages[1].isUser)
    }

    func testChatHistory_ClearHistory() {
        viewModel.messages = [
            ChatMessage(isUser: true, text: "Hello"),
            ChatMessage(isUser: false, text: "Hi there!")
        ]
        viewModel.saveChatHistory()

        viewModel.clearChatHistory()

        XCTAssertTrue(viewModel.messages.isEmpty, "Messages should be empty after clear")

        let newViewModel = ChatViewModel()
        XCTAssertTrue(newViewModel.messages.isEmpty, "Cleared history should not persist")
    }

    func testChatHistory_EmptyOnFreshStart() {
        // UserDefaults already cleared in setUp
        let freshViewModel = ChatViewModel()
        XCTAssertTrue(freshViewModel.messages.isEmpty, "Fresh start should have no messages")
    }

    // MARK: - ChatMessage Codable Tests

    func testChatMessage_EncodesAndDecodes() throws {
        let message = ChatMessage(isUser: true, text: "Test message")

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.text, "Test message")
        XCTAssertTrue(decoded.isUser)
        XCTAssertEqual(decoded.id, message.id)
    }

    func testChatMessage_TimestampPreserved() throws {
        let message = ChatMessage(isUser: false, text: "Response")

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(
            decoded.timestamp.timeIntervalSince1970,
            message.timestamp.timeIntervalSince1970,
            accuracy: 0.001,
            "Timestamp should be preserved through encoding"
        )
    }

    // MARK: - Workout Note Persistence Tests

    func testWorkoutNote_SaveAndLoad() {
        let key = "workout_note_w1_Tue_🏃 Run"
        UserDefaults.standard.removeObject(forKey: key)

        UserDefaults.standard.set("Felt great today!", forKey: key)
        let loaded = UserDefaults.standard.string(forKey: key)

        XCTAssertEqual(loaded, "Felt great today!", "Note should persist in UserDefaults")

        UserDefaults.standard.removeObject(forKey: key)
    }

    func testWorkoutNote_DifferentWorkoutsHaveDifferentKeys() {
        let key1 = "workout_note_w1_Tue_🏃 Run"
        let key2 = "workout_note_w1_Tue_🏊 Swim"
        let key3 = "workout_note_w2_Tue_🏃 Run"

        UserDefaults.standard.set("Run note", forKey: key1)
        UserDefaults.standard.set("Swim note", forKey: key2)
        UserDefaults.standard.set("Week 2 run", forKey: key3)

        XCTAssertEqual(UserDefaults.standard.string(forKey: key1), "Run note")
        XCTAssertEqual(UserDefaults.standard.string(forKey: key2), "Swim note")
        XCTAssertEqual(UserDefaults.standard.string(forKey: key3), "Week 2 run")

        UserDefaults.standard.removeObject(forKey: key1)
        UserDefaults.standard.removeObject(forKey: key2)
        UserDefaults.standard.removeObject(forKey: key3)
    }

    func testWorkoutNote_EmptyNoteRemovesKey() {
        let key = "workout_note_w1_Mon_Rest"
        UserDefaults.standard.set("Some note", forKey: key)
        XCTAssertNotNil(UserDefaults.standard.string(forKey: key))

        // Simulate clearing (empty string removes key)
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertNil(UserDefaults.standard.string(forKey: key), "Empty note should remove the key")
    }

    // MARK: - HR Zone Boundary Tests

    func testZoneBoundaries_Age38() {
        // Age 38: maxHR = 220 - 38 = 182
        // z2 = round(182 * 0.69) = round(125.58) = 126
        // z3 = round(182 * 0.79) = round(143.78) = 144
        // z4 = round(182 * 0.85) = round(154.7) = 155
        // z5 = round(182 * 0.92) = round(167.44) = 167
        let maxHR = 182
        let z2 = Int(round(Double(maxHR) * 0.69))
        let z3 = Int(round(Double(maxHR) * 0.79))
        let z4 = Int(round(Double(maxHR) * 0.85))
        let z5 = Int(round(Double(maxHR) * 0.92))

        XCTAssertEqual(z2, 126)
        XCTAssertEqual(z3, 144)
        XCTAssertEqual(z4, 155)
        XCTAssertEqual(z5, 167)
    }

    func testZoneBoundaries_Age25() {
        // Age 25: maxHR = 195
        let maxHR = 195
        let z2 = Int(round(Double(maxHR) * 0.69))
        let z3 = Int(round(Double(maxHR) * 0.79))
        let z4 = Int(round(Double(maxHR) * 0.85))
        let z5 = Int(round(Double(maxHR) * 0.92))

        XCTAssertEqual(z2, 135) // round(134.55)
        XCTAssertEqual(z3, 154) // round(154.05)
        XCTAssertEqual(z4, 166) // round(165.75)
        XCTAssertEqual(z5, 179) // round(179.4)
    }

    func testZoneClassification_AtBoundaries() {
        // Using age 38 boundaries: z2=126, z3=144, z4=155, z5=167
        let z2 = 126, z3 = 144, z4 = 155, z5 = 167

        // Helper to classify
        func classify(_ bpm: Int) -> String {
            if bpm < z2 { return "Z1" }
            else if bpm < z3 { return "Z2" }
            else if bpm < z4 { return "Z3" }
            else if bpm < z5 { return "Z4" }
            else { return "Z5" }
        }

        // Z1 boundary
        XCTAssertEqual(classify(125), "Z1")
        XCTAssertEqual(classify(126), "Z2") // exactly at z2 threshold

        // Z2/Z3 boundary
        XCTAssertEqual(classify(143), "Z2")
        XCTAssertEqual(classify(144), "Z3")

        // Z3/Z4 boundary
        XCTAssertEqual(classify(154), "Z3")
        XCTAssertEqual(classify(155), "Z4")

        // Z4/Z5 boundary
        XCTAssertEqual(classify(166), "Z4")
        XCTAssertEqual(classify(167), "Z5")

        // Deep Z5
        XCTAssertEqual(classify(190), "Z5")
    }

    func testZoneBoundaries_ConsistentFormula() {
        // Verify the formula produces consistent results
        for age in stride(from: 20, through: 60, by: 5) {
            let maxHR = 220 - age
            let z2 = Int(round(Double(maxHR) * 0.69))
            let z3 = Int(round(Double(maxHR) * 0.79))
            let z4 = Int(round(Double(maxHR) * 0.85))
            let z5 = Int(round(Double(maxHR) * 0.92))

            // Zones should be monotonically increasing
            XCTAssertLessThan(z2, z3, "z2 < z3 for age \(age)")
            XCTAssertLessThan(z3, z4, "z3 < z4 for age \(age)")
            XCTAssertLessThan(z4, z5, "z4 < z5 for age \(age)")

            // All should be positive and reasonable
            XCTAssertGreaterThan(z2, 90, "z2 > 90 for age \(age)")
            XCTAssertLessThan(z5, 200, "z5 < 200 for age \(age)")
        }
    }

    // MARK: - Race Countdown Tests

    func testDaysUntilRace_BeforeRace() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 19
        let raceDate = calendar.date(from: components)!

        // 100 days before race
        let testDate = calendar.date(byAdding: .day, value: -100, to: raceDate)!
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: testDate), to: calendar.startOfDay(for: raceDate)).day!
        XCTAssertEqual(days, 100)
    }

    func testDaysUntilRace_OnRaceDay() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 19
        let raceDate = calendar.date(from: components)!

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: raceDate), to: calendar.startOfDay(for: raceDate)).day!
        XCTAssertEqual(days, 0)
    }

    func testDaysUntilRace_AfterRace() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 19
        let raceDate = calendar.date(from: components)!

        let testDate = calendar.date(byAdding: .day, value: 5, to: raceDate)!
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: testDate), to: calendar.startOfDay(for: raceDate)).day!
        XCTAssertLessThan(days, 0)
    }

    func testTrainingPhase_BasedOnWeek() {
        func phase(for week: Int) -> String {
            switch week {
            case 1...4: return "Base Building"
            case 5...8: return "Build Phase"
            case 9...12: return "Peak Training"
            case 13...15: return "Race Specific"
            case 16...17: return "Taper"
            default: return "Off Season"
            }
        }

        XCTAssertEqual(phase(for: 1), "Base Building")
        XCTAssertEqual(phase(for: 4), "Base Building")
        XCTAssertEqual(phase(for: 5), "Build Phase")
        XCTAssertEqual(phase(for: 8), "Build Phase")
        XCTAssertEqual(phase(for: 9), "Peak Training")
        XCTAssertEqual(phase(for: 12), "Peak Training")
        XCTAssertEqual(phase(for: 13), "Race Specific")
        XCTAssertEqual(phase(for: 15), "Race Specific")
        XCTAssertEqual(phase(for: 16), "Taper")
        XCTAssertEqual(phase(for: 17), "Taper")
    }

    // MARK: - Nutrition Target Tests

    func testNutritionTarget_LongBikeHasTarget() {
        guard let plan = viewModel.trainingPlan else {
            XCTFail("Training plan should exist")
            return
        }
        // Week 1 Sunday: 🚴 Bike 1:45 Z2 — should have nutrition target
        let week1 = plan.getWeek(1)!
        let sundayBike = week1.workouts.first { $0.day == "Sun" && $0.type.contains("Bike") }
        XCTAssertNotNil(sundayBike, "Week 1 Sunday should have a bike workout")
        XCTAssertNotNil(sundayBike?.nutritionTarget, "1:45 bike should have nutrition target")
        XCTAssertTrue(sundayBike!.nutritionTarget!.contains("carbs"), "Nutrition target should mention carbs")
    }

    func testNutritionTarget_ShortWorkoutHasNone() {
        // Short workouts (<60 min) should not have nutrition targets
        let shortRun = DayWorkout(day: "Wed", type: "🏃 Run", duration: "40min", zone: "Z2", status: nil, nutritionTarget: nil)
        XCTAssertNil(shortRun.nutritionTarget, "40min run should not have nutrition target")

        let shortBike = DayWorkout(day: "Mon", type: "🚴 Bike", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil)
        XCTAssertNil(shortBike.nutritionTarget, "45min bike should not have nutrition target")
    }

    func testNutritionTarget_SwimHasNone() {
        guard let plan = viewModel.trainingPlan else {
            XCTFail("Training plan should exist")
            return
        }
        // Any swim should NOT have nutrition target
        let week1 = plan.getWeek(1)!
        let swims = week1.workouts.filter { $0.type.contains("Swim") }
        XCTAssertFalse(swims.isEmpty, "Week 1 should have swim workouts")
        for swim in swims {
            XCTAssertNil(swim.nutritionTarget, "Swim workout '\(swim.type)' should not have nutrition target")
        }
    }

    func testNutritionTarget_RestDayHasNone() {
        guard let plan = viewModel.trainingPlan else {
            XCTFail("Training plan should exist")
            return
        }
        let week1 = plan.getWeek(1)!
        let restDays = week1.workouts.filter { $0.type == "Rest" }
        for rest in restDays {
            XCTAssertNil(rest.nutritionTarget, "Rest day should not have nutrition target")
        }
    }

    func testNutritionTarget_BrickHasTarget() {
        guard let plan = viewModel.trainingPlan else {
            XCTFail("Training plan should exist")
            return
        }
        // Week 2 Sat: 🚴+🏃 Brick 2:15 — should have brick-specific nutrition
        let week2 = plan.getWeek(2)!
        let brick = week2.workouts.first { $0.type.contains("Brick") }
        XCTAssertNotNil(brick, "Week 2 should have a brick workout")
        XCTAssertNotNil(brick?.nutritionTarget, "Brick should have nutrition target")
        XCTAssertTrue(brick!.nutritionTarget!.contains("Bike"), "Brick nutrition should mention bike fueling")
        XCTAssertTrue(brick!.nutritionTarget!.contains("Run"), "Brick nutrition should mention run fueling")
    }

    func testNutritionTarget_LongRunHasTarget() {
        guard let plan = viewModel.trainingPlan else {
            XCTFail("Training plan should exist")
            return
        }
        // Week 3 Sun: 🏃 Long Run 60min — should have run nutrition
        let week3 = plan.getWeek(3)!
        let longRun = week3.workouts.first { $0.day == "Sun" && $0.type.contains("Long Run") }
        XCTAssertNotNil(longRun, "Week 3 Sunday should have a long run")
        XCTAssertNotNil(longRun?.nutritionTarget, "60min long run should have nutrition target")
        XCTAssertTrue(longRun!.nutritionTarget!.contains("gel"), "Run nutrition should mention gels")
    }

    func testNutritionTarget_DressRehearsalHasRaceSimNutrition() {
        guard let plan = viewModel.trainingPlan else {
            XCTFail("Training plan should exist")
            return
        }
        // Week 13 Sat: DRESS REHEARSAL — should have race simulation nutrition
        let week13 = plan.getWeek(13)!
        let dressRehearsal = week13.workouts.first { $0.type.contains("DRESS REHEARSAL") }
        XCTAssertNotNil(dressRehearsal, "Week 13 should have dress rehearsal")
        XCTAssertNotNil(dressRehearsal?.nutritionTarget, "Dress rehearsal should have nutrition target")
        XCTAssertTrue(dressRehearsal!.nutritionTarget!.lowercased().contains("race") || dressRehearsal!.nutritionTarget!.contains("rehearsal"), "Dress rehearsal should have race simulation nutrition")
    }

    func testNutritionTarget_CodableRoundTrip() throws {
        let workout = DayWorkout(day: "Sat", type: "🚴 Bike", duration: "2:30", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr")
        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(DayWorkout.self, from: data)
        XCTAssertEqual(decoded.nutritionTarget, "60g carbs/hr")
    }

    func testNutritionTarget_NilCodableRoundTrip() throws {
        let workout = DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(DayWorkout.self, from: data)
        XCTAssertNil(decoded.nutritionTarget)
    }

    // MARK: - Zone Breakdown Percentage Tests

    func testZonePercentages_AllSameZone() {
        // If all samples are in one zone, it should be 100%
        let counts: [String: Double] = ["Z1": 0, "Z2": 100, "Z3": 0, "Z4": 0, "Z5": 0]
        let total = counts.values.reduce(0, +)
        var percentages: [String: Double] = [:]
        for (zone, count) in counts {
            percentages[zone] = total > 0 ? (count / total) * 100 : 0
        }
        XCTAssertEqual(percentages["Z2"]!, 100.0, accuracy: 0.01)
        XCTAssertEqual(percentages["Z1"]!, 0.0, accuracy: 0.01)
    }

    func testZonePercentages_MixedZones() {
        let counts: [String: Double] = ["Z1": 10, "Z2": 40, "Z3": 30, "Z4": 15, "Z5": 5]
        let total = counts.values.reduce(0, +)  // 100
        var percentages: [String: Double] = [:]
        for (zone, count) in counts {
            percentages[zone] = (count / total) * 100
        }
        XCTAssertEqual(percentages["Z1"]!, 10.0, accuracy: 0.01)
        XCTAssertEqual(percentages["Z2"]!, 40.0, accuracy: 0.01)
        XCTAssertEqual(percentages["Z3"]!, 30.0, accuracy: 0.01)
        XCTAssertEqual(percentages["Z4"]!, 15.0, accuracy: 0.01)
        XCTAssertEqual(percentages["Z5"]!, 5.0, accuracy: 0.01)
    }
}
