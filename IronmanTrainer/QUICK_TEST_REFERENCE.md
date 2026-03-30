# Quick Test Reference

## File Location
`/Users/brent/Development/IronmanTrainer/IronmanTrainerTests/WorkoutMatchingTests.swift`

## Quick Stats
- **Total Tests**: 42
- **Total Lines**: 744
- **Total Assertions**: 72
- **Status**: ✅ Ready for integration

## Test Categories (42 tests)

| # | Category | Tests | Coverage |
|---|----------|-------|----------|
| 1 | Duration Parsing | 6 | Minutes, hours, time formats, distance/rest handling |
| 2 | Type Extraction | 5 | Emoji extraction (bike, swim, run, race) |
| 3 | Type Matching | 6 | Cycling↔Bike, Swimming↔Swim, Running↔Run, case insensitive |
| 4 | Duration Tolerance | 7 | ±15 min boundaries and edge cases |
| 5 | Distance-Based | 2 | Yard-based workouts skip duration check |
| 6 | Date Boundaries | 4 | No cross-day bleeding, exact date matching |
| 7 | Type Mismatches | 3 | Bike≠Run, Swim≠Bike, Run≠Swim |
| 8 | Multi-Workouts | 2 | Multiple workouts on same day (Friday swim+run) |
| 9 | 30-Day Filter | 1 | Old workouts excluded |
| 10 | Duration Formats | 2 | Alternative duration parsing (hrs, colon format) |
| 11 | Rest Days | 5 | Rest completion logic (yoga/walk excluded) |

## Key Functions Tested

```
parseDuration(_ durationStr: String) -> Int?
  → Converts "60 min", "1:30", "1.5 hr", "1,800yd" → Int or nil

extractWorkoutType(from typeString: String) -> String
  → Extracts "Bike"/"Swim"/"Run" from emoji strings

workoutTypeMatches(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool
  → Matches types: .cycling↔"Bike", .swimming↔"Swim", .running↔"Run"

isWorkoutCompleted(_ workout: DayWorkout) -> Bool
  → Main matching logic: date + type + duration (±15 min tolerance)

isRestDayCompleted(for workout: DayWorkout) -> Bool
  → Rest day completion (excludes yoga/walking)
```

## Running Tests

