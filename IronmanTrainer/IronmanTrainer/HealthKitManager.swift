import Foundation
import HealthKit

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
        let dobType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        let typesToRead: Set<HKObjectType> = [workoutType, heartRateType, dobType]

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
        let typesToRead: Set<HKObjectType> = [workoutType, heartRateType, dobType]

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

    var restingHeartRate: Int {
        // Estimate resting HR from age. Overridable in future.
        let age = getUserAge()
        if age < 30 { return 60 }
        if age < 40 { return 63 }
        if age < 50 { return 65 }
        return 68
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
            limit: HKObjectQueryNoLimit,
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
            limit: HKObjectQueryNoLimit,
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
}
