import XCTest
@testable import IronmanTrainer

// MARK: - UserProfile Tests

final class UserProfileTests: XCTestCase {

    func testEmptyProfileCreation() {
        let profile = UserProfile.empty(uid: "test-uid-123")
        XCTAssertEqual(profile.uid, "test-uid-123")
        XCTAssertEqual(profile.name, "")
        XCTAssertFalse(profile.onboardingComplete)
        XCTAssertNil(profile.dateOfBirth)
        XCTAssertNil(profile.biologicalSex)
        XCTAssertNil(profile.heightCm)
        XCTAssertNil(profile.weightKg)
        XCTAssertNil(profile.restingHR)
        XCTAssertNil(profile.vo2Max)
        XCTAssertNil(profile.homeZip)
    }

    func testUserProfileCodable() throws {
        let profile = UserProfile(
            uid: "uid-1",
            name: "Brent",
            dateOfBirth: Date(timeIntervalSince1970: 600000000),
            biologicalSex: "male",
            heightCm: 180.0,
            weightKg: 75.0,
            restingHR: 55,
            vo2Max: 57.8,
            homeZip: "80202",
            homeElevationM: 1609.0,
            onboardingComplete: true,
            createdAt: Date(timeIntervalSince1970: 1700000000)
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded.uid, "uid-1")
        XCTAssertEqual(decoded.name, "Brent")
        XCTAssertEqual(decoded.biologicalSex, "male")
        XCTAssertEqual(decoded.heightCm, 180.0)
        XCTAssertEqual(decoded.weightKg, 75.0)
        XCTAssertEqual(decoded.restingHR, 55)
        XCTAssertEqual(decoded.vo2Max, 57.8)
        XCTAssertEqual(decoded.homeZip, "80202")
        XCTAssertEqual(decoded.homeElevationM, 1609.0)
        XCTAssertTrue(decoded.onboardingComplete)
    }
}

// MARK: - GoalType Tests

final class GoalTypeTests: XCTestCase {

    func testTimeTargetCodable() throws {
        let goal = GoalType.timeTarget(21600) // 6 hours
        let data = try JSONEncoder().encode(goal)
        let decoded = try JSONDecoder().decode(GoalType.self, from: data)

        if case .timeTarget(let seconds) = decoded {
            XCTAssertEqual(seconds, 21600)
        } else {
            XCTFail("Expected .timeTarget")
        }
    }

    func testJustCompleteCodable() throws {
        let goal = GoalType.justComplete
        let data = try JSONEncoder().encode(goal)
        let decoded = try JSONDecoder().decode(GoalType.self, from: data)

        if case .justComplete = decoded {
            // pass
        } else {
            XCTFail("Expected .justComplete")
        }
    }

    func testGoalTypeEquality() {
        XCTAssertEqual(GoalType.justComplete, GoalType.justComplete)
        XCTAssertEqual(GoalType.timeTarget(3600), GoalType.timeTarget(3600))
        XCTAssertNotEqual(GoalType.timeTarget(3600), GoalType.timeTarget(7200))
        XCTAssertNotEqual(GoalType.timeTarget(3600), GoalType.justComplete)
    }
}

// MARK: - Race Tests

final class RaceTests: XCTestCase {

    func testRaceCodable() throws {
        let race = Race(
            name: "Ironman 70.3 Oregon",
            date: Date(timeIntervalSince1970: 1784620800),
            location: "Salem, OR",
            type: .triathlon,
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            courseType: "road",
            elevationGainM: 450.0,
            elevationAtVenueM: 46.0,
            historicalWeather: "Sunny, 85°F",
            userGoal: .timeTarget(21600)
        )

        let data = try JSONEncoder().encode(race)
        let decoded = try JSONDecoder().decode(Race.self, from: data)

        XCTAssertEqual(decoded.name, "Ironman 70.3 Oregon")
        XCTAssertEqual(decoded.location, "Salem, OR")
        XCTAssertEqual(decoded.type, .triathlon)
        XCTAssertEqual(decoded.distances["swim"], 1.2)
        XCTAssertEqual(decoded.distances["bike"], 56.0)
        XCTAssertEqual(decoded.distances["run"], 13.1)
        XCTAssertEqual(decoded.courseType, "road")
        XCTAssertEqual(decoded.elevationGainM, 450.0)
        XCTAssertEqual(decoded.historicalWeather, "Sunny, 85°F")

        if case .timeTarget(let seconds) = decoded.userGoal {
            XCTAssertEqual(seconds, 21600)
        } else {
            XCTFail("Expected timeTarget goal")
        }
    }

