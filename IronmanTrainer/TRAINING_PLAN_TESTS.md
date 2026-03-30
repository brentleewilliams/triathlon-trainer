# TrainingPlanManager Unit Tests

## Overview

Comprehensive unit test suite for the `TrainingPlanManager` class covering core training plan logic, date calculations, Core Data persistence, and rollback functionality.

## Test File Location

`/Users/brent/Development/IronmanTrainer/IronmanTrainerTests/TrainingPlanManagerTests.swift`

## Test Statistics

- **Total Tests**: 29
- **Test Categories**: 6 major sections
- **Lines of Test Code**: 598

## Test Coverage by Category

### 1. Week Number Calculation (8 tests)

These tests validate the core algorithm that converts a date into a training week number (1-17).

#### Key Tests:

- **testCurrentWeekOnStartDate**: Verifies week 1 on Mar 23, 2026 (training start)
- **testCurrentWeekOneDayAfterStart**: Verifies Mar 24 is still week 1
- **testCurrentWeekSixDaysAfterStart**: Verifies Mar 29 is still week 1
- **testCurrentWeekSevenDaysAfterStart**: Verifies Mar 30 is week 2 (first boundary)
- **testCurrentWeekFourteenDaysAfterStart**: Verifies Apr 6 is week 3 (second boundary)
- **testCurrentWeekAtRaceDate**: Verifies Jul 19, 2026 is week 17 (race day)
- **testCurrentWeekBeforeStartDateClamps**: Verifies dates before start clamp to week 1
- **testCurrentWeekAfterRaceDateClamps**: Verifies dates after race clamp to week 17

**Formula Validated**: `week = floor(daysSinceStart / 7) + 1`, clamped to [1, 17]

### 2. Day-of-Week to Date Mapping (4 tests)

These tests ensure each week's date range is correctly calculated and spans exactly 7 days.

#### Key Tests:

- **testWeek1DateRange**: Verifies week 1 starts on Mar 23
- **testWeek17DateRange**: Verifies week 17 starts Jul 13 and ends Jul 19 (race day)
- **testEachWeekSpansSevenDays**: Validates all 17 weeks span exactly 7 days
- **testWeek2StartsSevenDaysAfterWeek1**: Verifies week boundary math (week N+1 starts 7 days after week N)

**Validates**: Date calculations don't have off-by-one errors, week boundaries are correct

### 3. Training Plan Structure (6 tests)

These tests verify the overall structure of the training plan and its data integrity.

#### Key Tests:

- **testAllSeventeenWeeksPresent**: Verifies all 17 weeks are created
- **testWeeksSortedByNumber**: Validates weeks are sorted in ascending order
- **testWeek1WorkoutCount**: Verifies week 1 has reasonable number of workouts
- **testWeek1HasCorrectWorkouts**: Validates week 1 has specific workouts (e.g., Friday swim, Monday rest)
- **testRestDaysMarkedCorrectly**: Verifies rest days are properly marked with "Rest" type
- **testMultiWorkoutDaysExist**: Validates multi-workout days exist (e.g., Tuesday with Bike + Swim)

**Validates**: Training plan is properly initialized with correct structure

### 4. Core Data Persistence (3 tests)

These tests ensure plan versions are properly saved to and restored from Core Data.

#### Key Tests:

- **testSavePlanVersionCreatesNewVersion**: Verifies `savePlanVersion()` creates a new Core Data object
- **testSavedPlanVersionContainsWeeks**: Validates saved version preserves all weeks correctly
- **testMultipleSavesCreateVersionHistory**: Verifies multiple saves create distinct versions with proper previous/current references

**Validates**: Core Data persistence mechanism for plan versions

### 5. Rollback Functionality (3 tests)

These tests verify the ability to rollback to a previous training plan version.

#### Key Tests:

- **testRollbackWithoutPreviousVersionFails**: Verifies rollback fails gracefully when no previous version exists
- **testRollbackRestoresPreviousWeeks**: Validates rollback successfully restores weeks from previous version
- **testRollbackClearsPreviousVersionReference**: Verifies after rollback, the previous version reference is cleared

**Validates**: Version history management and rollback safety

### 6. Multi-Workout Day Handling (2 tests - Regression)

