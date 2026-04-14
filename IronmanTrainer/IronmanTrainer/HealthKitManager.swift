import Foundation
import HealthKit

// MARK: - Readiness Metrics Snapshot
/// Captures the health signals used to compute morning readiness.
/// All fields are optional — missing data is acceptable and treated as "unknown".
struct ReadinessSnapshot: Codable, Equatable {
    var sleepHours: Double?          // Last night's asleep hours (in-bed minus awake)
    var hrvMs: Double?               // Most recent HRV SDNN (ms)
    var hrvBaselineMs: Double?       // 7-day average HRV (ms)
    var restingHR: Int?              // Most recent resting HR (bpm)
    var restingHRBaseline: Int?      // 7-day average resting HR (bpm)
    var capturedAt: Date = Date()
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

    /// Readiness-related types for authorization & queries.
    private var readinessTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { set.insert(hrv) }
        if let rhr = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { set.insert(rhr) }
        return set
    }

    override init() {
        super.init()
        // Don't check authorization on init — it can trigger system prompts
        // before the user reaches the onboarding HK screen.
        // checkAuthorization() is called explicitly after onboarding completes.
    }

    func checkAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            syncError = "HealthKit not available"
            return
        }

        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let dobType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        var typesToRead: Set<HKObjectType> = [workoutType, heartRateType, dobType]
        typesToRead.formUnion(readinessTypes)

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
        let dobType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        var typesToRead: Set<HKObjectType> = [workoutType, heartRateType, dobType]
        typesToRead.formUnion(readinessTypes)

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

                zones[zone] = zones[zone]! + 1
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
                zones[zone] = zones[zone]! + 1
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
        for workout in recent {
            getWorkoutZoneBreakdown(workout: workout) { zones in
                DispatchQueue.main.async {
                    self.workoutZones[workout.uuid] = zones
                }
            }
        }
    }

    // MARK: - Readiness Queries (sleep, HRV, resting HR)

    /// Fetches last night's sleep duration in hours.
    /// Uses "asleep*" stages (core, deep, REM, unspecified) across the window ending at wake time.
    /// Returns nil if no sleep samples are available.
    func fetchLastNightSleepHours(reference: Date = Date()) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }

        // Window: 6pm yesterday → now (covers typical sleep period)
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: reference)
        guard let windowStart = calendar.date(byAdding: .hour, value: -6, to: calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: reference, options: [])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                guard let samples = results as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let asleepValues: Set<Int> = {
                    var v: Set<Int> = [HKCategoryValueSleepAnalysis.asleep.rawValue]
                    if #available(iOS 16.0, *) {
                        v.insert(HKCategoryValueSleepAnalysis.asleepCore.rawValue)
                        v.insert(HKCategoryValueSleepAnalysis.asleepDeep.rawValue)
                        v.insert(HKCategoryValueSleepAnalysis.asleepREM.rawValue)
                        v.insert(HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
                    }
                    return v
                }()

                let asleepSeconds = samples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

                continuation.resume(returning: asleepSeconds > 0 ? asleepSeconds / 3600.0 : nil)
            }
            healthStore.execute(query)
        }
    }

    /// Most recent HRV SDNN sample value in milliseconds.
    func fetchLatestHRV(reference: Date = Date()) async -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let startDate = Calendar.current.date(byAdding: .day, value: -2, to: reference) ?? reference
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: reference, options: [])

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, results, _ in
                guard let sample = (results as? [HKQuantitySample])?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: .secondUnit(with: .milli)))
            }
            healthStore.execute(query)
        }
    }

    /// Average HRV SDNN over the last 7 days (excluding the most recent 24h for baseline contrast).
    func fetchHRVBaseline(reference: Date = Date()) async -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .day, value: -1, to: reference),
              let start = cal.date(byAdding: .day, value: -8, to: reference) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrvType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                let avg = stats?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: avg)
            }
            healthStore.execute(query)
        }
    }

    /// Most recent resting heart rate in bpm.
    func fetchLatestRestingHR(reference: Date = Date()) async -> Int? {
        guard let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let startDate = Calendar.current.date(byAdding: .day, value: -3, to: reference) ?? reference
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: reference, options: [])

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: rhrType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, results, _ in
                guard let sample = (results as? [HKQuantitySample])?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: Int(round(sample.quantity.doubleValue(for: bpmUnit))))
            }
            healthStore.execute(query)
        }
    }

    /// Average resting HR over the last 7 days (excluding most recent 24h).
    func fetchRestingHRBaseline(reference: Date = Date()) async -> Int? {
        guard let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .day, value: -1, to: reference),
              let start = cal.date(byAdding: .day, value: -8, to: reference) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: rhrType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                guard let avg = stats?.averageQuantity()?.doubleValue(for: bpmUnit) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Int(round(avg)))
            }
            healthStore.execute(query)
        }
    }

    /// Fetches a full readiness snapshot by gathering all signals concurrently.
    func fetchReadinessSnapshot(reference: Date = Date()) async -> ReadinessSnapshot {
        async let sleep = fetchLastNightSleepHours(reference: reference)
        async let hrv = fetchLatestHRV(reference: reference)
        async let hrvBase = fetchHRVBaseline(reference: reference)
        async let rhr = fetchLatestRestingHR(reference: reference)
        async let rhrBase = fetchRestingHRBaseline(reference: reference)

        return ReadinessSnapshot(
            sleepHours: await sleep,
            hrvMs: await hrv,
            hrvBaselineMs: await hrvBase,
            restingHR: await rhr,
            restingHRBaseline: await rhrBase,
            capturedAt: reference
        )
    }
}
