import Foundation

// MARK: - Race Type

enum RaceType: String, Codable, CaseIterable {
    case triathlon, running, cycling, swimming
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
