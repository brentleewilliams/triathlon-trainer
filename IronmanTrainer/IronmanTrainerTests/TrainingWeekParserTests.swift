import XCTest
@testable import Race1_Trainer

final class TrainingWeekParserTests: XCTestCase {

    // MARK: - Happy path

    func testParse_validJSON_returnsWeeks() throws {
        let json = """
        [
          {
            "weekNumber": 1,
            "phase": "Base",
            "startDate": "2026-01-05",
            "endDate": "2026-01-11",
            "workouts": [
              {"day": "Mon", "type": "🏃 Run", "duration": "45min", "zone": "Z2"},
              {"day": "Wed", "type": "🚴 Bike", "duration": "60min", "zone": "Z2"},
              {"day": "Sat", "type": "🏊 Swim", "duration": "30min", "zone": "Z2"}
            ]
          }
        ]
        """
        let weeks = try TrainingWeekParser.parse(json)
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks[0].weekNumber, 1)
        XCTAssertEqual(weeks[0].phase, "Base")
        XCTAssertEqual(weeks[0].workouts.count, 3)
    }

    func testParse_multipleWeeks_sortedByWeekNumber() throws {
        let json = """
        [
          {"weekNumber": 3, "phase": "Peak", "startDate": "2026-01-19", "endDate": "2026-01-25",
           "workouts": [{"day": "Mon", "type": "Rest", "duration": "-", "zone": "-"}]},
          {"weekNumber": 1, "phase": "Base", "startDate": "2026-01-05", "endDate": "2026-01-11",
           "workouts": [{"day": "Mon", "type": "🏃 Run", "duration": "30min", "zone": "Z2"}]},
          {"weekNumber": 2, "phase": "Build", "startDate": "2026-01-12", "endDate": "2026-01-18",
           "workouts": [{"day": "Tue", "type": "🚴 Bike", "duration": "45min", "zone": "Z3"}]}
        ]
        """
        let weeks = try TrainingWeekParser.parse(json)
        XCTAssertEqual(weeks.map { $0.weekNumber }, [1, 2, 3])
        XCTAssertEqual(weeks.map { $0.phase }, ["Base", "Build", "Peak"])
    }

    func testParse_markdownFenced_stripsAndParses() throws {
        let json = """
        ```json
        [
          {"weekNumber": 1, "phase": "Base", "startDate": "2026-01-05", "endDate": "2026-01-11",
           "workouts": [{"day": "Mon", "type": "Rest", "duration": "-", "zone": "-"}]}
        ]
        ```
        """
        let weeks = try TrainingWeekParser.parse(json)
        XCTAssertEqual(weeks.count, 1)
    }

    func testParse_backtickFencedOnly_stripsAndParses() throws {
        let json = """
        ```
        [
          {"weekNumber": 1, "phase": "Build", "startDate": "2026-02-02", "endDate": "2026-02-08",
           "workouts": [{"day": "Wed", "type": "🏊 Swim", "duration": "40min", "zone": "Z1"}]}
        ]
        ```
        """
        let weeks = try TrainingWeekParser.parse(json)
        XCTAssertEqual(weeks[0].phase, "Build")
    }

    func testParse_dataOverload_matchesStringOverload() throws {
        let json = """
        [{"weekNumber": 1, "phase": "Taper", "startDate": "2026-07-13", "endDate": "2026-07-19",
          "workouts": [{"day": "Mon", "type": "Rest", "duration": "-", "zone": "-"}]}]
        """
        let fromString = try TrainingWeekParser.parse(json)
        let data = json.data(using: .utf8)!
        let fromData = try TrainingWeekParser.parse(data)
        XCTAssertEqual(fromString.count, fromData.count)
        XCTAssertEqual(fromString[0].weekNumber, fromData[0].weekNumber)
        XCTAssertEqual(fromString[0].phase, fromData[0].phase)
    }

    // MARK: - Workout fields

    func testParse_workoutFields_mappedCorrectly() throws {
        let json = """
        [{"weekNumber": 1, "phase": "Base", "startDate": "2026-01-05", "endDate": "2026-01-11",
          "workouts": [
            {"day": "Fri", "type": "🚴 Bike", "duration": "90min", "zone": "Z3",
             "nutritionTarget": "60g carbs/hr", "notes": "Stay aero"}
          ]}]
        """
        let weeks = try TrainingWeekParser.parse(json)
        let workout = try XCTUnwrap(weeks.first?.workouts.first)
        XCTAssertEqual(workout.day, "Fri")
        XCTAssertEqual(workout.type, "🚴 Bike")
        XCTAssertEqual(workout.duration, "90min")
        XCTAssertEqual(workout.zone, "Z3")
        XCTAssertEqual(workout.nutritionTarget, "60g carbs/hr")
        XCTAssertEqual(workout.notes, "Stay aero")
    }

    func testParse_missingOptionalFields_usesDefaults() throws {
        let json = """
        [{"weekNumber": 1, "phase": "Base", "startDate": "2026-01-05", "endDate": "2026-01-11",
          "workouts": [{"day": "Mon", "type": "Rest"}]}]
        """
        let weeks = try TrainingWeekParser.parse(json)
        let workout = try XCTUnwrap(weeks.first?.workouts.first)
        XCTAssertEqual(workout.duration, "-")
        XCTAssertEqual(workout.zone, "-")
        XCTAssertNil(workout.nutritionTarget)
        XCTAssertNil(workout.notes)
    }

    // MARK: - All-same-day redistribution

    func testParse_allWorkoutsSameDay_redistributesMondayToSunday() throws {
        // 7 workouts all on "Mon" — should be spread across the week
        let workouts = (0..<7).map { _ in
            """
            {"day": "Mon", "type": "🏃 Run", "duration": "30min", "zone": "Z2"}
            """
        }.joined(separator: ",")
        let json = """
        [{"weekNumber": 1, "phase": "Base", "startDate": "2026-01-05", "endDate": "2026-01-11",
          "workouts": [\(workouts)]}]
        """
        let weeks = try TrainingWeekParser.parse(json)
        let days = weeks[0].workouts.map { $0.day }
        XCTAssertEqual(Set(days).count, 7, "Expected workouts redistributed across 7 different days")
        XCTAssertEqual(days[0], "Mon")
        XCTAssertEqual(days[6], "Sun")
    }

    func testParse_fewWorkoutsSameDay_noRedistribution() throws {
        // 3 workouts on the same day — below the 5-workout threshold, no redistribution
        let json = """
        [{"weekNumber": 1, "phase": "Base", "startDate": "2026-01-05", "endDate": "2026-01-11",
          "workouts": [
            {"day": "Mon", "type": "🏃 Run", "duration": "30min", "zone": "Z2"},
            {"day": "Mon", "type": "🚴 Bike", "duration": "45min", "zone": "Z2"},
            {"day": "Mon", "type": "🏊 Swim", "duration": "20min", "zone": "Z1"}
          ]}]
        """
        let weeks = try TrainingWeekParser.parse(json)
        let days = weeks[0].workouts.map { $0.day }
        XCTAssertEqual(Set(days), ["Mon"], "3 workouts on same day should NOT be redistributed")
    }

    // MARK: - Error cases

    func testParse_emptyString_throws() {
        XCTAssertThrowsError(try TrainingWeekParser.parse(""))
    }

    func testParse_emptyArray_throws() {
        XCTAssertThrowsError(try TrainingWeekParser.parse("[]"))
    }

    func testParse_malformedJSON_throws() {
        XCTAssertThrowsError(try TrainingWeekParser.parse("{not valid json}"))
    }

    func testParse_weeksWithoutRequiredFields_skipped() throws {
        // Week 1 is missing "workouts" — should be skipped; week 2 is valid
        let json = """
        [
          {"weekNumber": 1, "phase": "Base"},
          {"weekNumber": 2, "phase": "Build", "startDate": "2026-01-12", "endDate": "2026-01-18",
           "workouts": [{"day": "Tue", "type": "🚴 Bike", "duration": "60min", "zone": "Z2"}]}
        ]
        """
        let weeks = try TrainingWeekParser.parse(json)
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks[0].weekNumber, 2)
    }

    // MARK: - Date fallback (no startDate/endDate)

    func testParse_noDateFields_usesRaceDateFallback() throws {
        // 3-week plan with no explicit dates — fallback uses raceDate anchor.
        // Week 1 is 2 weeks before race, week 3 is race week.
        let json = """
        [{"weekNumber": 1, "phase": "Base",
          "workouts": [{"day": "Mon", "type": "Rest", "duration": "-", "zone": "-"}]},
         {"weekNumber": 2, "phase": "Build",
          "workouts": [{"day": "Mon", "type": "Rest", "duration": "-", "zone": "-"}]},
         {"weekNumber": 3, "phase": "Taper",
          "workouts": [{"day": "Mon", "type": "Rest", "duration": "-", "zone": "-"}]}]
        """
        var components = DateComponents()
        // Monday race date avoids weekday-alignment edge case in parseDates
        components.year = 2026; components.month = 7; components.day = 20
        let raceDate = Calendar.current.date(from: components)!
        let weeks = try TrainingWeekParser.parse(json, raceDate: raceDate)
        XCTAssertEqual(weeks.count, 3)
        // Week 1 is 2 weeks before race — must be well before raceDate
        XCTAssertLessThan(weeks[0].startDate, raceDate)
        // Each week's startDate must be earlier than the next
        XCTAssertLessThan(weeks[0].startDate, weeks[1].startDate)
        XCTAssertLessThan(weeks[1].startDate, weeks[2].startDate)
    }
}
