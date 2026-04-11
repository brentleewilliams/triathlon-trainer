import XCTest
@testable import Race1_Trainer

/// Tests for the tool-calling plan change architecture.
/// Covers all four user-facing operations: drop, swap days, replace workout, and undo.
final class PlanChangeToolTests: XCTestCase {

    var viewModel: ChatViewModel!
    var plan: TrainingPlanManager!

    /// Week 3 has a known mix of workouts used across tests.
    /// Wed: Run + Bike (two workouts — needed for replace tests)
    /// Tue: Swim only
    /// Thu: Run only
    /// Sat: Bike only
    var testWeek: TrainingWeek {
        TrainingWeek(
            weekNumber: 3,
            phase: "Base",
            startDate: Date(),
            endDate: Date(),
            workouts: [
                DayWorkout(day: "Tue", type: "🏊 Swim",  duration: "45min", zone: "Z2",    status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run",   duration: "40min", zone: "Z2",    status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🚴 Bike",  duration: "1:00",  zone: "Z2",    status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🏃 Run",   duration: "50min", zone: "Z3",    status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴 Bike",  duration: "2:00",  zone: "Z2",    status: nil, nutritionTarget: nil),
            ]
        )
    }

    override func setUp() {
        super.setUp()
        viewModel = ChatViewModel(skipHistory: true)
        plan = TrainingPlanManager(useInMemoryStore: true)
        plan.weeks[2] = testWeek   // index 2 = week 3
        viewModel.trainingPlan = plan
    }

    override func tearDown() {
        viewModel = nil
        plan = nil
        super.tearDown()
    }

    // MARK: - Drop (remove entire day)

