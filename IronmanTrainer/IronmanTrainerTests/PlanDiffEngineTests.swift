import XCTest
@testable import Race1_Trainer

final class PlanDiffEngineTests: XCTestCase {

    // MARK: - Test Fixtures

    private func makeWeek(
        number: Int = 1,
        phase: String = "Base",
        workouts: [DayWorkout]
    ) -> TrainingWeek {
        TrainingWeek(
            weekNumber: number,
            phase: phase,
            startDate: Date(),
            endDate: Date(),
            workouts: workouts
        )
    }

    private func makePlan(weeks: [TrainingWeek]) -> TrainingPlanManager {
        let plan = TrainingPlanManager(useInMemoryStore: true)
        for (i, week) in weeks.enumerated() {
            if i < plan.weeks.count {
                plan.weeks[i] = week
            }
        }
        return plan
    }

    private let baseWorkouts: [DayWorkout] = [
        DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
        DayWorkout(day: "Tue", type: "🏊 Swim", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
        DayWorkout(day: "Wed", type: "🏃 Run", duration: "40min", zone: "Z2", status: nil, nutritionTarget: nil),
        DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: nil),
        DayWorkout(day: "Fri", type: "🏃 Run", duration: "30min", zone: "Z1", status: nil, nutritionTarget: nil),
        DayWorkout(day: "Sat", type: "🚴 Bike", duration: "2:00", zone: "Z2", status: nil, nutritionTarget: nil),
        DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
    ]

    // MARK: - Enrichment per Action Type

    func testEnrich_dropAction_marksDayAsDropped() {
        let week = makeWeek(number: 3, workouts: baseWorkouts)
        let plan = makePlan(weeks: [week, week, week])
        let proposal = PlanChangeProposal(
            id: UUID(),
            summary: "Drop Wed",
            changes: [PlanChange(action: .drop, week: 3, day: "Wed")]
        )

        let enriched = PlanDiffEngine.enrich(proposal, plan: plan)

        let weekDiff = enriched.weekDiffs.first!
        let wedDiff = weekDiff.dayDiffs.first { $0.day == "Wed" }!
        XCTAssertEqual(wedDiff.status, .dropped)
        // Proposed should have no Wed workouts
        XCTAssertTrue(wedDiff.proposedWorkouts.filter { $0.day == "Wed" }.isEmpty)
    }

    func testEnrich_addAction_marksDayAsAdded() {
        let week = makeWeek(number: 1, workouts: baseWorkouts)
        let plan = makePlan(weeks: [week])
        let proposal = PlanChangeProposal(
            id: UUID(),
            summary: "Add Mon swim",
            changes: [PlanChange(action: .add, week: 1, day: "Mon", type: "🏊 Swim", duration: "30min", zone: "Z1")]
        )

        let enriched = PlanDiffEngine.enrich(proposal, plan: plan)
        let monDiff = enriched.weekDiffs.first!.dayDiffs.first { $0.day == "Mon" }!
        XCTAssertEqual(monDiff.status, .added)
        XCTAssertTrue(monDiff.proposedWorkouts.contains { $0.type == "🏊 Swim" })
    }

    func testEnrich_swapAction_marksBothDaysAsSwapped() {
        let week = makeWeek(number: 1, workouts: baseWorkouts)
        let plan = makePlan(weeks: [week])
        let proposal = PlanChangeProposal(
            id: UUID(),
            summary: "Swap Tue and Thu",
            changes: [PlanChange(action: .swap, week: 1, fromDay: "Tue", toDay: "Thu")]
        )

        let enriched = PlanDiffEngine.enrich(proposal, plan: plan)
        let diffs = enriched.weekDiffs.first!.dayDiffs
        XCTAssertEqual(diffs.first { $0.day == "Tue" }!.status, .swapped)
        XCTAssertEqual(diffs.first { $0.day == "Thu" }!.status, .swapped)
    }

