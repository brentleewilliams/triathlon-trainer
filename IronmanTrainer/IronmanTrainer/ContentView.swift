import SwiftUI
import Foundation
import HealthKit

// MARK: - Secrets & Configuration
struct Secrets {
    static let anthropicAPIKey: String = {
        // Load from Config.plist
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath),
           let key = config["ANTHROPIC_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ""
    }()

    static let langsmithAPIKey: String = {
        // Load from Config.plist
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath),
           let key = config["LANGSMITH_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ""
    }()
}

// MARK: - Training Plan Data
struct TrainingWeek {
    let weekNumber: Int
    let phase: String
    let startDate: Date
    let endDate: Date
    let workouts: [DayWorkout]
}

struct DayWorkout: Equatable {
    let day: String
    let type: String
    let duration: String
    let zone: String
    let status: String?
}

class TrainingPlanManager: ObservableObject {
    @Published var weeks: [TrainingWeek] = []
    @Published var currentWeekNumber: Int = 1

    private let planStartDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 23
        return Calendar.current.date(from: components) ?? Date()
    }()

    init() {
        setupTrainingPlan()
        calculateCurrentWeek()
    }

    func calculateCurrentWeek() {
        let calendar = Calendar.current
        let today = Date()

        let daysSinceStart = calendar.dateComponents([.day], from: planStartDate, to: today).day ?? 0
        let weekNumber = (daysSinceStart / 7) + 1

        // Clamp between 1 and 17
        currentWeekNumber = max(1, min(17, weekNumber))
    }

    func getWeek(_ weekNumber: Int) -> TrainingWeek? {
        return weeks.first { $0.weekNumber == weekNumber }
    }

    private func setupTrainingPlan() {
        let phaseNames = ["Ramp Up", "Ramp Up", "Ramp Up", "Ramp Up", "Build 1", "Build 1", "Build 2", "Build 2", "Build 3", "Taper", "Taper", "Taper", "Race Prep", "Race Prep", "Race Prep", "Rest", "Race Week"]

        for week in 1...17 {
            let weekStartDate = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: planStartDate) ?? planStartDate
            let weekEndDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate

            weeks.append(TrainingWeek(
                weekNumber: week,
                phase: phaseNames[week - 1],
                startDate: weekStartDate,
                endDate: weekEndDate,
                workouts: workoutsForWeek(week)
            ))
        }

        // Sort by week number
        weeks.sort { $0.weekNumber < $1.weekNumber }
    }

    private func workoutsForWeek(_ weekNumber: Int) -> [DayWorkout] {
        // 100% Accurate workouts from IRONMAN_703_Oregon_Sub6_Plan_FINAL.pdf
        let baseWorkouts: [[DayWorkout]] = [
            // Week 1 — Mar 23 (~7.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,600yd", zone: "Z2", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "40min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,800yd", zone: "Z2", status: nil),
                DayWorkout(day: "Sat", type: "🏃 Run", duration: "50min", zone: "Z2", status: nil),
                DayWorkout(day: "Sun", type: "🚴 Bike", duration: "1:45", zone: "Z2", status: nil)
            ],
            // Week 2 — Mar 30 (~8 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,800yd", zone: "Z2", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "45min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:15", zone: "Z2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,000yd", zone: "Z2", status: nil),
                DayWorkout(day: "Fri", type: "🏃 Run", duration: "30min", zone: "Z2", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:15", zone: "Z2", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "55min", zone: "Z2", status: nil)
            ],
            // Week 3 — Apr 6 (~8.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,000yd", zone: "Z2", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "45min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike + mini-brick", duration: "1:10", zone: "Z2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,200yd", zone: "Z2", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:35", zone: "Z2", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "60min", zone: "Z2", status: nil)
            ],
            // Week 4 — Apr 13 — RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,500yd", zone: "Z1-2", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "30min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,500yd", zone: "Z1-2", status: nil),
                DayWorkout(day: "Sat", type: "🏃 Run", duration: "35min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil)
            ],
            // Week 5 — Apr 20 (~9 hrs) - Build 1
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z4", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,200yd", zone: "Z2", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "50min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,400yd", zone: "Z2-Z3", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:35", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "70min", zone: "Z2", status: nil)
            ],
            // Week 6 — Apr 27 (~9.5 hrs) - Build 1
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z4", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,400yd", zone: "Z2", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "55min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:00 + mini-brick", zone: "Z2-3", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,500yd", zone: "Z2-Z3", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:55", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "75min", zone: "Z2", status: nil)
            ],
            // Week 7 — May 4 (~10 hrs) - Build 1 KEY WEEK
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z4", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,800yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Tempo Run", duration: "60min", zone: "Z2-3", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike + mini-brick", duration: "1:15", zone: "Z2-3", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,800yd", zone: "Z2-Z3", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "3:35", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "80min", zone: "Z2", status: nil)
            ],
            // Week 8 — May 11 — RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,800yd", zone: "Z1-2", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "30min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,500yd", zone: "Z1-2", status: nil),
                DayWorkout(day: "Sat", type: "🏃 Run", duration: "35min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil)
            ],
            // Week 9 — May 18 (~10.5 hrs) - Build 2 / Race Specificity
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z3-4", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,500yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "55min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🏃 Tempo Run", duration: "65min", zone: "Z2-3", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,800yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Race Sim", duration: "3:25", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "90min", zone: "Z2", status: nil)
            ],
            // Week 10 — May 25 - SPRINT TRI TUNE-UP
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,200yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "40min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z2-3", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,500yd", zone: "Z2", status: nil),
                DayWorkout(day: "Fri", type: "🏃 Run", duration: "20min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Sat", type: "★ SPRINT TRI", duration: "Race", zone: "-", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Run", duration: "60min", zone: "Z2", status: nil)
            ],
            // Week 11 — Jun 1 - PEAK WEEK (~11-12 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z3-4", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "3,000yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Tempo Run", duration: "70min", zone: "Z2-3", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike + mini-brick", duration: "1:15", zone: "Z2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,800yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 KEY BRICK", duration: "3:50", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sun", type: "🏃 LONGEST RUN", duration: "1:45", zone: "Z2", status: nil)
            ],
            // Week 12 — Jun 8 - RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,000yd", zone: "Z1-2", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "30min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,500yd", zone: "Z1-2", status: nil),
                DayWorkout(day: "Sat", type: "🏃 Run", duration: "35min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil)
            ],
            // Week 13 — Jun 15 (~9.5 hrs) - DRESS REHEARSAL
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z2-3", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,500yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "55min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🏃 Run", duration: "60min", zone: "Z2-3", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,400yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 DRESS REHEARSAL", duration: "3:05", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "75min", zone: "Z2", status: nil)
            ],
            // Week 14 — Jun 22 (~8.5 hrs) - Peak & Sharpen
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2-3", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,200yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "45min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike + mini-brick", duration: "55min", zone: "Z2-3", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,000yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:25", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Run", duration: "60min", zone: "Z2", status: nil)
            ],
            // Week 15 — Jun 29 (~8 hrs) - Last hard week
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2-3", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,000yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Tempo Run", duration: "50min", zone: "Z2-3", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,800yd", zone: "Z2-3", status: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:05", zone: "Z2", status: nil),
                DayWorkout(day: "Sun", type: "🏃 Run", duration: "50min", zone: "Z2", status: nil)
            ],
            // Week 16 — Jul 6 - TAPER (~5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,500yd", zone: "Z2", status: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2-3", status: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "35min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z2", status: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,200yd", zone: "Z1-2", status: nil),
                DayWorkout(day: "Fri", type: "🏃 Run", duration: "20min", zone: "Z1-2", status: nil),
                DayWorkout(day: "Sat", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil)
            ],
            // Week 17 — Jul 13 - RACE WEEK
            [
                DayWorkout(day: "Mon", type: "✈️ Travel", duration: "Denver→Portland", zone: "-", status: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,000yd", zone: "Z2", status: nil),
                DayWorkout(day: "Wed", type: "🚴 Bike + 🏃 Run", duration: "40min + 15min", zone: "Z2", status: nil),
                DayWorkout(day: "Thu", type: "🏃 Easy Jog", duration: "20min", zone: "Z1", status: nil),
                DayWorkout(day: "Fri", type: "Rest", duration: "-", zone: "-", status: nil),
                DayWorkout(day: "Sat", type: "🏊 Shakeout Swim", duration: "15min", zone: "Z1", status: nil),
                DayWorkout(day: "Sun", type: "🏁 RACE DAY", duration: "~5:45-5:58", zone: "Race", status: nil)
            ]
        ]

        guard weekNumber >= 1 && weekNumber <= baseWorkouts.count else {
            return []
        }

        return baseWorkouts[weekNumber - 1]
    }
}

