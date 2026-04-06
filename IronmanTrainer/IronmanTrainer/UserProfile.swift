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

// MARK: - Preparatory Race

struct PrepRace: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var date: Date
    var distance: String  // e.g. "Sprint Tri", "10K", "Half Marathon", "Olympic Tri"
    var notes: String?

    var isPast: Bool {
        date < Date()
    }
}

// MARK: - Prep Races Manager

class PrepRacesManager: ObservableObject {
    static let shared = PrepRacesManager()

    @Published var races: [PrepRace] = []

    private let storageKey = "prep_races"

    init() {
        load()
    }

    func add(_ race: PrepRace) {
        races.append(race)
        races.sort { $0.date < $1.date }
        save()
    }

    func remove(at offsets: IndexSet) {
        races.remove(atOffsets: offsets)
        save()
    }

    func removeByID(_ id: UUID) {
        races.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(races) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([PrepRace].self, from: data) else { return }
        races = saved
    }

    /// Returns dates that should be blocked (race day + day before) for all prep races
    func blockedDates() -> Set<Date> {
        let calendar = Calendar.current
        var dates = Set<Date>()
        for race in races {
            let raceDay = calendar.startOfDay(for: race.date)
            dates.insert(raceDay)
            if let dayBefore = calendar.date(byAdding: .day, value: -1, to: raceDay) {
                dates.insert(dayBefore)
            }
        }
        return dates
    }

    /// Check if a given date falls on a prep race day or the day before
    func isBlockedDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return blockedDates().contains(startOfDay)
    }

    /// Returns the prep race name if the date is a race day
    func raceOnDate(_ date: Date) -> PrepRace? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return races.first { calendar.startOfDay(for: $0.date) == startOfDay }
    }

    /// Format for Claude coaching context
    func contextString() -> String? {
        guard !races.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let lines = races.map { race in
            var line = "- \(race.name) (\(race.distance)) on \(formatter.string(from: race.date))"
            if let notes = race.notes, !notes.isEmpty { line += " — \(notes)" }
            if race.isPast { line += " [COMPLETED]" }
            return line
        }
        return "PREPARATORY RACES:\n" + lines.joined(separator: "\n")
    }
}

// MARK: - Plan Metadata

struct PlanMetadata: Codable {
    var generatedAt: Date
    var generatedBy: String // "hardcoded" or "claude-generated"
    var raceId: String?
    var approved: Bool
}