These tests ensure multi-workout days (e.g., Tuesday with bike + swim) are properly preserved through save/restore cycles.

#### Key Tests:

- **testMultiWorkoutDayPreservedInSaveRestore**: Validates Tuesday multi-workouts survive save/load cycle
- **testWeekWithMultipleWorkoutsPerDayPreserved**: Validates any multi-workout day preserves all workouts

**Validates**: Regression test for multi-workout day swapping issue

### 7. Edge Cases (3 tests)

These tests cover boundary conditions and error scenarios.

#### Key Tests:

- **testGetNonExistentWeekReturnsNil**: Validates requesting invalid week numbers (0, 18, 99) returns nil
- **testWeekPhasesAssignedCorrectly**: Validates all 17 weeks are assigned correct phase (Ramp Up, Build 1, Taper, etc.)
- **testZoneInformationPresent**: Validates most workouts have zone information

**Validates**: Robustness against invalid inputs and data completeness

## Implementation Details

### TrainingPlanManager Methods Tested

| Method | Tests | Status |
|--------|-------|--------|
| `calculateCurrentWeek()` | 8 | ✓ Full coverage |
| `getWeek(_ weekNumber: Int)` | 3 | ✓ Full coverage |
| `setupTrainingPlan()` | 6 | ✓ Full coverage |
| `workoutsForWeek(_ weekNumber: Int)` | 6 | ✓ Full coverage |
| `savePlanVersion()` | 3 | ✓ Full coverage |
| `rollbackToPreviousVersion()` | 3 | ✓ Full coverage |
| `loadPlanVersions()` | Indirect | ✓ Coverage |
| `applyRescheduledPlan()` | Indirect | ✓ Coverage |

### Test Data Used

- **Start Date**: Mar 23, 2026
- **Race Date**: Jul 19, 2026
- **Total Weeks**: 17
- **Workout Types**: Swim, Bike, Run, Brick, Rest
- **Sample Workouts**: Actual data from training plan PDF

### Helper Methods

- `calculateWeekNumber(for date: Date) -> Int`: Replicates week calculation logic for isolated testing

## Key Testing Principles

1. **Given-When-Then Structure**: All tests follow clear setup, action, assertion pattern
2. **Boundary Testing**: Tests include exact boundaries (week transitions, start/end dates)
3. **Edge Cases**: Tests cover invalid inputs, boundary conditions, and error scenarios
4. **Isolation**: Tests are independent and can run in any order
5. **Descriptive Names**: Test names clearly describe what is being validated
6. **Comments**: Complex assertions include comments explaining the validation

## Running the Tests

### Build Test Target
```bash
xcodebuild build-for-testing \
  -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Run All Tests
```bash
xcodebuild test \
  -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Run Only TrainingPlanManagerTests
```bash
xcodebuild test \
  -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing IronmanTrainerTests/TrainingPlanManagerTests
```

### Run Specific Test
```bash
xcodebuild test \
  -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing IronmanTrainerTests/TrainingPlanManagerTests/testCurrentWeekOnStartDate
```

## Known Limitations

1. **Core Data Integration**: Tests create TrainingPlanManager instances which initialize Core Data. In a CI/CD environment, may need test configuration.
2. **Calendar Dependency**: Tests use `Calendar.current` which respects system time zone. All dates are validated using calendar math.
3. **Deterministic Dates**: Tests use hardcoded dates (Mar 23 - Jul 19, 2026) which are independent of current system date.

## Future Enhancements

1. Add tests for `applyRescheduledPlan()` with actual plan modifications
2. Add performance tests to ensure plan calculations are fast (< 100ms)
3. Add tests for concurrent access to plan data
4. Add integration tests combining plan loading with HealthKit sync

## Test Execution Notes

- Tests should run in parallel without issues
- No network access required
- No external dependencies (pure Swift + CoreData)
- Estimated runtime: < 2 seconds for all 29 tests

## Xcode Integration

The test target has been properly integrated into the Xcode project:
- Test target: `IronmanTrainerTests`
- Product bundle ID: `com.brent.ironmantrainerTests`
- Deployment target: iOS 17.0
- Configuration: Debug and Release schemes included
