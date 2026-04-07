import XCTest
@testable import IronmanTrainer

@MainActor
final class TemplateSelectionTests: XCTestCase {

    var viewModel: OnboardingViewModel!

    override func setUp() {
        super.setUp()
        viewModel = OnboardingViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Helper

    /// Creates a RaceSearchResult with the given type and distances.
    private func makeRace(
        name: String = "Test Race",
        type: String,
        distances: [String: Double],
        date: Date? = nil
    ) -> RaceSearchResult {
        RaceSearchResult(
            name: name,
            date: date ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())!,
            location: "Test Location",
            type: type,
            distances: distances,
            courseType: "road",
            elevationGainM: nil,
            elevationAtVenueM: nil,
            historicalWeather: nil
        )
    }

    // MARK: - classifyRaceForTemplate() — Triathlon

    func testClassify_SprintTriathlon() {
        // Total distance < 20 miles → sprint
        viewModel.raceSearchResult = makeRace(
            type: "triathlon",
            distances: ["swim": 0.5, "bike": 12.4, "run": 3.1] // ~16 miles
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "triathlon")
        XCTAssertEqual(result?.subtype, "sprint")
    }

    func testClassify_OlympicTriathlon() {
        // Total distance 20–40 miles → olympic
        viewModel.raceSearchResult = makeRace(
            type: "triathlon",
            distances: ["swim": 0.93, "bike": 24.8, "run": 6.2] // ~31.9 miles
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "triathlon")
        XCTAssertEqual(result?.subtype, "olympic")
    }