// MARK: - HealthKit Manager
class HealthKitManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = HealthKitManager()

    @Published var isAuthorized = false
    @Published var isSyncing = false
    @Published var syncError: String?
    @Published var workouts: [HKWorkout] = []

    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        checkAuthorization()
        // Auto-request authorization on app open
        Task {
            await self.requestAuthorization()
        }
    }

    func checkAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            syncError = "HealthKit not available"
            return
        }

        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let typesToRead: Set<HKObjectType> = [workoutType, heartRateType]

        healthStore.getRequestStatusForAuthorization(toShare: [], read: typesToRead) { status, _ in
            DispatchQueue.main.async {
                self.isAuthorized = (status == .unnecessary)
            }
        }
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run {
                syncError = "HealthKit not available"
            }
            return
        }

        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let typesToRead: Set<HKObjectType> = [workoutType, heartRateType]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            await MainActor.run {
                self.isAuthorized = true
                self.syncError = nil
            }
        } catch {
            await MainActor.run {
                self.isAuthorized = false
                self.syncError = error.localizedDescription
            }
        }
    }

    func syncWorkouts() async {
        await MainActor.run {
            isSyncing = true
            syncError = nil
        }

        // Run sync on background thread to avoid blocking UI
        let result = await Task.detached(priority: .background) { () -> (success: Bool, error: String?) in
            if !self.isAuthorized {
                await self.requestAuthorization()
                if !self.isAuthorized {
                    return (false, "HealthKit permission denied")
                }
            }

            // Only fetch workouts from last 30 days to avoid freezing
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: .strictStartDate)

            let workoutType = HKObjectType.workoutType()
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            return await withCheckedContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: workoutType,
                    predicate: predicate,
                    limit: 100, // Limit to 100 most recent workouts
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(returning: (false, error.localizedDescription))
                        return
                    }

                    if let workouts = results as? [HKWorkout] {
                        DispatchQueue.main.async {
                            self.workouts = workouts
                        }
                    }

                    continuation.resume(returning: (true, nil))
                }

                self.healthStore.execute(query)
            }
        }.value

        await MainActor.run {
            isSyncing = false
            if !result.success {
                syncError = result.error ?? "Unknown error"
            } else {
                syncError = nil
            }
        }
    }
}

