import Foundation

// MARK: - Verified Race Entry

struct VerifiedRaceEntry {
    let name: String
    let date: Date
    let location: String
    let raceType: String           // "triathlon", "running", "cycling"
    let distances: [String: Double]
    let distanceLabel: String      // "Marathon", "Half Marathon", "10K", etc.
    let courseType: String
    let historicalWeather: String?

    /// All tokens must appear in the normalized query to match.
    let requiredKeywords: [String]
    /// If ANY token appears in the query, skip this entry (used to differentiate variants).
    let excludedKeywords: [String]

    func toRaceSearchResult() -> RaceSearchResult {
        RaceSearchResult(
            name: name,
            date: date,
            location: location,
            type: raceType,
            distances: distances,
            courseType: courseType,
            elevationGainM: nil,
            elevationAtVenueM: nil,
            historicalWeather: historicalWeather
        )
    }

    func toPrepRaceSearchResult() -> PrepRaceSearchResult {
        PrepRaceSearchResult(name: name, date: date, distance: distanceLabel)
    }
}

// MARK: - Database

enum VerifiedRaceDatabase {

    /// Returns the best matching verified race for a query, or nil if no confident match.
    static func lookup(query: String) -> VerifiedRaceEntry? {
        let normalized = normalize(query)
        return entries.first { entry in
            entry.requiredKeywords.allSatisfy { normalized.contains($0) }
            && entry.excludedKeywords.allSatisfy { !normalized.contains($0) }
        }
    }

    // MARK: - Normalization

    private static func normalize(_ query: String) -> String {
        var q = query.lowercased()
        // Normalize Ironman distance shorthand
        q = q.replacingOccurrences(of: "70.2", with: "70.3")
            .replacingOccurrences(of: "702", with: "70.3")
            .replacingOccurrences(of: "703", with: "70.3")
        // Normalize "half iron" variants
        q = q.replacingOccurrences(of: "half-iron", with: "half iron")
        return q
    }

    // MARK: - Date Helper

