import SwiftUI
import HealthKit

// MARK: - Analytics ViewModel

@MainActor
class AnalyticsViewModel: ObservableObject {
    @Published var cachedVolume: (swim: Double, bike: Double, run: Double) = (0, 0, 0)
    @Published var cachedPlannedVolume: (swim: Double, bike: Double, run: Double) = (0, 0, 0)
    @Published var cachedZonePercentages: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]

    func recalculate(week: TrainingWeek?, hkWorkouts: [HKWorkout]) {
        guard let week else {
            cachedVolume = (0, 0, 0)
            cachedPlannedVolume = (0, 0, 0)
            cachedZonePercentages = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
            return
        }

        // Actual volume from HealthKit (single pass)
        let calendar = Calendar.current
        let weekStart = calendar.startOfDay(for: week.startDate)
        let weekEnd = calendar.startOfDay(for: week.endDate)
        var swimH: Double = 0, bikeH: Double = 0, runH: Double = 0

        for hkWorkout in hkWorkouts {
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            guard workoutDate >= weekStart && workoutDate <= weekEnd else { continue }
            let hours = hkWorkout.duration / 3600
            switch hkWorkout.workoutActivityType {
            case .swimming: swimH += hours
            case .cycling: bikeH += hours
            case .running: runH += hours
            default: break
            }
        }
        cachedVolume = (swimH, bikeH, runH)

        // Planned volume + zone distribution (single pass over workouts)
        var pSwim: Double = 0, pBike: Double = 0, pRun: Double = 0
        var zoneHours: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]

        for workout in week.workouts {
            if workout.type.contains("Rest") { continue }
            let hours = parseDurationHours(workout.duration)

            // Planned volume
            if workout.type.contains("\u{1F3CA}") {
                pSwim += hours
            } else if workout.type.contains("\u{1F6B4}") && !workout.type.contains("\u{1F3C3}") {
                pBike += hours
            } else if workout.type.contains("\u{1F3C3}") && !workout.type.contains("\u{1F6B4}") {
                pRun += hours
            } else if workout.type.contains("\u{1F6B4}") && workout.type.contains("\u{1F3C3}") {
                pBike += hours * 0.6
                pRun += hours * 0.4
            }

            // Zone distribution
            let zones = parseZone(workout.zone)
            for z in zones {
                zoneHours[z, default: 0] += hours / Double(zones.count)
            }
        }
        cachedPlannedVolume = (pSwim, pBike, pRun)

        // Zone percentages
        let total = zoneHours.values.reduce(0, +)
        if total > 0 {
            cachedZonePercentages = zoneHours.mapValues { ($0 / total) * 100 }
        } else {
            cachedZonePercentages = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
        }
    }

    /// Parse a duration string to hours (Double). Used for planned volume calculations.
    func parseDurationHours(_ duration: String) -> Double {
        let trimmed = duration.trimmingCharacters(in: .whitespaces)

        if trimmed.contains("min") {
            let value = trimmed.replacingOccurrences(of: "min", with: "").trimmingCharacters(in: .whitespaces)
            return (Double(value) ?? 0) / 60
        }

        if trimmed.contains(":") {
            let components = trimmed.split(separator: ":")
            if components.count == 2,
               let hours = Double(components[0]),
               let minutes = Double(components[1]) {
                return hours + (minutes / 60)
            }
        }

        if trimmed.contains("yd") {
            let value = trimmed.replacingOccurrences(of: "yd", with: "").trimmingCharacters(in: .whitespaces)
            let cleanValue = value.replacingOccurrences(of: ",", with: "")
            if let yardage = Double(cleanValue) {
                return yardage / 1800
            }
        }

        if trimmed.lowercased() == "race" {
            return 3.0
        }

        return 0
    }

    func parseZone(_ zone: String) -> [String] {
        let trimmed = zone.trimmingCharacters(in: .whitespaces)

        if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-")
            if parts.count == 2 {
                if let firstNum = parts[0].last, let secondNum = parts[1].last {
                    let first = Int(String(firstNum)) ?? 2
                    let second = Int(String(secondNum)) ?? 2
                    return Array(first...second).map { "Z\($0)" }
                }
            }
        }

        return [trimmed]
    }
}