    func testClassify_HalfIronTriathlon() {
        // Total distance 40–80 miles → 70.3
        viewModel.raceSearchResult = makeRace(
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1] // ~70.3 miles
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "triathlon")
        XCTAssertEqual(result?.subtype, "70.3")
    }

    func testClassify_FullIronmanTriathlon() {
        // Total distance >= 80 miles → 140.6
        viewModel.raceSearchResult = makeRace(
            type: "triathlon",
            distances: ["swim": 2.4, "bike": 112.0, "run": 26.2] // ~140.6 miles
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "triathlon")
        XCTAssertEqual(result?.subtype, "140.6")
    }

    func testClassify_TriathlonDetectedByDistances() {
        // Even without "triathlon" type, having swim+bike+run triggers triathlon classification
        viewModel.raceSearchResult = makeRace(
            type: "multisport",
            distances: ["swim": 0.5, "bike": 12.4, "run": 3.1]
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "triathlon")
        XCTAssertEqual(result?.subtype, "sprint")
    }

    // MARK: - classifyRaceForTemplate() — Running

    func testClassify_5kRun() {
        // Run distance < 4 miles → 5k
        viewModel.raceSearchResult = makeRace(
            type: "running",
            distances: ["run": 3.1]
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "running")
        XCTAssertEqual(result?.subtype, "5k")
    }

    func testClassify_10kRun() {
        // Run distance 4–8 miles → 10k
        viewModel.raceSearchResult = makeRace(
            type: "running",
            distances: ["run": 6.2]
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "running")
        XCTAssertEqual(result?.subtype, "10k")
    }

    func testClassify_HalfMarathon() {
        // Run distance 8–15 miles → half
        viewModel.raceSearchResult = makeRace(
            type: "running",
            distances: ["run": 13.1]
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "running")
        XCTAssertEqual(result?.subtype, "half")
    }

    func testClassify_Marathon() {
        // Run distance >= 15 miles → marathon
        viewModel.raceSearchResult = makeRace(
            type: "running",
            distances: ["run": 26.2]
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "running")
        XCTAssertEqual(result?.subtype, "marathon")
    }

    func testClassify_RunDetectedByDistancesOnly() {
        // Only "run" distance present, no swim/bike → running classification
        viewModel.raceSearchResult = makeRace(
            type: "race",
            distances: ["run": 6.2]
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, "running")
        XCTAssertEqual(result?.subtype, "10k")
    }

    // MARK: - classifyRaceForTemplate() — Returns nil

    func testClassify_CyclingRace_ReturnsNil() {
        viewModel.raceSearchResult = makeRace(
            type: "cycling",
            distances: ["bike": 100.0]
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNil(result, "Cycling races should return nil (custom fallback)")
    }

    func testClassify_SwimmingRace_ReturnsNil() {
        viewModel.raceSearchResult = makeRace(
            type: "swimming",
            distances: ["swim": 2.4]
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNil(result, "Swimming races should return nil (custom fallback)")
    }

    func testClassify_UnknownRaceType_ReturnsNil() {
        viewModel.raceSearchResult = makeRace(
            type: "obstacle course",
            distances: ["obstacle": 5.0]
        )
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNil(result, "Unknown race types should return nil (custom fallback)")
    }

    func testClassify_NoRaceSearchResult_ReturnsNil() {
        viewModel.raceSearchResult = nil
        let result = viewModel.classifyRaceForTemplate()
        XCTAssertNil(result)
    }

    // MARK: - validateGoal() — No warning

    func testValidateGoal_TimeTargetWithinRange_NoWarning() {
        // Set up a 70.3 triathlon (finishTimeHourRange 4...9)
        viewModel.raceSearchResult = makeRace(
            name: "IRONMAN 70.3 Test",
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            date: Calendar.current.date(byAdding: .month, value: 4, to: Date())
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 5
        viewModel.targetMinutes = 30

        viewModel.validateGoal()

        XCTAssertNil(viewModel.goalValidationWarning, "Time goal within range should produce no warning")
    }

    func testValidateGoal_JustComplete_NoWarning() {
        viewModel.raceSearchResult = makeRace(
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1]
        )
        viewModel.goalType = .justComplete

        viewModel.validateGoal()

        XCTAssertNil(viewModel.goalValidationWarning, "Just complete goal should have no warning")
    }

    func testValidateGoal_Custom_NoWarning() {
        viewModel.raceSearchResult = makeRace(
            type: "running",
            distances: ["run": 26.2]
        )
        viewModel.goalType = .custom

        viewModel.validateGoal()

        XCTAssertNil(viewModel.goalValidationWarning, "Custom goal should have no warning (validated server-side)")
    }

    // MARK: - validateGoal() — Warning set

    func testValidateGoal_TimeTargetFasterThanMinimum_WarningSet() {
        // 70.3 triathlon: finishTimeHourRange lower bound is 4 hours
        viewModel.raceSearchResult = makeRace(
            name: "IRONMAN 70.3 Test",
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            date: Calendar.current.date(byAdding: .month, value: 3, to: Date())
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 3
        viewModel.targetMinutes = 30

        viewModel.validateGoal()

        XCTAssertNotNil(viewModel.goalValidationWarning, "Time target below minimum should produce a warning")
        XCTAssertTrue(viewModel.goalValidationWarning?.contains("ambitious") == true)
    }

    func testValidateGoal_MarathonUnder2Hours_WarningSet() {
        // Marathon: finishTimeHourRange lower bound is 2 hours
        viewModel.raceSearchResult = makeRace(
            type: "running",
            distances: ["run": 26.2],
            date: Calendar.current.date(byAdding: .month, value: 3, to: Date())
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 1
        viewModel.targetMinutes = 45

        viewModel.validateGoal()

        XCTAssertNotNil(viewModel.goalValidationWarning, "Marathon goal under 2 hours should produce a warning")
    }

    func testValidateGoal_ClearsWarningWhenGoalTypeChanges() {
        // First set an ambitious time target
        viewModel.raceSearchResult = makeRace(
            name: "IRONMAN 70.3 Test",
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            date: Calendar.current.date(byAdding: .month, value: 3, to: Date())
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 3
        viewModel.targetMinutes = 0
        viewModel.validateGoal()
        XCTAssertNotNil(viewModel.goalValidationWarning)

        // Then switch to justComplete — warning should clear
        viewModel.goalType = .justComplete
        viewModel.validateGoal()
        XCTAssertNil(viewModel.goalValidationWarning, "Warning should clear when switching away from timeTarget")
    }

    // MARK: - SchedulePattern Tests

    func testSchedulePattern_AllCasesHaveNonEmptyLabel() {
        for pattern in SchedulePattern.allCases {
            XCTAssertFalse(pattern.label.isEmpty, "\(pattern.rawValue) should have a non-empty label")
        }
    }

    func testSchedulePattern_AllCasesHaveNonEmptyDescription() {
        for pattern in SchedulePattern.allCases {
            XCTAssertFalse(pattern.description.isEmpty, "\(pattern.rawValue) should have a non-empty description")
        }
    }

    func testSchedulePattern_AllCasesHaveNonEmptyIcon() {
        for pattern in SchedulePattern.allCases {
            XCTAssertFalse(pattern.icon.isEmpty, "\(pattern.rawValue) should have a non-empty icon")
        }
    }

    func testSchedulePattern_RawValues() {
        XCTAssertEqual(SchedulePattern.spread.rawValue, "spread")
        XCTAssertEqual(SchedulePattern.weekendWarrior.rawValue, "weekendWarrior")
        XCTAssertEqual(SchedulePattern.compressed.rawValue, "compressed")
    }

    func testSchedulePattern_CaseCount() {
        XCTAssertEqual(SchedulePattern.allCases.count, 3)
    }
}
