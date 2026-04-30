import Foundation
import HealthKit

// MARK: - Sleep Summary (Morning Check-In v1)
/// Captured overnight sleep snapshot used by the Morning Check-In feature.
/// v1 surfaces duration + source only; stage fields are populated when the
/// HealthKit samples report them (Apple Watch) and nil otherwise.
/// See PRD §3.6.3.
struct SleepSummary: Codable, Equatable {
    /// "Night of" date — the calendar date the sleep period began.
    let date: Date
    /// Total asleep minutes: asleepCore + asleepDeep + asleepREM + asleepUnspecified.
    let totalSleepMinutes: Int
    /// Time in bed (may exceed total sleep).
    let timeInBedMinutes: Int
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let awakeMinutes: Int?
    /// Sample source name. Examples: "Apple Watch", "iPhone", third-party app name.
    /// UI treats all sources equivalently in v1.
    let source: String
}

// MARK: - HealthKit Manager
class HealthKitManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = HealthKitManager()

    @Published var isAuthorized = false
    @Published var isSyncing = false
    @Published var syncError: String?
    @Published var workouts: [HKWorkout] = []
    @Published var workoutZones: [UUID: [String: Double]] = [:]

    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        // Don't check authorization on init — it can trigger system prompts
        // before the user reaches the onboarding HK screen.
        // checkAuthorization() is called explicitly after onboarding completes.
    }

    /// HealthKit types the app reads. Force-unwraps are safe here: all identifiers
    /// are standard Apple-defined constants that cannot return nil at runtime.
    /// Morning Check-In v1: includes sleep analysis. HRV + resting HR deferred to v2.
    static let requiredHKTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
        HKQuantityType.quantityType(forIdentifier: .vo2Max)!,
        HKQuantityType.quantityType(forIdentifier: .height)!,
        HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,
        HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
        HKObjectType.characteristicType(forIdentifier: .biologicalSex)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.categoryType(forIdentifier: .appleStandHour)!,
    ]

    func checkAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            syncError = "HealthKit not available"
            return
        }

        healthStore.getRequestStatusForAuthorization(toShare: [], read: Self.requiredHKTypes) { status, _ in
            DispatchQueue.main.async {
                self.isAuthorized = (status == .unnecessary)
            }
        }
    }

    private static let typesToShare: Set<HKSampleType> = [
        HKObjectType.workoutType()
    ]

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run {
                syncError = "HealthKit not available"
            }
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: Self.typesToShare, read: Self.requiredHKTypes)
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

    // MARK: - Save / Delete Workout

    func deleteWorkout(_ workout: HKWorkout) async throws {
        try await healthStore.delete(workout)
        await MainActor.run {
            workouts.removeAll { $0.uuid == workout.uuid }
        }
    }

    func saveWorkout(activityType: HKWorkoutActivityType, start: Date, end: Date) async throws {
        // Ensure write authorization has been requested (read may be authorized but write may not)
        try await healthStore.requestAuthorization(toShare: Self.typesToShare, read: [])
        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        try await builder.finishWorkout()
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
            let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: sixtyDaysAgo, end: Date(), options: .strictStartDate)

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
                            self.fetchZonesForRecentWorkouts()
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

    // MARK: - HR Zone Analysis

    private var cachedAge: Int?

    func getUserAge() -> Int {
        if let cached = cachedAge {
            return cached
        }

        do {
            let dobComponents = try healthStore.dateOfBirthComponents()
            let dateOfBirth = Calendar.current.date(from: dobComponents) ?? Date()
            let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 38
            cachedAge = age
            return age
        } catch {
            print("Could not read date of birth from HealthKit: \(error)")
            return 38  // Fallback to default age
        }
    }

    var maxHeartRate: Int {
        220 - getUserAge()
    }

    /// BPM zone boundaries derived from maxHeartRate using %maxHR thresholds.
    /// Single source of truth for both analytics and Claude coaching.
    var zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int) {
        let maxHR = Double(maxHeartRate)
        return (
            z2: Int(round(maxHR * 0.69)),
            z3: Int(round(maxHR * 0.79)),
            z4: Int(round(maxHR * 0.85)),
            z5: Int(round(maxHR * 0.92))
        )
    }

    func calculateZoneBreakdown(startDate: Date, endDate: Date, onComplete: @escaping ([String: Double]) -> Void) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            onComplete(["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        var zones: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]

        let bounds = zoneBoundaries

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: 5000,
            sortDescriptors: [sortDescriptor]
        ) { _, results, error in
            if error != nil {
                onComplete(zones)
                return
            }

            guard let samples = results as? [HKQuantitySample] else {
                onComplete(zones)
                return
            }

            for sample in samples {
                let bpm = Int(round(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))))

                let zone: String
                if bpm < bounds.z2 {
                    zone = "Z1"
                } else if bpm < bounds.z3 {
                    zone = "Z2"
                } else if bpm < bounds.z4 {
                    zone = "Z3"
                } else if bpm < bounds.z5 {
                    zone = "Z4"
                } else {
                    zone = "Z5"
                }

                zones[zone, default: 0] += 1
            }

            onComplete(zones)
        }

        healthStore.execute(query)
    }

    func getWorkoutZoneBreakdown(workout: HKWorkout, completion: @escaping ([String: Double]) -> Void) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion([:])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let bounds = zoneBoundaries

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: 5000,
            sortDescriptors: [sortDescriptor]
        ) { _, results, error in
            var zones: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]

            guard let samples = results as? [HKQuantitySample], !samples.isEmpty else {
                completion(zones)
                return
            }

            for sample in samples {
                let bpm = Int(round(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))))
                let zone: String
                if bpm < bounds.z2 { zone = "Z1" }
                else if bpm < bounds.z3 { zone = "Z2" }
                else if bpm < bounds.z4 { zone = "Z3" }
                else if bpm < bounds.z5 { zone = "Z4" }
                else { zone = "Z5" }
                zones[zone, default: 0] += 1
            }

            // Convert counts to percentages
            let total = samples.count
            var percentages: [String: Double] = [:]
            for (zone, count) in zones {
                percentages[zone] = (count / Double(total)) * 100
            }

            completion(percentages)
        }

        healthStore.execute(query)
    }

    func fetchZonesForRecentWorkouts() {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recent = workouts.filter { $0.startDate >= twoWeeksAgo }
        guard !recent.isEmpty else { return }

        // Collect all zone breakdowns before publishing to avoid N separate @Published
        // mutations (each of which triggers a full re-render of every observing view).
        let lock = NSLock()
        var collected: [UUID: [String: Double]] = [:]
        var remaining = recent.count

        for workout in recent {
            getWorkoutZoneBreakdown(workout: workout) { zones in
                lock.lock()
                collected[workout.uuid] = zones
                remaining -= 1
                let done = remaining == 0
                lock.unlock()

                if done {
                    DispatchQueue.main.async {
                        // Single mutation → single re-render
                        self.workoutZones.merge(collected) { _, new in new }
                    }
                }
            }
        }
    }

    // MARK: - Sleep (Morning Check-In v1)

    /// Fetches the previous night's sleep for the morning of `date`.
    ///
    /// Looks at samples whose start falls in the 18-hour window ending at
    /// `date`'s 12:00pm local time — this covers bedtimes from the prior
    /// afternoon through the requested morning.
    ///
    /// v1 scope (§11.1): single signal = sleep duration. Any HealthKit sleep
    /// source (Apple Watch, iPhone, third-party) is accepted; the source
    /// string is captured but the UI treats all sources equivalently.
    ///
    /// Returns nil when no samples are found or HealthKit is unavailable.
    func fetchSleepData(for date: Date) async -> SleepSummary? {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let calendar = Calendar.current
        // Window: noon the day before → noon on `date` (covers the full night).
        let noonOfRequested = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let windowStart = calendar.date(byAdding: .hour, value: -24, to: noonOfRequested) ?? noonOfRequested
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: noonOfRequested, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        return Self.summarizeSleep(samples: samples, nightOf: calendar.startOfDay(for: windowStart))
    }

    /// Pure summarization helper. Exposed for unit tests (see `SleepFetchTests`).
    static func summarizeSleep(samples: [HKCategorySample], nightOf date: Date) -> SleepSummary? {
        guard !samples.isEmpty else { return nil }

        var total = 0
        var inBed = 0
        var deep = 0
        var rem = 0
        var awake = 0
        var sawStages = false

        for s in samples {
            let minutes = Int(s.endDate.timeIntervalSince(s.startDate) / 60.0)
            guard minutes > 0 else { continue }

            // Value uses HKCategoryValueSleepAnalysis. We match on raw values
            // to avoid SDK-deprecation warnings on `.asleep` (iOS <16) vs
            // `.asleepUnspecified` (iOS 16+).
            let raw = s.value
            if raw == HKCategoryValueSleepAnalysis.inBed.rawValue {
                inBed += minutes
            } else if raw == HKCategoryValueSleepAnalysis.awake.rawValue {
                awake += minutes
                sawStages = true
            } else if raw == HKCategoryValueSleepAnalysis.asleepCore.rawValue {
                total += minutes
                sawStages = true
            } else if raw == HKCategoryValueSleepAnalysis.asleepDeep.rawValue {
                total += minutes
                deep += minutes
                sawStages = true
            } else if raw == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                total += minutes
                rem += minutes
                sawStages = true
            } else if raw == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                total += minutes
            }
        }

        // If no explicit in-bed samples, approximate with asleep total so consumers
        // always see a non-zero `timeInBedMinutes` when sleep was recorded.
        if inBed == 0 { inBed = total + awake }
        guard total > 0 || inBed > 0 else { return nil }

        // Pick a representative source name. Prefer the longest sample's source.
        let rawSource = samples.max(by: { $0.endDate.timeIntervalSince($0.startDate) < $1.endDate.timeIntervalSince($1.startDate) })?.sourceRevision.source.name
        let source = (rawSource?.isEmpty == false) ? rawSource! : "Unknown"

        return SleepSummary(
            date: date,
            totalSleepMinutes: total,
            timeInBedMinutes: inBed,
            deepSleepMinutes: sawStages ? deep : nil,
            remSleepMinutes: sawStages ? rem : nil,
            awakeMinutes: sawStages ? awake : nil,
            source: source
        )
    }

    // MARK: - Training Status Helpers

    func fetchHRSamples(for workout: HKWorkout) async -> [HKQuantitySample] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    func fetchHRSamples(from startDate: Date, to endDate: Date) async -> [HKQuantitySample] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    func fetchDistanceSamples(for workout: HKWorkout) async -> [HKQuantitySample] {
        let identifier: HKQuantityTypeIdentifier = workout.workoutActivityType == .cycling
            ? .distanceCycling
            : .distanceWalkingRunning
        guard let distType = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: distType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    struct ActivityRings {
        let activeCalories: Int
        let exerciseMinutes: Int
        let standHours: Int
    }

    func fetchActivityRings(for date: Date = Date()) async -> ActivityRings {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        async let calories = sumQuantity(identifier: .activeEnergyBurned, predicate: predicate, unit: .kilocalorie())
        async let exercise = sumQuantity(identifier: .appleExerciseTime, predicate: predicate, unit: .minute())
        async let stand = countStandHours(start: start, end: end)

        return await ActivityRings(
            activeCalories: Int(calories),
            exerciseMinutes: Int(exercise),
            standHours: stand
        )
    }

    private func sumQuantity(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    private func countStandHours(start: Date, end: Date) async -> Int {
        guard let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let stood = HKCategoryValueAppleStandHour.stood.rawValue
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: standType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                let count = (results as? [HKCategorySample])?.filter { $0.value == stood }.count ?? 0
                continuation.resume(returning: count)
            }
            healthStore.execute(query)
        }
    }

    func fetchHRVSamples(days: Int = 60) async -> [HKQuantitySample] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }
}
