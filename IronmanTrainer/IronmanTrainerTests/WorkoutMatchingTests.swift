import XCTest
import HealthKit
@testable import Race1_Trainer

/// Tests for the standalone workout matching helper functions
/// defined in WorkoutMatchingHelpers.swift.
///
/// The integration tests (isWorkoutCompleted, isRestDayCompleted) that were
/// previously here have been removed because those methods live on SwiftUI views
/// and cannot be tested independently without app source changes.
class WorkoutMatchingTests: XCTestCase {

    // MARK: - Duration Parsing Tests (parseWorkoutDuration)

    func testParseDuration_MinutesFormat() {
        XCTAssertEqual(parseWorkoutDuration("60 min"), 60)
        XCTAssertEqual(parseWorkoutDuration("45 min"), 45)
        XCTAssertEqual(parseWorkoutDuration("30min"), 30) // No space
    }

    func testParseDuration_HoursFormat() {
        XCTAssertEqual(parseWorkoutDuration("1.5 hr"), 90)
        XCTAssertEqual(parseWorkoutDuration("2 hr"), 120)
        XCTAssertEqual(parseWorkoutDuration("1hr"), 60) // No space
    }

    func testParseDuration_ColonFormat() {
        // "1:00" -> 60 min
        XCTAssertEqual(parseWorkoutDuration("1:00"), 60)
        // "1:30" -> 90 min
        XCTAssertEqual(parseWorkoutDuration("1:30"), 90)
        // "1:45" -> 105 min
        XCTAssertEqual(parseWorkoutDuration("1:45"), 105)
        // "2:15" -> 135 min
        XCTAssertEqual(parseWorkoutDuration("2:15"), 135)
    }

    func testParseDuration_DistanceBasedReturnsNil() {
        XCTAssertNil(parseWorkoutDuration("1,800yd"))
        XCTAssertNil(parseWorkoutDuration("2,000yd"))
        XCTAssertNil(parseWorkoutDuration("3,200yd"))
    }

    func testParseDuration_RestReturnsNil() {
        XCTAssertNil(parseWorkoutDuration("Rest"))
        XCTAssertNil(parseWorkoutDuration("rest"))
    }

    func testParseDuration_DashReturnsNil() {
        // "-" is not distance-based or rest, so it returns nil because
        // it doesn't match any known format
        XCTAssertNil(parseWorkoutDuration("-"))
    }

    func testParseDuration_CaseInsensitive() {
        XCTAssertEqual(parseWorkoutDuration("60 MIN"), 60)
        XCTAssertEqual(parseWorkoutDuration("1.5 HR"), 90)
    }

    // MARK: - Type Extraction Tests (extractWorkoutTypeFromString)

    func testExtractWorkoutType_BikeEmoji() {
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F6B4} Bike"), "Bike")
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F6B4} Bike + mini-brick"), "Bike")
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F6B4}+\u{1F3C3} Brick"), "Bike")
    }

    func testExtractWorkoutType_SwimEmoji() {
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F3CA} Swim"), "Swim")
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F3CA} Shakeout Swim"), "Swim")
    }

    func testExtractWorkoutType_RunEmoji() {
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F3C3} Run"), "Run")
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F3C3} Long Run"), "Run")
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F3C3} Tempo Run"), "Run")
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F3C3} Easy Jog"), "Run")
    }

    func testExtractWorkoutType_RaceEmoji() {
        XCTAssertEqual(extractWorkoutTypeFromString("\u{1F3C1} RACE DAY"), "Run")
    }

    func testExtractWorkoutType_NoEmojiReturnsOriginal() {
        XCTAssertEqual(extractWorkoutTypeFromString("Rest"), "Rest")
        XCTAssertEqual(extractWorkoutTypeFromString("Unknown Workout"), "Unknown Workout")
    }

    // MARK: - Type Matching Tests (workoutTypeMatchesActivityType)

    func testWorkoutTypeMatches_BikeMatching() {
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: "Bike", healthKitType: .cycling))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: "Bike", healthKitType: .swimming))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: "Bike", healthKitType: .running))
    }

    func testWorkoutTypeMatches_SwimMatching() {
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: "Swim", healthKitType: .swimming))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: "Swim", healthKitType: .cycling))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: "Swim", healthKitType: .running))
    }

    func testWorkoutTypeMatches_RunMatching() {
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: "Run", healthKitType: .running))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: "Run", healthKitType: .cycling))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: "Run", healthKitType: .swimming))
    }

    func testWorkoutTypeMatches_WalkMatching() {
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: "Walk", healthKitType: .walking))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: "Walk", healthKitType: .running))
    }

    func testWorkoutTypeMatches_CaseInsensitive() {
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: "BIKE", healthKitType: .cycling))
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: "swim", healthKitType: .swimming))
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: "RuN", healthKitType: .running))
    }

    func testWorkoutTypeMatches_UnknownTypeDoesNotMatch() {
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: "Unknown", healthKitType: .cycling))
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: "Yoga", healthKitType: .yoga))
    }

    // MARK: - End-to-End Extraction + Matching

    /// Verify that extracting a type from an emoji-prefixed string
    /// and then matching it against a HealthKit type works correctly.
    func testExtractThenMatch_BikeWorkout() {
        let extracted = extractWorkoutTypeFromString("\u{1F6B4} Bike")
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: extracted, healthKitType: .cycling))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: extracted, healthKitType: .running))
    }

    func testExtractThenMatch_SwimWorkout() {
        let extracted = extractWorkoutTypeFromString("\u{1F3CA} Swim")
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: extracted, healthKitType: .swimming))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: extracted, healthKitType: .cycling))
    }

    func testExtractThenMatch_RunWorkout() {
        let extracted = extractWorkoutTypeFromString("\u{1F3C3} Tempo Run")
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: extracted, healthKitType: .running))
        XCTAssertFalse(workoutTypeMatchesActivityType(plannedType: extracted, healthKitType: .swimming))
    }

    func testExtractThenMatch_BrickFavorsBike() {
        // Brick workouts (🚴+🏃) extract as "Bike" because 🚴 comes first
        let extracted = extractWorkoutTypeFromString("\u{1F6B4}+\u{1F3C3} Brick")
        XCTAssertEqual(extracted, "Bike")
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: extracted, healthKitType: .cycling))
    }

    func testExtractThenMatch_RaceDayMatchesRunning() {
        let extracted = extractWorkoutTypeFromString("\u{1F3C1} RACE DAY")
        XCTAssertEqual(extracted, "Run")
        XCTAssertTrue(workoutTypeMatchesActivityType(plannedType: extracted, healthKitType: .running))
    }

    // MARK: - Duration Parsing Edge Cases

    func testParseDuration_LargeColonValues() {
        XCTAssertEqual(parseWorkoutDuration("3:35"), 215)
        XCTAssertEqual(parseWorkoutDuration("3:50"), 230)
        XCTAssertEqual(parseWorkoutDuration("2:55"), 175)
    }

    func testParseDuration_SmallDurations() {
        XCTAssertEqual(parseWorkoutDuration("15min"), 15)
        XCTAssertEqual(parseWorkoutDuration("20 min"), 20)
    }

    func testParseDuration_EmptyString() {
        XCTAssertNil(parseWorkoutDuration(""))
    }

    func testParseDuration_GarbageInput() {
        XCTAssertNil(parseWorkoutDuration("Denver→Portland"))
        XCTAssertNil(parseWorkoutDuration("Race"))
        XCTAssertNil(parseWorkoutDuration("~5:45-5:58"))
    }
}
