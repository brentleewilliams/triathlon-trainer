import XCTest
@testable import Race1_Trainer

// PlanChangeTests disabled — these tests cover the old text-based [PLAN_CHANGES] parsing
// and .modify action, both of which have been replaced by the tool-calling architecture.
// TODO: rewrite these tests for the new drop/add/swap tool-based flow.
#if false

final class PlanChangeTests: XCTestCase {

    var viewModel: ChatViewModel!
    var plan: TrainingPlanManager!

    // A minimal week with known workouts used across tests
    let testWeek = TrainingWeek(
        weekNumber: 1,
        phase: "Base",
        startDate: Date(),
        endDate: Date(),
        workouts: [
            DayWorkout(day: "Tue", type: "🏊 Swim", duration: "45min",  zone: "Z2",    status: nil, nutritionTarget: nil),
            DayWorkout(day: "Wed", type: "🚴 Bike", duration: "1:05",   zone: "Z2",    status: nil, nutritionTarget: nil),
            DayWorkout(day: "Wed", type: "🏊 Swim", duration: "31min",  zone: "Z1-Z2", status: nil, nutritionTarget: nil),
            DayWorkout(day: "Thu", type: "🏃 Run",  duration: "45min",  zone: "Z2",    status: nil, nutritionTarget: nil),
            DayWorkout(day: "Sat", type: "🚴 Bike", duration: "1:45",   zone: "Z2",    status: nil, nutritionTarget: nil),
        ]
    )

    override func setUp() {
        super.setUp()
        viewModel = ChatViewModel(skipHistory: true)
        plan = TrainingPlanManager(useInMemoryStore: true)
        // Replace week 1 with our predictable test week
        plan.weeks[0] = testWeek
        viewModel.trainingPlan = plan
    }

    override func tearDown() {
        viewModel = nil
        plan = nil
        super.tearDown()
    }

    // MARK: - parsePlanChanges

    func testParse_completePlanChangesBlock() {
        let response = """
        I'll drop the swim on Tuesday.
        [PLAN_CHANGES]
        {"id":"11111111-0000-0000-0000-000000000000","summary":"Drop Tue swim","changes":[
          {"action":"drop","week":1,"day":"Tue","type":"🏊 Swim"}
        ]}
        [/PLAN_CHANGES]
        Rest up!
        """
        let proposal = viewModel.parsePlanChanges(from: response)
        XCTAssertNotNil(proposal)
        XCTAssertEqual(proposal?.changes.count, 1)
        XCTAssertEqual(proposal?.changes.first?.action, .drop)
        XCTAssertEqual(proposal?.changes.first?.day, "Tue")
        XCTAssertEqual(proposal?.changes.first?.type, "🏊 Swim")
    }

    func testParse_truncatedResponse_recoversCompleteChanges() {
        // Closing tag is missing — simulates a cut-off LLM response
        let response = """
        Dropping your workouts for recovery.
        [PLAN_CHANGES]
        {"id":"22222222-0000-0000-0000-000000000000","summary":"Illness rest","changes":[
          {"action":"drop","week":1,"day":"Tue","type":"🏊 Swim"},
          {"action":"drop","week":1,"day":"Wed","type":"🚴 Bike"}
        ]}
        """
        let proposal = viewModel.parsePlanChanges(from: response)
        XCTAssertNotNil(proposal, "Should recover proposal from truncated response")
        XCTAssertEqual(proposal?.changes.count, 2)
    }

    func testParse_truncatedResponse_partialChanges() {
        // Response cut off mid-way through the changes array
        let response = """
        [PLAN_CHANGES]
        {"id":"33333333-0000-0000-0000-000000000000","summary":"Partial","changes":[
          {"action":"drop","week":1,"day":"Tue","type":"🏊 Swim"},
          {"action":"drop","week":1,"day":"Wed","type":"🚴 Bike
        """
        // Should recover at least the first complete change
        let proposal = viewModel.parsePlanChanges(from: response)
        XCTAssertNotNil(proposal, "Should recover at least partial proposal")
        if let proposal {
            XCTAssertGreaterThanOrEqual(proposal.changes.count, 1)
        }
    }

    func testParse_noPlanChangesTag_returnsNil() {
        let response = "I think you should rest on Tuesday. Stay healthy!"
        XCTAssertNil(viewModel.parsePlanChanges(from: response))
    }

