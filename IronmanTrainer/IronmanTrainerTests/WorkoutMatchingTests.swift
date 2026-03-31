// TODO: References methods not yet extracted from views (parseDuration, extractWorkoutType, workoutTypeMatches).
#if false
import XCTest
import HealthKit

class WorkoutMatchingTests: XCTestCase {

    // MARK: - Test Data Setup

    var healthKitManager: HealthKitManager!
    let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        healthKitManager = HealthKitManager()
    }

    override func tearDown() {
        super.tearDown()
        healthKitManager = nil
    }

    // MARK: - Helper Functions

    /// Create a test HKWorkout with specified parameters
    func createTestWorkout(
        activityType: HKWorkoutActivityType,
        startDate: Date,
        duration: TimeInterval
    ) -> HKWorkout {
        let endDate = Date(timeInterval: duration, since: startDate)
        return HKWorkout(
            activityType: activityType,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        )
    }

    /// Get a date for a specific day (Mon-Sun) in the current week
    func getDateForDay(_ dayName: String) -> Date {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard let dayIndex = dayOrder.firstIndex(of: dayName) else {
            XCTFail("Invalid day name: \(dayName)")
            return Date()
        }

        // March 23, 2026 is a Sunday, so March 23 = Sunday, Mar 24 = Monday of week 1
        let weekStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 24))!
        return calendar.date(byAdding: .day, value: dayIndex, to: weekStart) ?? weekStart
    }

    // MARK: - Duration Parsing Tests

    func testParseDuration_MinutesFormat() {
        // "60 min" → 60
        XCTAssertEqual(healthKitManager.parseDuration("60 min"), 60)
        XCTAssertEqual(healthKitManager.parseDuration("45 min"), 45)
        XCTAssertEqual(healthKitManager.parseDuration("30min"), 30) // No space
    }

    func testParseDuration_HoursFormat() {
        // "1.5 hr" → 90
        XCTAssertEqual(healthKitManager.parseDuration("1.5 hr"), 90)
        XCTAssertEqual(healthKitManager.parseDuration("2 hr"), 120)
        XCTAssertEqual(healthKitManager.parseDuration("1hr"), 60) // No space
    }

    func testParseDuration_ColonFormat() {
        // "1:00" → 60 min
        XCTAssertEqual(healthKitManager.parseDuration("1:00"), 60)
        // "1:30" → 90 min
        XCTAssertEqual(healthKitManager.parseDuration("1:30"), 90)
        // "1:45" → 105 min
        XCTAssertEqual(healthKitManager.parseDuration("1:45"), 105)
        // "2:15" → 135 min
        XCTAssertEqual(healthKitManager.parseDuration("2:15"), 135)
    }

    func testParseDuration_DistanceBasedReturnsNil() {
        // Distance-based durations should return nil (no time tolerance check)
        XCTAssertNil(healthKitManager.parseDuration("1,800yd"))
        XCTAssertNil(healthKitManager.parseDuration("2,000yd"))
        XCTAssertNil(healthKitManager.parseDuration("3,200yd"))
    }

    func testParseDuration_RestReturnsNil() {
        XCTAssertNil(healthKitManager.parseDuration("Rest"))
        XCTAssertNil(healthKitManager.parseDuration("rest"))
        XCTAssertNil(healthKitManager.parseDuration("-"))
    }

    func testParseDuration_CaseInsensitive() {
        XCTAssertEqual(healthKitManager.parseDuration("60 MIN"), 60)
        XCTAssertEqual(healthKitManager.parseDuration("1:00 HR"), nil) // "hr" not at start
        XCTAssertEqual(healthKitManager.parseDuration("1.5 HR"), 90)
    }

    // MARK: - Type Extraction Tests

    func testExtractWorkoutType_BikeEmoji() {
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🚴 Bike"), "Bike")
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🚴 Bike + mini-brick"), "Bike")
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🚴+🏃 Brick"), "Bike")
    }

    func testExtractWorkoutType_SwimEmoji() {
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🏊 Swim"), "Swim")
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🏊 Shakeout Swim"), "Swim")
    }

    func testExtractWorkoutType_RunEmoji() {
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🏃 Run"), "Run")
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🏃 Long Run"), "Run")
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🏃 Tempo Run"), "Run")
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🏃 Easy Jog"), "Run")
    }

    func testExtractWorkoutType_RaceEmoji() {
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🏁 RACE DAY"), "Run")
    }

    func testExtractWorkoutType_NoEmojiReturnsOriginal() {
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "Rest"), "Rest")
        XCTAssertEqual(healthKitManager.extractWorkoutType(from: "Unknown Workout"), "Unknown Workout")
    }

    // MARK: - Type Matching Tests

    func testWorkoutTypeMatches_BikeMatching() {
        XCTAssertTrue(healthKitManager.workoutTypeMatches(plannedType: "Bike", healthKitType: .cycling))
        XCTAssertFalse(healthKitManager.workoutTypeMatches(plannedType: "Bike", healthKitType: .swimming))
        XCTAssertFalse(healthKitManager.workoutTypeMatches(plannedType: "Bike", healthKitType: .running))
    }

    func testWorkoutTypeMatches_SwimMatching() {
        XCTAssertTrue(healthKitManager.workoutTypeMatches(plannedType: "Swim", healthKitType: .swimming))
        XCTAssertFalse(healthKitManager.workoutTypeMatches(plannedType: "Swim", healthKitType: .cycling))
        XCTAssertFalse(healthKitManager.workoutTypeMatches(plannedType: "Swim", healthKitType: .running))
    }

    func testWorkoutTypeMatches_RunMatching() {
        XCTAssertTrue(healthKitManager.workoutTypeMatches(plannedType: "Run", healthKitType: .running))
        XCTAssertFalse(healthKitManager.workoutTypeMatches(plannedType: "Run", healthKitType: .cycling))
        XCTAssertFalse(healthKitManager.workoutTypeMatches(plannedType: "Run", healthKitType: .swimming))
    }

    func testWorkoutTypeMatches_WalkMatching() {
        XCTAssertTrue(healthKitManager.workoutTypeMatches(plannedType: "Walk", healthKitType: .walking))
        XCTAssertFalse(healthKitManager.workoutTypeMatches(plannedType: "Walk", healthKitType: .running))
    }

    func testWorkoutTypeMatches_CaseInsensitive() {
        XCTAssertTrue(healthKitManager.workoutTypeMatches(plannedType: "BIKE", healthKitType: .cycling))
        XCTAssertTrue(healthKitManager.workoutTypeMatches(plannedType: "swim", healthKitType: .swimming))
        XCTAssertTrue(healthKitManager.workoutTypeMatches(plannedType: "RuN", healthKitType: .running))
    }

    func testWorkoutTypeMatches_UnknownTypeDoesNotMatch() {
        XCTAssertFalse(healthKitManager.workoutTypeMatches(plannedType: "Unknown", healthKitType: .cycling))
        XCTAssertFalse(healthKitManager.workoutTypeMatches(plannedType: "Yoga", healthKitType: .yoga))
    }

    // MARK: - Duration Tolerance Tests

    func testIsWorkoutCompleted_ExactDurationMatch() {
        // Setup: Plan is 60 min run on Tuesday
        let plannedWorkout = DayWorkout(
            day: "Tue",
            type: "🏃 Run",
            duration: "60 min",
            zone: "Z2",
            status: nil
        )

        let tuesdayDate = getDateForDay("Tue")
        let hkWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: tuesdayDate),
            duration: 60 * 60  // 60 minutes
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_WithinTolerance_Under() {
        // Plan is 60 min, actual is 50 min (10 min under, within ±15 tolerance)
        let plannedWorkout = DayWorkout(
            day: "Wed",
            type: "🏃 Run",
            duration: "60 min",
            zone: "Z2",
            status: nil
        )

        let wednesdayDate = getDateForDay("Wed")
        let hkWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: wednesdayDate),
            duration: 50 * 60  // 50 minutes
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_WithinTolerance_Over() {
        // Plan is 60 min, actual is 70 min (10 min over, within ±15 tolerance)
        let plannedWorkout = DayWorkout(
            day: "Thu",
            type: "🏃 Run",
            duration: "60 min",
            zone: "Z2",
            status: nil
        )

        let thursdayDate = getDateForDay("Thu")
        let hkWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: thursdayDate),
            duration: 70 * 60  // 70 minutes
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_AtToleranceBoundary_Lower() {
        // Plan is 60 min, actual is 45 min (exactly 15 min under, should match)
        let plannedWorkout = DayWorkout(
            day: "Fri",
            type: "🏃 Run",
            duration: "60 min",
            zone: "Z2",
            status: nil
        )

        let fridayDate = getDateForDay("Fri")
        let hkWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: fridayDate),
            duration: 45 * 60  // 45 minutes
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_AtToleranceBoundary_Upper() {
        // Plan is 60 min, actual is 75 min (exactly 15 min over, should match)
        let plannedWorkout = DayWorkout(
            day: "Sat",
            type: "🏃 Run",
            duration: "60 min",
            zone: "Z2",
            status: nil
        )

        let saturdayDate = getDateForDay("Sat")
        let hkWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: saturdayDate),
            duration: 75 * 60  // 75 minutes
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_ExceedsTolerance_Under() {
        // Plan is 60 min, actual is 44 min (16 min under, exceeds ±15 tolerance)
        let plannedWorkout = DayWorkout(
            day: "Sun",
            type: "🏃 Run",
            duration: "60 min",
            zone: "Z2",
            status: nil
        )

        let sundayDate = getDateForDay("Sun")
        let hkWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: sundayDate),
            duration: 44 * 60  // 44 minutes
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertFalse(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_ExceedsTolerance_Over() {
        // Plan is 60 min, actual is 76 min (16 min over, exceeds ±15 tolerance)
        let plannedWorkout = DayWorkout(
            day: "Mon",
            type: "🚴 Bike",
            duration: "60 min",
            zone: "Z2",
            status: nil
        )

        let mondayDate = getDateForDay("Mon")
        let hkWorkout = createTestWorkout(
            activityType: .cycling,
            startDate: calendar.startOfDay(for: mondayDate),
            duration: 76 * 60  // 76 minutes
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertFalse(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    // MARK: - Distance-Based Duration Tests

    func testIsWorkoutCompleted_DistanceBasedDuration_SkipsDurationCheck() {
        // Plan is 1,800yd swim (distance-based, no time check needed)
        // HK has any swim on that day, regardless of duration
        let plannedWorkout = DayWorkout(
            day: "Tue",
            type: "🏊 Swim",
            duration: "1,800yd",
            zone: "Z2",
            status: nil
        )

        let tuesdayDate = getDateForDay("Tue")

        // Even a 30-minute swim should match
        let shortSwim = createTestWorkout(
            activityType: .swimming,
            startDate: calendar.startOfDay(for: tuesdayDate),
            duration: 30 * 60  // 30 minutes (way under expected)
        )

        healthKitManager.workouts = [shortSwim]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_DistanceBasedDuration_RequiresTypeMatch() {
        // Plan is 1,800yd swim, but HK has a run
        let plannedWorkout = DayWorkout(
            day: "Fri",
            type: "🏊 Swim",
            duration: "2,000yd",
            zone: "Z2",
            status: nil
        )

        let fridayDate = getDateForDay("Fri")
        let runWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: fridayDate),
            duration: 45 * 60
        )

        healthKitManager.workouts = [runWorkout]
        XCTAssertFalse(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    // MARK: - Date Boundary Tests (No Cross-Day Bleeding)

    func testIsWorkoutCompleted_DifferentDay_NoMatch() {
        // Plan is Tuesday run, but HK workout is on Monday
        let plannedWorkout = DayWorkout(
            day: "Tue",
            type: "🏃 Run",
            duration: "45 min",
            zone: "Z2",
            status: nil
        )

        let mondayDate = getDateForDay("Mon")
        let hkWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: mondayDate),
            duration: 45 * 60
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertFalse(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_ExactDateMatch() {
        // Plan is Wednesday, HK workout is also Wednesday
        let plannedWorkout = DayWorkout(
            day: "Wed",
            type: "🏃 Run",
            duration: "45 min",
            zone: "Z2",
            status: nil
        )

        let wednesdayDate = getDateForDay("Wed")
        let hkWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: wednesdayDate),
            duration: 45 * 60
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_TimeOfDay_DoesNotMatter() {
        // HK workout can be at any time of day on the correct date
        let plannedWorkout = DayWorkout(
            day: "Thu",
            type: "🚴 Bike",
            duration: "60 min",
            zone: "Z2",
            status: nil
        )

        let thursdayDate = getDateForDay("Thu")

        // Create workout at 2 PM on Thursday
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: thursdayDate)
        dateComponents.hour = 14
        dateComponents.minute = 0
        let afternoonDate = calendar.date(from: dateComponents)!

        let hkWorkout = createTestWorkout(
            activityType: .cycling,
            startDate: afternoonDate,
            duration: 60 * 60
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    // MARK: - Type Mismatch Tests

    func testIsWorkoutCompleted_NoCrossMatching_BikeToRun() {
        // Plan is a bike workout, HK has a run
        let plannedWorkout = DayWorkout(
            day: "Tue",
            type: "🚴 Bike",
            duration: "60 min",
            zone: "Z2",
            status: nil
        )

        let tuesdayDate = getDateForDay("Tue")
        let runWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: tuesdayDate),
            duration: 60 * 60
        )

        healthKitManager.workouts = [runWorkout]
        XCTAssertFalse(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_NoCrossMatching_SwimToBike() {
        // Plan is a swim, HK has a bike
        let plannedWorkout = DayWorkout(
            day: "Wed",
            type: "🏊 Swim",
            duration: "1,800yd",
            zone: "Z2",
            status: nil
        )

        let wednesdayDate = getDateForDay("Wed")
        let bikeWorkout = createTestWorkout(
            activityType: .cycling,
            startDate: calendar.startOfDay(for: wednesdayDate),
            duration: 60 * 60
        )

        healthKitManager.workouts = [bikeWorkout]
        XCTAssertFalse(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_NoCrossMatching_RunToSwim() {
        // Plan is a run, HK has a swim
        let plannedWorkout = DayWorkout(
            day: "Fri",
            type: "🏃 Run",
            duration: "50 min",
            zone: "Z2",
            status: nil
        )

        let fridayDate = getDateForDay("Fri")
        let swimWorkout = createTestWorkout(
            activityType: .swimming,
            startDate: calendar.startOfDay(for: fridayDate),
            duration: 50 * 60
        )

        healthKitManager.workouts = [swimWorkout]
        XCTAssertFalse(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    // MARK: - Multiple Workouts Same Day Tests

    func testIsWorkoutCompleted_MultipleWorkoutsOnSameDay_FirstMatches() {
        // Friday has 2 planned workouts: swim and run
        // HK has both workouts on Friday
        // Checking swim: should find the swim HK workout
        let plannedSwim = DayWorkout(
            day: "Fri",
            type: "🏊 Swim",
            duration: "2,000yd",
            zone: "Z2",
            status: nil
        )

        let fridayDate = getDateForDay("Fri")
        let fridayStart = calendar.startOfDay(for: fridayDate)

        let swimWorkout = createTestWorkout(
            activityType: .swimming,
            startDate: fridayStart,
            duration: 40 * 60  // 40 min swim
        )

        let runWorkout = createTestWorkout(
            activityType: .running,
            startDate: Date(timeInterval: 2 * 3600, since: fridayStart),
            duration: 30 * 60  // 30 min run, 2 hours after swim
        )

        healthKitManager.workouts = [swimWorkout, runWorkout]

        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedSwim))
    }

    func testIsWorkoutCompleted_MultipleWorkoutsOnSameDay_SecondMatches() {
        // Friday has swim and run planned
        // HK has swim and run on Friday
        // Checking run: should find the run HK workout
        let plannedRun = DayWorkout(
            day: "Fri",
            type: "🏃 Run",
            duration: "30 min",
            zone: "Z1-2",
            status: nil
        )

        let fridayDate = getDateForDay("Fri")
        let fridayStart = calendar.startOfDay(for: fridayDate)

        let swimWorkout = createTestWorkout(
            activityType: .swimming,
            startDate: fridayStart,
            duration: 40 * 60
        )

        let runWorkout = createTestWorkout(
            activityType: .running,
            startDate: Date(timeInterval: 2 * 3600, since: fridayStart),
            duration: 30 * 60
        )

        healthKitManager.workouts = [swimWorkout, runWorkout]

        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedRun))
    }

    // MARK: - Last 30 Days Filtering Tests

    func testIsWorkoutCompleted_OldWorkoutNotMatched() {
        // Plan is for current week (Mar 24, 2026)
        // HK workout is from 31+ days ago (before cutoff)
        let plannedWorkout = DayWorkout(
            day: "Mon",
            type: "🏃 Run",
            duration: "45 min",
            zone: "Z2",
            status: nil
        )

        let todayDate = Date(timeIntervalSince1970: 1711324800) // Mar 25, 2026
        let thirtyTwoDaysAgo = calendar.date(byAdding: .day, value: -32, to: todayDate)!

        let oldWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: thirtyTwoDaysAgo),
            duration: 45 * 60
        )

        healthKitManager.workouts = [oldWorkout]

        // Even though date/type/duration match in isolation,
        // the workout manager filters by 30 days, so won't be in workouts array
        // This test verifies the logic doesn't incorrectly match old workouts
        XCTAssertFalse(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    // MARK: - Hour Format Duration Tests

    func testIsWorkoutCompleted_HourFormatDuration() {
        // Plan is "1.5 hr" = 90 min
        let plannedWorkout = DayWorkout(
            day: "Sun",
            type: "🚴 Bike",
            duration: "1.5 hr",
            zone: "Z2",
            status: nil
        )

        let sundayDate = getDateForDay("Sun")
        let hkWorkout = createTestWorkout(
            activityType: .cycling,
            startDate: calendar.startOfDay(for: sundayDate),
            duration: 90 * 60  // 90 minutes
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    func testIsWorkoutCompleted_ColonFormatDuration() {
        // Plan is "1:45" = 105 min
        let plannedWorkout = DayWorkout(
            day: "Sat",
            type: "🚴 Bike",
            duration: "1:45",
            zone: "Z2",
            status: nil
        )

        let saturdayDate = getDateForDay("Sat")
        let hkWorkout = createTestWorkout(
            activityType: .cycling,
            startDate: calendar.startOfDay(for: saturdayDate),
            duration: 105 * 60  // 105 minutes
        )

        healthKitManager.workouts = [hkWorkout]
        XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
    }

    // MARK: - Rest Day Tests

    func testIsRestDayCompleted_NoWorkouts() {
        // Rest day with no workouts = completed
        let restWorkout = DayWorkout(
            day: "Mon",
            type: "Rest",
            duration: "-",
            zone: "-",
            status: nil
        )

        let mondayDate = getDateForDay("Mon")
        healthKitManager.workouts = [] // No workouts on rest day

        XCTAssertTrue(healthKitManager.isRestDayCompleted(for: restWorkout))
    }

    func testIsRestDayCompleted_WithYogaWorkout() {
        // Rest day with yoga = still completed (yoga excluded from rest violation)
        let restWorkout = DayWorkout(
            day: "Sun",
            type: "Rest",
            duration: "-",
            zone: "-",
            status: nil
        )

        let sundayDate = getDateForDay("Sun")
        let yogaWorkout = createTestWorkout(
            activityType: .yoga,
            startDate: calendar.startOfDay(for: sundayDate),
            duration: 30 * 60
        )

        healthKitManager.workouts = [yogaWorkout]

        XCTAssertTrue(healthKitManager.isRestDayCompleted(for: restWorkout))
    }

    func testIsRestDayCompleted_WithWalkingWorkout() {
        // Rest day with walking = still completed (walking excluded)
        let restWorkout = DayWorkout(
            day: "Wed",
            type: "Rest",
            duration: "-",
            zone: "-",
            status: nil
        )

        let wednesdayDate = getDateForDay("Wed")
        let walkWorkout = createTestWorkout(
            activityType: .walking,
            startDate: calendar.startOfDay(for: wednesdayDate),
            duration: 30 * 60
        )

        healthKitManager.workouts = [walkWorkout]

        XCTAssertTrue(healthKitManager.isRestDayCompleted(for: restWorkout))
    }

    func testIsRestDayCompleted_WithRunWorkout() {
        // Rest day with run = NOT completed (run not allowed)
        let restWorkout = DayWorkout(
            day: "Thu",
            type: "Rest",
            duration: "-",
            zone: "-",
            status: nil
        )

        let thursdayDate = getDateForDay("Thu")
        let runWorkout = createTestWorkout(
            activityType: .running,
            startDate: calendar.startOfDay(for: thursdayDate),
            duration: 30 * 60
        )

        healthKitManager.workouts = [runWorkout]

        XCTAssertFalse(healthKitManager.isRestDayCompleted(for: restWorkout))
    }

    func testIsRestDayCompleted_WithBikeWorkout() {
        // Rest day with bike = NOT completed
        let restWorkout = DayWorkout(
            day: "Fri",
            type: "Rest",
            duration: "-",
            zone: "-",
            status: nil
        )

        let fridayDate = getDateForDay("Fri")
        let bikeWorkout = createTestWorkout(
            activityType: .cycling,
            startDate: calendar.startOfDay(for: fridayDate),
            duration: 60 * 60
        )

        healthKitManager.workouts = [bikeWorkout]

        XCTAssertFalse(healthKitManager.isRestDayCompleted(for: restWorkout))
    }
}
#endif