    func testEnrich_replaceAction_marksDayAsModified() {
        let week = makeWeek(number: 1, workouts: baseWorkouts)
        let plan = makePlan(weeks: [week])
        let proposal = PlanChangeProposal(
            id: UUID(),
            summary: "Replace Wed run with swim",
            changes: [PlanChange(action: .replace, week: 1, day: "Wed", type: "🏊 Swim", fromType: "Run")]
        )

        let enriched = PlanDiffEngine.enrich(proposal, plan: plan)
        let wedDiff = enriched.weekDiffs.first!.dayDiffs.first { $0.day == "Wed" }!
        XCTAssertEqual(wedDiff.status, .modified)
    }

    // MARK: - Multi-Week Grouping

    func testEnrich_multiWeekChanges_groupsByWeek() {
        let week1 = makeWeek(number: 1, workouts: baseWorkouts)
        let week2 = makeWeek(number: 2, workouts: baseWorkouts)
        let plan = makePlan(weeks: [week1, week2])
        let proposal = PlanChangeProposal(
            id: UUID(),
            summary: "Multi-week adjustment",
            changes: [
                PlanChange(action: .drop, week: 1, day: "Wed"),
                PlanChange(action: .drop, week: 2, day: "Thu"),
            ]
        )

        let enriched = PlanDiffEngine.enrich(proposal, plan: plan)
        XCTAssertEqual(enriched.weekDiffs.count, 2)
        XCTAssertEqual(enriched.weekDiffs[0].weekNumber, 1)
        XCTAssertEqual(enriched.weekDiffs[1].weekNumber, 2)
    }

    // MARK: - Key Session Detection

    func testKeySession_brickIsAlwaysKey() {
        let workout = DayWorkout(day: "Sat", type: "Brick", duration: "2:00", zone: "Z2", status: nil, nutritionTarget: nil)
        XCTAssertTrue(PlanDiffEngine.isKeySession(workout, weekPhase: "Base"))
    }

    func testKeySession_raceSimIsAlwaysKey() {
        let workout = DayWorkout(day: "Sat", type: "Race Sim", duration: "3:00", zone: "Z3", status: nil, nutritionTarget: nil)
        XCTAssertTrue(PlanDiffEngine.isKeySession(workout, weekPhase: "Build"))
    }

    func testKeySession_taperWeek_allWorkoutsAreKey() {
        let workout = DayWorkout(day: "Tue", type: "🏊 Swim", duration: "30min", zone: "Z1", status: nil, nutritionTarget: nil)
        XCTAssertTrue(PlanDiffEngine.isKeySession(workout, weekPhase: "Taper"))
    }

    func testKeySession_raceWeek_allWorkoutsAreKey() {
        let workout = DayWorkout(day: "Mon", type: "🏃 Run", duration: "20min", zone: "Z1", status: nil, nutritionTarget: nil)
        XCTAssertTrue(PlanDiffEngine.isKeySession(workout, weekPhase: "Race Week"))
    }

    func testKeySession_z4IntensityIsKey() {
        let workout = DayWorkout(day: "Wed", type: "🏃 Run", duration: "40min", zone: "Z4", status: nil, nutritionTarget: nil)
        XCTAssertTrue(PlanDiffEngine.isKeySession(workout, weekPhase: "Build"))
    }

    func testKeySession_thresholdIsKey() {
        let workout = DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:00", zone: "Threshold", status: nil, nutritionTarget: nil)
        XCTAssertTrue(PlanDiffEngine.isKeySession(workout, weekPhase: "Base"))
    }

    func testKeySession_longRunIsKey() {
        let workout = DayWorkout(day: "Sat", type: "🏃 Run", duration: "1:30", zone: "Z2", status: nil, nutritionTarget: nil)
        XCTAssertTrue(PlanDiffEngine.isKeySession(workout, weekPhase: "Base"))
    }

    func testKeySession_longBikeIsKey() {
        let workout = DayWorkout(day: "Sat", type: "🚴 Bike", duration: "2:00", zone: "Z2", status: nil, nutritionTarget: nil)
        XCTAssertTrue(PlanDiffEngine.isKeySession(workout, weekPhase: "Base"))
    }

