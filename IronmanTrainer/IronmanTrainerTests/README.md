# IronmanTrainer Unit Tests

This directory contains comprehensive unit tests for the IronmanTrainer iOS app, focusing on core business logic including workout matching, training plan management, and weather forecasting.

## Test Files

### 1. WorkoutMatchingTests.swift
Comprehensive tests for the workout matching algorithm that determines if a HealthKit workout matches a planned training workout.

**Coverage:**
- Duration parsing (minutes, hours, time format)
- Type extraction from emoji strings
- Type matching logic
- Duration tolerance (±15 minutes)
- Distance-based workout handling
- Date boundary testing (prevents cross-day bleeding)
- Type mismatch prevention
- Multi-workout day support
- Rest day completion logic

**Test Count:** 42 tests

**Key Functions Tested:**
- `parseDuration(_ durationStr: String) -> Int?`
- `extractWorkoutType(from typeString: String) -> String`
- `workoutTypeMatches(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool`
- `isWorkoutCompleted(_ workout: DayWorkout) -> Bool`
- `isRestDayCompleted(for workout: DayWorkout) -> Bool`

### 2. TrainingPlanManagerTests.swift
Tests for the training plan management system, including week calculations and plan persistence.

### 3. WeatherForecastTests.swift
Tests for deterministic weather forecast generation with seasonal progression and daily variation.

## Running Tests

### Run All Tests
```bash
xcodebuild test -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Run Specific Test Class
```bash
xcodebuild test -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing IronmanTrainerTests/WorkoutMatchingTests
```

### Run Specific Test Method
```bash
xcodebuild test -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing IronmanTrainerTests/WorkoutMatchingTests/testIsWorkoutCompleted_ExactDurationMatch
```

### Run in Xcode
1. Open `IronmanTrainer.xcodeproj`
2. Press `Cmd+U` to run all tests
3. Or select a specific test and press `Ctrl+Alt+Cmd+U`

## Test Organization

Tests are organized by functionality:

### WorkoutMatchingTests.swift Structure
```
WorkoutMatchingTests
├── Duration Parsing Tests (6)
├── Type Extraction Tests (5)
├── Type Matching Tests (6)
├── Duration Tolerance Tests (7)
├── Distance-Based Duration Tests (2)
├── Date Boundary Tests (4)
├── Type Mismatch Tests (3)
├── Multiple Workouts Same Day Tests (2)
├── Last 30 Days Filtering Tests (1)
├── Duration Format Tests (2)
└── Rest Day Tests (5)
```

## Test Examples

### Example 1: Duration Tolerance Testing
```swift
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
```

### Example 2: Date Boundary Testing
```swift
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
```

### Example 3: Type Extraction Testing
```swift
func testExtractWorkoutType_BikeEmoji() {
    XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🚴 Bike"), "Bike")
    XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🚴 Bike + mini-brick"), "Bike")
    XCTAssertEqual(healthKitManager.extractWorkoutType(from: "🚴+🏃 Brick"), "Bike")
}
```

## Test Data Conventions

### Week Reference
Tests use week 1 (March 24-30, 2026) as the reference period:
- Monday = March 24
- Tuesday = March 25
- Wednesday = March 26
- Thursday = March 27
- Friday = March 28
- Saturday = March 29
- Sunday = March 30

### Duration Parsing Examples
- `"60 min"` → 60 minutes
- `"1:00"` → 60 minutes
- `"1.5 hr"` → 90 minutes
- `"1,800yd"` → nil (distance-based, no time check)
- `"Rest"` → nil (rest day)

### Type Mapping
- 🚴 → "Bike" ↔ HKWorkoutActivityType.cycling
- 🏊 → "Swim" ↔ HKWorkoutActivityType.swimming
- 🏃 → "Run" ↔ HKWorkoutActivityType.running
- 🏁 → "Run" ↔ HKWorkoutActivityType.running

## Key Testing Principles

### 1. Boundary Testing
Tests include exact tolerance boundaries and values just outside:
- ±15 min tolerance: Tests at -15, -16, +15, +16 minutes

### 2. Type Safety
All tests validate type matching is case-insensitive and non-matching

### 3. Date Accuracy
Calendar-based testing prevents off-by-one errors using `Calendar.startOfDay()`

### 4. No Cross-Matching
Explicit tests ensure workout types don't incorrectly match:
- Bike planned ≠ Run HK
- Swim planned ≠ Bike HK
- Run planned ≠ Swim HK

### 5. Happy Path & Edge Cases
Each test category includes both successful and failing scenarios

## Test Assertions

Common assertion patterns used:

```swift
// Equality assertions
XCTAssertEqual(result, expected)
XCTAssertNil(result)

// Boolean assertions
XCTAssertTrue(result)
XCTAssertFalse(result)

// Multiple assertions per test
XCTAssertEqual(healthKitManager.parseDuration("60 min"), 60)
XCTAssertEqual(healthKitManager.parseDuration("45 min"), 45)
XCTAssertEqual(healthKitManager.parseDuration("30min"), 30)
```

## Helper Methods

### createTestWorkout()
Creates a test HKWorkout object:
```swift
func createTestWorkout(
    activityType: HKWorkoutActivityType,
    startDate: Date,
    duration: TimeInterval  // in seconds
) -> HKWorkout
```

### getDateForDay()
Returns the date for a specific weekday:
```swift
func getDateForDay(_ dayName: String) -> Date
// Input: "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"
// Output: Absolute Date for that weekday in week 1 (Mar 24-30, 2026)
```

## Debugging Tests

### View Test Results in Xcode
1. Open `Report Navigator` (Cmd+9)
2. Select the latest test run
3. View detailed results and assertions

### Print Debugging
Tests can use `print()` statements that appear in test output:
```swift
func testExample() {
    let result = healthKitManager.parseDuration("60 min")
    print("Parsed duration: \(result)")  // Appears in test log
    XCTAssertEqual(result, 60)
}
```

### Breakpoint Debugging
1. Click in the test file to set a breakpoint
2. Run the test
3. Debug normally (step through, inspect variables)

## Future Test Coverage

### Recommended Additions
- Mock HealthKitManager for isolated unit testing
- Week boundary calculation tests
- Multi-week workout history validation
- Timezone handling edge cases
- Integration tests with real HealthKit (on physical device)

### Excluded (As Designed)
- UI tests (SwiftUI view testing)
- Performance benchmarks
- Claude API mocking
- Real HealthKit integration in unit tests

## CI/CD Integration

Tests can be integrated into continuous integration:

```yaml
# Example GitHub Actions workflow
- name: Run Unit Tests
  run: |
    xcodebuild test \
      -scheme IronmanTrainer \
      -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Documentation

- **WorkoutMatchingTests.swift** - This file (test implementation)
- **TEST_COVERAGE.md** - Detailed test coverage documentation
- **TEST_IMPLEMENTATION_SUMMARY.md** - Implementation summary and integration guide

## Contact & Maintenance

Tests are maintained as part of the IronmanTrainer development process. Update tests when:
- Matching logic changes
- New workout types are added
- Duration parsing format changes
- Date handling is modified
- Rest day rules change

## License

Tests are part of the IronmanTrainer project and follow the same license.