// MARK: - Analytics View
struct AnalyticsView: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager
    @StateObject private var analyticsVM = AnalyticsViewModel()
    @State private var selectedWeek: Int = 1
    @State private var hasAppearedOnce = false
    @State private var actualZoneData: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
    @State private var actualZonePercentages: [String: Double] = [:]
    @State private var isLoadingZones = false

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    func recalculateAnalytics() {
        analyticsVM.recalculate(week: currentWeek, hkWorkouts: healthKit.workouts)
    }

    func complianceTrendData() -> [(week: Int, percent: Double)] {
        var results: [(week: Int, percent: Double)] = []
        let currentWeekNum = trainingPlan.currentWeekNumber
        let startWeek = max(1, currentWeekNum - 5)
        let endWeek = min(currentWeekNum, trainingPlan.weeks.count)

        for weekNum in startWeek...endWeek {
            guard let week = trainingPlan.getWeek(weekNum) else { continue }
            if let pct = calculateWeekCompliance(week: week, hkWorkouts: healthKit.workouts) {
                results.append((week: weekNum, percent: pct))
            }
        }
        return results
    }

    func complianceBarColor(_ percent: Double) -> Color {
        if percent >= 80 { return .green }
        if percent >= 50 { return .yellow }
        return .red
    }

    func fetchActualZoneData() {
        guard let week = currentWeek else { return }
        isLoadingZones = true

        HealthKitManager.shared.calculateZoneBreakdown(
            startDate: week.startDate,
            endDate: week.endDate
        ) { zoneData in
            DispatchQueue.main.async {
                self.actualZoneData = zoneData
                // Convert zone counts to percentages
                let totalSamples = zoneData.values.reduce(0, +)
                if totalSamples > 0 {
                    self.actualZonePercentages = zoneData.mapValues { ($0 / totalSamples) * 100 }
                } else {
                    self.actualZonePercentages = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
                }
                self.isLoadingZones = false
            }
        }
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

                    let hasAnyVolume = analyticsVM.cachedPlannedVolume.swim > 0 || analyticsVM.cachedPlannedVolume.bike > 0 || analyticsVM.cachedPlannedVolume.run > 0
                    if hasAnyVolume {
                        HStack(spacing: 20) {
                            if analyticsVM.cachedPlannedVolume.swim > 0 {
                                VolumeCard(label: "Swim", hours: analyticsVM.cachedVolume.swim, planned: analyticsVM.cachedPlannedVolume.swim, color: .blue)
                            }
                            if analyticsVM.cachedPlannedVolume.bike > 0 {
                                VolumeCard(label: "Bike", hours: analyticsVM.cachedVolume.bike, planned: analyticsVM.cachedPlannedVolume.bike, color: .orange)
                            }
                            if analyticsVM.cachedPlannedVolume.run > 0 {
                                VolumeCard(label: "Run", hours: analyticsVM.cachedVolume.run, planned: analyticsVM.cachedPlannedVolume.run, color: .green)
                            }
                        }
                    } else {
                        Text("Rest Week")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Zone Distribution
                VStack(spacing: 12) {
                    Text("Zone Distribution (Week \(selectedWeek))")
                        .font(.headline)

                    if isLoadingZones {
                        HStack {
                            ProgressView()
                            Text("Loading zone data...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else {
                        // Legend
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(width: 8, height: 8)
                                Text("Planned")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.5))
                                    .frame(width: 8, height: 8)
                                Text("Actual")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.bottom, 4)

                        HStack(spacing: 20) {
                            ZoneBar(zone: "Z1", plannedPercent: analyticsVM.cachedZonePercentages["Z1"] ?? 0, actualPercent: actualZonePercentages["Z1"] ?? 0, color: .gray)
                            ZoneBar(zone: "Z2", plannedPercent: analyticsVM.cachedZonePercentages["Z2"] ?? 0, actualPercent: actualZonePercentages["Z2"] ?? 0, color: .green)
                            ZoneBar(zone: "Z3", plannedPercent: analyticsVM.cachedZonePercentages["Z3"] ?? 0, actualPercent: actualZonePercentages["Z3"] ?? 0, color: .yellow)
                            ZoneBar(zone: "Z4", plannedPercent: analyticsVM.cachedZonePercentages["Z4"] ?? 0, actualPercent: actualZonePercentages["Z4"] ?? 0, color: .orange)
                            ZoneBar(zone: "Z5", plannedPercent: analyticsVM.cachedZonePercentages["Z5"] ?? 0, actualPercent: actualZonePercentages["Z5"] ?? 0, color: .red)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Weekly Compliance Trend
                VStack(spacing: 12) {
                    Text("Weekly Compliance Trend")
                        .font(.headline)

                    let trendData = complianceTrendData()
                    if trendData.isEmpty {
                        Text("No compliance data yet")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(trendData, id: \.week) { entry in
                                VStack(spacing: 4) {
                                    Text("\(Int(entry.percent))%")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)

                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(complianceBarColor(entry.percent))
                                        .frame(height: max(4, CGFloat(entry.percent) * 0.8))

                                    Text("W\(entry.week)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 100)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < -50 && selectedWeek < trainingPlan.weeks.count {
                            withAnimation { selectedWeek += 1 }
                        } else if value.translation.width > 50 && selectedWeek > 1 {
                            withAnimation { selectedWeek -= 1 }
                        }
                    }
            )
            .onAppear {
                if !hasAppearedOnce {
                    selectedWeek = trainingPlan.currentWeekNumber
                    hasAppearedOnce = true
                }
                recalculateAnalytics()
                fetchActualZoneData()
            }
            .onChange(of: selectedWeek) { _, _ in
                recalculateAnalytics()
                fetchActualZoneData()
            }
        }
    }
}

struct VolumeCard: View {
    let label: String
    let hours: Double
    let planned: Double
    let color: Color

    var deviationColor: Color {
        guard planned > 0 else { return color }
        let deviation = abs(hours - planned) / planned
        if deviation <= 0.20 { return .green }
        if deviation <= 0.50 { return .yellow }
        return .red
    }

    var completionFraction: Double {
        guard planned > 0 else { return 0 }
        return min(hours / planned, 1.5)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)

            Text("\(String(format: "%.1f", hours))h")
                .font(.headline)
                .foregroundColor(hours > 0 ? deviationColor : color)

            Text("plan: \(String(format: "%.1f", planned))h")
                .font(.caption2)
                .foregroundColor(.gray)

            // Compliance progress bar
            if planned > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray4))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(deviationColor)
                            .frame(width: geo.size.width * min(completionFraction, 1.0), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ZoneBar: View {
    let zone: String
    let plannedPercent: Double
    let actualPercent: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(zone)
                .font(.caption)
                .fontWeight(.semibold)

            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Planned zone bar (solid color)
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(color)
                            .frame(height: geometry.size.height * (plannedPercent / 100))
                    }

                    // Actual zone bar overlay (semi-transparent, darker)
                    if actualPercent > 0 {
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(color.opacity(0.5))
                                .frame(height: geometry.size.height * (actualPercent / 100))
                        }
                    }
                }
            }
            .frame(height: 80)

            VStack(spacing: 2) {
                Text("\(Int(plannedPercent))%")
                    .font(.caption2)
                if actualPercent > 0 {
                    Text("\(Int(actualPercent))%")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - Workout Drop Delegate
struct WorkoutDropDelegate: DropDelegate {
    let targetDay: String
    let selectedWeek: Int
    let trainingPlan: TrainingPlanManager
    let getDraggedFromDay: () -> String?
    let isCompleted: (String) -> Bool
    let clearDragState: () -> Void

    func dropEntered(info: DropInfo) {
        if let from = getDraggedFromDay() {
            print("[DROP] Entered target day: \(targetDay) from: \(from)")
        }
    }

    func dropExited(info: DropInfo) {
        print("[DROP] Exited target day: \(targetDay)")
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private func isDayInPast(_ day: String) -> Bool {
        guard let week = trainingPlan.getWeek(selectedWeek) else { return false }
        let offset = Self.dayOrder.firstIndex(of: day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: week.startDate) ?? week.startDate
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedFromDay = getDraggedFromDay() else {
            print("[DROP] performDrop: No draggedFromDay")
            return false
        }

        print("[DROP] performDrop: from=\(draggedFromDay) to=\(targetDay) week=\(selectedWeek)")

        // Block swaps involving past days
        guard !isDayInPast(draggedFromDay) && !isDayInPast(targetDay) else {
            print("[DROP] Blocked: cannot move workouts for past days")
            clearDragState()
            return false
        }

        guard draggedFromDay != targetDay else {
            print("[DROP] Same day, clearing state")
            clearDragState()
            return false
        }

        // Swap workouts in the plan
        var updatedWeeks = trainingPlan.weeks
        if let weekIdx = updatedWeeks.firstIndex(where: { $0.weekNumber == selectedWeek }) {
            var newWorkouts = updatedWeeks[weekIdx].workouts

            // Count workouts for each day (some days have multiple)
            let fromDayWorkouts = newWorkouts.filter { $0.day == draggedFromDay }
            let toDayWorkouts = newWorkouts.filter { $0.day == targetDay }

            guard !fromDayWorkouts.isEmpty && !toDayWorkouts.isEmpty else {
                print("[DROP] One of the days has no workouts")
                return false
            }

            print("[DROP] Swapping \(fromDayWorkouts.count) workout(s) from \(draggedFromDay) with \(toDayWorkouts.count) workout(s) from \(targetDay)")

            // Swap days: change all draggedFromDay to targetDay and vice versa
            newWorkouts = newWorkouts.map { workout in
                if workout.day == draggedFromDay {
                    // Change draggedFromDay workouts to targetDay
                    return DayWorkout(day: targetDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget)
                } else if workout.day == targetDay {
                    // Change targetDay workouts to draggedFromDay
                    return DayWorkout(day: draggedFromDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget)
                } else {
                    return workout
                }
            }

            // Create new TrainingWeek with updated workouts
            updatedWeeks[weekIdx] = TrainingWeek(
                weekNumber: updatedWeeks[weekIdx].weekNumber,
                phase: updatedWeeks[weekIdx].phase,
                startDate: updatedWeeks[weekIdx].startDate,
                endDate: updatedWeeks[weekIdx].endDate,
                workouts: newWorkouts
            )

            let workoutTypes = fromDayWorkouts.map { $0.type }.joined(separator: ", ")

            print("[DROP] Applying rescheduled plan: [\(workoutTypes)]")

            // Update plan
            trainingPlan.applyRescheduledPlan(
                updatedWeeks,
                source: "drag",
                description: "Swapped \(draggedFromDay) and \(targetDay)"
            )

            // Clear drag state immediately
            clearDragState()
            print("[DROP] Drop completed successfully")
            return true
        } else {
            print("[DROP] Could not find week with number \(selectedWeek)")
            return false
        }
    }
}