    func testParse_multipleActions() {
        let response = """
        [PLAN_CHANGES]
        {"id":"44444444-0000-0000-0000-000000000000","summary":"Mixed changes","changes":[
          {"action":"drop","week":1,"day":"Tue","type":"🏊 Swim"},
          {"action":"add","week":1,"day":"Fri","type":"🧘 Yoga","duration":"30min","zone":"Z1"},
          {"action":"modify","week":1,"day":"Thu","type":"🏃 Run","field":"duration","from":"45min","to":"30min"}
        ]}
        [/PLAN_CHANGES]
        """
        let proposal = viewModel.parsePlanChanges(from: response)
        XCTAssertEqual(proposal?.changes.count, 3)
        XCTAssertEqual(proposal?.changes[0].action, .drop)
        XCTAssertEqual(proposal?.changes[1].action, .add)
        XCTAssertEqual(proposal?.changes[2].action, .modify)
    }

    // MARK: - stripPlanChangesBlock

    func testStrip_removesBlockLeavesText() {
        let response = """
        I'll drop the swim.
        [PLAN_CHANGES]
        {"id":"abc","summary":"x","changes":[]}
        [/PLAN_CHANGES]
        Feel better soon!
        """
        let stripped = viewModel.stripPlanChangesBlock(from: response)
        XCTAssertTrue(stripped.contains("I'll drop the swim."))
        XCTAssertTrue(stripped.contains("Feel better soon!"))
        XCTAssertFalse(stripped.contains("[PLAN_CHANGES]"))
        XCTAssertFalse(stripped.contains("PLAN_CHANGES"))
    }

    func testStrip_truncatedBlock_removesFromTagOnward() {
        let response = "Here are the changes:\n[PLAN_CHANGES]\n{\"id\":\"x\",\"summary\""
        let stripped = viewModel.stripPlanChangesBlock(from: response)
        XCTAssertTrue(stripped.contains("Here are the changes:"))
        XCTAssertFalse(stripped.contains("[PLAN_CHANGES]"))
    }

    // MARK: - executePlanChanges — drop

