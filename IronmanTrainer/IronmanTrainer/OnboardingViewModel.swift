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
    @Published var hkHasLocation = false

    // Race data (step 3)
    @Published var raceSearchQuery: String = ""
    @Published var raceSearchResult: RaceSearchResult?
    @Published var isSearchingRace = false

    // Goal data (step 4)
    @Published var goalType: GoalSelection = .justComplete
    @Published var targetHours: Int = 6
    @Published var targetMinutes: Int = 0

    /// Default finish time based on race type/distance. Returns (hours, minutes).
    /// Check if race name/distances indicate a half-iron (70.3) vs full Ironman
    private var isHalfIron: Bool {
        guard let result = raceSearchResult else { return false }
        let name = result.name.lowercased()
        if name.contains("70.3") || name.contains("half iron") { return true }
        let totalMiles = result.distances.values.reduce(0, +)
        return totalMiles > 50 && totalMiles <= 100
    }

    var defaultFinishTime: (hours: Int, minutes: Int) {
        guard let result = raceSearchResult else { return (6, 0) }
        let type = result.type.lowercased()

        if type.contains("triathlon") || type.contains("tri") {
            if isHalfIron { return (6, 0) }                  // Half Iron (~70.3 mi)
            let totalMiles = result.distances.values.reduce(0, +)
            if totalMiles > 100 { return (13, 0) }           // Full Ironman (~140.6 mi)
            if totalMiles > 50 { return (6, 0) }             // Half Iron (by distance)
            if totalMiles > 30 { return (3, 0) }             // Olympic (~31 mi)
            return (1, 30)                                    // Sprint (~16 mi)
        } else if type.contains("running") || type.contains("run") {
            let runMiles = result.distances["run"] ?? result.distances.values.max() ?? 0
            if runMiles >= 25 { return (4, 30) }            // Marathon
            if runMiles >= 12 { return (2, 0) }             // Half Marathon
            if runMiles >= 6 { return (0, 55) }             // 10K
            if runMiles >= 3 { return (0, 28) }             // 5K
            return (0, 45)                                   // Other short
        } else if type.contains("cycling") || type.contains("bike") {
            let bikeMiles = result.distances["bike"] ?? result.distances.values.max() ?? 0
            if bikeMiles >= 90 { return (6, 0) }            // Century
            if bikeMiles >= 50 { return (3, 30) }           // Half century
            return (2, 0)                                    // Short
        } else if type.contains("swimming") || type.contains("swim") {
            return (1, 0)
        }
        return (6, 0)
    }

    /// Reasonable hour range for the time picker based on race type
    var finishTimeHourRange: ClosedRange<Int> {
        guard let result = raceSearchResult else { return 0...17 }
        let type = result.type.lowercased()

        if type.contains("triathlon") || type.contains("tri") {
            if isHalfIron { return 4...9 }             // Half Iron
            let totalMiles = result.distances.values.reduce(0, +)
            if totalMiles > 100 { return 8...17 }      // Full Ironman
            if totalMiles > 50 { return 4...9 }        // Half Iron (by distance)
            if totalMiles > 30 { return 1...5 }        // Olympic
            return 0...3                                // Sprint
        } else if type.contains("running") || type.contains("run") {
            let runMiles = result.distances["run"] ?? result.distances.values.max() ?? 0
            if runMiles >= 25 { return 2...7 }          // Marathon
            if runMiles >= 12 { return 1...4 }          // Half Marathon
            if runMiles >= 6 { return 0...2 }           // 10K
            return 0...1                                 // 5K
        } else if type.contains("cycling") || type.contains("bike") {
            return 1...10
        } else if type.contains("swimming") || type.contains("swim") {
            return 0...3
        }
        return 0...17
    }

    // Per-sport skill levels (step 4, part of goal setting)
    @Published var swimLevel: SkillLevel?
    @Published var bikeLevel: SkillLevel?
    @Published var runLevel: SkillLevel?

    // Fitness chat answers (step 5)
    @Published var fitnessHours: String = ""
    @Published var fitnessSchedule: String = ""
    @Published var fitnessInjuries: String = ""
    @Published var fitnessEquipment: String = ""

    // Plan generation (step 6)
    @Published var planApproved = false
    @Published var generatedPlan: [TrainingWeek]?
    @Published var isGeneratingPlan = false
    @Published var planGenerationError: String?

    var totalSteps: Int { OnboardingStep.allCases.count }
    var progressPercent: Double { Double(currentStep.rawValue + 1) / Double(totalSteps) }

    /// Which sports are relevant based on race type
    var relevantSports: [String] {
        guard let raceType = raceSearchResult?.type.lowercased() else {
            return ["swim", "bike", "run"] // default to triathlon
        }
        if raceType.contains("triathlon") || raceType.contains("tri") {
            return ["swim", "bike", "run"]
        } else if raceType.contains("cycling") || raceType.contains("bike") {
            return ["bike"]
        } else if raceType.contains("running") || raceType.contains("run") {
            return ["run"]
        } else if raceType.contains("swimming") || raceType.contains("swim") {
            return ["swim"]
        }
        return ["swim", "bike", "run"]
    }

    /// Whether all required skill levels are selected
    var allSkillsSelected: Bool {
        let sports = relevantSports
        if sports.contains("swim") && swimLevel == nil { return false }
        if sports.contains("bike") && bikeLevel == nil { return false }
        if sports.contains("run") && runLevel == nil { return false }
        return true
    }

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

        // Try to infer home training area from workout locations
        let inferredZip = await helper.inferHomeZipCode()
        if let zip = inferredZip, !zip.isEmpty {
            homeZip = zip
            hkHasLocation = true
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
            var result = try await searchRaceWithClaude(query: raceSearchQuery)
            // Ensure race date is in the future; bump to next year if needed
            let now = Date()
            if result.date < now {
                var dateComponents = Calendar.current.dateComponents([.month, .day], from: result.date)
                let currentYear = Calendar.current.component(.year, from: now)
                dateComponents.year = currentYear
                if let candidateDate = Calendar.current.date(from: dateComponents), candidateDate > now {
                    result = result.withDate(candidateDate)
                } else {
                    dateComponents.year = currentYear + 1
                    if let nextYear = Calendar.current.date(from: dateComponents) {
                        result = result.withDate(nextYear)
                    }
                }
            }
            raceSearchResult = result
        } catch {
            self.error = "Could not find race details: \(error.localizedDescription)"
        }

        isSearchingRace = false
    }

    private func searchRaceWithClaude(query: String) async throws -> RaceSearchResult {
        return try await LLMProxyService.shared.searchRace(query: query)
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

    // MARK: - Plan Generation

    func startPlanGeneration(chatMessages: [ChatMessage] = []) {
        guard !isGeneratingPlan else { return }
        isGeneratingPlan = true
        planGenerationError = nil
        generatedPlan = nil

        Task {
            // Keep the network request alive if the user backgrounds the app
            let taskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            do {
                let input = buildPlanGenerationInput(chatMessages: chatMessages)
                input.save() // Save for regeneration from Settings
                let plan = try await LLMProxyService.shared.generatePlan(input: input)
                generatedPlan = plan
            } catch {
                planGenerationError = error.localizedDescription
            }
            isGeneratingPlan = false
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    func buildPlanGenerationInput(chatMessages: [ChatMessage] = []) -> PlanGenerationInput {
        let race = buildRace() ?? Race(
            name: "Race",
            date: Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date(),
            location: "TBD",
            type: .triathlon,
            distances: [:],
            courseType: "road",
            userGoal: .justComplete
        )

        let profile = buildUserProfile(uid: AuthService.shared.currentUserID ?? "")

        // Build HK summary string
        var hkSummary: String?
        if let hkProfile = hkProfile {
            var parts: [String] = []
            if let vol = hkProfile.recentWeeklyVolume {
                parts.append("Weekly avg: Swim \(Int(vol.avgSwimYardsPerWeek))yd, Bike \(String(format: "%.1f", vol.avgBikeHoursPerWeek))hrs, Run \(String(format: "%.1f", vol.avgRunMilesPerWeek))mi (\(String(format: "%.1f", vol.avgWorkoutsPerWeek)) workouts/wk over \(vol.periodWeeks) weeks)")
            }
            if !hkProfile.recentWorkoutDetails.isEmpty {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d"
                let recentLines = hkProfile.recentWorkoutDetails.prefix(10).map { w in
                    var line = "\(dateFormatter.string(from: w.date)): \(w.type) \(Int(w.durationMinutes))min"
                    if let dist = w.distanceMiles { line += " \(String(format: "%.1f", dist))mi" }
                    return line
                }
                parts.append("Recent: " + recentLines.joined(separator: "; "))
            }
            if !parts.isEmpty { hkSummary = parts.joined(separator: "\n") }
        }

        // Build chat summary
        var chatSummary: String?
        if !chatMessages.isEmpty {
            let lines = chatMessages.map { msg in
                "\(msg.isUser ? "Athlete" : "Coach"): \(msg.text)"
            }
            chatSummary = lines.joined(separator: "\n")
        }

        return PlanGenerationInput(
            race: race,
            profile: profile,
            swimLevel: swimLevel,
            bikeLevel: bikeLevel,
            runLevel: runLevel,
            fitnessHours: fitnessHours,
            fitnessSchedule: fitnessSchedule,
            fitnessInjuries: fitnessInjuries,
            fitnessEquipment: fitnessEquipment,
            hkSummary: hkSummary,
            chatSummary: chatSummary
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

    func withDate(_ newDate: Date) -> RaceSearchResult {
        RaceSearchResult(name: name, date: newDate, location: location, type: type,
                         distances: distances, courseType: courseType,
                         elevationGainM: elevationGainM, elevationAtVenueM: elevationAtVenueM,
                         historicalWeather: historicalWeather)
    }
}
