import Foundation

// MARK: - Bundled Course Profiles
//
// v1 ships with a single hardcoded profile (Ironman 70.3 Oregon, July 19
// 2026). In v2 this is joined by Firestore cache + Cloud Function research.
// Keep the bundle small and only add profiles that are actively used.

enum BundledCourseProfiles {
    static let ironman703Oregon2026: RaceCourseProfile = {
        var raceDateComps = DateComponents()
        raceDateComps.year = 2026
        raceDateComps.month = 7
        raceDateComps.day = 19
        raceDateComps.hour = 7 // local-morning race start, noon UTC-ish
        let raceDate = Calendar(identifier: .gregorian).date(from: raceDateComps) ?? Date()

        return RaceCourseProfile(
            raceId: "im703-oregon-2026",
            raceName: "Ironman 70.3 Oregon",
            venue: "Salem, OR",
            raceDate: raceDate,
            raceType: .triathlon,
            totalDistanceDescription: "1.2mi swim / 56mi bike / 13.1mi run",
            terrain: .rolling,
            totalElevationGainFeet: 2200,
            venueElevationFeet: 150,
            expectedWeather: ExpectedWeather(
                tempHighF: 82,
                tempLowF: 57,
                conditionsSummary: "Partly cloudy, low humidity, light winds"
            ),
            dataSource: .bundled,
            // "Last refreshed" is meaningless for bundled data; use the
            // app's current-build date stamp as a conservative default.
            lastRefreshed: Date(timeIntervalSince1970: 1_744_588_800) // 2025-04-14
        )
    }()

    /// All bundled profiles keyed by raceId.
    static let all: [String: RaceCourseProfile] = [
        ironman703Oregon2026.raceId: ironman703Oregon2026
    ]
}
