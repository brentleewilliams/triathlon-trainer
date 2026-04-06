import Foundation
import HealthKit
import CoreLocation

// MARK: - Onboarding Data Models

struct HealthKitOnboardingProfile {
    var dateOfBirth: Date?
    var biologicalSex: String?          // "male", "female", "other"
    var heightCm: Double?
    var weightKg: Double?
    var restingHR: Int?
    var vo2Max: Double?
    var recentWeeklyVolume: WeeklyTrainingVolume?
    var monthlyTrends: [MonthlyTrainingSummary]
    var recentWorkoutDetails: [WorkoutSummary]  // last 2 weeks individual workouts

    init() {
        self.monthlyTrends = []
        self.recentWorkoutDetails = []
    }
}

struct WeeklyTrainingVolume {
    var avgSwimYardsPerWeek: Double
    var avgBikeHoursPerWeek: Double
    var avgRunMilesPerWeek: Double
    var avgWorkoutsPerWeek: Double
    var periodWeeks: Int  // how many weeks this covers
}

struct MonthlyTrainingSummary {
    var month: String           // "2025-10"
    var swimSessions: Int
    var bikeSessions: Int
    var runSessions: Int
    var totalDurationHours: Double
}

struct WorkoutSummary {
    var date: Date
    var type: String            // "Swimming", "Cycling", "Running"
    var durationMinutes: Double
    var distanceMiles: Double?
    var calories: Double?
}

// MARK: - HealthKit Onboarding Helper

/// Standalone helper that creates its own HKHealthStore for onboarding data pulls.
/// This avoids modifying the existing HealthKitManager while providing expanded data access.
class HealthKitOnboardingHelper {
    private let healthStore = HKHealthStore()

    // MARK: - Authorization