// MARK: - LangSmith Tracer
class LangSmithTracer {
    static let shared = LangSmithTracer()

    private let langsmithAPIKey: String
    private let baseURL = "https://api.smith.langchain.com/runs"
    private let sessionName = "IronmanTrainer"

    init() {
        // Load API key from Secrets (Config.xcconfig)
        self.langsmithAPIKey = Secrets.langsmithAPIKey
    }

    func isEnabled() -> Bool {
        !langsmithAPIKey.isEmpty
    }

    func startRun(systemPrompt: String, userMessage: String) -> String {
        guard isEnabled() else { return "" }

        // LangSmith expects lowercase UUID format without dashes
        let runID = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let now = ISO8601DateFormatter().string(from: Date())

        let inputs: [String: Any] = [
            "system_prompt": systemPrompt,
            "user_message": userMessage
        ]

        let body: [String: Any] = [
            "id": runID,
            "name": "IronmanCoach",
            "run_type": "llm",
            "inputs": inputs,
            "start_time": now,
            "session_name": sessionName
        ]

        Task {
            await logRunToLangSmith(body)
        }

        return runID
    }

    func endRun(runID: String, response: String) {
        guard isEnabled() && !runID.isEmpty else { return }

        let now = ISO8601DateFormatter().string(from: Date())

        let outputs: [String: Any] = [
            "response": response
        ]

        let body: [String: Any] = [
            "outputs": outputs,
            "end_time": now
        ]

        Task {
            await updateRunInLangSmith(runID: runID, body: body)
        }
    }

    private func logRunToLangSmith(_ body: [String: Any]) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(langsmithAPIKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 202 {
                    print("✅ LangSmith run logged")
                } else {
                    if let errorText = String(data: data, encoding: .utf8) {
                        print("⚠️ LangSmith error \(httpResponse.statusCode): \(errorText)")
                    } else {
                        print("⚠️ LangSmith error: \(httpResponse.statusCode)")
                    }
                }
            }
        } catch {
            print("❌ LangSmith logging failed: \(error)")
        }
    }

    private func updateRunInLangSmith(runID: String, body: [String: Any]) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        let updateURL = "\(baseURL)/\(runID)"
        var request = URLRequest(url: URL(string: updateURL)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(langsmithAPIKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 202 {
                    print("✅ LangSmith run completed")
                } else {
                    print("⚠️ LangSmith update error: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("❌ LangSmith update failed: \(error)")
        }
    }
}

// MARK: - Claude Service
class ClaudeService: NSObject, ObservableObject {
    static let shared = ClaudeService()

    private let apiKey: String
    private let model = "claude-opus-4-6"
    private let baseURL = "https://api.anthropic.com/v1/messages"

    override init() {
        // Load API key from Secrets (Config.xcconfig)
        self.apiKey = Secrets.anthropicAPIKey
        super.init()
    }

    func sendMessage(userMessage: String, trainingContext: String, workoutHistory: String) async throws -> String {
        let systemPrompt = buildSystemPrompt(context: trainingContext, history: workoutHistory)

        // Start LangSmith run
        let runID = LangSmithTracer.shared.startRun(systemPrompt: systemPrompt, userMessage: userMessage)

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": userMessage
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw ClaudeServiceError.invalidRequest
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeServiceError.networkError
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let responseBody = try decoder.decode(ClaudeResponse.self, from: data)
            if let content = responseBody.content.first?.text {
                // End LangSmith run with response
                LangSmithTracer.shared.endRun(runID: runID, response: content)
                return content
            }
            throw ClaudeServiceError.invalidResponse
        case 401:
            throw ClaudeServiceError.invalidAPIKey
        case 429:
            throw ClaudeServiceError.rateLimitExceeded
        default:
            // Return more detailed error info
            if let errorData = String(data: data, encoding: .utf8) {
                print("API Error: \(httpResponse.statusCode) - \(errorData)")
            }
            throw ClaudeServiceError.serverError
        }
    }

    private func buildSystemPrompt(context: String, history: String) -> String {
        """
        You are a personal triathlon coaching assistant for Brent, training for Ironman 70.3 Oregon (Jul 19, 2026, Salem OR).

        TRAINING PLAN: 17-week program (Mar 23 - Jul 19, 2026)
        ATHLETE: VO2 Max 57.8, HR zones Z1-Z5, 8-10 hrs/wk available
        RACE GOAL: Sub-6:00 finish (Swim 38-42m | Bike 3:00-3:10 | Run 1:95-2:02)

        TRAINING CONTEXT:
        \(context)

        RECENT WORKOUTS:
        \(history)

        Give specific coaching advice based on Brent's training plan, zones, and race strategy.
        """
    }
}

enum ClaudeServiceError: LocalizedError {
    case invalidRequest
    case networkError
    case invalidResponse
    case invalidAPIKey
    case rateLimitExceeded
    case serverError

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid request format"
        case .networkError:
            return "Network connection failed"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .serverError:
            return "Server error"
        }
    }
}

struct ClaudeResponse: Codable {
    struct Content: Codable {
        let text: String
    }

    let content: [Content]
}

