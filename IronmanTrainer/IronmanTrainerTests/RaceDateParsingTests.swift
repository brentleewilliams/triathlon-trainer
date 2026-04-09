import XCTest
@testable import Race1_Trainer

/// Tests for race date parsing logic in PrepRaceSearchHelper.
///
/// Race dates verified from official race websites (April 2026).
/// All dates represent 2026 editions unless otherwise noted.
final class RaceDateParsingTests: XCTestCase {

    // MARK: - Verified Race Dataset (20 races)

    struct VerifiedRace {
        let name: String
        let expectedDate: String // YYYY-MM-DD
    }

    let verifiedRaces: [VerifiedRace] = [
        // World Marathon Majors
        VerifiedRace(name: "Tokyo Marathon",                    expectedDate: "2026-03-01"),
        VerifiedRace(name: "Boston Marathon",                   expectedDate: "2026-04-20"),
        VerifiedRace(name: "TCS London Marathon",               expectedDate: "2026-04-26"),
        VerifiedRace(name: "Berlin Marathon",                   expectedDate: "2026-09-27"),
        VerifiedRace(name: "Bank of America Chicago Marathon",  expectedDate: "2026-10-11"),
        VerifiedRace(name: "TCS New York City Marathon",        expectedDate: "2026-11-01"),
        VerifiedRace(name: "Bolder Boulder 10K",               expectedDate: "2026-05-25"),
        // 5Ks & 10Ks
        VerifiedRace(name: "AJC Peachtree Road Race 10K",       expectedDate: "2026-07-04"),
        VerifiedRace(name: "Bay to Breakers 12K",              expectedDate: "2026-05-17"),
        VerifiedRace(name: "Thanksgiving Turkey Trot 5K",      expectedDate: "2026-11-26"),
        VerifiedRace(name: "Grand Traverse Ultra Run",         expectedDate: "2026-09-05"),
        VerifiedRace(name: "Copper Triangle",                  expectedDate: "2026-08-01"),
        // Other Marathons
        VerifiedRace(name: "Marine Corps Marathon",             expectedDate: "2026-10-25"),
        // Ironman 70.3
        VerifiedRace(name: "Ironman 70.3 Oceanside",           expectedDate: "2026-03-28"),
        VerifiedRace(name: "Ironman 70.3 Chattanooga",         expectedDate: "2026-05-17"),
        VerifiedRace(name: "Ironman 70.3 Boulder",             expectedDate: "2026-06-13"),
        VerifiedRace(name: "Ironman 70.3 Oregon",              expectedDate: "2026-07-19"),
        VerifiedRace(name: "Ironman 70.3 Santa Cruz",          expectedDate: "2026-09-13"),
        VerifiedRace(name: "Ironman 70.3 Augusta",             expectedDate: "2026-09-27"),
        // Full Ironman
        VerifiedRace(name: "Ironman World Championship Kona",  expectedDate: "2026-10-10"),
        // User-verified races
        VerifiedRace(name: "Steamboat Marathon",               expectedDate: "2026-06-07"),
        VerifiedRace(name: "Steamboat Half Marathon",          expectedDate: "2026-06-07"),
        VerifiedRace(name: "Steamboat 10K",                    expectedDate: "2026-06-07"),
        VerifiedRace(name: "Colfax Marathon Denver",           expectedDate: "2026-05-16"),
        VerifiedRace(name: "Colfax Half Marathon Denver",      expectedDate: "2026-05-16"),
    ]

    // MARK: - parseDate: Valid YYYY-MM-DD inputs

    func testParseDate_ValidFormat_ReturnsDate() {
        for race in verifiedRaces {
            let result = PrepRaceSearchHelper.parseDate(race.expectedDate)
            XCTAssertNotNil(result, "\(race.name): parseDate returned nil for \(race.expectedDate)")
        }
    }

    func testParseDate_CorrectCalendarDay() {
        for race in verifiedRaces {
            guard let date = PrepRaceSearchHelper.parseDate(race.expectedDate) else {
                XCTFail("\(race.name): parse returned nil")
                continue
            }
            let formatted = isoString(from: date)
            XCTAssertEqual(formatted, race.expectedDate,
                "\(race.name): expected \(race.expectedDate), got \(formatted)")
        }
    }

    // MARK: - parseDate: Timezone safety

    /// Date must resolve to the correct calendar day in both UTC-12 and UTC+14 (full range).
    func testParseDate_TimezoneInvariant() {
        let dateString = "2026-07-19"
        guard let date = PrepRaceSearchHelper.parseDate(dateString) else {
            XCTFail("parse returned nil"); return
        }

        for offsetHours in stride(from: -12, through: 14, by: 1) {
            guard let tz = TimeZone(secondsFromGMT: offsetHours * 3600) else { continue }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(comps.year,  2026, "Year wrong in UTC\(offsetHours > 0 ? "+" : "")\(offsetHours)")
            XCTAssertEqual(comps.month, 7,    "Month wrong in UTC\(offsetHours > 0 ? "+" : "")\(offsetHours)")
            XCTAssertEqual(comps.day,   19,   "Day wrong in UTC\(offsetHours > 0 ? "+" : "")\(offsetHours)")
        }
    }

    // MARK: - parseDate: Invalid / alternate formats that Claude should NOT return

    func testParseDate_MonthNameFormat_ReturnsNil() {
        // e.g. Claude returning "July 19, 2026" instead of "2026-07-19"
        XCTAssertNil(PrepRaceSearchHelper.parseDate("July 19, 2026"))
        XCTAssertNil(PrepRaceSearchHelper.parseDate("19 July 2026"))
        XCTAssertNil(PrepRaceSearchHelper.parseDate("Jul 19, 2026"))
    }

    func testParseDate_SlashFormat_ReturnsNil() {
        XCTAssertNil(PrepRaceSearchHelper.parseDate("07/19/2026"))
        XCTAssertNil(PrepRaceSearchHelper.parseDate("7/19/2026"))
        XCTAssertNil(PrepRaceSearchHelper.parseDate("19/07/2026"))
    }

    func testParseDate_EmptyString_ReturnsNil() {
        XCTAssertNil(PrepRaceSearchHelper.parseDate(""))
    }

    func testParseDate_RandomText_ReturnsNil() {
        XCTAssertNil(PrepRaceSearchHelper.parseDate("their upcoming race"))
        XCTAssertNil(PrepRaceSearchHelper.parseDate("TBD"))
        XCTAssertNil(PrepRaceSearchHelper.parseDate("unknown"))
    }

    func testParseDate_PartialDate_ReturnsNil() {
        XCTAssertNil(PrepRaceSearchHelper.parseDate("2026-07"))
        XCTAssertNil(PrepRaceSearchHelper.parseDate("2026"))
    }

    // MARK: - Helpers

    private func isoString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
