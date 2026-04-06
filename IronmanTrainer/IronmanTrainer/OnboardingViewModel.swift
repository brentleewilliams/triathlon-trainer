import Foundation
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case healthKit = 0
    case profile = 1
    case raceSearch = 2
    case goalSetting = 3
    case fitnessChat = 4
    case planReview = 5
}

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .healthKit
    @Published var isProcessing = false
    @Published var error: String?

    // HealthKit data (populated in step 1)
    @Published var hkProfile: HealthKitOnboardingProfile?
    @Published var hkDataLoaded = false

    // Profile data (step 2 - only fields not from HK)
    @Published var userName: String = ""
    @Published var userDOB: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @Published var userSex: String = ""
    @Published var userHeightCm: Double?
    @Published var userWeightKg: Double?
    @Published var userRestingHR: Int?
    @Published var homeZip: String = ""

    // Flags for what HK provided
    @Published var hkHasDOB = false
    @Published var hkHasSex = false
    @Published var hkHasHeight = false
    @Published var hkHasWeight = false
    @Published var hkHasRestingHR = false

    // Race data (step 3)
    @Published var raceSearchQuery: String = ""
    @Published var raceSearchResult: RaceSearchResult?
    @Published var isSearchingRace = false

    // Goal data (step 4)
    @Published var goalType: GoalSelection = .justComplete
    @Published var targetHours: Int = 6
    @Published var targetMinutes: Int = 0

    // Per-sport skill levels (step 4, part of goal setting)
    @Published var swimLevel: SkillLevel = .beginner
    @Published var bikeLevel: SkillLevel = .intermediate
    @Published var runLevel: SkillLevel = .intermediate

    // Fitness chat answers (step 5)
    @Published var fitnessHours: String = ""
    @Published var fitnessExperience: String = ""
    @Published var fitnessInjuries: String = ""
    @Published var fitnessEquipment: String = ""

    // Plan approval (step 6)
    @Published var planApproved = false

    var totalSteps: Int { OnboardingStep.allCases.count }
    var progressPercent: Double { Double(currentStep.rawValue + 1) / Double(totalSteps) }

    func advance() {
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            withAnimation { currentStep = next }
        }
    }

    func goBack() {
        if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            withAnimation { currentStep = prev }
        }
    }

    // MARK: - HealthKit Data Loading

    func loadHealthKitData() async {
        isProcessing = true
        let helper = HealthKitOnboardingHelper()
        await helper.requestExpandedAuthorization()
        let profile = await helper.fetchOnboardingProfile()

        hkProfile = profile

        // Set flags for what HK provided
        if let dob = profile.dateOfBirth {
            userDOB = dob
            hkHasDOB = true
        }
        if let sex = profile.biologicalSex {
            userSex = sex
            hkHasSex = true
        }
        if let height = profile.heightCm {
            userHeightCm = height
            hkHasHeight = true
        }
        if let weight = profile.weightKg {
            userWeightKg = weight
            hkHasWeight = true
        }
        if let rhr = profile.restingHR {
            userRestingHR = rhr
            hkHasRestingHR = true
        }

        hkDataLoaded = true
        isProcessing = false
    }

    // MARK: - Race Search via Claude + Web Search

    func searchRace() async {
        guard !raceSearchQuery.isEmpty else { return }
        isSearchingRace = true
        error = nil

        do {
            let result = try await searchRaceWithClaude(query: raceSearchQuery)
            raceSearchResult = result
        } catch {
            self.error = "Could not find race details: \(error.localizedDescription)"
        }

        isSearchingRace = false
    }

    private func searchRaceWithClaude(query: String) async throws -> RaceSearchResult {
        let apiKey = Secrets.anthropicAPIKey
        guard !apiKey.isEmpty else { throw ClaudeServiceError.invalidAPIKey }

        let systemPrompt = """
        You are helping a user find details about a race they want to train for. \
        Search the web for the race and return ONLY a JSON object with these fields:
        {
            "name": "Official Race Name",
            "date": "YYYY-MM-DD",
            "location": "City, State/Country",
            "type": "triathlon|running|cycling|swimming",
            "distances": {"swim": miles, "bike": miles, "run": miles},
            "courseType": "road|trail|mixed",
            "elevationGainM": number_or_null,
            "elevationAtVenueM": number_or_null,
            "historicalWeather": "Brief description of typical weather for race day"
        }
        For single-sport races, only include the relevant distance key.
        Return ONLY valid JSON, no other text.
        """

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": systemPrompt,
            "tools": [
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "max_uses": 3
                ]
            ],
            "messages": [
                ["role": "user", "content": "Find details about this race: \(query)"]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw ClaudeServiceError.invalidRequest
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeServiceError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("[RACE SEARCH] API error \(httpResponse.statusCode): \(errorBody)")
            }
            throw ClaudeServiceError.serverError
        }

        // Parse Claude response - extract text from content blocks
        let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = responseJSON?["content"] as? [[String: Any]] else {
            throw ClaudeServiceError.invalidResponse
        }

        // Find the text block (skip tool_use and tool_result blocks)
        var jsonText = ""
        for block in content {
            if block["type"] as? String == "text", let text = block["text"] as? String {
                jsonText = text
                break
            }
        }

        // Extract JSON from the response (might be wrapped in markdown code block)
        if let jsonStart = jsonText.range(of: "{"),
           let jsonEnd = jsonText.range(of: "}", options: .backwards) {
            jsonText = String(jsonText[jsonStart.lowerBound...jsonEnd.upperBound])
        }

        guard let resultData = jsonText.data(using: .utf8) else {
            throw ClaudeServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateStr) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }

        return try decoder.decode(RaceSearchResult.self, from: resultData)
    }

    // MARK: - Build Domain Objects

    func buildUserProfile(uid: String) -> UserProfile {
        return UserProfile(
            uid: uid,
            name: userName,
            dateOfBirth: userDOB,
            biologicalSex: userSex.isEmpty ? nil : userSex,
            heightCm: userHeightCm,
            weightKg: userWeightKg,
            restingHR: userRestingHR,
            vo2Max: hkProfile?.vo2Max,
            homeZip: homeZip.isEmpty ? nil : homeZip,
            homeElevationM: nil,
            onboardingComplete: true,
            createdAt: Date()
        )
    }

    func buildRace() -> Race? {
        guard let result = raceSearchResult else { return nil }

        let goal: GoalType
        switch goalType {
        case .timeTarget:
            goal = .timeTarget(TimeInterval(targetHours * 3600 + targetMinutes * 60))
        case .justComplete:
            goal = .justComplete
        }

        return Race(
            name: result.name,
            date: result.date,
            location: result.location,
            type: RaceType(rawValue: result.type) ?? .triathlon,
            distances: result.distances,
            courseType: result.courseType,
            elevationGainM: result.elevationGainM,
            elevationAtVenueM: result.elevationAtVenueM,
            historicalWeather: result.historicalWeather,
            userGoal: goal
        )
    }
}

// MARK: - Supporting Types

enum SkillLevel: String, CaseIterable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var description: String {
        switch self {
        case .beginner: return "New or limited experience"
        case .intermediate: return "Regular training, comfortable"
        case .advanced: return "Competitive, years of experience"
        }
    }
}

enum GoalSelection {
    case timeTarget
    case justComplete
}

struct RaceSearchResult: Codable {
    let name: String
    let date: Date
    let location: String
    let type: String
    let distances: [String: Double]
    let courseType: String
    let elevationGainM: Double?
    let elevationAtVenueM: Double?
    let historicalWeather: String?
}