    func testKeySession_longSwimIsKey() {
        let workout = DayWorkout(day: "Sat", type: "🏊 Swim", duration: "1:15", zone: "Z2", status: nil, nutritionTarget: nil)
        XCTAssertTrue(PlanDiffEngine.isKeySession(workout, weekPhase: "Build"))
    }

    func testKeySession_shortSwimIsNotKey() {
        let workout = DayWorkout(day: "Tue", type: "🏊 Swim", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil)
        XCTAssertFalse(PlanDiffEngine.isKeySession(workout, weekPhase: "Base"))
    }

    func testKeySession_restIsNeverKey() {
        let workout = DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
        XCTAssertFalse(PlanDiffEngine.isKeySession(workout, weekPhase: "Taper"))
    }

    // MARK: - Volume Calculation

    func testVolume_dropReducesMinutes() {
        let week = makeWeek(number: 1, workouts: baseWorkouts)
        let plan = makePlan(weeks: [week])
        let proposal = PlanChangeProposal(
            id: UUID(),
            summary: "Drop Wed",
            changes: [PlanChange(action: .drop, week: 1, day: "Wed")]
        )

        let enriched = PlanDiffEngine.enrich(proposal, plan: plan)
        XCTAssertLessThan(enriched.proposedTotalMinutes, enriched.originalTotalMinutes)
    }

    func testVolume_addIncreasesMinutes() {
        let week = makeWeek(number: 1, workouts: baseWorkouts)
        let plan = makePlan(weeks: [week])
        let proposal = PlanChangeProposal(
            id: UUID(),
            summary: "Add Mon swim",
            changes: [PlanChange(action: .add, week: 1, day: "Mon", type: "🏊 Swim", duration: "45min", zone: "Z2")]
        )

        let enriched = PlanDiffEngine.enrich(proposal, plan: plan)
        XCTAssertGreaterThan(enriched.proposedTotalMinutes, enriched.originalTotalMinutes)
    }

    // MARK: - Rationale Passthrough

    func testRationale_passedThroughToDayDiff() {
        let week = makeWeek(number: 1, workouts: baseWorkouts)
        let plan = makePlan(weeks: [week])
        let proposal = PlanChangeProposal(
            id: UUID(),
            summary: "Drop Wed for recovery",
            changes: [PlanChange(action: .drop, week: 1, day: "Wed", rationale: "Allowing extra recovery after hard bike")]
        )

        let enriched = PlanDiffEngine.enrich(proposal, plan: plan)
        let wedDiff = enriched.weekDiffs.first!.dayDiffs.first { $0.day == "Wed" }!
        XCTAssertEqual(wedDiff.rationale, "Allowing extra recovery after hard bike")
    }

    // MARK: - Format Helpers

    func testFormatMinutes_hoursAndMinutes() {
        XCTAssertEqual(PlanDiffEngine.formatMinutes(90), "1h 30m")
        XCTAssertEqual(PlanDiffEngine.formatMinutes(60), "1h")
        XCTAssertEqual(PlanDiffEngine.formatMinutes(45), "45m")
        XCTAssertEqual(PlanDiffEngine.formatMinutes(0), "0m")
    }

    func testFormatVolumeChange_positiveNegativeZero() {
        XCTAssertEqual(PlanDiffEngine.formatVolumeChange(30), "+30m")
        XCTAssertEqual(PlanDiffEngine.formatVolumeChange(-45), "-45m")
        XCTAssertEqual(PlanDiffEngine.formatVolumeChange(0), "no change")
    }

    // MARK: - Simulate Changes

    func testSimulateChanges_doesNotMutateOriginal() {
        let week = makeWeek(number: 1, workouts: baseWorkouts)
        let originalCount = week.workouts.count
        let changes = [PlanChange(action: .drop, week: 1, day: "Wed")]

        let simulated = PlanDiffEngine.simulateChanges(changes, on: week)
        XCTAssertEqual(week.workouts.count, originalCount, "Original week should not be mutated")
        XCTAssertLessThan(simulated.count, originalCount, "Simulated should have fewer workouts after drop")
    }
}
