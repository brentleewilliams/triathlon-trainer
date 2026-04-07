import Foundation
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case healthKit = 0
    case profile = 1
    case raceSearch = 2
    case goalSetting = 3
    case tutorial = 4
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

    // Fitness details (collected in goal setting step)
    @Published var fitnessInjuries: String = "No current injuries or limitations"
    @Published var fitnessEquipment: String = "Full setup — bike trainer, pool access, gym, outdoor routes"

    // Plan generation (step 7)
    @Published var planApproved = false
    @Published var generatedPlan: [TrainingWeek]?
    @Published var isGeneratingPlan = false
    @Published var planGenerationError: String?
    @Published var planBatchesCompleted = 0
    @Published var planTotalBatches = 3
    @Published var schedulePattern: SchedulePattern = .spread
    @Published var includeStrength: Bool = true
    @Published var customGoalText: String = ""
    @Published var goalValidationWarning: String? = nil
    @Published var planMethod: String = "template"
    @Published var planWarnings: [String] = []

    var minimumWeeksLoaded: Bool {
        (generatedPlan?.count ?? 0) >= 4
    }

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
        // When advancing from goalSetting, trigger plan generation
        if currentStep == .goalSetting {
            startEarlyPlanGeneration()
        }
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            withAnimation { currentStep = next }
        }
    }

    /// Start plan generation early so it runs during the tutorial step.
    func startEarlyPlanGeneration() {
        startTemplatePlanGeneration()
    }

    func goBack() {
        if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            withAnimation { currentStep = prev }
        }
    }

    /// Navigate back to goal setting (used by "Go Back & Adjust" on plan review)
    func goBackToGoalSetting() {
        withAnimation { currentStep = .goalSetting }
    }

    /// Retry plan generation after a failure
    func retryPlanGeneration() {
        startTemplatePlanGeneration()
    }

    // MARK: - Template Classification

    /// Maps the current race to a template category and subtype.
    /// Returns nil if the race cannot be classified (triggers fully custom fallback).
    func classifyRaceForTemplate() -> (category: String, subtype: String)? {
        guard let result = raceSearchResult else { return nil }
        let type = result.type.lowercased()
        let distances = result.distances

        let hasSwim = distances["swim"] != nil
        let hasBike = distances["bike"] != nil
        let hasRun = distances["run"] != nil

        if type.contains("triathlon") || (hasSwim && hasBike && hasRun) {
            let totalMiles = distances.values.reduce(0, +)
            let subtype: String
            if totalMiles < 20 { subtype = "sprint" }
            else if totalMiles < 40 { subtype = "olympic" }
            else if totalMiles < 80 { subtype = "70.3" }
            else { subtype = "140.6" }
            return ("triathlon", subtype)
        }

        if type.contains("running") || type.contains("run") || (hasRun && !hasBike && !hasSwim) {
            let runMiles = distances["run"] ?? distances.values.max() ?? 0
            let subtype: String
            if runMiles < 4 { subtype = "5k" }
            else if runMiles < 8 { subtype = "10k" }
            else if runMiles < 15 { subtype = "half" }
            else { subtype = "marathon" }
            return ("running", subtype)
        }

        return nil
    }

    /// Validates the user's goal against heuristic time bounds.
    func validateGoal() {
        guard goalType == .timeTarget else {
            goalValidationWarning = nil
            return
        }
        let targetSeconds = targetHours * 3600 + targetMinutes * 60
        let minHours = finishTimeHourRange.lowerBound
        let minSeconds = minHours * 3600
        let weeksAvailable = max(1, Calendar.current.dateComponents(
            [.weekOfYear], from: Date(), to: raceSearchResult?.date ?? Date()
        ).weekOfYear ?? 12)

        if targetSeconds < minSeconds {
            goalValidationWarning = "This time goal is ambitious for \(weeksAvailable) weeks of training. Consider a more conservative target."
        } else {
            goalValidationWarning = nil
        }
    }

    /// Update includeStrength default based on race classification.
    func updateStrengthDefault() {
        guard let classification = classifyRaceForTemplate() else { return }
        switch classification.subtype {
        case "70.3", "140.6", "marathon", "half":
            includeStrength = true
        default:
            includeStrength = false
        }
    }

    /// Whether strength training is recommended for the current race distance.
    var strengthRecommended: Bool {
        guard let classification = classifyRaceForTemplate() else { return true }
        switch classification.subtype {
        case "70.3", "140.6", "marathon", "half":
            return true
        default:
            return false
        }
    }

    // MARK: - Template Plan Generation

    func startTemplatePlanGeneration() {
        // If we can't classify, fall back to batch generation
        guard let classification = classifyRaceForTemplate() else {
            startPlanGeneration()
            return
        }

        guard !isGeneratingPlan else { return }
        isGeneratingPlan = true
        planGenerationError = nil
        generatedPlan = nil
        planBatchesCompleted = 0
        planTotalBatches = 1
        planMethod = "template"
        planWarnings = []

        Task {
            let taskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

            let input = buildPlanGenerationInput()
            input.save()

            let goalTier: String
            switch goalType {
            case .justComplete: goalTier = "finish"
            case .timeTarget: goalTier = "timeGoal"
            case .custom: goalTier = "custom"
            }

            let templateParams = TemplateParams(
                raceCategory: classification.category,
                raceSubtype: classification.subtype,
                goalTier: goalTier,
                customGoalText: goalType == .custom ? customGoalText : nil,
                schedulePattern: schedulePattern.rawValue,
                includeStrength: includeStrength
            )

            do {
                let result = try await LLMProxyService.shared.generatePlanFromTemplate(
                    input: input,
                    templateParams: templateParams
                )
                generatedPlan = result.weeks
                planMethod = result.method
                planWarnings = result.warnings
                planBatchesCompleted = 1
                planTotalBatches = 1
            } catch {
                print("[TemplatePlan] Template generation failed, falling back to batch: \(error.localizedDescription)")
                isGeneratingPlan = false
                UIApplication.shared.endBackgroundTask(taskID)
                // Fall back to batch generation
                startPlanGeneration()
                return
            }

            isGeneratingPlan = false
            UIApplication.shared.endBackgroundTask(taskID)
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
            updateStrengthDefault()
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

    func startPlanGeneration() {
        guard !isGeneratingPlan else { return }
        isGeneratingPlan = true
        planGenerationError = nil
        generatedPlan = nil
        planBatchesCompleted = 0

        Task {
            // Keep the network request alive if the user backgrounds the app
            let taskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

            let input = buildPlanGenerationInput()
            input.save() // Save for regeneration from Settings

            let totalWeeks = max(4, Calendar.current.dateComponents(
                [.weekOfYear], from: Date(), to: input.race.date
            ).weekOfYear ?? 12)

            // Split into batches of ~5 weeks each (dynamic for any plan length)
            let batchSize = 5
            var batches: [(start: Int, end: Int)] = []
            var week = 1
            while week <= totalWeeks {
                let end = min(week + batchSize - 1, totalWeeks)
                batches.append((start: week, end: end))
                week = end + 1
            }

            planTotalBatches = batches.count

            for batch in batches {
                do {
                    let weeks = try await LLMProxyService.shared.generatePlanBatch(
                        input: input,
                        weekStart: batch.start,
                        weekEnd: batch.end,
                        totalWeeks: totalWeeks
                    )
                    if generatedPlan == nil {
                        generatedPlan = weeks
                    } else {
                        generatedPlan?.append(contentsOf: weeks)
                    }
                    planBatchesCompleted += 1
                } catch {
                    // If we already have enough weeks, silently stop; otherwise surface error
                    if minimumWeeksLoaded {
                        print("[PlanGen] Batch \(batch.start)-\(batch.end) failed but have \(generatedPlan?.count ?? 0) weeks, continuing")
                    } else {
                        planGenerationError = error.localizedDescription
                    }
                    break
                }
            }

            isGeneratingPlan = false
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    func buildPlanGenerationInput() -> PlanGenerationInput {
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

        return PlanGenerationInput(
            race: race,
            profile: profile,
            swimLevel: swimLevel,
            bikeLevel: bikeLevel,
            runLevel: runLevel,
            fitnessHours: schedulePattern.label,
            fitnessSchedule: schedulePattern.label,
            fitnessInjuries: fitnessInjuries,
            fitnessEquipment: fitnessEquipment,
            hkSummary: hkSummary,
            chatSummary: nil
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
        case .custom:
            goal = .custom(customGoalText)
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
    case custom
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