    func testRaceTypeValues() {
        XCTAssertEqual(RaceType.triathlon.rawValue, "triathlon")
        XCTAssertEqual(RaceType.running.rawValue, "running")
        XCTAssertEqual(RaceType.cycling.rawValue, "cycling")
        XCTAssertEqual(RaceType.swimming.rawValue, "swimming")
        XCTAssertEqual(RaceType.allCases.count, 4)
    }
}

// MARK: - PlanMetadata Tests

final class PlanMetadataTests: XCTestCase {

    func testPlanMetadataCodable() throws {
        let metadata = PlanMetadata(
            generatedAt: Date(timeIntervalSince1970: 1700000000),
            generatedBy: "claude-generated",
            raceId: "race-123",
            approved: true
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(PlanMetadata.self, from: data)

        XCTAssertEqual(decoded.generatedBy, "claude-generated")
        XCTAssertEqual(decoded.raceId, "race-123")
        XCTAssertTrue(decoded.approved)
    }

    func testHardcodedPlanMetadata() throws {
        let metadata = PlanMetadata(
            generatedAt: Date(),
            generatedBy: "hardcoded",
            raceId: nil,
            approved: true
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(PlanMetadata.self, from: data)

        XCTAssertEqual(decoded.generatedBy, "hardcoded")
        XCTAssertNil(decoded.raceId)
    }
}

// MARK: - RaceSearchResult Tests

final class RaceSearchResultTests: XCTestCase {

    func testRaceSearchResultDecoding() throws {
        let json = """
        {
            "name": "Boston Marathon",
            "date": "2026-04-20",
            "location": "Boston, MA",
            "type": "running",
            "distances": {"run": 26.2},
            "courseType": "road",
            "elevationGainM": 150,
            "elevationAtVenueM": 6,
            "historicalWeather": "Cool, 50-60°F, possible rain"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateStr) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }

        let result = try decoder.decode(RaceSearchResult.self, from: json)

        XCTAssertEqual(result.name, "Boston Marathon")
        XCTAssertEqual(result.location, "Boston, MA")
        XCTAssertEqual(result.type, "running")
        XCTAssertEqual(result.distances["run"], 26.2)
        XCTAssertEqual(result.courseType, "road")
        XCTAssertEqual(result.elevationGainM, 150)
        XCTAssertEqual(result.historicalWeather, "Cool, 50-60°F, possible rain")
    }
}

// MARK: - OnboardingChatHelper Tests

final class OnboardingChatHelperTests: XCTestCase {

    func testBuildOnboardingSystemPrompt_WithRace() {
        let race = Race(
            name: "Ironman 70.3 Oregon",
            date: Date(timeIntervalSinceNow: 86400 * 112), // ~16 weeks out
            location: "Salem, OR",
            type: .triathlon,
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            courseType: "road",
            elevationGainM: 450,
            elevationAtVenueM: 46,
            historicalWeather: "Sunny and warm",
            userGoal: .timeTarget(21600)
        )

        let prompt = OnboardingChatHelper.buildOnboardingSystemPrompt(
            profile: nil,
            userName: "Brent",
            race: race,
            goal: .timeTarget(21600)
        )

        XCTAssertTrue(prompt.contains("ATHLETE: Brent"))
        XCTAssertTrue(prompt.contains("Ironman 70.3 Oregon"))
        XCTAssertTrue(prompt.contains("Salem, OR"))
        XCTAssertTrue(prompt.contains("triathlon"))
        XCTAssertTrue(prompt.contains("Finish in 6h 00m"))
        XCTAssertTrue(prompt.contains("ASSESSMENT GUIDELINES"))
        XCTAssertTrue(prompt.contains("FEASIBILITY ASSESSMENT"))
    }

    func testBuildOnboardingSystemPrompt_JustComplete() {
        let prompt = OnboardingChatHelper.buildOnboardingSystemPrompt(
            profile: nil,
            userName: "Test",
            race: nil,
            goal: .justComplete
        )

        XCTAssertTrue(prompt.contains("Complete the race"))
    }

    func testBuildOnboardingSystemPrompt_NoProfile() {
        let prompt = OnboardingChatHelper.buildOnboardingSystemPrompt(
            profile: nil,
            userName: "Test",
            race: nil,
            goal: nil
        )

        XCTAssertTrue(prompt.contains("Not available"))
    }

    func testBuildOnboardingSystemPrompt_WithProfile() {
        var profile = HealthKitOnboardingProfile()
        profile.vo2Max = 57.8
        profile.restingHR = 52
        profile.biologicalSex = "male"
        profile.weightKg = 75.0

        let prompt = OnboardingChatHelper.buildOnboardingSystemPrompt(
            profile: profile,
            userName: "Brent",
            race: nil,
            goal: nil
        )

        XCTAssertTrue(prompt.contains("VO2 Max: 57.8"))
        XCTAssertTrue(prompt.contains("Resting HR: 52"))
        XCTAssertTrue(prompt.contains("Sex: male"))
        XCTAssertTrue(prompt.contains("Weight: 75.0"))
    }

    func testBuildPlanConversionPrompt() {
        let race = Race(
            name: "Test Race",
            date: Date(timeIntervalSinceNow: 86400 * 84),
            location: "Denver, CO",
            type: .running,
            distances: ["run": 13.1],
            courseType: "road",
            elevationGainM: nil,
            elevationAtVenueM: 1609,
            historicalWeather: nil,
            userGoal: .justComplete
        )

        let profile = UserProfile(
            uid: "test",
            name: "Test User",
            dateOfBirth: nil,
            biologicalSex: nil,
            heightCm: nil,
            weightKg: nil,
            restingHR: nil,
            vo2Max: nil,
            homeZip: nil,
            homeElevationM: nil,
            onboardingComplete: false,
            createdAt: Date()
        )

        let messages = [
            ChatMessage(isUser: true, text: "I run 20 miles a week"),
            ChatMessage(isUser: false, text: "Great base! Let's build a plan."),
        ]

        let prompt = OnboardingChatHelper.buildPlanConversionPrompt(
            chatHistory: messages,
            race: race,
            profile: profile
        )

        XCTAssertTrue(prompt.contains("Test Race"))
        XCTAssertTrue(prompt.contains("running"))
        XCTAssertTrue(prompt.contains("run: 13.1"))
        XCTAssertTrue(prompt.contains("Complete the race"))
        XCTAssertTrue(prompt.contains("weekNumber"))
        XCTAssertTrue(prompt.contains("Athlete: I run 20 miles a week"))
        XCTAssertTrue(prompt.contains("Coach: Great base!"))
    }
}

// MARK: - OnboardingStep Tests

final class OnboardingStepTests: XCTestCase {

    func testStepCount() {
        XCTAssertEqual(OnboardingStep.allCases.count, 6)
    }

    func testStepOrder() {
        XCTAssertEqual(OnboardingStep.healthKit.rawValue, 0)
        XCTAssertEqual(OnboardingStep.profile.rawValue, 1)
        XCTAssertEqual(OnboardingStep.raceSearch.rawValue, 2)
        XCTAssertEqual(OnboardingStep.goalSetting.rawValue, 3)
        XCTAssertEqual(OnboardingStep.tutorial.rawValue, 4)
        XCTAssertEqual(OnboardingStep.planReview.rawValue, 5)
    }
}

// MARK: - OnboardingFlow Tests

@MainActor
final class OnboardingFlowTests: XCTestCase {

    var viewModel: OnboardingViewModel!

    override func setUp() {
        super.setUp()
        viewModel = OnboardingViewModel()
    }

    // MARK: - Helpers

    private func makeRaceSearchResult(
        name: String,
        type: String,
        distances: [String: Double],
        daysFromNow: Int = 120
    ) -> RaceSearchResult {
        let futureDate = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return RaceSearchResult(
            name: name,
            date: futureDate,
            location: "Test Location",
            type: type,
            distances: distances,
            courseType: "road",
            elevationGainM: 300.0,
            elevationAtVenueM: 100.0,
            historicalWeather: "Partly cloudy, 70°F"
        )
    }

    // MARK: - Scenario 1: Half Ironman (70.3) — triathlon, timeTarget, spread

    func testHalfIronman_classifyRaceForTemplate() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Ironman 70.3 Oregon",
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1]
        )
        let classification = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(classification)
        XCTAssertEqual(classification?.category, "triathlon")
        XCTAssertEqual(classification?.subtype, "70.3")
    }

    func testHalfIronman_validateGoal_noWarning() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Ironman 70.3 Oregon",
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1]
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 6
        viewModel.targetMinutes = 0
        viewModel.validateGoal()
        XCTAssertNil(viewModel.goalValidationWarning)
    }

    func testHalfIronman_buildPlanGenerationInput() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Ironman 70.3 Oregon",
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1]
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 6
        viewModel.targetMinutes = 0
        viewModel.schedulePattern = .spread
        viewModel.userName = "Brent"

        let input = viewModel.buildPlanGenerationInput()

        XCTAssertEqual(input.race.name, "Ironman 70.3 Oregon")
        XCTAssertEqual(input.race.distances["swim"], 1.2)
        XCTAssertEqual(input.race.distances["bike"], 56.0)
        XCTAssertEqual(input.race.distances["run"], 13.1)
        XCTAssertEqual(input.fitnessHours, SchedulePattern.spread.label)
        XCTAssertEqual(input.fitnessSchedule, SchedulePattern.spread.label)
    }

    func testHalfIronman_buildRace() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Ironman 70.3 Oregon",
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1]
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 6
        viewModel.targetMinutes = 0

        let race = viewModel.buildRace()
        XCTAssertNotNil(race)
        XCTAssertEqual(race?.type, .triathlon)
        if case .timeTarget(let seconds) = race?.userGoal {
            XCTAssertEqual(seconds, 21600, accuracy: 1)
        } else {
            XCTFail("Expected timeTarget goal")
        }
    }

    func testHalfIronman_advanceFromGoalSettingTriggersGeneration() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Ironman 70.3 Oregon",
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1]
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 6
        viewModel.targetMinutes = 0
        viewModel.currentStep = .goalSetting

        viewModel.advance()

        XCTAssertEqual(viewModel.currentStep, .tutorial)
        XCTAssertTrue(viewModel.isGeneratingPlan)
    }

    func testHalfIronman_strengthRecommended() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Ironman 70.3 Oregon",
            type: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1]
        )
        XCTAssertTrue(viewModel.strengthRecommended)
    }

    // MARK: - Scenario 2: 10K Run — running, justComplete, weekendWarrior

    func testTenK_classifyRaceForTemplate() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Denver 10K",
            type: "running",
            distances: ["run": 6.2]
        )
        let classification = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(classification)
        XCTAssertEqual(classification?.category, "running")
        XCTAssertEqual(classification?.subtype, "10k")
    }

    func testTenK_validateGoal_noWarningForJustComplete() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Denver 10K",
            type: "running",
            distances: ["run": 6.2]
        )
        viewModel.goalType = .justComplete
        viewModel.validateGoal()
        XCTAssertNil(viewModel.goalValidationWarning)
    }

    func testTenK_buildPlanGenerationInput() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Denver 10K",
            type: "running",
            distances: ["run": 6.2]
        )
        viewModel.goalType = .justComplete
        viewModel.schedulePattern = .weekendWarrior
        viewModel.userName = "Brent"

        let input = viewModel.buildPlanGenerationInput()

        XCTAssertEqual(input.race.name, "Denver 10K")
        XCTAssertEqual(input.race.distances["run"], 6.2)
        XCTAssertEqual(input.fitnessHours, SchedulePattern.weekendWarrior.label)
        XCTAssertEqual(input.fitnessSchedule, SchedulePattern.weekendWarrior.label)
    }

    func testTenK_buildRace() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Denver 10K",
            type: "running",
            distances: ["run": 6.2]
        )
        viewModel.goalType = .justComplete

        let race = viewModel.buildRace()
        XCTAssertNotNil(race)
        XCTAssertEqual(race?.type, .running)
        if case .justComplete = race?.userGoal {
            // pass
        } else {
            XCTFail("Expected justComplete goal")
        }
    }

    func testTenK_advanceFromGoalSettingTriggersGeneration() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Denver 10K",
            type: "running",
            distances: ["run": 6.2]
        )
        viewModel.goalType = .justComplete
        viewModel.schedulePattern = .weekendWarrior
        viewModel.currentStep = .goalSetting

        viewModel.advance()

        XCTAssertEqual(viewModel.currentStep, .tutorial)
        XCTAssertTrue(viewModel.isGeneratingPlan)
    }

    func testTenK_strengthNotRecommended() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Denver 10K",
            type: "running",
            distances: ["run": 6.2]
        )
        XCTAssertFalse(viewModel.strengthRecommended)
    }

    // MARK: - Scenario 3: Marathon — running, timeTarget, compressed

    func testMarathon_classifyRaceForTemplate() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Chicago Marathon",
            type: "running",
            distances: ["run": 26.2]
        )
        let classification = viewModel.classifyRaceForTemplate()
        XCTAssertNotNil(classification)
        XCTAssertEqual(classification?.category, "running")
        XCTAssertEqual(classification?.subtype, "marathon")
    }

    func testMarathon_validateGoal_noWarning() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Chicago Marathon",
            type: "running",
            distances: ["run": 26.2]
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 4
        viewModel.targetMinutes = 30
        viewModel.validateGoal()
        XCTAssertNil(viewModel.goalValidationWarning)
    }

    func testMarathon_buildPlanGenerationInput() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Chicago Marathon",
            type: "running",
            distances: ["run": 26.2]
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 4
        viewModel.targetMinutes = 30
        viewModel.schedulePattern = .compressed
        viewModel.userName = "Brent"

        let input = viewModel.buildPlanGenerationInput()

        XCTAssertEqual(input.race.name, "Chicago Marathon")
        XCTAssertEqual(input.race.distances["run"], 26.2)
        XCTAssertEqual(input.fitnessHours, SchedulePattern.compressed.label)
        XCTAssertEqual(input.fitnessSchedule, SchedulePattern.compressed.label)
    }

    func testMarathon_buildRace() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Chicago Marathon",
            type: "running",
            distances: ["run": 26.2]
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 4
        viewModel.targetMinutes = 30

        let race = viewModel.buildRace()
        XCTAssertNotNil(race)
        XCTAssertEqual(race?.type, .running)
        if case .timeTarget(let seconds) = race?.userGoal {
            XCTAssertEqual(seconds, 16200, accuracy: 1) // 4h30m = 16200s
        } else {
            XCTFail("Expected timeTarget goal")
        }
    }

    func testMarathon_advanceFromGoalSettingTriggersGeneration() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Chicago Marathon",
            type: "running",
            distances: ["run": 26.2]
        )
        viewModel.goalType = .timeTarget
        viewModel.targetHours = 4
        viewModel.targetMinutes = 30
        viewModel.schedulePattern = .compressed
        viewModel.currentStep = .goalSetting

        viewModel.advance()

        XCTAssertEqual(viewModel.currentStep, .tutorial)
        XCTAssertTrue(viewModel.isGeneratingPlan)
    }

    func testMarathon_strengthRecommended() {
        viewModel.raceSearchResult = makeRaceSearchResult(
            name: "Chicago Marathon",
            type: "running",
            distances: ["run": 26.2]
        )
        XCTAssertTrue(viewModel.strengthRecommended)
    }
}

// MARK: - HealthKitOnboardingProfile Tests

final class HealthKitOnboardingProfileTests: XCTestCase {

    func testEmptyProfileInit() {
        let profile = HealthKitOnboardingProfile()
        XCTAssertNil(profile.dateOfBirth)
        XCTAssertNil(profile.biologicalSex)
        XCTAssertNil(profile.heightCm)
        XCTAssertNil(profile.weightKg)
        XCTAssertNil(profile.restingHR)
        XCTAssertNil(profile.vo2Max)
        XCTAssertNil(profile.recentWeeklyVolume)
        XCTAssertTrue(profile.monthlyTrends.isEmpty)
        XCTAssertTrue(profile.recentWorkoutDetails.isEmpty)
    }

    func testFormatForClaude_Empty() {
        let profile = HealthKitOnboardingProfile()
        let formatted = profile.formatForClaude()
        XCTAssertTrue(formatted.contains("HealthKit Profile"))
    }

    func testFormatForClaude_WithData() {
        var profile = HealthKitOnboardingProfile()
        profile.vo2Max = 45.0
        profile.restingHR = 60
        profile.biologicalSex = "female"
        profile.heightCm = 165.0
        profile.weightKg = 60.0
        profile.monthlyTrends = [
            MonthlyTrainingSummary(month: "2026-01", swimSessions: 4, bikeSessions: 8, runSessions: 12, totalDurationHours: 20.5),
            MonthlyTrainingSummary(month: "2026-02", swimSessions: 5, bikeSessions: 10, runSessions: 14, totalDurationHours: 25.0),
        ]

        let formatted = profile.formatForClaude()
        XCTAssertTrue(formatted.contains("45.0"), "Should contain VO2 max value")
        XCTAssertTrue(formatted.contains("60"), "Should contain resting HR value")
        XCTAssertTrue(formatted.contains("female"), "Should contain sex")
        XCTAssertTrue(formatted.contains("165"), "Should contain height")
    }
}