    /// Request read access to all HealthKit types needed for onboarding profile.
    func requestExpandedAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[Onboarding] HealthKit not available on this device")
            return
        }

        var typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKCharacteristicType.characteristicType(forIdentifier: .biologicalSex)!,
            HKQuantityType.quantityType(forIdentifier: .height)!,
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
        ]

        if let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            typesToRead.insert(vo2MaxType)
        }
        typesToRead.insert(HKSeriesType.workoutRoute())

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            print("[Onboarding] HealthKit authorization granted")
        } catch {
            print("[Onboarding] HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Full Profile Fetch

    /// Pulls all available onboarding data from HealthKit in one call.
    func fetchOnboardingProfile() async -> HealthKitOnboardingProfile {
        var profile = HealthKitOnboardingProfile()

        // Characteristics (synchronous)
        profile.dateOfBirth = fetchDateOfBirth()
        profile.biologicalSex = fetchBiologicalSex()

        // Quantity samples (async, run in parallel)
        async let height = fetchMostRecentSample(typeIdentifier: .height)
        async let weight = fetchMostRecentSample(typeIdentifier: .bodyMass)
        async let restingHR = fetchMostRecentSample(typeIdentifier: .restingHeartRate)
        async let vo2Max = fetchMostRecentSample(typeIdentifier: .vo2Max)

        let heightSample = await height
        let weightSample = await weight
        let restingHRSample = await restingHR
        let vo2MaxSample = await vo2Max

        if let sample = heightSample {
            profile.heightCm = sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
        }
        if let sample = weightSample {
            profile.weightKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        }
        if let sample = restingHRSample {
            profile.restingHR = Int(round(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))))
        }
        if let sample = vo2MaxSample {
            let unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))
            profile.vo2Max = sample.quantity.doubleValue(for: unit)
        }

        // Workout history (last 12 months)
        let workouts = await fetchWorkoutHistory(months: 12)

        profile.monthlyTrends = computeMonthlyTrends(workouts: workouts)
        profile.recentWeeklyVolume = computeWeeklyVolume(workouts: workouts, recentMonths: 3)
        profile.recentWorkoutDetails = computeRecentWorkoutDetails(workouts: workouts, weeks: 2)

        return profile
    }

    // MARK: - Characteristic Reads

    private func fetchDateOfBirth() -> Date? {
        do {
            let components = try healthStore.dateOfBirthComponents()
            return Calendar.current.date(from: components)
        } catch {
            print("[Onboarding] Could not read date of birth: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchBiologicalSex() -> String? {
        do {
            let bioSex = try healthStore.biologicalSex()
            switch bioSex.biologicalSex {
            case .male: return "male"
            case .female: return "female"
            case .other: return "other"
            case .notSet: return nil
            @unknown default: return nil
            }
        } catch {
            print("[Onboarding] Could not read biological sex: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Quantity Sample Reads

    private func fetchMostRecentSample(typeIdentifier: HKQuantityTypeIdentifier) async -> HKQuantitySample? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    print("[Onboarding] Error fetching \(typeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: results?.first as? HKQuantitySample)
            }
            self.healthStore.execute(query)
        }
    }

    // MARK: - Workout History

    private func fetchWorkoutHistory(months: Int) async -> [HKWorkout] {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .month, value: -months, to: Date()) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    print("[Onboarding] Error fetching workout history: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            self.healthStore.execute(query)
        }
    }

    // MARK: - Computed Aggregations

    private func workoutTypeName(_ activityType: HKWorkoutActivityType) -> String? {
        switch activityType {
        case .swimming: return "Swimming"
        case .cycling: return "Cycling"
        case .running: return "Running"
        default: return nil
        }
    }

    private func computeMonthlyTrends(workouts: [HKWorkout]) -> [MonthlyTrainingSummary] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        dateFormatter.timeZone = TimeZone.current

        var grouped: [String: (swim: Int, bike: Int, run: Int, durationSec: Double)] = [:]

        for workout in workouts {
            let monthKey = dateFormatter.string(from: workout.startDate)
            var entry = grouped[monthKey] ?? (swim: 0, bike: 0, run: 0, durationSec: 0)

            switch workout.workoutActivityType {
            case .swimming: entry.swim += 1
            case .cycling: entry.bike += 1
            case .running: entry.run += 1
            default: continue
            }

            entry.durationSec += workout.duration
            grouped[monthKey] = entry
        }

        return grouped.map { key, value in
            MonthlyTrainingSummary(
                month: key,
                swimSessions: value.swim,
                bikeSessions: value.bike,
                runSessions: value.run,
                totalDurationHours: value.durationSec / 3600.0
            )
        }.sorted { $0.month < $1.month }
    }

    private func computeWeeklyVolume(workouts: [HKWorkout], recentMonths: Int) -> WeeklyTrainingVolume? {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .month, value: -recentMonths, to: Date()) else {
            return nil
        }

        let recentWorkouts = workouts.filter { $0.startDate >= cutoff }
        guard !recentWorkouts.isEmpty else { return nil }

        let daysBetween = calendar.dateComponents([.day], from: cutoff, to: Date()).day ?? 1
        let periodWeeks = max(1, daysBetween / 7)

        var totalSwimYards: Double = 0
        var totalBikeSeconds: Double = 0
        var totalRunMeters: Double = 0
        var workoutCount = 0

        for workout in recentWorkouts {
            let distanceMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0

            switch workout.workoutActivityType {
            case .swimming:
                // Convert meters to yards
                totalSwimYards += distanceMeters * 1.09361
                workoutCount += 1
            case .cycling:
                totalBikeSeconds += workout.duration
                workoutCount += 1
            case .running:
                totalRunMeters += distanceMeters
                workoutCount += 1
            default:
                break
            }
        }

        let weeks = Double(periodWeeks)
        return WeeklyTrainingVolume(
            avgSwimYardsPerWeek: totalSwimYards / weeks,
            avgBikeHoursPerWeek: (totalBikeSeconds / 3600.0) / weeks,
            avgRunMilesPerWeek: (totalRunMeters / 1609.34) / weeks,
            avgWorkoutsPerWeek: Double(workoutCount) / weeks,
            periodWeeks: periodWeeks
        )
    }

    private func computeRecentWorkoutDetails(workouts: [HKWorkout], weeks: Int) -> [WorkoutSummary] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .weekOfYear, value: -weeks, to: Date()) else {
            return []
        }

        return workouts
            .filter { $0.startDate >= cutoff }
            .compactMap { workout -> WorkoutSummary? in
                guard let typeName = workoutTypeName(workout.workoutActivityType) else {
                    return nil
                }

                let distanceMiles: Double?
                if let distance = workout.totalDistance {
                    distanceMiles = distance.doubleValue(for: .mile())
                } else {
                    distanceMiles = nil
                }

                let calories: Double?
                if let energy = workout.totalEnergyBurned {
                    calories = energy.doubleValue(for: .kilocalorie())
                } else {
                    calories = nil
                }

                return WorkoutSummary(
                    date: workout.startDate,
                    type: typeName,
                    durationMinutes: workout.duration / 60.0,
                    distanceMiles: distanceMiles,
                    calories: calories
                )
            }
            .sorted { $0.date > $1.date }
    }
    // MARK: - Location Inference

    /// Infer the user's home zip code from workout route data.
    /// Clusters nearby workout start locations and picks the largest cluster,
    /// so vacation/travel workouts don't skew the result.
    func inferHomeZipCode() async -> String? {
        // Prioritize recent workouts (last 2 months), fall back to 6 months if needed
        var workouts = await fetchWorkoutHistory(months: 2)
        if workouts.count < 5 {
            workouts = await fetchWorkoutHistory(months: 6)
        }
        guard !workouts.isEmpty else { return nil }

        // Collect starting locations from workout routes
        var locations: [CLLocation] = []

        for workout in workouts.prefix(30) {
            if let startLocation = await getWorkoutStartLocation(workout) {
                locations.append(startLocation)
            }
        }

        guard !locations.isEmpty else { return nil }

        // Cluster locations within ~15 miles of each other
        let clusterRadiusMeters: Double = 25_000
        var clusters: [[CLLocation]] = []

        for location in locations {
            var addedToCluster = false
            for i in clusters.indices {
                // Check if this location is near the first point in an existing cluster
                if location.distance(from: clusters[i][0]) < clusterRadiusMeters {
                    clusters[i].append(location)
                    addedToCluster = true
                    break
                }
            }
            if !addedToCluster {
                clusters.append([location])
            }
        }

        // Pick the largest cluster (most workouts = likely home)
        guard let homeCluster = clusters.max(by: { $0.count < $1.count }),
              homeCluster.count >= 2 else {
            // Need at least 2 workouts in a cluster to be confident
            return nil
        }

        // Average the cluster locations for a stable center point
        let avgLat = homeCluster.map(\.coordinate.latitude).reduce(0, +) / Double(homeCluster.count)
        let avgLon = homeCluster.map(\.coordinate.longitude).reduce(0, +) / Double(homeCluster.count)
        let centerLocation = CLLocation(latitude: avgLat, longitude: avgLon)

        // Reverse geocode to get city/state/zip
        return await reverseGeocodeToZip(location: centerLocation)
    }

    private func getWorkoutStartLocation(_ workout: HKWorkout) async -> CLLocation? {
        return await withCheckedContinuation { continuation in
            let routeType = HKSeriesType.workoutRoute()
            let routeQuery = HKSampleQuery(
                sampleType: routeType,
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: 1,
                sortDescriptors: nil
            ) { [weak self] _, results, _ in
                guard let route = results?.first as? HKWorkoutRoute,
                      let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                // Get first location point from route (handler fires multiple times)
                var resumed = false
                let locationQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
                    guard !resumed else { return }
                    if let firstLocation = locations?.first {
                        resumed = true
                        continuation.resume(returning: firstLocation)
                    } else if done {
                        resumed = true
                        continuation.resume(returning: nil)
                    }
                }
                self.healthStore.execute(locationQuery)
            }
            self.healthStore.execute(routeQuery)
        }
    }

    private func reverseGeocodeToZip(location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                // Return "City, ST ZIP" or just zip
                var parts: [String] = []
                if let city = placemark.locality { parts.append(city) }
                if let state = placemark.administrativeArea { parts.append(state) }
                if let zip = placemark.postalCode { parts.append(zip) }
                return parts.joined(separator: ", ")
            }
        } catch {
            print("[Onboarding] Reverse geocode failed: \(error.localizedDescription)")
        }
        return nil
    }
}

