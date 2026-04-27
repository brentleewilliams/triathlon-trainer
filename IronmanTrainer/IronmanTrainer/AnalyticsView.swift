import SwiftUI
import HealthKit

// MARK: - Bonus Volume Formatting

/// Format total bonus hours with "h" / "min" granularity based on magnitude.
/// Short bonus sessions (<1h) render as minutes to avoid "0.3h" rounding.
fileprivate func formatBonusHours(_ hours: Double) -> String {
    if hours >= 1 {
        return String(format: "%.1fh", hours)
    } else {
        return "\(Int(round(hours * 60)))min"
    }
}

/// Render a per-discipline breakdown of bonus activity, omitting zero buckets.
/// E.g. `(0, 0.5, 0, 0.75)` → `["Bike 30min", "Other 45min"]`.
fileprivate func bonusBreakdown(_ u: (swim: Double, bike: Double, run: Double, other: Double)) -> [String] {
    var parts: [String] = []
    if u.swim > 0 { parts.append("Swim \(formatBonusHours(u.swim))") }
    if u.bike > 0 { parts.append("Bike \(formatBonusHours(u.bike))") }
    if u.run > 0 { parts.append("Run \(formatBonusHours(u.run))") }
    if u.other > 0 { parts.append("Other \(formatBonusHours(u.other))") }
    return parts
}

// MARK: - Analytics ViewModel

@MainActor
class AnalyticsViewModel: ObservableObject {
    @Published var cachedVolume: (swim: Double, bike: Double, run: Double) = (0, 0, 0)
    @Published var cachedPlannedVolume: (swim: Double, bike: Double, run: Double) = (0, 0, 0)
    @Published var cachedZonePercentages: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
    /// Off-plan volume for the week, split by discipline. "other" captures types we
    /// don't chart (strength, hike, yoga, etc). Used by the Volume Summary footer
    /// to surface bonus activity the user completed outside their plan.
    @Published var cachedUnplannedVolume: (swim: Double, bike: Double, run: Double, other: Double) = (0, 0, 0, 0)
    /// Compliance trend for the last 6 weeks — cached so body never recomputes it.
    @Published var cachedComplianceTrend: [(week: Int, percent: Double)] = []