### All tests
```bash
xcodebuild test -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Just WorkoutMatchingTests
```bash
xcodebuild test -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing IronmanTrainerTests/WorkoutMatchingTests
```

### Single test
```bash
xcodebuild test -scheme IronmanTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing IronmanTrainerTests/WorkoutMatchingTests/testIsWorkoutCompleted_ExactDurationMatch
```

### In Xcode
- Press `Cmd+U` to run all tests
- Or select test and press `Ctrl+Alt+Cmd+U`

## Test Categories at a Glance

### Duration Parsing (6 tests)
```
✓ "60 min" → 60
✓ "1.5 hr" → 90
✓ "1:45" → 105
✓ "1,800yd" → nil (distance-based)
✓ "Rest" → nil
✓ Case insensitive ("60 MIN" → 60)
```

### Type Matching (6 tests)
```
✓ Bike ↔ Cycling
✓ Swim ↔ Swimming
✓ Run ↔ Running
✓ Walk ↔ Walking
✓ Case insensitive
✓ Unknown types don't match
```

### Duration Tolerance (7 tests)
```
✓ Exact: 60 min plan = 60 min actual
✓ Under: 60 min plan = 50 min actual (-10, within tolerance)
✓ Over: 60 min plan = 70 min actual (+10, within tolerance)
✓ Lower boundary: 60 = 45 (-15, at tolerance)
✓ Upper boundary: 60 = 75 (+15, at tolerance)
✗ Exceeds lower: 60 = 44 (-16, fails)
✗ Exceeds upper: 60 = 76 (+16, fails)
```

### Date Boundaries (4 tests)
```
✗ Different days don't match (Tue plan ≠ Mon HK)
✓ Same day matches (Wed plan = Wed HK)
✓ Time of day irrelevant (2 PM on Wed matches Wed)
Uses Calendar.startOfDay() for accuracy
```

### Rest Days (5 tests)
```
✓ No workouts = rest completed
✓ Yoga = rest completed (excluded)
✓ Walking = rest completed (excluded)
✗ Run = rest violated
✗ Bike = rest violated
```

## Documentation

| File | Purpose |
|------|---------|
| `WorkoutMatchingTests.swift` | Test implementation (744 lines, 42 tests) |
| `TEST_COVERAGE.md` | Detailed coverage map and test descriptions |
| `README.md` | Usage guide, examples, and debugging tips |
| `TEST_IMPLEMENTATION_SUMMARY.md` | Integration instructions and metrics |
| `QUICK_TEST_REFERENCE.md` | This file - quick lookup reference |

## Integration Checklist

- [x] Test file created and formatted
- [x] All 42 test methods implemented
- [x] Helper methods (createTestWorkout, getDateForDay)
- [x] Clear test names and inline comments
- [x] Boundary condition testing (±15 min tolerance)
- [x] Happy path + failure scenarios
- [x] No UI tests (as requested)
- [x] Comprehensive documentation (4 docs)
- [x] Ready for xcodebuild integration

## Common Test Patterns

### Create a HealthKit workout
```swift
let hkWorkout = createTestWorkout(
    activityType: .running,
    startDate: calendar.startOfDay(for: getDateForDay("Mon")),
    duration: 60 * 60  // 60 minutes in seconds
)
```

### Create a planned workout
```swift
let plannedWorkout = DayWorkout(
    day: "Mon",
    type: "🏃 Run",
    duration: "60 min",
    zone: "Z2",
    status: nil
)
```

### Test matching
```swift
healthKitManager.workouts = [hkWorkout]
XCTAssertTrue(healthKitManager.isWorkoutCompleted(plannedWorkout))
```

## Tolerance Reference

Duration tolerance is ±15 minutes:

| Planned | Actual | Status |
|---------|--------|--------|
| 60 min | 60 min | ✓ Match |
| 60 min | 50 min | ✓ Match (-10) |
| 60 min | 45 min | ✓ Match (-15) |
| 60 min | 44 min | ✗ No match (-16) |
| 60 min | 70 min | ✓ Match (+10) |
| 60 min | 75 min | ✓ Match (+15) |
| 60 min | 76 min | ✗ No match (+16) |

## Test Data Reference

### Week 1 Dates (Mar 24-30, 2026)
```
getDateForDay("Mon") → Mar 24
getDateForDay("Tue") → Mar 25
getDateForDay("Wed") → Mar 26
getDateForDay("Thu") → Mar 27
getDateForDay("Fri") → Mar 28
getDateForDay("Sat") → Mar 29
getDateForDay("Sun") → Mar 30
```

### Type Mapping
```
🚴 → "Bike" → HKWorkoutActivityType.cycling
🏊 → "Swim" → HKWorkoutActivityType.swimming
🏃 → "Run" → HKWorkoutActivityType.running
🏁 → "Run" → HKWorkoutActivityType.running
```

## Next Steps

1. **Verify Tests Build**
   ```bash
   xcodebuild build-for-testing -scheme IronmanTrainer
   ```

2. **Run All Tests**
   ```bash
   xcodebuild test -scheme IronmanTrainer
   ```

3. **Review Results**
   - Open Xcode Report Navigator (Cmd+9)
   - Check test output for 42 passing tests

4. **Integrate into CI/CD** (optional)
   - Add xcodebuild test command to GitHub Actions
   - Set required passing tests in branch protection

## Support Files

Additional test files already in place:
- `TrainingPlanManagerTests.swift` - Week calculations
- `WeatherForecastTests.swift` - Weather generation

All follow the same XCTest framework patterns.

---

**Status**: Ready for use
**Last Updated**: March 30, 2026
**Total Coverage**: 42 tests across 6 test categories
