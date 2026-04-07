import Foundation

// MARK: - Race Type

enum RaceType: String, Codable, CaseIterable {
    case triathlon, running, cycling, swimming
}

// MARK: - Race Distance

enum RaceDistance: String, Codable, CaseIterable {
    case sprint        // Sprint Tri: 750m swim, 20km bike, 5km run
    case olympic       // Olympic Tri: 1.5km swim, 40km bike, 10km run
    case half          // 70.3: 1.2mi swim, 56mi bike, 13.1mi run
    case full          // 140.6: 2.4mi swim, 112mi bike, 26.2mi run
    case ultra         // Ultra-distance: longer than full Ironman

    var displayName: String {
        switch self {
        case .sprint: return "Sprint"
        case .olympic: return "Olympic"
        case .half: return "70.3"
        case .full: return "Full Ironman"
        case .ultra: return "Ultra"
        }
    }

    var typicalWeeks: ClosedRange<Int> {
        switch self {
        case .sprint: return 8...12
        case .olympic: return 12...16
        case .half: return 16...20
        case .full: return 20...30
        case .ultra: return 24...36
        }
    }

    var swimDistance: String {
        switch self {
        case .sprint: return "750m"
        case .olympic: return "1.5km"
        case .half: return "1.2mi"
        case .full: return "2.4mi"
        case .ultra: return "Varies"
        }
    }

    var bikeDistance: String {
        switch self {
        case .sprint: return "20km"
        case .olympic: return "40km"
        case .half: return "56mi"
        case .full: return "112mi"
        case .ultra: return "Varies"
        }
    }

    var runDistance: String {
        switch self {
        case .sprint: return "5km"
        case .olympic: return "10km"
        case .half: return "13.1mi"
        case .full: return "26.2mi"
        case .ultra: return "Varies"
        }
    }

    var weeklyVolumeRangeHours: ClosedRange<Double> {
        switch self {
        case .sprint: return 4...8
        case .olympic: return 6...12
        case .half: return 8...16
        case .full: return 12...20
        case .ultra: return 15...25
        }
    }
}

// MARK: - Goal Type

enum GoalType: Codable, Equatable {
    case timeTarget(TimeInterval) // seconds
    case justComplete

    // MARK: - Custom Codable (associated value enum)

    private enum CodingKeys: String, CodingKey {
        case type, targetSeconds
    }

    private enum GoalKind: String, Codable {
        case timeTarget, justComplete
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .timeTarget(let seconds):
            try container.encode(GoalKind.timeTarget, forKey: .type)
            try container.encode(seconds, forKey: .targetSeconds)
        case .justComplete:
            try container.encode(GoalKind.justComplete, forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(GoalKind.self, forKey: .type)
        switch kind {
        case .timeTarget:
            let seconds = try container.decode(TimeInterval.self, forKey: .targetSeconds)
            self = .timeTarget(seconds)
        case .justComplete:
            self = .justComplete
        }
    }
}

// MARK: - Race

struct Race: Codable, Equatable {
    var name: String
    var date: Date
    var location: String
    var type: RaceType
    var raceDistance: RaceDistance?
    var distances: [String: Double] // e.g., {"swim": 1.2, "bike": 56, "run": 13.1} in miles
    var courseType: String // road, trail, mixed
    var elevationGainM: Double?
    var elevationAtVenueM: Double?
    var historicalWeather: String?
    var userGoal: GoalType
}

// MARK: - User Profile

struct UserProfile: Codable {
    var uid: String
    var name: String
    var dateOfBirth: Date?
    var biologicalSex: String? // male, female, other
    var heightCm: Double?
    var weightKg: Double?
    var restingHR: Int?
    var vo2Max: Double?
    var homeZip: String?
    var homeElevationM: Double?
    var onboardingComplete: Bool
    var createdAt: Date

    static func empty(uid: String) -> UserProfile {
        UserProfile(
            uid: uid,
            name: "",
            onboardingComplete: false,
            createdAt: Date()
        )
    }
}

// MARK: - Plan Metadata

struct PlanMetadata: Codable {
    var generatedAt: Date
    var generatedBy: String // "hardcoded" or "claude-generated"
    var raceId: String?
    var approved: Bool
}
