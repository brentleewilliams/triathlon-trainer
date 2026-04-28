import SwiftUI

// MARK: - Plan View

struct PlanView: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @State private var showConnectedApps = false
    @State private var showManagePlan = false
    @State private var expandedWeeks: Set<Int> = []

    // MARK: - Computed Properties

    var raceDate: Date {
        if let ts = UserDefaults.standard.object(forKey: "race_date") as? Double {
            return Date(timeIntervalSince1970: ts)
        }
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 19
        return Calendar.current.date(from: c) ?? Date()
    }

    var daysUntilRace: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let race  = Calendar.current.startOfDay(for: raceDate)
        return Calendar.current.dateComponents([.day], from: today, to: race).day ?? 0
    }

    var currentPhase: String {
        trainingPlan.getWeek(trainingPlan.currentWeekNumber)?.phase ?? "Base"
    }

    var planName: String {
        let raw = RaceCourseService.shared.currentProfile?.raceName ?? "Half Iron Tri Plan"
        // Strip "Race1 — " prefix if present
        if raw.hasPrefix("Race1 — ") {
            return String(raw.dropFirst("Race1 — ".count))
        }
        return raw
    }

    var completedWeeks: Int {
        max(0, trainingPlan.currentWeekNumber - 1)
    }

    var totalWeeks: Int {
        trainingPlan.weeks.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PersistentTopNavView(
                    title: "Plan",
                    isTransparent: false,
                    onProfile: {
                        NotificationCenter.default.post(name: .openSettings, object: nil)
                    },
                    onChat: {
                        NotificationCenter.default.post(name: .navigateToChat, object: nil)
                    },
                    onCalendar: {
                        NotificationCenter.default.post(name: .openCalendar, object: nil)
                    },
                    onAddWorkout: {
                        NotificationCenter.default.post(name: .openLogWorkout, object: nil)
                    }
                )

                ScrollView {
                    VStack(spacing: AppTheme.cardSpacing) {

                        // Plan Hero Card
                        PlanHeroCard(
                            planName: planName,
                            raceDate: raceDate,
                            completedWeeks: completedWeeks,
                            totalWeeks: totalWeeks
                        )
                        .padding(.horizontal, AppTheme.cardPadding)

                        // Summary sentence
                        HStack {
                            Text("Week \(trainingPlan.currentWeekNumber) of \(totalWeeks) · \(currentPhase) phase · \(daysUntilRace) days to race")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, AppTheme.cardPadding)

                        // Action Grid
                        HStack(spacing: 12) {
                            PlanActionButton(
                                label: "Connected Apps",
                                icon: "link"
                            ) {
                                showConnectedApps = true
                            }
                            PlanActionButton(
                                label: "Manage Plan",
                                icon: "slider.horizontal.3"
                            ) {
                                showManagePlan = true
                            }
                        }
                        .padding(.horizontal, AppTheme.cardPadding)

                        // Weekly Breakdown
                        VStack(spacing: 8) {
                            ForEach(
                                trainingPlan.weeks.sorted { $0.weekNumber < $1.weekNumber },
                                id: \.weekNumber
                            ) { week in
                                PlanWeekCard(
                                    week: week,
                                    isCurrentWeek: week.weekNumber == trainingPlan.currentWeekNumber,
                                    isExpanded: expandedWeeks.contains(week.weekNumber),
                                    onToggle: {
                                        if expandedWeeks.contains(week.weekNumber) {
                                            expandedWeeks.remove(week.weekNumber)
                                        } else {
                                            expandedWeeks.insert(week.weekNumber)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.cardPadding)

                        Spacer(minLength: 24)
                    }
                    .padding(.top, AppTheme.cardSpacing)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Expand current week by default (only on first appear)
            if expandedWeeks.isEmpty {
                expandedWeeks.insert(trainingPlan.currentWeekNumber)
            }
        }
        .sheet(isPresented: $showConnectedApps) {
            ConnectedAppsSheet()
        }
        .sheet(isPresented: $showManagePlan) {
            ManagePlanSheet()
        }
    }
}

// MARK: - Plan Hero Card

private struct PlanHeroCard: View {
    let planName: String
    let raceDate: Date
    let completedWeeks: Int
    let totalWeeks: Int

    var raceDateString: String {
        Formatters.fullDate.string(from: raceDate)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1B2540"), Color(hex: "28456A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .cornerRadius(16)

            VStack(alignment: .leading, spacing: 12) {
                // Plan name + distance badge
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(planName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text(raceDateString)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Spacer()
                    Text("70.3 MI")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                }

                // Progress capsules
                GeometryReader { geo in
                    let capsuleWidth = (geo.size.width - CGFloat(totalWeeks - 1) * 4) / CGFloat(max(totalWeeks, 1))
                    HStack(spacing: 4) {
                        ForEach(0..<totalWeeks, id: \.self) { idx in
                            Capsule()
                                .fill(idx < completedWeeks ? Color.white : Color.white.opacity(0.3))
                                .frame(width: capsuleWidth, height: 4)
                        }
                    }
                }
                .frame(height: 4)

                // Stats row
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TOTAL WEEKS")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(completedWeeks)/\(totalWeeks)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TOTAL DISTANCE")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        Text("247.8 mi")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Plan Action Button

private struct PlanActionButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(AppTheme.cardCornerRadius)
        }
    }
}

// MARK: - Plan Week Card

struct PlanWeekCard: View {
    let week: TrainingWeek
    let isCurrentWeek: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    @EnvironmentObject var trainingPlan: TrainingPlanManager

    @State private var dropTargetDay: String? = nil

    private let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // MARK: - Helpers

    var weekStartString: String {
        Formatters.shortDate.string(from: week.startDate)
    }

    var weekEndString: String {
        Formatters.shortDate.string(from: week.endDate)
    }

    var nonRestWorkouts: [DayWorkout] {
        week.workouts.filter { !$0.type.lowercased().contains("rest") }
    }

    var workoutCount: Int { nonRestWorkouts.count }

    var estimatedDistance: String {
        // Return a simple workout count label; distance parsing would be complex
        "\(workoutCount) workout\(workoutCount == 1 ? "" : "s")"
    }

    var sortedWorkouts: [DayWorkout] {
        week.workouts.sorted {
            let aIdx = dayOrder.firstIndex(of: $0.day) ?? 7
            let bIdx = dayOrder.firstIndex(of: $1.day) ?? 7
            return aIdx < bIdx
        }
    }

    // MARK: - Completion Check

    func isPastWorkout(_ workout: DayWorkout) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayOffset = dayOrder.firstIndex(of: workout.day) ?? 0
        guard let workoutDate = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: week.startDate)) else {
            return false
        }
        return workoutDate < today
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Week header (always visible)
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 8) {
                    // Week number badge
                    Text("W\(week.weekNumber)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black)
                        .clipShape(Capsule())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(weekStartString) – \(weekEndString)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            if isCurrentWeek {
                                Text("NOW")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        }

                        Text("\(estimatedDistance) · \(week.phase)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded workout rows
            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)

                VStack(spacing: 0) {
                    ForEach(sortedWorkouts) { workout in
                        WorkoutPlanRow(
                            workout: workout,
                            isPast: isPastWorkout(workout),
                            weekNumber: week.weekNumber,
                            isDropTarget: dropTargetDay == workout.day,
                            onSwap: { ref, destDay in
                                trainingPlan.swapOrMoveWorkout(
                                    weekNumber: week.weekNumber,
                                    source: ref.workout,
                                    sourceDay: ref.sourceDay,
                                    destDay: destDay
                                )
                            },
                            onTargetedChange: { targeted, day in
                                dropTargetDay = targeted ? day : (dropTargetDay == day ? nil : dropTargetDay)
                            }
                        )
                        if workout.id != sortedWorkouts.last?.id {
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .fill(isCurrentWeek
                      ? Color(.secondarySystemBackground)
                      : Color(.systemBackground))
                .shadow(
                    color: Color.black.opacity(AppTheme.cardShadowOpacity),
                    radius: AppTheme.cardShadowRadius,
                    x: 0,
                    y: 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .strokeBorder(
                    isCurrentWeek ? Color.green.opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }
}

// MARK: - Workout Plan Row

private struct WorkoutPlanRow: View {
    let workout: DayWorkout
    let isPast: Bool
    let weekNumber: Int
    let isDropTarget: Bool
    let onSwap: (DraggedWorkoutRef, String) -> Void
    let onTargetedChange: (Bool, String) -> Void

    var isRest: Bool {
        workout.type.lowercased().contains("rest")
    }

    var truncatedType: String {
        let raw = workout.type
        if raw.count > 25 {
            return String(raw.prefix(25)) + "…"
        }
        return raw
    }

    var body: some View {
        HStack(spacing: 10) {
            // Discipline color dot
            Circle()
                .fill(AppTheme.sportColor(for: workout.type))
                .frame(width: 8, height: 8)

            // Day abbreviation
            Text(workout.day)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)

            // Workout type
            Text(truncatedType)
                .font(.subheadline)
                .foregroundColor(isRest ? .secondary : .primary)
                .lineLimit(1)

            if !isRest && !workout.duration.isEmpty && workout.duration != "-" {
                Text(workout.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Completion indicator
            if isRest {
                // No check for rest days
                Image(systemName: "minus")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))
            } else if isPast {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.statusGreen)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .modifier(WorkoutRowDragDrop(
            isRest: isRest,
            weekNumber: weekNumber,
            workout: workout,
            onSwap: onSwap,
            onTargetedChange: onTargetedChange
        ))
    }
}

/// Conditionally attaches .draggable + .dropDestination so rest rows are
/// drop-targets only (you can drag *to* them but can't drag a rest day).
private struct WorkoutRowDragDrop: ViewModifier {
    let isRest: Bool
    let weekNumber: Int
    let workout: DayWorkout
    let onSwap: (DraggedWorkoutRef, String) -> Void
    let onTargetedChange: (Bool, String) -> Void

    func body(content: Content) -> some View {
        let dropApplied = content.dropDestination(for: DraggedWorkoutRef.self) { items, _ in
            guard let ref = items.first else { return false }
            onSwap(ref, workout.day)
            return true
        } isTargeted: { targeted in
            onTargetedChange(targeted, workout.day)
        }

        if isRest {
            dropApplied
        } else {
            dropApplied.draggable(DraggedWorkoutRef(
                weekNumber: weekNumber,
                sourceDay: workout.day,
                workout: workout
            ))
        }
    }
}

// MARK: - Connected Apps Sheet

private struct ConnectedAppsSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .frame(width: 28)
                        Text("HealthKit")
                            .font(.body)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppTheme.statusGreen)
                        Text("Connected")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.statusGreen)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundColor(Color(hex: "FC4C02"))
                            .frame(width: 28)
                        Text("Strava")
                            .font(.body)
                        Spacer()
                        Text("Coming Soon")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Image(systemName: "watch.analog")
                            .foregroundColor(Color(hex: "1C5FA6"))
                            .frame(width: 28)
                        Text("Garmin")
                            .font(.body)
                        Spacer()
                        Text("Coming Soon")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Connected Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Manage Plan Sheet

private struct ManagePlanSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Plan Customization")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Plan customization coming soon")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .navigationTitle("Manage Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