// MARK: - Chat ViewModel
struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    let timestamp: Date = Date()
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading = false
    @Published var error: String?

    private let claudeService = ClaudeService.shared
    var trainingPlan: TrainingPlanManager?
    var healthKit: HealthKitManager?

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        print("DEBUG: sendMessage called - trainingPlan: \(trainingPlan != nil), healthKit: \(healthKit != nil)")

        await MainActor.run {
            inputText = ""
            messages.append(ChatMessage(isUser: true, text: text))
            isLoading = true
            error = nil
        }

        do {
            let context = getContextForClaude()
            let history = getWorkoutHistoryForClaude()
            let response = try await claudeService.sendMessage(userMessage: text, trainingContext: context, workoutHistory: history)

            await MainActor.run {
                messages.append(ChatMessage(isUser: false, text: response))
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func getContextForClaude() -> String {
        guard let plan = trainingPlan else {
            return "No training plan available"
        }

        let currentWeek = plan.getWeek(plan.currentWeekNumber) ?? plan.getWeek(1)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone.current

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        dayFormatter.timeZone = TimeZone.current

        let today = Date()
        var context = "TODAY'S DATE: \(formatter.string(from: today)) (\(dayFormatter.string(from: today)))\n\n"
        context += "CURRENT WEEK PLAN:\n"

        if let week = currentWeek {
            context += "Week \(week.weekNumber) (\(formatter.string(from: week.startDate)) - \(formatter.string(from: week.endDate))): \(week.phase)\n\n"

            let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            for day in dayOrder {
                let dayWorkouts = week.workouts.filter { $0.day == day }
                if !dayWorkouts.isEmpty {
                    let workoutTexts = dayWorkouts.map { "\($0.type) (\($0.duration) • \($0.zone))" }.joined(separator: " + ")
                    context += "- \(day): \(workoutTexts)\n"
                }
            }
        }

        print("DEBUG: ChatViewModel context being sent to Claude:\n\(context)")
        return context
    }

    private func getWorkoutHistoryForClaude() -> String {
        guard let healthKit = healthKit else {
            print("DEBUG: healthKit is nil in getWorkoutHistoryForClaude")
            return "No workout history available"
        }

        print("DEBUG: healthKit has \(healthKit.workouts.count) total workouts")

        let calendar = Calendar.current
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) ?? Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        print("DEBUG: Filtering workouts from \(formatter.string(from: fourWeeksAgo)) to now")

        var swimCount = 0
        var bikeCount = 0
        var runCount = 0
        var totalSwimYards = 0.0
        var totalBikeHours = 0.0
        var totalRunMinutes = 0.0

        for workout in healthKit.workouts {
            let workoutTypeStr: String
            switch workout.workoutActivityType {
            case .swimming:
                workoutTypeStr = "Swimming"
            case .cycling:
                workoutTypeStr = "Cycling"
            case .running:
                workoutTypeStr = "Running"
            default:
                workoutTypeStr = "Other"
            }
            let workoutDate = formatter.string(from: workout.startDate)
            let durationMins = Int(workout.duration / 60)

            print("DEBUG: Workout - \(workoutTypeStr) on \(workoutDate) (\(durationMins) min)")

            guard workout.startDate >= fourWeeksAgo else {
                print("DEBUG:   -> FILTERED OUT (older than 4 weeks)")
                continue
            }

            let durationHours = workout.duration / 3600
            let durationMinutes = workout.duration / 60

            switch workout.workoutActivityType {
            case .swimming:
                swimCount += 1
                totalSwimYards += durationHours * 1800
                print("DEBUG:   -> Added to swimming (\(swimCount) total)")
            case .cycling:
                bikeCount += 1
                totalBikeHours += durationHours
                print("DEBUG:   -> Added to cycling (\(bikeCount) total)")
            case .running:
                runCount += 1
                totalRunMinutes += durationMinutes
                print("DEBUG:   -> Added to running (\(runCount) total)")
            default:
                print("DEBUG:   -> UNKNOWN TYPE, skipped")
                break
            }
        }

        var history = "LAST 4 WEEKS COMPLETED WORKOUTS:\n"
        history += "- Swimming: \(swimCount) sessions (\(Int(totalSwimYards)) total yards)\n"
        history += "- Cycling: \(bikeCount) sessions (\(String(format: "%.1f", totalBikeHours)) total hours)\n"
        history += "- Running: \(runCount) sessions (\(Int(totalRunMinutes)) total minutes)\n\n"
        history += "COMPLIANCE: \(healthKit.workouts.filter { $0.startDate >= fourWeeksAgo }.count) completed workouts in last 4 weeks"

        print("DEBUG: Final workout history:\n\(history)")
        return history
    }
}

struct ContentView: View {
    @StateObject private var trainingPlan = TrainingPlanManager()
    @EnvironmentObject var healthKit: HealthKitManager
    @StateObject private var chatViewModel = ChatViewModel()

    var body: some View {
        // Set managers on chatViewModel immediately so they're available when messages are sent
        chatViewModel.trainingPlan = trainingPlan
        chatViewModel.healthKit = healthKit

        return TabView {
            HomeView()
                .environmentObject(trainingPlan)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            AnalyticsView()
                .environmentObject(trainingPlan)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }

            ChatView(viewModel: chatViewModel)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }

            PlanView()
                .tabItem {
                    Label("Plan", systemImage: "calendar")
                }
        }
    }
}

