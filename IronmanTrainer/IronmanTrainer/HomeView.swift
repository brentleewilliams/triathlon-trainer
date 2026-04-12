import SwiftUI
import HealthKit

/// Returns the Monday of the ISO week containing the given date.
/// Handles cases where a generated plan's startDate is not exactly Monday.
func mondayOfWeek(_ date: Date) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2 // Monday
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return cal.date(from: comps) ?? date
}

// MARK: - Widget Tip Card
struct WidgetTipCard: View {
    @Binding var isVisible: Bool
    @State private var showInstructions = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add the Race1 widget")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("See today's workout on your home screen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showInstructions = true } label: {
                Text("How")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Button { withAnimation { isVisible = false } } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 12)
        .sheet(isPresented: $showInstructions) {
            WidgetInstructionsSheet()
                .presentationDetents([.medium])
        }
    }
}

struct WidgetInstructionsSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Add the Race1 Widget")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array([
                    ("1", "Long-press your home screen until icons wiggle"),
                    ("2", "Tap the \"+\" button in the top-left corner"),
                    ("3", "Search for \"Race1\""),
                    ("4", "Select the widget and tap \"Add Widget\"")
                ].enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(step.0)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.blue)
                            .clipShape(Circle())
                        Text(step.1)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 32)
    }
}

// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @State private var selectedWeek: Int = 1
    @State private var hasAppearedOnce = false
    @State private var draggedFromDay: String?
    @State private var showWidgetTip: Bool = !UserDefaults.standard.bool(forKey: "widget_tip_dismissed")
    @State private var draggedWorkout: DayWorkout?

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    var formattedDateRange: String {
        guard let week = currentWeek else { return "" }
        let startStr = Formatters.shortDate.string(from: week.startDate)
        let endStr = Formatters.shortDate.string(from: week.endDate)
        return "\(startStr) - \(endStr), 2026"
    }

    var daysUntilRace: Int {
        let calendar = Calendar.current
        let raceDate: Date
        if let saved = UserDefaults.standard.object(forKey: "race_date") as? Double {
            raceDate = Date(timeIntervalSince1970: saved)
        } else {
            // Fallback to hardcoded Ironman 70.3 Oregon date
            var comps = DateComponents()
            comps.year = 2026; comps.month = 7; comps.day = 19
            raceDate = calendar.date(from: comps) ?? Date()
        }
        let today = calendar.startOfDay(for: Date())
        let race = calendar.startOfDay(for: raceDate)
        return calendar.dateComponents([.day], from: today, to: race).day ?? 0
    }

    var currentPhase: String {
        trainingPlan.getWeek(selectedWeek)?.phase ?? ""
    }

    var completionCounts: (total: Int, completed: Int) {
        guard let week = currentWeek else { return (0, 0) }

        let calendar = Calendar.current
        let todayStartOfDay = calendar.startOfDay(for: Date())
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let grouped = Dictionary(grouping: week.workouts, by: { $0.day })

        var total = 0
        var completed = 0

        for day in dayOrder {
            guard let dayWorkouts = grouped[day] else { continue }
            let sampleWorkout = dayWorkouts[0]
            let dayDate = getDateForDay(sampleWorkout)
            let dayStartOfDay = calendar.startOfDay(for: dayDate)
            guard dayStartOfDay <= todayStartOfDay else { continue }
            // Skip pre-plan days: user didn't have the app yet, not counted.
            if OnboardingStore.isPrePlan(dayDate) { continue }

            if let restWorkout = dayWorkouts.first(where: { $0.type.contains("Rest") }) {
                if isRestDayCompleted(for: restWorkout) {
                    total += 1
                    completed += 1
                }
            } else {
                for workout in dayWorkouts {
                    total += 1
                    if isWorkoutCompleted(workout) {
                        completed += 1
                    }
                }
            }
        }

        return (total, completed)
    }

    var todaysTotalWorkouts: Int { completionCounts.total }
    var todaysCompletedWorkouts: Int { completionCounts.completed }

    var weeklyComplianceText: String? {
        guard let week = currentWeek else { return nil }
        if let pct = calculateWeekCompliance(week: week, hkWorkouts: healthKit.workouts) {
            return "\(Int(pct))%"
        }
        return nil
    }

    var workoutsByDay: [(day: String, workouts: [DayWorkout])] {
        guard let week = currentWeek else { return [] }

        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let grouped = Dictionary(grouping: week.workouts, by: { $0.day })
        let calendar = Calendar.current
        let weekMonday = mondayOfWeek(week.startDate)

        // Render the actual plan data for every day, past or future, EXCEPT
        // days strictly before the user's onboarding date — those are hidden
        // entirely (the plan didn't exist for them yet). Past days after
        // onboarding show their real plan content so edits are visible.
        return dayOrder.enumerated().compactMap { (index, day) in
            let dayDate = calendar.date(byAdding: .day, value: index, to: weekMonday) ?? weekMonday
            if OnboardingStore.isPrePlan(dayDate) { return nil }
            if let workouts = grouped[day] {
                return (day: day, workouts: workouts)
            } else {
                // Day has no workouts at all (e.g. dropped/cancelled) — show as Rest.
                let rest = DayWorkout(day: day, type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil, notes: nil)
                return (day: day, workouts: [rest])
            }
        }
    }

    func isWorkoutCompleted(_ workout: DayWorkout) -> Bool {
        let isBrick = workout.type.lowercased().contains("brick") || workout.type.lowercased().contains("race sim")
        let targetDate = getDateForDay(workout)

        if isBrick {
            // Brick requires both bike AND run on the same day
            let calendar = Calendar.current
            let targetDay = calendar.startOfDay(for: targetDate)
            let hasBike = healthKit.workouts.contains { hkWorkout in
                calendar.startOfDay(for: hkWorkout.startDate) == targetDay &&
                hkWorkout.workoutActivityType == .cycling
            }
            let hasRun = healthKit.workouts.contains { hkWorkout in
                calendar.startOfDay(for: hkWorkout.startDate) == targetDay &&
                hkWorkout.workoutActivityType == .running
            }
            return hasBike && hasRun
        }

        // Standard workout: check type + duration tolerance
        let workoutType = extractWorkoutTypeFromString(workout.type)
        let plannedDurationMinutes = parseWorkoutDuration(workout.duration)
        let toleranceMinutes = 15

        return healthKit.workouts.contains { hkWorkout in
            let calendar = Calendar.current
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let targetStartOfDay = calendar.startOfDay(for: targetDate)

            guard workoutDate == targetStartOfDay &&
                   workoutTypeMatchesActivityType(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType) else {
                return false
            }

            if let plannedMin = plannedDurationMinutes {
                let hkDurationMinutes = Int(hkWorkout.duration / 60)
                let durationDiff = abs(hkDurationMinutes - plannedMin)
                return durationDiff <= toleranceMinutes
            }

            return true
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
        dateForWorkoutDay(workout.day, weekStartDate: mondayOfWeek(currentWeek?.startDate ?? Date()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Race Countdown Banner
                HStack {
                    if daysUntilRace > 0 {
                        HStack(spacing: 4) {
                            Text("\(daysUntilRace)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("DAYS TO RACE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                    } else if daysUntilRace == 0 {
                        Text("RACE DAY!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    } else {
                        Text("RACE COMPLETE")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Text("Week \(selectedWeek) \u{00B7} \(currentPhase)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        Task { await healthKit.syncWorkouts() }
                    } label: {
                        if healthKit.isSyncing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .disabled(healthKit.isSyncing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(10)

                // Widget tip card (shown until dismissed)
                if showWidgetTip {
                    WidgetTipCard(isVisible: Binding(
                        get: { showWidgetTip },
                        set: { newVal in
                            showWidgetTip = newVal
                            if !newVal { UserDefaults.standard.set(true, forKey: "widget_tip_dismissed") }
                        }
                    ))
                }

                // Week Navigation Header with Completion Count and Undo
                HStack {
                    WeekNavigationHeader(selectedWeek: $selectedWeek, completionText: "\(todaysCompletedWorkouts)/\(todaysTotalWorkouts)", complianceText: weeklyComplianceText)

                    if trainingPlan.previousPlanVersion != nil {
                        Button(action: {
                            _ = trainingPlan.rollbackToPreviousVersion()
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    }
                }

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
                        parent: self,
                        draggedWorkout: $draggedWorkout,
                        draggedFromDay: $draggedFromDay,
                        selectedWeek: selectedWeek
                    )
                }
                .onDrop(of: [.plainText], isTargeted: nil) { _ in
                    print("[DROP] ScrollView catch-all onDrop fired, clearing drag state")
                    draggedFromDay = nil
                    draggedWorkout = nil
                    return false
                }
                .onTapGesture {
                    if draggedFromDay != nil {
                        print("[DRAG] Tap detected, clearing draggedFromDay=\(draggedFromDay ?? "nil")")
                        draggedFromDay = nil
                        draggedWorkout = nil
                    }
                }
                .onChange(of: selectedWeek) { _, _ in
                    draggedFromDay = nil
                    draggedWorkout = nil
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < -50 && selectedWeek < 17 {
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
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToWeek)) { notification in
                if let week = notification.userInfo?["week"] as? Int {
                    withAnimation { selectedWeek = week }
                }
            }
        }
    }
}