    func testExecute_drop_exactTypeMatch() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 1, day: "Tue", type: "🏊 Swim")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(1)!
        XCTAssertFalse(week.workouts.contains { $0.day == "Tue" && $0.type == "🏊 Swim" })
        // Other days untouched
        XCTAssertEqual(week.workouts.filter { $0.day == "Wed" }.count, 2)
    }

    func testExecute_drop_fuzzyTypeMatch_emojiVariant() {
        // Claude generates "Swim" (no emoji) — fuzzy keyword match should still find "🏊 Swim"
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 1, day: "Tue", type: "Swim")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(1)!
        XCTAssertFalse(week.workouts.contains { $0.day == "Tue" && $0.type.lowercased().contains("swim") },
                       "Fuzzy match should have removed the swim on Tue")
    }

    func testExecute_drop_multipleWorkoutsOnDay_onlyDropsMatched() {
        // Wed has Bike + Swim; dropping Bike should leave Swim intact
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 1, day: "Wed", type: "🚴 Bike")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(1)!
        XCTAssertFalse(week.workouts.contains { $0.day == "Wed" && $0.type == "🚴 Bike" })
        XCTAssertTrue(week.workouts.contains { $0.day == "Wed" && $0.type == "🏊 Swim" })
    }

    func testExecute_drop_wrongDay_skipped() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 1, day: "Mon", type: "🏊 Swim") // no workout on Mon
        ])
        viewModel.executePlanChanges(proposal)

        // Confirm message should say 0 applied, not crash
        let lastMsg = viewModel.messages.last
        XCTAssertNotNil(lastMsg)
        XCTAssertTrue(lastMsg!.text.contains("Skipped"))
    }

    func testExecute_drop_wrongWeek_skipped() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 99, day: "Tue", type: "🏊 Swim") // week 99 doesn't exist
        ])
        viewModel.executePlanChanges(proposal)

        let lastMsg = viewModel.messages.last!
        XCTAssertTrue(lastMsg.text.contains("Skipped"))
    }

    func testExecute_drop_illnessDays_allThreeDays() {
        // Reproduce the exact scenario from the bug report: drop Tue swim, Wed bike, Wed swim, Thu run
        let proposal = makeProposal(summary: "Illness: rest Tue-Thu", changes: [
            PlanChange(action: .drop, week: 1, day: "Tue", type: "🏊 Swim"),
            PlanChange(action: .drop, week: 1, day: "Wed", type: "🚴 Bike"),
            PlanChange(action: .drop, week: 1, day: "Wed", type: "🏊 Swim"),
            PlanChange(action: .drop, week: 1, day: "Thu", type: "🏃 Run"),
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(1)!
        XCTAssertTrue(week.workouts.filter { $0.day == "Tue" }.isEmpty)
        XCTAssertTrue(week.workouts.filter { $0.day == "Wed" }.isEmpty)
        XCTAssertTrue(week.workouts.filter { $0.day == "Thu" }.isEmpty)
        // Saturday untouched
        XCTAssertFalse(week.workouts.filter { $0.day == "Sat" }.isEmpty)

        let lastMsg = viewModel.messages.last!
        XCTAssertTrue(lastMsg.text.contains("Applied 4"))
    }

    // MARK: - executePlanChanges — add

    func testExecute_add_appendsWorkout() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .add, week: 1, day: "Mon", type: "🧘 Yoga", duration: "30min", zone: "Z1")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(1)!
        XCTAssertTrue(week.workouts.contains { $0.day == "Mon" && $0.type == "🧘 Yoga" })
    }

    func testExecute_add_missingType_skipped() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .add, week: 1, day: "Mon", type: nil) // type required for add
        ])
        viewModel.executePlanChanges(proposal)

        let lastMsg = viewModel.messages.last!
        XCTAssertTrue(lastMsg.text.contains("Skipped"))
    }

    // MARK: - executePlanChanges — modify

    func testExecute_modify_duration() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .modify, week: 1, day: "Thu", type: "🏃 Run", field: "duration", from: "45min", to: "30min")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(1)!
        let run = week.workouts.first { $0.day == "Thu" && $0.type == "🏃 Run" }
        XCTAssertEqual(run?.duration, "30min")
    }

    func testExecute_modify_zone() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .modify, week: 1, day: "Sat", type: "🚴 Bike", field: "zone", from: "Z2", to: "Z3")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(1)!
        let bike = week.workouts.first { $0.day == "Sat" && $0.type == "🚴 Bike" }
        XCTAssertEqual(bike?.zone, "Z3")
    }

    func testExecute_modify_notFound_skipped() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .modify, week: 1, day: "Mon", type: "🏃 Run", field: "duration", from: "45min", to: "30min")
        ])
        viewModel.executePlanChanges(proposal)

        let lastMsg = viewModel.messages.last!
        XCTAssertTrue(lastMsg.text.contains("Skipped"))
    }

    // MARK: - activityKeyword (via fuzzy drop behaviour)

    func testFuzzy_bikeVariants_allMatch() {
        for variant in ["🚴 Bike", "Bike", "bike", "cycling", "Cycling"] {
            plan.weeks[0] = testWeek  // reset
            let proposal = makeProposal(changes: [
                PlanChange(action: .drop, week: 1, day: "Wed", type: variant)
            ])
            viewModel.executePlanChanges(proposal)
            let week = plan.getWeek(1)!
            XCTAssertFalse(week.workouts.contains { $0.day == "Wed" && $0.type == "🚴 Bike" },
                           "'\(variant)' should have matched 🚴 Bike via fuzzy keyword")
            plan.weeks[0] = testWeek  // reset for next iteration
        }
    }

    func testFuzzy_swimVariants_allMatch() {
        for variant in ["🏊 Swim", "Swim", "swim"] {
            plan.weeks[0] = testWeek
            let proposal = makeProposal(changes: [
                PlanChange(action: .drop, week: 1, day: "Tue", type: variant)
            ])
            viewModel.executePlanChanges(proposal)
            let week = plan.getWeek(1)!
            XCTAssertFalse(week.workouts.contains { $0.day == "Tue" && $0.type.lowercased().contains("swim") },
                           "'\(variant)' should have matched via fuzzy keyword")
            plan.weeks[0] = testWeek
        }
    }

    // MARK: - Helpers

    private func makeProposal(summary: String = "Test change", changes: [PlanChange]) -> PlanChangeProposal {
        PlanChangeProposal(id: UUID(), summary: summary, changes: changes)
    }
}

#endif // PlanChangeTests disabled
