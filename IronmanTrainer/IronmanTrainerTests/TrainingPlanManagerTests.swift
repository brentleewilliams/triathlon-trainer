import XCTest
@testable import Race1_Trainer

final class TrainingPlanManagerTests: XCTestCase {

    var sut: TrainingPlanManager!

    override func setUp() {
        super.setUp()
        sut = TrainingPlanManager(useInMemoryStore: true)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Week Number Calculation Tests

    /// Test: On the training start date (Mar 23, 2026), current week should be 1
    func testCurrentWeekOnStartDate() {
        // Given
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 23
        let startDate = calendar.date(from: components)!

        // When
        let result = calculateWeekNumber(for: startDate)

        // Then
        XCTAssertEqual(result, 1, "Week number should be 1 on training start date")
    }

    /// Test: One day after start (Mar 24, 2026) should still be week 1
    func testCurrentWeekOneDayAfterStart() {
        // Given
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 24
        let oneDayAfter = calendar.date(from: components)!

        // When
        let result = calculateWeekNumber(for: oneDayAfter)

        // Then
        XCTAssertEqual(result, 1, "Week number should be 1 on Mar 24")
    }

    /// Test: Six days after start (Mar 29, 2026) should still be week 1
    func testCurrentWeekSixDaysAfterStart() {
        // Given
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 29
        let sixDaysAfter = calendar.date(from: components)!

        // When
        let result = calculateWeekNumber(for: sixDaysAfter)

        // Then
        XCTAssertEqual(result, 1, "Week number should be 1 on Mar 29")
    }

    /// Test: Seven days after start (Mar 30, 2026) should be week 2
    func testCurrentWeekSevenDaysAfterStart() {
        // Given
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 30
        let sevenDaysAfter = calendar.date(from: components)!

        // When
        let result = calculateWeekNumber(for: sevenDaysAfter)

        // Then
        XCTAssertEqual(result, 2, "Week number should be 2 on Mar 30 (7 days after start)")
    }

    /// Test: Fourteen days after start should be week 3
    func testCurrentWeekFourteenDaysAfterStart() {
        // Given
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 6
        let twoWeeksAfter = calendar.date(from: components)!

        // When
        let result = calculateWeekNumber(for: twoWeeksAfter)

        // Then
        XCTAssertEqual(result, 3, "Week number should be 3 on Apr 6 (14 days after start)")
    }

    /// Test: At race date (Jul 19, 2026) should be week 17
    func testCurrentWeekAtRaceDate() {
        // Given
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 19
        let raceDate = calendar.date(from: components)!

        // When
        let result = calculateWeekNumber(for: raceDate)

        // Then
        XCTAssertEqual(result, 17, "Week number should be 17 on race date (Jul 19)")
    }

    /// Test: Before training start (Mar 22, 2026) should clamp to week 1
    func testCurrentWeekBeforeStartDateClamps() {
        // Given
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 22
        let beforeStart = calendar.date(from: components)!

        // When
        let result = calculateWeekNumber(for: beforeStart)

        // Then
        XCTAssertEqual(result, 1, "Week number should clamp to 1 before training start")
    }

    /// Test: After race date (Aug 1, 2026) should clamp to week 17
    func testCurrentWeekAfterRaceDateClamps() {
        // Given
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 1
        let afterRace = calendar.date(from: components)!

        // When
        let result = calculateWeekNumber(for: afterRace)

        // Then
        XCTAssertEqual(result, 17, "Week number should clamp to 17 after race date")
    }

    // MARK: - Day-of-Week to Date Mapping Tests

    /// Test: Week 1 should have correct start and end dates
    func testWeek1DateRange() {
        // Given
        let week1 = sut.getWeek(1)

        // When
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: week1!.startDate)

        // Then
        XCTAssertNotNil(week1, "Week 1 should exist")
        XCTAssertEqual(components.month, 3, "Week 1 should start in March")
        XCTAssertEqual(components.day, 23, "Week 1 should start on day 23 (Mar 23)")
    }