    func testDrop_removesAllWorkoutsOnDay() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 3, day: "Wed")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(3)!
        XCTAssertTrue(week.workouts.filter { $0.day == "Wed" }.isEmpty,
                      "Drop should remove all Wed workouts (Run + Bike)")
    }

    func testDrop_leavesOtherDaysUntouched() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 3, day: "Wed")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(3)!
        XCTAssertFalse(week.workouts.filter { $0.day == "Tue" }.isEmpty, "Tue should be untouched")
        XCTAssertFalse(week.workouts.filter { $0.day == "Thu" }.isEmpty, "Thu should be untouched")
        XCTAssertFalse(week.workouts.filter { $0.day == "Sat" }.isEmpty, "Sat should be untouched")
    }

    func testDrop_emptyDay_skipped() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 3, day: "Mon") // no workouts on Mon
        ])
        viewModel.executePlanChanges(proposal)

        let lastMsg = viewModel.messages.last!
        XCTAssertTrue(lastMsg.text.contains("Skipped"), "Dropping an empty day should be skipped")
    }

    func testDrop_multipleDrops_allApplied() {
        // Illness scenario: drop Tue, Wed, Thu
        let proposal = makeProposal(summary: "Illness rest Tue-Thu", changes: [
            PlanChange(action: .drop, week: 3, day: "Tue"),
            PlanChange(action: .drop, week: 3, day: "Wed"),
            PlanChange(action: .drop, week: 3, day: "Thu"),
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(3)!
        XCTAssertTrue(week.workouts.filter { $0.day == "Tue" }.isEmpty)
        XCTAssertTrue(week.workouts.filter { $0.day == "Wed" }.isEmpty)
        XCTAssertTrue(week.workouts.filter { $0.day == "Thu" }.isEmpty)
        XCTAssertFalse(week.workouts.filter { $0.day == "Sat" }.isEmpty, "Sat untouched")

        let lastMsg = viewModel.messages.last!
        XCTAssertTrue(lastMsg.text.contains("Applied 3"))
    }

    // MARK: - Swap days

    func testSwapDays_exchangesAllWorkouts() {
        // Swap Wed (Run + Bike) with Tue (Swim)
        let proposal = makeProposal(changes: [
            PlanChange(action: .swap, week: 3, fromDay: "Wed", toDay: "Tue")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(3)!
        // Tue should now have Run + Bike
        let tueSports = week.workouts.filter { $0.day == "Tue" }.map { $0.type }
        XCTAssertTrue(tueSports.contains("🏃 Run"), "Tue should have Run after swap")
        XCTAssertTrue(tueSports.contains("🚴 Bike"), "Tue should have Bike after swap")
        // Wed should now have Swim
        let wedSports = week.workouts.filter { $0.day == "Wed" }.map { $0.type }
        XCTAssertEqual(wedSports, ["🏊 Swim"], "Wed should have only Swim after swap")
    }

    func testSwapDays_workoutDetailsPreserved() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .swap, week: 3, fromDay: "Thu", toDay: "Sat")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(3)!
        // Thu had Run 50min Z3 → should now be on Sat
        let satRun = week.workouts.first { $0.day == "Sat" && $0.type == "🏃 Run" }
        XCTAssertNotNil(satRun, "Run should be on Sat after swap")
        XCTAssertEqual(satRun?.duration, "50min")
        XCTAssertEqual(satRun?.zone, "Z3")
    }

    func testSwapDays_missingFields_skipped() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .swap, week: 3) // no fromDay/toDay
        ])
        viewModel.executePlanChanges(proposal)

        let lastMsg = viewModel.messages.last!
        XCTAssertTrue(lastMsg.text.contains("Skipped"))
    }

    // MARK: - Replace workout (swap one workout for another on a multi-workout day)

    func testReplace_swapsRunForSwim_leavingBikeIntact() {
        // Wed has Run + Bike. Replace Run with Swim.
        let proposal = makeProposal(changes: [
            PlanChange(action: .replace, week: 3, day: "Wed", type: "🏊 Swim", duration: "45min", zone: "Z1-Z2", fromType: "Run")
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(3)!
        let wedWorkouts = week.workouts.filter { $0.day == "Wed" }
        // Swim should be there now
        XCTAssertTrue(wedWorkouts.contains { $0.type == "🏊 Swim" }, "Swim should replace Run on Wed")
        // Bike should still be there
        XCTAssertTrue(wedWorkouts.contains { $0.type == "🚴 Bike" }, "Bike should remain on Wed")
        // Run should be gone
        XCTAssertFalse(wedWorkouts.contains { $0.type == "🏃 Run" }, "Run should be removed on Wed")
    }

    func testReplace_keywordVariants_fuzzyMatch() {
        // LLM might say "run", "running", or "🏃 Run" — all should match
        for variant in ["run", "running", "🏃 Run", "Run"] {
            plan.weeks[2] = testWeek // reset
            let proposal = makeProposal(changes: [
                PlanChange(action: .replace, week: 3, day: "Wed", type: "🏊 Swim", fromType: variant)
            ])
            viewModel.executePlanChanges(proposal)

            let week = plan.getWeek(3)!
            let wedWorkouts = week.workouts.filter { $0.day == "Wed" }
            XCTAssertFalse(wedWorkouts.contains { $0.type == "🏃 Run" },
                           "'\(variant)' should fuzzy-match and remove 🏃 Run")
            XCTAssertTrue(wedWorkouts.contains { $0.type == "🚴 Bike" },
                          "Bike should be untouched after replacing run with '\(variant)'")
        }
    }

    func testReplace_preservesDurationAndZoneFromOriginal_whenNotProvided() {
        // Replace with no duration/zone → should inherit from the original workout
        let proposal = makeProposal(changes: [
            PlanChange(action: .replace, week: 3, day: "Thu", type: "🏊 Swim", fromType: "Run")
            // no duration/zone provided
        ])
        viewModel.executePlanChanges(proposal)

        let week = plan.getWeek(3)!
        let swim = week.workouts.first { $0.day == "Thu" && $0.type == "🏊 Swim" }
        XCTAssertNotNil(swim)
        XCTAssertEqual(swim?.duration, "50min", "Should inherit original run duration")
        XCTAssertEqual(swim?.zone, "Z3", "Should inherit original run zone")
    }

    func testReplace_noMatchingWorkout_skipped() {
        // Wed has Run + Bike, not Yoga
        let proposal = makeProposal(changes: [
            PlanChange(action: .replace, week: 3, day: "Wed", type: "🏊 Swim", fromType: "Yoga")
        ])
        viewModel.executePlanChanges(proposal)

        let lastMsg = viewModel.messages.last!
        XCTAssertTrue(lastMsg.text.contains("Skipped"))
        // Wed should be unchanged
        let week = plan.getWeek(3)!
        XCTAssertEqual(week.workouts.filter { $0.day == "Wed" }.count, 2)
    }

    func testReplace_missingFields_skipped() {
        let proposal = makeProposal(changes: [
            PlanChange(action: .replace, week: 3, day: "Wed", type: "🏊 Swim") // no fromType
        ])
        viewModel.executePlanChanges(proposal)

        let lastMsg = viewModel.messages.last!
        XCTAssertTrue(lastMsg.text.contains("Skipped"))
    }

    // MARK: - Undo (rollback to previous version)

    func testUndo_restoresPreviousPlan() {
        // Apply a change so there's a previous version to roll back to
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 3, day: "Tue")
        ])
        viewModel.executePlanChanges(proposal)

        // Confirm Tue is gone
        XCTAssertTrue(plan.getWeek(3)!.workouts.filter { $0.day == "Tue" }.isEmpty)

        // Rollback
        let success = plan.rollbackToPreviousVersion()
        XCTAssertTrue(success, "Rollback should succeed when a previous version exists")

        // Tue should be restored
        let tuAfter = plan.getWeek(3)!.workouts.filter { $0.day == "Tue" }
        XCTAssertFalse(tuAfter.isEmpty, "Rollback should restore Tue workouts")
    }

    func testUndo_clearsUndoStack_afterRollback() {
        let proposal = makeProposal(changes: [PlanChange(action: .drop, week: 3, day: "Tue")])
        viewModel.executePlanChanges(proposal)

        plan.rollbackToPreviousVersion()

        // Second rollback should fail — no more history
        let secondRollback = plan.rollbackToPreviousVersion()
        XCTAssertFalse(secondRollback, "Second rollback should fail — only single-step undo supported")
        XCTAssertNil(plan.previousPlanVersion, "previousPlanVersion should be nil after rollback")
    }

    func testUndo_noHistory_returnsFalse() {
        // No changes applied — nothing to roll back
        let success = plan.rollbackToPreviousVersion()
        XCTAssertFalse(success)
    }

    // MARK: - Persistence (Core Data round-trip)

    func testPersistence_changesRestoredAfterReload() {
        // Apply a drop — none of the remaining workouts have nutritionTarget set,
        // which previously triggered the stale-data guard and silently discarded
        // all saved changes on next launch.
        let proposal = makeProposal(changes: [
            PlanChange(action: .drop, week: 3, day: "Tue")
        ])
        viewModel.executePlanChanges(proposal)

        XCTAssertTrue(plan.getWeek(3)!.workouts.filter { $0.day == "Tue" }.isEmpty,
                      "Precondition: Tue should be dropped")

        // Simulate app relaunch: create a fresh manager using the same in-memory store
        // and call loadPlanVersions to restore from Core Data.
        plan.loadPlanVersions()

        let tuAfterReload = plan.getWeek(3)!.workouts.filter { $0.day == "Tue" }
        XCTAssertTrue(tuAfterReload.isEmpty,
                      "Drop should survive a loadPlanVersions call (Core Data round-trip)")
    }

    func testPersistence_noNutritionTargets_stillRestored() {
        // All workouts in testWeek have nutritionTarget = nil.
        // Confirm the plan still restores correctly — the old stale-data guard
        // would have thrown this away and reset to hardcoded defaults.
        plan.savePlanVersion(source: "test", description: "All nil nutritionTargets")
        plan.loadPlanVersions()

        let week = plan.getWeek(3)!
        XCTAssertFalse(week.workouts.isEmpty, "Plan should restore even when no workouts have nutritionTarget")
        XCTAssertEqual(week.workouts.count, testWeek.workouts.count)
    }

    // MARK: - workoutTypeMatches helper

    func testTypeMatches_exactType() {
        XCTAssertTrue(viewModel.workoutTypeMatches("🏃 Run", keyword: "🏃 Run"))
        XCTAssertTrue(viewModel.workoutTypeMatches("🚴 Bike", keyword: "🚴 Bike"))
        XCTAssertTrue(viewModel.workoutTypeMatches("🏊 Swim", keyword: "🏊 Swim"))
    }

    func testTypeMatches_caseInsensitive() {
        XCTAssertTrue(viewModel.workoutTypeMatches("🏃 Run", keyword: "run"))
        XCTAssertTrue(viewModel.workoutTypeMatches("🏃 Run", keyword: "RUN"))
        XCTAssertTrue(viewModel.workoutTypeMatches("🚴 Bike", keyword: "bike"))
    }

    func testTypeMatches_aliases() {
        XCTAssertTrue(viewModel.workoutTypeMatches("🚴 Bike", keyword: "cycling"))
        XCTAssertTrue(viewModel.workoutTypeMatches("🚴 Bike", keyword: "ride"))
        XCTAssertTrue(viewModel.workoutTypeMatches("🏃 Run", keyword: "running"))
        XCTAssertTrue(viewModel.workoutTypeMatches("🏊 Swim", keyword: "swimming"))
    }

    func testTypeMatches_noMatch() {
        XCTAssertFalse(viewModel.workoutTypeMatches("🏃 Run", keyword: "swim"))
        XCTAssertFalse(viewModel.workoutTypeMatches("🚴 Bike", keyword: "yoga"))
    }

    // MARK: - Helpers

    private func makeProposal(summary: String = "Test change", changes: [PlanChange]) -> PlanChangeProposal {
        PlanChangeProposal(id: UUID(), summary: summary, changes: changes)
    }
}