    func recalculate(week: TrainingWeek?, hkWorkouts: [HKWorkout],
                     allWeeks: [TrainingWeek] = [], currentWeekNum: Int = 0) {
        guard let week else {
            cachedVolume = (0, 0, 0)
            cachedPlannedVolume = (0, 0, 0)
            cachedZonePercentages = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
            cachedUnplannedVolume = (0, 0, 0, 0)
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

        // Off-plan volume: per-day, find HK workouts that don't match any
        // planned workout for that weekday. Uses the shared helper so the
        // split stays consistent with DayDetailView's "Other Activity" section.
        var uSwim: Double = 0, uBike: Double = 0, uRun: Double = 0, uOther: Double = 0
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for (offset, abbrev) in dayOrder.enumerated() {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let dayPlanned = week.workouts.filter { $0.day == abbrev }
            let unplanned = findUnplannedWorkouts(on: dayDate, plannedWorkouts: dayPlanned, hkWorkouts: hkWorkouts)
            for hk in unplanned {
                let hours = hk.duration / 3600
                switch hk.workoutActivityType {
                case .swimming: uSwim += hours
                case .cycling: uBike += hours
                case .running: uRun += hours
                default: uOther += hours
                }
            }
        }
        cachedUnplannedVolume = (uSwim, uBike, uRun, uOther)

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

        // Compliance trend (last 6 weeks) — computed here so body never triggers this scan
        if currentWeekNum > 0 && !allWeeks.isEmpty {
            let startWeek = max(1, currentWeekNum - 5)
            let endWeek = min(currentWeekNum, allWeeks.count)
            var trend: [(week: Int, percent: Double)] = []
            for weekNum in startWeek...endWeek {
                guard weekNum >= 1, weekNum <= allWeeks.count else { continue }
                let w = allWeeks[weekNum - 1]
                if let pct = calculateWeekCompliance(week: w, hkWorkouts: hkWorkouts) {
                    trend.append((week: weekNum, percent: pct))
                }
            }
            cachedComplianceTrend = trend
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
    @EnvironmentObject var trainingStatusService: TrainingStatusService
    @StateObject private var analyticsVM = AnalyticsViewModel()
    @State private var selectedWeek: Int = 1
    @State private var showWeekPicker = false
    @State private var hasAppearedOnce = false
    @State private var actualZoneData: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
    @State private var actualZonePercentages: [String: Double] = [:]
    @State private var isLoadingZones = false

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    var raceReadiness: [SportReadiness] {
        deriveRaceReadiness(from: trainingStatusService.status, today: "")
    }
    var raceReadinessOverall: Int {
        guard !raceReadiness.isEmpty else { return 0 }
        return raceReadiness.map(\.score).reduce(0, +) / raceReadiness.count
    }

    func recalculateAnalytics() {
        analyticsVM.recalculate(
            week: currentWeek,
            hkWorkouts: healthKit.workouts,
            allWeeks: trainingPlan.weeks,
            currentWeekNum: trainingPlan.currentWeekNumber
        )
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
            VStack(spacing: 0) {
                PersistentTopNavView(
                    title: "Analytics",
                    isTransparent: false,
                    weekLabel: "Week \(selectedWeek)/\(trainingPlan.weeks.count)",
                    onWeekSelector: { showWeekPicker = true },
                    onProfile: { NotificationCenter.default.post(name: .openSettings, object: nil) },
                    onChat: { NotificationCenter.default.post(name: .navigateToChat, object: nil) },
                    onCalendar: { NotificationCenter.default.post(name: .openCalendar, object: nil) }
                )

            ScrollView {
            VStack(spacing: 20) {
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

                    // Bonus (off-plan) activity summary
                    let u = analyticsVM.cachedUnplannedVolume
                    let totalBonusHours = u.swim + u.bike + u.run + u.other
                    if totalBonusHours > 0 {
                        Divider()
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bonus activity: \(formatBonusHours(totalBonusHours))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                                let parts = bonusBreakdown(u)
                                if !parts.isEmpty {
                                    Text(parts.joined(separator: " \u{2022} "))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
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

                    if analyticsVM.cachedComplianceTrend.isEmpty {
                        Text("No compliance data yet")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(analyticsVM.cachedComplianceTrend, id: \.week) { entry in
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

                // Training Load & Readiness
                if let ts = trainingStatusService.status {
                    TrainingLoadCard(status: ts)
                }

                // Race Readiness per discipline
                RaceReadinessCardView(
                    readiness: raceReadiness,
                    overall: raceReadinessOverall,
                    onSwap: {
                        NotificationCenter.default.post(name: .navigateToChat, object: nil)
                    }
                )

                Spacer(minLength: 32)
            }
            .padding()
            } // ScrollView
            .gesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < -30 && selectedWeek < trainingPlan.weeks.count {
                            withAnimation { selectedWeek += 1 }
                        } else if value.translation.width > 30 && selectedWeek > 1 {
                            withAnimation { selectedWeek -= 1 }
                        }
                    }
            )

            } // VStack
            .navigationBarHidden(true)
            .sheet(isPresented: $showWeekPicker) {
                WeekPickerSheet(selectedWeek: $selectedWeek, trainingPlan: trainingPlan)
            }
            .onAppear {
                if !hasAppearedOnce {
                    selectedWeek = trainingPlan.currentWeekNumber
                    hasAppearedOnce = true
                }
                // Defer heavy scan so the view renders first, then updates
                Task { @MainActor in
                    recalculateAnalytics()
                    fetchActualZoneData()
                }
            }
            .onChange(of: selectedWeek) { _, _ in
                Task { @MainActor in
                    recalculateAnalytics()
                    fetchActualZoneData()
                }
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

// MARK: - Training Load & Readiness Card

private struct TrainingLoadCard: View {
    let status: TrainingStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Load & Readiness")
                .font(.headline)

            ReadinessBadgeView(readiness: status.readiness)

            if let combined = status.combinedFitness {
                FitnessMetricsRow(metrics: combined)
            }

            DisciplineBalanceRow(
                fitnessPerDiscipline: status.fitnessPerDiscipline,
                gaps: status.disciplineGaps
            )

            HRVTrendRow(hrv: status.hrvTrend)

            IntensityPatternRow(pattern: status.intensityPattern)

            if status.loadSpike.isSpiked {
                LoadSpikeWarningRow(spike: status.loadSpike)
            }

            if let decoupling = status.recentDecoupling.first {
                DecouplingRow(result: decoupling)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

private struct ReadinessBadgeView: View {
    let readiness: CompositeReadiness

    private var ringColor: Color {
        switch readiness.level {
        case .race: return .green
        case .fresh: return .blue
        case .training: return .yellow
        case .tired: return .orange
        case .overreached: return .red
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(ringColor, lineWidth: 4)
                    .frame(width: 64, height: 64)
                VStack(spacing: 2) {
                    Text("\(readiness.score)")
                        .font(.title2).fontWeight(.bold)
                    Text("/ 100")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(readiness.level.rawValue.capitalized)
                    .font(.headline)
                    .foregroundStyle(ringColor)
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("TSB").font(.caption2).foregroundStyle(.secondary)
                        Text("\(readiness.tsbScore)/40").font(.caption).fontWeight(.medium)
                    }
                    VStack(alignment: .leading) {
                        Text("HRV").font(.caption2).foregroundStyle(.secondary)
                        Text("\(readiness.hrvScore)/30").font(.caption).fontWeight(.medium)
                    }
                    VStack(alignment: .leading) {
                        Text("Load").font(.caption2).foregroundStyle(.secondary)
                        Text("\(readiness.loadSpikeScore)/30").font(.caption).fontWeight(.medium)
                    }
                }
            }
            Spacer()
        }
    }
}

private struct FitnessMetricsRow: View {
    let metrics: FitnessMetrics

    private var tsbColor: Color {
        let tsb = metrics.tsb
        if tsb > 5 { return .green }
        if tsb > -10 { return .primary }
        return .red
    }

    var body: some View {
        HStack(spacing: 0) {
            MetricCell(label: "CTL", value: String(format: "%.0f", metrics.ctl))
            Divider().frame(height: 32)
            MetricCell(label: "ATL", value: String(format: "%.0f", metrics.atl))
            Divider().frame(height: 32)
            MetricCell(label: "Form", value: String(format: "%+.0f", metrics.tsb), valueColor: tsbColor)
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

private struct MetricCell: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct DisciplineBalanceRow: View {
    let fitnessPerDiscipline: [FitnessMetrics]
    let gaps: [DisciplineGap]

    private func metrics(for disc: TrainingDiscipline) -> FitnessMetrics? {
        fitnessPerDiscipline.first { $0.discipline == disc }
    }
    private func gap(for disc: TrainingDiscipline) -> DisciplineGap? {
        gaps.first { $0.discipline == disc }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Discipline Balance (CTL)")
                .font(.caption).foregroundStyle(.secondary)

            let swim = metrics(for: .swim)?.ctl ?? 0
            let bike = metrics(for: .bike)?.ctl ?? 0
            let run = metrics(for: .run)?.ctl ?? 0
            let total = swim + bike + run

            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach([TrainingDiscipline.swim, .bike, .run], id: \.rawValue) { disc in
                            let ctl: Double = metrics(for: disc)?.ctl ?? 0
                            let width = geo.size.width * CGFloat(ctl / total)
                            let g = gap(for: disc)
                            let barColor: Color = {
                                if g?.severity == .critical { return .red }
                                if g?.severity == .warning { return .orange }
                                switch disc {
                                case .swim: return .blue
                                case .bike: return .orange
                                case .run: return .green
                                default: return .gray
                                }
                            }()
                            Rectangle()
                                .fill(barColor)
                                .frame(width: max(width, 2))
                                .cornerRadius(3)
                        }
                    }
                }
                .frame(height: 16)

                HStack {
                    ForEach([TrainingDiscipline.swim, .bike, .run], id: \.rawValue) { disc in
                        let g = gap(for: disc)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(disc.rawValue.capitalized)
                                .font(.caption2)
                            if g?.severity == .critical {
                                Text("⚠️ No sessions in 14d")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.red)
                            } else if g?.severity == .warning {
                                Text("Undertrained")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("No data").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HRVTrendRow: View {
    let hrv: HRVTrend

    private var arrowIcon: String {
        switch hrv.direction {
        case .improving: return "arrow.up.circle.fill"
        case .declining: return "arrow.down.circle.fill"
        case .stable: return "arrow.right.circle.fill"
        case .insufficient: return "questionmark.circle"
        }
    }
    private var arrowColor: Color {
        switch hrv.direction {
        case .improving: return .green
        case .declining: return .red
        case .stable: return .blue
        case .insufficient: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: arrowIcon).foregroundStyle(arrowColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("HRV").font(.caption2).foregroundStyle(.secondary)
                if let today = hrv.todaySDNN {
                    Text(String(format: "%.0f ms today", today)).font(.caption)
                } else {
                    Text("No reading today").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let pct = hrv.percentFromBaseline {
                Text(String(format: "%+.0f%% vs baseline", pct))
                    .font(.caption)
                    .foregroundStyle(pct >= 0 ? .green : .red)
            }
        }
    }
}

private struct IntensityPatternRow: View {
    let pattern: IntensityPattern

    private var color: Color {
        switch pattern {
        case .polarized: return .green
        case .pyramidal: return .yellow
        case .thresholdHeavy: return .red
        case .mixed: return .orange
        case .insufficientData: return .secondary
        }
    }

    var body: some View {
        HStack {
            Text("Intensity Pattern (14d)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(pattern.rawValue.capitalized)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

private struct LoadSpikeWarningRow: View {
    let spike: LoadSpike

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(String(format: "Load spike: +%.0f%% vs last week", spike.increasePercent))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

private struct DecouplingRow: View {
    let result: DecouplingResult

    var body: some View {
        HStack {
            Text("Aerobic Decoupling (\(result.discipline.rawValue))")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f%%", result.decouplingPercent))
                .font(.caption).fontWeight(.semibold)
            Text(result.isRaceReady ? "✅" : "❌").font(.caption)
        }
    }
}