// MARK: - Week Navigation Header (Shared)
struct WeekNavigationHeader: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @Binding var selectedWeek: Int

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    var formattedDateRange: String {
        guard let week = currentWeek else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startStr = formatter.string(from: week.startDate)
        let endStr = formatter.string(from: week.endDate)
        return "\(startStr) - \(endStr), 2026"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { if selectedWeek > 1 { selectedWeek -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            .disabled(selectedWeek <= 1)

            VStack(alignment: .center, spacing: 4) {
                Text("Week \(selectedWeek) - \(currentWeek?.phase ?? "")")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(formattedDateRange)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)

            Button(action: { if selectedWeek < 17 { selectedWeek += 1 } }) {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .disabled(selectedWeek >= 17)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @State private var selectedWeek: Int = 1
    @State private var selectedDay: DayWorkout?
    @State private var showDayDetail = false

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    var formattedDateRange: String {
        guard let week = currentWeek else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startStr = formatter.string(from: week.startDate)
        let endStr = formatter.string(from: week.endDate)
        return "\(startStr) - \(endStr), 2026"
    }

    var todaysTotalWorkouts: Int {
        guard let week = currentWeek else { return 0 }

        let today = Date()
        let calendar = Calendar.current
        let todayStartOfDay = calendar.startOfDay(for: today)

        var count = 0

        // Count all non-rest workouts from start of week through today
        for workout in week.workouts {
            if !workout.type.contains("Rest") {
                let dayDate = getDateForDay(workout)
                let dayStartOfDay = calendar.startOfDay(for: dayDate)
                if dayStartOfDay <= todayStartOfDay {
                    count += 1
                }
            }
        }

        // Add 1 for each rest day from start through today that is "completed" (no non-yoga/walking workouts)
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for day in dayOrder {
            let dayWorkouts = week.workouts.filter { $0.day == day }
            if let restWorkout = dayWorkouts.first(where: { $0.type.contains("Rest") }) {
                let dayDate = getDateForDay(restWorkout)
                let dayStartOfDay = calendar.startOfDay(for: dayDate)
                if dayStartOfDay <= todayStartOfDay && isRestDayCompleted(for: restWorkout) {
                    count += 1
                }
            }
        }

        return count
    }

    var workoutsByDay: [(day: String, workouts: [DayWorkout])] {
        guard let week = currentWeek else { return [] }

        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let grouped = Dictionary(grouping: week.workouts, by: { $0.day })

        return dayOrder.compactMap { day in
            guard let workouts = grouped[day] else { return nil }
            return (day: day, workouts: workouts)
        }
    }

    var todaysCompletedWorkouts: Int {
        guard let week = currentWeek else { return 0 }

        let today = Date()
        let calendar = Calendar.current
        let todayStartOfDay = calendar.startOfDay(for: today)

        var count = 0

        // Count completed non-rest workouts from start through today
        for workout in week.workouts {
            if !workout.type.contains("Rest") {
                let dayDate = getDateForDay(workout)
                let dayStartOfDay = calendar.startOfDay(for: dayDate)
                if dayStartOfDay <= todayStartOfDay && isWorkoutCompleted(workout) {
                    count += 1
                }
            }
        }

        // Add 1 for each rest day from start through today that is "completed"
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for day in dayOrder {
            let dayWorkouts = week.workouts.filter { $0.day == day }
            if let restWorkout = dayWorkouts.first(where: { $0.type.contains("Rest") }) {
                let dayDate = getDateForDay(restWorkout)
                let dayStartOfDay = calendar.startOfDay(for: dayDate)
                if dayStartOfDay <= todayStartOfDay && isRestDayCompleted(for: restWorkout) {
                    count += 1
                }
            }
        }

        return count
    }

    func isWorkoutCompleted(_ workout: DayWorkout) -> Bool {
        // Check if there's a matching HealthKit workout
        let workoutType = extractWorkoutType(from: workout.type)
        let targetDate = getDateForDay(workout)

        return healthKit.workouts.contains { hkWorkout in
            let calendar = Calendar.current
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let targetStartOfDay = calendar.startOfDay(for: targetDate)

            return workoutDate == targetStartOfDay &&
                   workoutTypeMatches(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType)
        }
    }

    func isRestDayCompleted(for workout: DayWorkout) -> Bool {
        // Rest day is "completed" if no non-yoga/walking workouts were done
        let targetDate = getDateForDay(workout)
        let calendar = Calendar.current
        let targetStartOfDay = calendar.startOfDay(for: targetDate)

        return !healthKit.workouts.contains { hkWorkout in
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let isTargetDay = workoutDate == targetStartOfDay

            // Exclude yoga and walking
            let isYogaOrWalking = hkWorkout.workoutActivityType == .yoga ||
                                   hkWorkout.workoutActivityType == .walking

            return isTargetDay && !isYogaOrWalking
        }
    }

    func getDateForDay(_ workout: DayWorkout) -> Date {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayIndex = dayOrder.firstIndex(of: workout.day) ?? 0

        let calendar = Calendar.current
        let weekStart = currentWeek?.startDate ?? Date()
        let daysToAdd = dayIndex

        return calendar.date(byAdding: .day, value: daysToAdd, to: weekStart) ?? weekStart
    }

    func workoutTypeMatches(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool {
        let planned = plannedType.lowercased()
        switch healthKitType {
        case .cycling:
            return planned == "bike"
        case .swimming:
            return planned == "swim"
        case .running:
            return planned == "run"
        case .walking:
            return planned == "walk"
        default:
            return false
        }
    }

    func extractWorkoutType(from typeString: String) -> String {
        if typeString.contains("🚴") { return "Bike" }
        if typeString.contains("🏊") { return "Swim" }
        if typeString.contains("🏃") { return "Run" }
        if typeString.contains("🏁") { return "Run" }
        return typeString
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Week Navigation Header
                WeekNavigationHeader(selectedWeek: $selectedWeek)

                // Completion Counter
                HStack {
                    Text("Workouts Completed")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(todaysCompletedWorkouts)/\(todaysTotalWorkouts)")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

                // Sync Error Display
                if let error = healthKit.syncError {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Sync Error")
                                .font(.headline)
                        }
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                ScrollView {
                    DayGroupsView(
                        dayGroups: workoutsByDay,
                        week: currentWeek,
                        healthKit: healthKit,
                        parent: self
                    )
                }

                Spacer()
            }
            .navigationTitle("Training Plan")
            .onAppear {
                selectedWeek = trainingPlan.currentWeekNumber
            }
        }
    }
}

// MARK: - Day Detail View
struct DayDetailView: View {
    let day: DayWorkout
    let week: TrainingWeek
    @ObservedObject var healthKit: HealthKitManager
    @State private var note: String = ""
    @Environment(\.dismiss) var dismiss

    var dayName: String {
        let dayMap = ["Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday",
                      "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"]
        return dayMap[day.day] ?? day.day
    }

    var navTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(dayName), \(formatter.string(from: getDateForDay()))"
    }

    var matchingHealthKitWorkouts: [HKWorkout] {
        let workoutType = extractWorkoutType(from: day.type)
        let targetDate = getDateForDay()

        return healthKit.workouts.filter { hkWorkout in
            let calendar = Calendar.current
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let targetStartOfDay = calendar.startOfDay(for: targetDate)

            return workoutDate == targetStartOfDay &&
                   workoutTypeMatches(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType)
        }
    }

    func getDateForDay() -> Date {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayIndex = dayOrder.firstIndex(of: day.day) ?? 0

        let calendar = Calendar.current
        let weekStart = week.startDate
        let daysToAdd = dayIndex

        return calendar.date(byAdding: .day, value: daysToAdd, to: weekStart) ?? weekStart
    }

    func workoutTypeMatches(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool {
        let planned = plannedType.lowercased()
        switch healthKitType {
        case .cycling:
            return planned == "bike"
        case .swimming:
            return planned == "swim"
        case .running:
            return planned == "run"
        case .walking:
            return planned == "walk"
        default:
            return false
        }
    }

    func getWorkoutTypeName(_ workoutType: HKWorkoutActivityType) -> String {
        switch workoutType {
        case .cycling:
            return "Cycling"
        case .swimming:
            return "Swimming"
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        default:
            return "Workout"
        }
    }

    func extractWorkoutType(from typeString: String) -> String {
        if typeString.contains("🚴") { return "Bike" }
        if typeString.contains("🏊") { return "Swim" }
        if typeString.contains("🏃") { return "Run" }
        if typeString.contains("🏁") { return "Run" }
        return typeString
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Planned Workout
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Planned Workout")
                                .font(.headline)
                            Spacer()
                            if matchingHealthKitWorkouts.count > 0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }

                        if day.type.contains("Rest") {
                            Text("Rest Day")
                                .font(.title3)
                                .fontWeight(.semibold)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Type:")
                                    Spacer()
                                    Text(day.type)
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Duration:")
                                    Spacer()
                                    Text(day.duration)
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Zone:")
                                    Spacer()
                                    Text(day.zone)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // HealthKit Workouts
                    if !matchingHealthKitWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Completed Workouts")
                                .font(.headline)

                            ForEach(matchingHealthKitWorkouts, id: \.uuid) { workout in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(getWorkoutTypeName(workout.workoutActivityType))
                                        .fontWeight(.semibold)
                                    HStack {
                                        Text("Duration:")
                                        Spacer()
                                        Text(String(format: "%.0f", workout.duration / 60) + " min")
                                    }
                                    .font(.caption)
                                    if let energy = workout.totalEnergyBurned {
                                        HStack {
                                            Text("Calories:")
                                            Spacer()
                                            Text(String(format: "%.0f", energy.doubleValue(for: .kilocalorie())) + " kcal")
                                        }
                                        .font(.caption)
                                    }
                                }
                                .padding(10)
                                .background(Color(.systemGreen).opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    } else if !day.type.contains("Rest") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.orange)
                                Text("No completed workouts")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    // Notes Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: $note)
                            .frame(height: 120)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct WeekdayWorkoutRow: View {
    let day: String
    let type: String
    let duration: String
    let zone: String
    var isCompleted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(day)
                .fontWeight(.bold)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(type)
                    .fontWeight(.semibold)
                Text("\(duration) • \(zone)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Day Groups View
struct DayGroupsView: View {
    let dayGroups: [(day: String, workouts: [DayWorkout])]
    let week: TrainingWeek?
    @ObservedObject var healthKit: HealthKitManager
    let parent: HomeView

    var body: some View {
        if let week = week, !dayGroups.isEmpty {
            VStack(spacing: 12) {
                ForEach(dayGroups, id: \.day) { dayGroup in
                    NavigationLink(destination: DayDetailView(
                        day: dayGroup.workouts[0],
                        week: week,
                        healthKit: healthKit
                    )) {
                        DayRowView(
                            dayGroup: dayGroup,
                            weekStartDate: week.startDate,
                            parent: parent
                        )
                    }
                }
            }
            .padding()
        } else {
            VStack(spacing: 12) {
                Text("No workouts planned for this week")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
    }
}

// MARK: - Day Row View
struct DayRowView: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView

    var isRestDay: Bool {
        dayGroup.workouts.allSatisfy { $0.type.contains("Rest") }
    }

    var body: some View {
        if isRestDay {
            RestDayRow(dayGroup: dayGroup, weekStartDate: weekStartDate, parent: parent)
        } else {
            WorkoutDayRows(dayGroup: dayGroup, weekStartDate: weekStartDate, parent: parent)
        }
    }
}

// MARK: - Rest Day Row
struct RestDayRow: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    var dayDate: String {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate
        return Self.dateFormatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(dayGroup.day)
                    .fontWeight(.bold)
                Text(dayDate)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .frame(width: 40)

            HStack(spacing: 6) {
                Text("🛌")
                    .font(.title3)
                Text("Rest")
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }

            Spacer()

            if parent.isRestDayCompleted(for: dayGroup.workouts[0]) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Workout Day Rows
struct WorkoutDayRows: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    var dayDate: String {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate
        return Self.dateFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(dayGroup.workouts, id: \.duration) { workout in
                HStack(spacing: 12) {
                    if dayGroup.workouts.first == workout {
                        VStack(spacing: 0) {
                            Text(dayGroup.day)
                                .fontWeight(.bold)
                            Text(dayDate)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .frame(width: 40)
                    } else {
                        Spacer()
                            .frame(width: 40)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.type)
                            .fontWeight(.semibold)
                        Text("\(workout.duration) • \(workout.zone)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    if parent.isWorkoutCompleted(workout) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Analytics View
struct AnalyticsView: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var selectedWeek: Int = 1

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    var volumeData: (swim: Double, bike: Double, run: Double) {
        guard let week = currentWeek else { return (0, 0, 0) }

        let calendar = Calendar.current
        let weekStart = calendar.startOfDay(for: week.startDate)
        let weekEnd = calendar.startOfDay(for: week.endDate)

        var swimHours: Double = 0
        var bikeHours: Double = 0
        var runHours: Double = 0

        // Count completed workouts from HealthKit for this week
        for hkWorkout in healthKit.workouts {
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)

            // Only include workouts within the selected week
            guard workoutDate >= weekStart && workoutDate <= weekEnd else { continue }

            let hours = hkWorkout.duration / 3600 // Convert seconds to hours

            switch hkWorkout.workoutActivityType {
            case .swimming:
                swimHours += hours
            case .cycling:
                bikeHours += hours
            case .running:
                runHours += hours
            default:
                break
            }
        }

        return (swimHours, bikeHours, runHours)
    }

    var zoneDistribution: [String: Double] {
        guard let week = currentWeek else {
            return ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
        }

        var zoneHours: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]

        for workout in week.workouts {
            if workout.type.contains("Rest") { continue }

            let hours = parseWorkoutDuration(workout.duration)
            let zone = parseZone(workout.zone)

            for z in zone {
                zoneHours[z, default: 0] += hours / Double(zone.count)
            }
        }

        return zoneHours
    }

    var totalTrainingHours: Double {
        let volume = volumeData
        return volume.swim + volume.bike + volume.run
    }

    var zonePercentages: [String: Double] {
        let distribution = zoneDistribution
        let total = distribution.values.reduce(0, +)

        guard total > 0 else {
            return ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
        }

        return [
            "Z1": (distribution["Z1"] ?? 0) / total * 100,
            "Z2": (distribution["Z2"] ?? 0) / total * 100,
            "Z3": (distribution["Z3"] ?? 0) / total * 100,
            "Z4": (distribution["Z4"] ?? 0) / total * 100,
            "Z5": (distribution["Z5"] ?? 0) / total * 100
        ]
    }

    var plannedVolumeData: (swim: Double, bike: Double, run: Double) {
        guard let week = currentWeek else { return (0, 0, 0) }

        var swimHours: Double = 0
        var bikeHours: Double = 0
        var runHours: Double = 0

        for workout in week.workouts {
            if workout.type.contains("Rest") { continue }

            let hours = parseWorkoutDuration(workout.duration)

            if workout.type.contains("🏊") {
                swimHours += hours
            } else if workout.type.contains("🚴") && !workout.type.contains("🏃") {
                bikeHours += hours
            } else if workout.type.contains("🏃") && !workout.type.contains("🚴") {
                runHours += hours
            } else if workout.type.contains("🚴") && workout.type.contains("🏃") {
                // Brick workouts split between bike and run
                bikeHours += hours * 0.6
                runHours += hours * 0.4
            }
        }

        return (swimHours, bikeHours, runHours)
    }

    func parseWorkoutDuration(_ duration: String) -> Double {
        let trimmed = duration.trimmingCharacters(in: .whitespaces)

        // Handle "min" format (e.g., "40min")
        if trimmed.contains("min") {
            let value = trimmed.replacingOccurrences(of: "min", with: "").trimmingCharacters(in: .whitespaces)
            return (Double(value) ?? 0) / 60
        }

        // Handle "H:MM" format (e.g., "1:00", "2:30")
        if trimmed.contains(":") {
            let components = trimmed.split(separator: ":")
            if components.count == 2,
               let hours = Double(components[0]),
               let minutes = Double(components[1]) {
                return hours + (minutes / 60)
            }
        }

        // Handle yard format for swimming (approximate 1 yard = 1 minute in pool)
        if trimmed.contains("yd") {
            let value = trimmed.replacingOccurrences(of: "yd", with: "").trimmingCharacters(in: .whitespaces)
            let cleanValue = value.replacingOccurrences(of: ",", with: "")
            if let yardage = Double(cleanValue) {
                return yardage / 1800 // ~1800 yards per hour
            }
        }

        // Handle "Race" or other text
        if trimmed.lowercased() == "race" {
            return 3.0 // Assume sprint tri is ~3 hours
        }

        return 0
    }

    func parseZone(_ zone: String) -> [String] {
        let trimmed = zone.trimmingCharacters(in: .whitespaces)

        if trimmed.contains("-") {
            // Split zones like "Z2-3" or "Z1-2"
            let parts = trimmed.split(separator: "-")
            if parts.count == 2 {
                if let firstNum = parts[0].last, let secondNum = parts[1].last {
                    let first = Int(String(firstNum)) ?? 2
                    let second = Int(String(secondNum)) ?? 2
                    return Array(first...second).map { "Z\($0)" }
                }
            }
        }

        // Single zone like "Z2"
        return [trimmed]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Week Navigation Header (Shared)
                WeekNavigationHeader(selectedWeek: $selectedWeek)

                // Volume Summary
                VStack(spacing: 12) {
                    Text("Volume Summary")
                        .font(.headline)

                    HStack(spacing: 20) {
                        VolumeCard(label: "Swim", hours: volumeData.swim, planned: plannedVolumeData.swim, color: .blue)
                        VolumeCard(label: "Bike", hours: volumeData.bike, planned: plannedVolumeData.bike, color: .orange)
                        VolumeCard(label: "Run", hours: volumeData.run, planned: plannedVolumeData.run, color: .green)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Zone Distribution
                VStack(spacing: 12) {
                    Text("Zone Distribution (Week \(selectedWeek))")
                        .font(.headline)

                    HStack(spacing: 20) {
                        ZoneBar(zone: "Z1", percent: zonePercentages["Z1"] ?? 0, color: .gray)
                        ZoneBar(zone: "Z2", percent: zonePercentages["Z2"] ?? 0, color: .green)
                        ZoneBar(zone: "Z3", percent: zonePercentages["Z3"] ?? 0, color: .yellow)
                        ZoneBar(zone: "Z4", percent: zonePercentages["Z4"] ?? 0, color: .orange)
                        ZoneBar(zone: "Z5", percent: zonePercentages["Z5"] ?? 0, color: .red)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Spacer()
            }
            .padding()
            .navigationTitle("Analytics")
            .onAppear {
                selectedWeek = trainingPlan.currentWeekNumber
            }
        }
    }
}

struct VolumeCard: View {
    let label: String
    let hours: Double
    let planned: Double
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)

            Text("\(String(format: "%.1f", hours))h")
                .font(.headline)
                .foregroundColor(color)

            Text("plan: \(String(format: "%.1f", planned))h")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ZoneBar: View {
    let zone: String
    let percent: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(zone)
                .font(.caption)
                .fontWeight(.semibold)

            GeometryReader { geometry in
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(color)
                        .frame(height: geometry.size.height * (percent / 100))
                }
            }
            .frame(height: 80)

            Text("\(Int(percent))%")
                .font(.caption2)
        }
    }
}

// MARK: - Chat View
struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isLoading {
                                HStack(spacing: 4) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        Circle()
                                            .fill(Color.gray)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                                .padding()
                            }

                            if let error = viewModel.error {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .padding()
                            }
                        }
                        .padding()
                        .onChange(of: viewModel.messages.count) {
                            if let last = viewModel.messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onTapGesture {
                    isInputFocused = false
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("Ask about your training...", text: $viewModel.inputText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isLoading)
                        .focused($isInputFocused)

                    Button(action: {
                        Task {
                            await viewModel.sendMessage(viewModel.inputText)
                        }
                        isInputFocused = false
                    }) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)
                }
                .padding()
            }
            .navigationTitle("Training Coach")
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()

                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            } else {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .foregroundColor(.black)
                    .cornerRadius(12)

                Spacer()
            }
        }
    }
}

// MARK: - Plan View
struct PlanView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("17-Week Training Plan")
                    .font(.headline)
                    .padding()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(1...17, id: \.self) { week in
                            WeekCard(weekNumber: week)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Plan Overview")
        }
    }
}

struct WeekCard: View {
    let weekNumber: Int

    var phase: String {
        switch weekNumber {
        case 1...4: return "Volume Rebalance"
        case 5...8: return "Build 1"
        case 9...12: return "Build 2 / Race Specificity"
        case 13...15: return "Peak & Sharpen"
        default: return "Taper & Race"
        }
    }

    var startDate: String {
        let start = Date(timeIntervalSince1970: 1711190400) // Mar 23, 2026
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .weekOfYear, value: weekNumber - 1, to: start)!
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: weekStart)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week \(weekNumber)")
                    .fontWeight(.bold)

                Text(phase)
                    .font(.caption)
                    .foregroundColor(.gray)

                Text(startDate)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            if weekNumber == 5 {
                Text("NOW")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
        }
        .padding(12)
        .background(weekNumber == 5 ? Color(.systemGray5) : Color(.systemBackground))
        .border(weekNumber == 5 ? Color.green : Color.clear, width: weekNumber == 5 ? 2 : 0)
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