    private static func raceDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        PrepRaceSearchHelper.parseDate(String(format: "%04d-%02d-%02d", year, month, day)) ?? Date()
    }

    // MARK: - Verified Entries
    // Order matters: more specific entries (e.g., half marathon) before less specific (marathon).

    static let entries: [VerifiedRaceEntry] = [

        // MARK: Ironman Triathlons (full-distance first, then 70.3 by date)

        VerifiedRaceEntry(
            name: "Ironman World Championship",
            date: raceDate(2026, 10, 10),
            location: "Kailua-Kona, HI",
            raceType: "triathlon",
            distances: ["swim": 2.4, "bike": 112.0, "run": 26.2],
            distanceLabel: "Full Iron",
            courseType: "road",
            historicalWeather: "Hot and humid, 85-90°F, ocean swim",
            requiredKeywords: ["kona"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Ironman 70.3 Oceanside",
            date: raceDate(2026, 3, 28),
            location: "Oceanside, CA",
            raceType: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            distanceLabel: "Half Iron",
            courseType: "road",
            historicalWeather: "Mild, 60-70°F, light ocean breeze",
            requiredKeywords: ["oceanside"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Ironman 70.3 Chattanooga",
            date: raceDate(2026, 5, 17),
            location: "Chattanooga, TN",
            raceType: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            distanceLabel: "Half Iron",
            courseType: "road",
            historicalWeather: "Warm, 70-80°F, humid",
            requiredKeywords: ["chattanooga"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Ironman 70.3 Boulder",
            date: raceDate(2026, 6, 13),
            location: "Boulder, CO",
            raceType: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            distanceLabel: "Half Iron",
            courseType: "road",
            historicalWeather: "Warm, 75-85°F, low humidity at altitude",
            requiredKeywords: ["boulder", "ironman"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Ironman 70.3 Oregon",
            date: raceDate(2026, 7, 19),
            location: "Salem, OR",
            raceType: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            distanceLabel: "Half Iron",
            courseType: "road",
            historicalWeather: "Mild, 65-75°F, low humidity",
            requiredKeywords: ["oregon"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Ironman 70.3 Santa Cruz",
            date: raceDate(2026, 9, 13),
            location: "Santa Cruz, CA",
            raceType: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            distanceLabel: "Half Iron",
            courseType: "road",
            historicalWeather: "Mild, 65-72°F, coastal fog possible",
            requiredKeywords: ["santa cruz"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Ironman 70.3 Augusta",
            date: raceDate(2026, 9, 27),
            location: "Augusta, GA",
            raceType: "triathlon",
            distances: ["swim": 1.2, "bike": 56.0, "run": 13.1],
            distanceLabel: "Half Iron",
            courseType: "road",
            historicalWeather: "Warm, 75-85°F, humid",
            requiredKeywords: ["augusta", "ironman"],
            excludedKeywords: []
        ),

        // MARK: Marathon Majors

        VerifiedRaceEntry(
            name: "Tokyo Marathon",
            date: raceDate(2026, 3, 1),
            location: "Tokyo, Japan",
            raceType: "running",
            distances: ["run": 26.2],
            distanceLabel: "Marathon",
            courseType: "road",
            historicalWeather: "Cool, 40-55°F, low humidity",
            requiredKeywords: ["tokyo", "marathon"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Boston Marathon",
            date: raceDate(2026, 4, 20),
            location: "Boston, MA",
            raceType: "running",
            distances: ["run": 26.2],
            distanceLabel: "Marathon",
            courseType: "road",
            historicalWeather: "Cool to mild, 45-65°F",
            requiredKeywords: ["boston", "marathon"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "TCS London Marathon",
            date: raceDate(2026, 4, 26),
            location: "London, UK",
            raceType: "running",
            distances: ["run": 26.2],
            distanceLabel: "Marathon",
            courseType: "road",
            historicalWeather: "Cool, 50-60°F, chance of rain",
            requiredKeywords: ["london", "marathon"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Berlin Marathon",
            date: raceDate(2026, 9, 27),
            location: "Berlin, Germany",
            raceType: "running",
            distances: ["run": 26.2],
            distanceLabel: "Marathon",
            courseType: "road",
            historicalWeather: "Cool, 50-65°F",
            requiredKeywords: ["berlin", "marathon"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Bank of America Chicago Marathon",
            date: raceDate(2026, 10, 11),
            location: "Chicago, IL",
            raceType: "running",
            distances: ["run": 26.2],
            distanceLabel: "Marathon",
            courseType: "road",
            historicalWeather: "Cool, 45-60°F",
            requiredKeywords: ["chicago", "marathon"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Marine Corps Marathon",
            date: raceDate(2026, 10, 25),
            location: "Arlington, VA",
            raceType: "running",
            distances: ["run": 26.2],
            distanceLabel: "Marathon",
            courseType: "road",
            historicalWeather: "Cool, 45-60°F",
            requiredKeywords: ["marine corps"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "TCS New York City Marathon",
            date: raceDate(2026, 11, 1),
            location: "New York, NY",
            raceType: "running",
            distances: ["run": 26.2],
            distanceLabel: "Marathon",
            courseType: "road",
            historicalWeather: "Cool, 45-60°F",
            requiredKeywords: ["new york", "marathon"],
            excludedKeywords: []
        ),

        // MARK: Half Marathons (before full marathon entries to match first on "half")

        VerifiedRaceEntry(
            name: "Steamboat Half Marathon",
            date: raceDate(2026, 6, 7),
            location: "Steamboat Springs, CO",
            raceType: "running",
            distances: ["run": 13.1],
            distanceLabel: "Half Marathon",
            courseType: "road",
            historicalWeather: "Mild, 55-70°F, mountain air",
            requiredKeywords: ["steamboat", "half"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Colfax Half Marathon",
            date: raceDate(2026, 5, 16),
            location: "Denver, CO",
            raceType: "running",
            distances: ["run": 13.1],
            distanceLabel: "Half Marathon",
            courseType: "road",
            historicalWeather: "Mild, 50-65°F",
            requiredKeywords: ["colfax", "half"],
            excludedKeywords: []
        ),

        // MARK: Full Marathons (regional)

        VerifiedRaceEntry(
            name: "Steamboat Marathon",
            date: raceDate(2026, 6, 7),
            location: "Steamboat Springs, CO",
            raceType: "running",
            distances: ["run": 26.2],
            distanceLabel: "Marathon",
            courseType: "road",
            historicalWeather: "Mild, 55-70°F, mountain air",
            requiredKeywords: ["steamboat", "marathon"],
            excludedKeywords: ["half"]
        ),

        VerifiedRaceEntry(
            name: "Colfax Marathon",
            date: raceDate(2026, 5, 16),
            location: "Denver, CO",
            raceType: "running",
            distances: ["run": 26.2],
            distanceLabel: "Marathon",
            courseType: "road",
            historicalWeather: "Mild, 50-65°F",
            requiredKeywords: ["colfax", "marathon"],
            excludedKeywords: ["half"]
        ),

        // MARK: 10Ks & 5Ks

        VerifiedRaceEntry(
            name: "Bolder Boulder 10K",
            date: raceDate(2026, 5, 25),
            location: "Boulder, CO",
            raceType: "running",
            distances: ["run": 6.2],
            distanceLabel: "10K",
            courseType: "road",
            historicalWeather: "Mild, 55-70°F",
            requiredKeywords: ["bolder boulder"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Steamboat 10K",
            date: raceDate(2026, 6, 7),
            location: "Steamboat Springs, CO",
            raceType: "running",
            distances: ["run": 6.2],
            distanceLabel: "10K",
            courseType: "road",
            historicalWeather: "Mild, 55-70°F, mountain air",
            requiredKeywords: ["steamboat", "10k"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "AJC Peachtree Road Race",
            date: raceDate(2026, 7, 4),
            location: "Atlanta, GA",
            raceType: "running",
            distances: ["run": 6.2],
            distanceLabel: "10K",
            courseType: "road",
            historicalWeather: "Hot and humid, 75-90°F",
            requiredKeywords: ["peachtree"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Thanksgiving Turkey Trot 5K",
            date: raceDate(2026, 11, 26),
            location: "Various",
            raceType: "running",
            distances: ["run": 3.1],
            distanceLabel: "5K",
            courseType: "road",
            historicalWeather: "Cold, 30-45°F",
            requiredKeywords: ["turkey trot"],
            excludedKeywords: []
        ),

        // MARK: Other

        VerifiedRaceEntry(
            name: "Bay to Breakers",
            date: raceDate(2026, 5, 17),
            location: "San Francisco, CA",
            raceType: "running",
            distances: ["run": 7.5],
            distanceLabel: "12K",
            courseType: "road",
            historicalWeather: "Cool and foggy, 55-65°F",
            requiredKeywords: ["bay to breakers"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Grand Traverse Ultra Run",
            date: raceDate(2026, 9, 5),
            location: "Colorado",
            raceType: "running",
            distances: ["run": 40.0],
            distanceLabel: "Ultra",
            courseType: "trail",
            historicalWeather: "Cool mountain conditions, 45-65°F",
            requiredKeywords: ["grand traverse"],
            excludedKeywords: []
        ),

        VerifiedRaceEntry(
            name: "Copper Triangle",
            date: raceDate(2026, 8, 1),
            location: "Copper Mountain, CO",
            raceType: "cycling",
            distances: ["bike": 78.0],
            distanceLabel: "Century Ride",
            courseType: "road",
            historicalWeather: "Mild mountain conditions, 60-75°F",
            requiredKeywords: ["copper triangle"],
            excludedKeywords: []
        ),
    ]
}