// MARK: - Format for Claude

extension HealthKitOnboardingProfile {
    /// Formats the onboarding profile as a readable string for Claude context.
    func formatForClaude() -> String {
        var lines: [String] = []

        lines.append("## Athlete HealthKit Profile")
        lines.append("")

        // Demographics
        lines.append("### Demographics")
        if let dob = dateOfBirth {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
            lines.append("- Date of Birth: \(formatter.string(from: dob)) (age \(age))")
        }
        if let sex = biologicalSex {
            lines.append("- Biological Sex: \(sex)")
        }
        if let h = heightCm {
            let feet = Int(h / 2.54) / 12
            let inches = Int(h / 2.54) % 12
            lines.append("- Height: \(String(format: "%.1f", h)) cm (\(feet)'\(inches)\")")
        }
        if let w = weightKg {
            let lbs = w * 2.20462
            lines.append("- Weight: \(String(format: "%.1f", w)) kg (\(String(format: "%.0f", lbs)) lbs)")
        }
        lines.append("")

        // Fitness markers
        lines.append("### Fitness Markers")
        if let rhr = restingHR {
            lines.append("- Resting Heart Rate: \(rhr) bpm")
        }
        if let vo2 = vo2Max {
            lines.append("- VO2 Max: \(String(format: "%.1f", vo2)) mL/kg/min")
        }
        if restingHR == nil && vo2Max == nil {
            lines.append("- No fitness marker data available")
        }
        lines.append("")

        // Monthly trends
        if !monthlyTrends.isEmpty {
            lines.append("### Monthly Training Trends")
            for trend in monthlyTrends {
                let totalSessions = trend.swimSessions + trend.bikeSessions + trend.runSessions
                lines.append("- \(trend.month): \(totalSessions) sessions (Swim: \(trend.swimSessions), Bike: \(trend.bikeSessions), Run: \(trend.runSessions)) | \(String(format: "%.1f", trend.totalDurationHours)) hrs total")
            }
            lines.append("")
        }

        // Weekly volume averages
        if let vol = recentWeeklyVolume {
            lines.append("### Weekly Averages (last \(vol.periodWeeks) weeks)")
            lines.append("- Swim: \(String(format: "%.0f", vol.avgSwimYardsPerWeek)) yards/week")
            lines.append("- Bike: \(String(format: "%.1f", vol.avgBikeHoursPerWeek)) hours/week")
            lines.append("- Run: \(String(format: "%.1f", vol.avgRunMilesPerWeek)) miles/week")
            lines.append("- Workouts: \(String(format: "%.1f", vol.avgWorkoutsPerWeek))/week")
            lines.append("")
        }

        // Recent workout details
        if !recentWorkoutDetails.isEmpty {
            lines.append("### Recent Workouts (last 2 weeks)")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            dateFormatter.timeZone = TimeZone.current

            for workout in recentWorkoutDetails {
                var detail = "- \(dateFormatter.string(from: workout.date)) \(workout.type): \(String(format: "%.0f", workout.durationMinutes)) min"
                if let dist = workout.distanceMiles {
                    detail += ", \(String(format: "%.1f", dist)) mi"
                }
                if let cal = workout.calories {
                    detail += ", \(String(format: "%.0f", cal)) cal"
                }
                lines.append(detail)
            }
            lines.append("")
        }

        // Handle case with no data
        if dateOfBirth == nil && biologicalSex == nil && heightCm == nil && weightKg == nil
            && restingHR == nil && vo2Max == nil && monthlyTrends.isEmpty
            && recentWeeklyVolume == nil && recentWorkoutDetails.isEmpty {
            lines.append("No HealthKit data available. The athlete may not have granted permissions yet.")
        }

        return lines.joined(separator: "\n")
    }
}
