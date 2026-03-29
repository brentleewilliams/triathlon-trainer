import HealthKit
import Foundation

class HealthKitManager: NSObject, ObservableObject {
    static let shared = HealthKitManager()

    @Published var isAuthorized = false
    @Published var isSyncing = false
    @Published var syncError: String?
    @Published var workouts: [HKWorkout] = []

    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        checkAuthorization()
    }

    func checkAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            syncError = "HealthKit not available on this device"
            return
        }

        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let typesToRead: Set<HKObjectType> = [workoutType, heartRateType]

        healthStore.getRequestStatusForAuthorization(toShare: [], read: typesToRead) { status, error in
            DispatchQueue.main.async {
                self.isAuthorized = (status == .unnecessary)
            }
        }
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run {
                syncError = "HealthKit not available on this device"
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
        print("DEBUG: syncWorkouts called - isAuthorized: \(isAuthorized)")

        await MainActor.run {
            isSyncing = true
            syncError = nil
        }

        defer {
            DispatchQueue.main.async {
                self.isSyncing = false
            }
        }

        // Request authorization if not already authorized
        if !isAuthorized {
            print("DEBUG: Not authorized, requesting authorization")
            await requestAuthorization()
            if !isAuthorized {
                print("DEBUG: Authorization request failed")
                await MainActor.run {
                    syncError = "HealthKit permission denied"
                }
                return
            }
        }

        let workoutType = HKObjectType.workoutType()
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: nil,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, results, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("DEBUG: HealthKit query error: \(error.localizedDescription)")
                    self.syncError = "Failed to fetch workouts: \(error.localizedDescription)"
                    return
                }

                if let workouts = results as? [HKWorkout] {
                    print("DEBUG: HealthKit returned \(workouts.count) workouts")
                    for workout in workouts {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMM d, yyyy HH:mm"
                        print("DEBUG:   - \(workout.workoutActivityType.name) on \(formatter.string(from: workout.startDate)) (\(Int(workout.duration)) sec)")
                    }
                    self.workouts = workouts
                    self.syncError = nil
                } else {
                    print("DEBUG: No workouts found in results")
                }
            }
        }

        healthStore.execute(query)
    }
}