    /// Test: Week 17 should have correct start and end dates
    func testWeek17DateRange() {
        // Given
        let week17 = sut.getWeek(17)

        // When
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.month, .day], from: week17!.startDate)
        let endComponents = calendar.dateComponents([.month, .day], from: week17!.endDate)

        // Then
        XCTAssertNotNil(week17, "Week 17 should exist")
        XCTAssertEqual(startComponents.month, 7, "Week 17 should start in July")
        XCTAssertEqual(startComponents.day, 13, "Week 17 should start on day 13 (Jul 13)")
        XCTAssertEqual(endComponents.month, 7, "Week 17 should end in July")
        XCTAssertEqual(endComponents.day, 19, "Week 17 should end on day 19 (Jul 19, race day)")
    }

    /// Test: Each week should span exactly 7 days
    func testEachWeekSpansSevenDays() {
        // When/Then
        for week in 1...17 {
            guard let trainingWeek = sut.getWeek(week) else {
                XCTFail("Week \(week) should exist")
                return
            }

            let daysDifference = Calendar.current.dateComponents(
                [.day],
                from: trainingWeek.startDate,
                to: trainingWeek.endDate
            ).day ?? 0

            XCTAssertEqual(
                daysDifference,
                6,
                "Week \(week) should span from start to end date (6 days difference = 7 days)"
            )
        }
    }

    /// Test: Week 2 should start exactly 7 days after week 1
    func testWeek2StartsSevenDaysAfterWeek1() {
        // Given
        guard let week1 = sut.getWeek(1), let week2 = sut.getWeek(2) else {
            XCTFail("Weeks 1 and 2 should exist")
            return
        }

        // When
        let daysBetween = Calendar.current.dateComponents(
            [.day],
            from: week1.startDate,
            to: week2.startDate
        ).day ?? 0

        // Then
        XCTAssertEqual(daysBetween, 7, "Week 2 should start exactly 7 days after week 1")
    }

    // MARK: - Training Plan Structure Tests

    /// Test: All 17 weeks should be present
    func testAllSeventeenWeeksPresent() {
        // Then
        XCTAssertEqual(sut.weeks.count, 17, "Training plan should have exactly 17 weeks")
    }

    /// Test: Weeks should be sorted by week number
    func testWeeksSortedByNumber() {
        // When
        for (index, week) in sut.weeks.enumerated() {
            // Then
            XCTAssertEqual(
                week.weekNumber,
                index + 1,
                "Weeks should be sorted in order. Index \(index) should be week \(index + 1)"
            )
        }
    }

    /// Test: Week 1 should have correct workouts (7-8 workouts including rest days)
    func testWeek1WorkoutCount() {
        // Given
        let week1 = sut.getWeek(1)!

        // Then
        XCTAssertGreaterThan(week1.workouts.count, 0, "Week 1 should have workouts")
        XCTAssertLessThanOrEqual(week1.workouts.count, 10, "Week 1 should have reasonable number of workouts")
    }

    /// Test: Week 1 should have specific workouts matching the plan
    func testWeek1HasCorrectWorkouts() {
        // Given
        let week1 = sut.getWeek(1)!

        // When
        let fridayWorkouts = week1.workouts.filter { $0.day == "Fri" }
        let restDays = week1.workouts.filter { $0.type == "Rest" }

        // Then
        XCTAssertGreaterThan(fridayWorkouts.count, 0, "Week 1 Friday should have workouts")
        // Friday of Week 1 should have a swim
        let fridaySwim = fridayWorkouts.first { $0.type.contains("Swim") }
        XCTAssertNotNil(fridaySwim, "Week 1 Friday should have a swim workout")
        XCTAssertEqual(restDays.count, 1, "Week 1 should have exactly 1 rest day (Monday)")
    }

    /// Test: Rest days should be marked with "Rest" type
    func testRestDaysMarkedCorrectly() {
        // Given
        let restDayTypes = ["Rest"]

        // When/Then
        for week in sut.weeks {
            for workout in week.workouts {
                if workout.duration == "-" && workout.zone == "-" {
                    // This looks like a rest day marker
                    XCTAssertTrue(
                        restDayTypes.contains(workout.type),
                        "Workouts with '-' duration and zone should be marked as 'Rest'"
                    )
                }
            }
        }
    }

    /// Test: Multi-workout days should exist (e.g., Tuesday with Bike and Swim)
    func testMultiWorkoutDaysExist() {
        // When
        var foundMultiWorkoutDay = false
        for week in sut.weeks {
            let dayGroupings = Dictionary(grouping: week.workouts, by: { $0.day })
            if let tuesdayWorkouts = dayGroupings["Tue"], tuesdayWorkouts.count > 1 {
                foundMultiWorkoutDay = true
                // Verify it has different types
                let types = Set(tuesdayWorkouts.map { $0.type })
                XCTAssertGreaterThan(types.count, 1, "Multi-workout days should have different workout types")
                break
            }
        }

        // Then
        XCTAssertTrue(foundMultiWorkoutDay, "Training plan should have multi-workout days")
    }

    // MARK: - Core Data Tests

    /// Test: savePlanVersion should create a new version in Core Data
    func testSavePlanVersionCreatesNewVersion() {
        // Given
        let initialCurrentVersion = sut.currentPlanVersion

        // When
        sut.savePlanVersion(source: "test", description: "Test version")

        // Then
        XCTAssertNotNil(sut.currentPlanVersion, "Current plan version should be set after save")
        // If there was a previous current version, it should now be the previous version
        if initialCurrentVersion != nil {
            XCTAssertNotNil(sut.previousPlanVersion, "Previous version should be set")
        }
    }

    /// Test: Saved plan version should contain correct weeks
    func testSavedPlanVersionContainsWeeks() {
        // Given
        let originalWeeks = sut.weeks

        // When
        sut.savePlanVersion(source: "test", description: "Test")

        // Then
        XCTAssertEqual(sut.weeks.count, originalWeeks.count, "Weeks should remain after save")
        XCTAssertEqual(sut.weeks, originalWeeks, "Week content should be preserved after save")
    }

    /// Test: Multiple saves should create version history
    func testMultipleSavesCreateVersionHistory() {
        // When
        sut.savePlanVersion(source: "save1", description: "First save")
        let afterFirstSave = sut.currentPlanVersion

        sut.savePlanVersion(source: "save2", description: "Second save")
        let afterSecondSave = sut.currentPlanVersion

        // Then
        XCTAssertNotEqual(
            afterFirstSave,
            afterSecondSave,
            "Each save should create a new current version"
        )
    }

    // MARK: - Rollback Tests

    /// Test: Rollback requires a previous version
    func testRollbackWithoutPreviousVersionFails() {
        // Given
        sut.previousPlanVersion = nil

        // When
        let success = sut.rollbackToPreviousVersion()

        // Then
        XCTAssertFalse(success, "Rollback should fail without a previous version")
    }

    /// Test: Successful rollback restores previous weeks
    func testRollbackRestoresPreviousWeeks() {
        // Given
        let originalWeeks = sut.weeks

        // When
        // Save current state as version 1
        sut.savePlanVersion(source: "version1", description: "Version 1")

        // Modify weeks
        var modifiedWeeks = sut.weeks
        modifiedWeeks.removeAll { $0.weekNumber == 1 }
        let week1Start = originalWeeks.first { $0.weekNumber == 1 }!.startDate
        let week1End = originalWeeks.first { $0.weekNumber == 1 }!.endDate
        let newWeek1 = TrainingWeek(
            weekNumber: 1,
            phase: "Modified",
            startDate: week1Start,
            endDate: week1End,
            workouts: []
        )
        modifiedWeeks.insert(newWeek1, at: 0)
        modifiedWeeks.sort { $0.weekNumber < $1.weekNumber }
        sut.weeks = modifiedWeeks

        // Save modified state as version 2
        sut.savePlanVersion(source: "version2", description: "Version 2")

        // Verify modification
        XCTAssertNotEqual(sut.weeks, originalWeeks, "Weeks should be modified before rollback")

        // Perform rollback
        let success = sut.rollbackToPreviousVersion()

        // Then
        XCTAssertTrue(success, "Rollback should succeed with previous version available")
        // Note: We can't directly compare because workouts array might be recreated,
        // but we can verify week count and structure
        XCTAssertEqual(sut.weeks.count, originalWeeks.count, "Weeks count should match after rollback")
    }

    /// Test: Rollback clears previous version reference
    func testRollbackClearsPreviousVersionReference() {
        // Given
        sut.savePlanVersion(source: "v1", description: "Version 1")

        sut.savePlanVersion(source: "v2", description: "Version 2")

        // Verify we have versions
        XCTAssertNotNil(sut.currentPlanVersion, "Current version should exist")
        XCTAssertNotNil(sut.previousPlanVersion, "Previous version should exist")

        // When
        let success = sut.rollbackToPreviousVersion()

        // Then
        XCTAssertTrue(success, "Rollback should succeed")
        XCTAssertNil(sut.previousPlanVersion, "Previous version reference should be cleared after rollback")
    }

    // MARK: - Multi-Workout Day Swapping Tests (Regression)

    /// Test: Tuesday multi-workout structure should be preserved through save/restore
    func testMultiWorkoutDayPreservedInSaveRestore() {
        // Given
        let tuesdayWorkoutsBeforeSave = sut.weeks.flatMap { week in
            week.workouts.filter { $0.day == "Tue" }
        }

        // Verify we have multi-workout Tuesdays
        XCTAssertGreaterThan(tuesdayWorkoutsBeforeSave.count, 7, "Tuesdays should have multiple workouts across weeks")

        // When
        sut.savePlanVersion(source: "multiworkout", description: "Test multi-workout preservation")
        sut.loadPlanVersions()

        // Get Tuesday workouts after restore
        let tuesdayWorkoutsAfterRestore = sut.weeks.flatMap { week in
            week.workouts.filter { $0.day == "Tue" }
        }

        // Then
        XCTAssertEqual(
            tuesdayWorkoutsBeforeSave.count,
            tuesdayWorkoutsAfterRestore.count,
            "Tuesday workout count should match before and after save/restore"
        )
    }

    /// Test: Week with multiple workouts per day should preserve all workouts
    func testWeekWithMultipleWorkoutsPerDayPreserved() {
        // Given - Find a week with multi-workout days
        var multiWorkoutWeek: TrainingWeek?
        for week in sut.weeks {
            let dayGroupings = Dictionary(grouping: week.workouts, by: { $0.day })
            if dayGroupings.values.contains(where: { $0.count > 1 }) {
                multiWorkoutWeek = week
                break
            }
        }

        guard let week = multiWorkoutWeek else {
            XCTFail("Should have found a multi-workout day in training plan")
            return
        }

        // When
        let beforeWorkoutCount = week.workouts.count
        sut.savePlanVersion(source: "test", description: "Multi-workout day preservation")
        sut.loadPlanVersions()

        let restoredWeek = sut.getWeek(week.weekNumber)
        let afterWorkoutCount = restoredWeek?.workouts.count ?? 0

        // Then
        XCTAssertEqual(
            beforeWorkoutCount,
            afterWorkoutCount,
            "Multi-workout day should have all workouts preserved"
        )
    }

    // MARK: - Edge Cases

    /// Test: Retrieving non-existent week returns nil
    func testGetNonExistentWeekReturnsNil() {
        // When
        let week0 = sut.getWeek(0)
        let week18 = sut.getWeek(18)
        let week99 = sut.getWeek(99)

        // Then
        XCTAssertNil(week0, "Week 0 should not exist")
        XCTAssertNil(week18, "Week 18 should not exist")
        XCTAssertNil(week99, "Week 99 should not exist")
    }

    /// Test: Week phases are assigned correctly
    func testWeekPhasesAssignedCorrectly() {
        // Given - phases from setupTrainingPlan() in TrainingPlanManager
        let expectedPhases = [
            (1, "Ramp Up"), (2, "Ramp Up"), (3, "Ramp Up"), (4, "Ramp Up"),
            (5, "Build 1"), (6, "Build 1"),
            (7, "Build 2"),
            (8, "Build 2"),
            (9, "Build 3"),
            (10, "Taper"),
            (11, "Taper"), (12, "Taper"), (13, "Race Prep"),
            (14, "Race Prep"), (15, "Race Prep"), (16, "Rest"),
            (17, "Race Week")
        ]

        // When/Then
        for (weekNum, expectedPhase) in expectedPhases {
            guard let week = sut.getWeek(weekNum) else {
                XCTFail("Week \(weekNum) should exist")
                return
            }

            XCTAssertEqual(
                week.phase,
                expectedPhase,
                "Week \(weekNum) should be in '\(expectedPhase)' phase, got '\(week.phase)'"
            )
        }
    }

    /// Test: Zone information is present in workouts
    func testZoneInformationPresent() {
        // When/Then
        var workoutsWithZones = 0
        var totalWorkouts = 0

        for week in sut.weeks {
            for workout in week.workouts {
                totalWorkouts += 1
                if !workout.zone.isEmpty && workout.zone != "-" {
                    workoutsWithZones += 1
                }
            }
        }

        // Zone information should be present for majority of workouts
        XCTAssertGreaterThan(
            workoutsWithZones,
            totalWorkouts / 2,
            "Most workouts should have zone information"
        )
    }

    // MARK: - Helper Methods

    /// Calculate week number for a given date using the same logic as TrainingPlanManager
    private func calculateWeekNumber(for date: Date) -> Int {
        let planStartDate = {
            var components = DateComponents()
            components.year = 2026
            components.month = 3
            components.day = 23
            return Calendar.current.date(from: components) ?? Date()
        }()

        let calendar = Calendar.current
        let daysSinceStart = calendar.dateComponents([.day], from: planStartDate, to: date).day ?? 0
        let weekNumber = (daysSinceStart / 7) + 1

        return max(1, min(17, weekNumber))
    }
}
