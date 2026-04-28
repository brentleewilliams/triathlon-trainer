import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drag payload
// Identifies a workout being dragged so the drop site knows where it came
// from (week + day) and can issue a move that preserves the original cell's
// content. Using a Codable Transferable keeps the payload self-contained —
// no shared state needed across the drag session.
struct DraggedWorkoutRef: Codable, Transferable {
    let weekNumber: Int
    let sourceDay: String
    let workout: DayWorkout

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Training Calendar View

struct TrainingCalendarView: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @Environment(\.dismiss) private var dismiss

    // Sheet state for adding workouts
    @State private var showAddSheet = false
    @State private var addTargetDay: String = "Mon"
    @State private var addTargetWeekNumber: Int = 1

    // Alert state for reset confirmation
    @State private var showResetAlert = false
    @State private var resetTargetWeekNumber: Int = 1

    // Toast state
    @State private var toastMessage: String? = nil

    private let dayAbbrevs = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(trainingPlan.weeks.sorted { $0.weekNumber < $1.weekNumber }, id: \.weekNumber) { week in
                        WeekSection(
                            week: week,
                            isCurrentWeek: week.weekNumber == trainingPlan.currentWeekNumber,
                            dayAbbrevs: dayAbbrevs,
                            onAddWorkout: { day in
                                addTargetDay = day
                                addTargetWeekNumber = week.weekNumber
                                showAddSheet = true
                            },
                            onResetWeek: {
                                resetTargetWeekNumber = week.weekNumber
                                showResetAlert = true
                            },
                            onMoveWorkout: { ref, destDay in
                                moveWorkout(ref, toWeek: week.weekNumber, toDay: destDay)
                            }
                        )
                        .id(week.weekNumber)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear {
                // Small delay to ensure layout is ready before scrolling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(trainingPlan.currentWeekNumber, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("Training Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Changes (drag/swap, +Add) persist immediately via
            // TrainingPlanManager, so this button is just a dismiss.
            // Single Done in the trailing slot, no duplicate top-left.
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddWorkoutSheet(
                day: addTargetDay,
                weekNumber: addTargetWeekNumber,
                onAdd: { newWorkout in
                    addWorkout(newWorkout, toWeek: addTargetWeekNumber)
                    showAddSheet = false
                },
                onCancel: {
                    showAddSheet = false
                }
            )
        }
        .alert("Reset Week", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                handleResetWeek(resetTargetWeekNumber)
            }
        } message: {
            Text("Reset Week \(resetTargetWeekNumber) to its original planned workouts? Any manually added workouts will be removed.")
        }
        .overlay(alignment: .bottom) {
            if let message = toastMessage {
                ToastView(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Helpers

    private func addWorkout(_ workout: DayWorkout, toWeek weekNumber: Int) {
        guard let weekIdx = trainingPlan.weeks.firstIndex(where: { $0.weekNumber == weekNumber }) else {
            showToast("Week not found")
            return
        }
        let week = trainingPlan.weeks[weekIdx]
        var updatedWorkouts = week.workouts
        updatedWorkouts.append(workout)
        updatedWorkouts.sort {
            (dayAbbrevs.firstIndex(of: $0.day) ?? 0) < (dayAbbrevs.firstIndex(of: $1.day) ?? 0)
        }
        trainingPlan.weeks[weekIdx] = TrainingWeek(
            weekNumber: week.weekNumber,
            phase: week.phase,
            startDate: week.startDate,
            endDate: week.endDate,
            workouts: updatedWorkouts
        )
        trainingPlan.savePlanVersion(source: "calendar", description: "Added \(workout.type) on \(workout.day) (Week \(weekNumber))")
    }

    /// Moves a workout from its source (week + day, encoded in `ref`) to a new
    /// week + day. Same-day no-ops fall through silently. Both source and
    /// destination weeks may be the same — we update them in a single pass so
    /// in-place moves don't briefly drop the workout.
    private func moveWorkout(_ ref: DraggedWorkoutRef, toWeek destWeek: Int, toDay destDay: String) {
        guard ref.sourceDay != destDay || ref.weekNumber != destWeek else { return }

        // Find source week
        guard let srcIdx = trainingPlan.weeks.firstIndex(where: { $0.weekNumber == ref.weekNumber }) else {
            showToast("Source week not found")
            return
        }

        // Remove from source
        var srcWorkouts = trainingPlan.weeks[srcIdx].workouts
        guard let removeAt = srcWorkouts.firstIndex(where: { $0 == ref.workout }) else {
            showToast("Workout not found")
            return
        }
        var moved = srcWorkouts.remove(at: removeAt)
        // Reflect new day in the moved workout (DayWorkout.day drives sort order
        // and downstream display).
        moved = DayWorkout(
            day: destDay,
            type: moved.type,
            duration: moved.duration,
            zone: moved.zone,
            status: moved.status,
            nutritionTarget: moved.nutritionTarget,
            notes: moved.notes
        )

        let srcWeek = trainingPlan.weeks[srcIdx]

        if ref.weekNumber == destWeek {
            // Same-week move: insert in same array, sort, write back once.
            srcWorkouts.append(moved)
            srcWorkouts.sort {
                (dayAbbrevs.firstIndex(of: $0.day) ?? 0) < (dayAbbrevs.firstIndex(of: $1.day) ?? 0)
            }
            trainingPlan.weeks[srcIdx] = TrainingWeek(
                weekNumber: srcWeek.weekNumber,
                phase: srcWeek.phase,
                startDate: srcWeek.startDate,
                endDate: srcWeek.endDate,
                workouts: srcWorkouts
            )
        } else {
            // Cross-week move: write source without the workout, then add to dest.
            trainingPlan.weeks[srcIdx] = TrainingWeek(
                weekNumber: srcWeek.weekNumber,
                phase: srcWeek.phase,
                startDate: srcWeek.startDate,
                endDate: srcWeek.endDate,
                workouts: srcWorkouts
            )
            guard let destIdx = trainingPlan.weeks.firstIndex(where: { $0.weekNumber == destWeek }) else {
                showToast("Destination week not found")
                return
            }
            let destWeekObj = trainingPlan.weeks[destIdx]
            var destWorkouts = destWeekObj.workouts
            destWorkouts.append(moved)
            destWorkouts.sort {
                (dayAbbrevs.firstIndex(of: $0.day) ?? 0) < (dayAbbrevs.firstIndex(of: $1.day) ?? 0)
            }
            trainingPlan.weeks[destIdx] = TrainingWeek(
                weekNumber: destWeekObj.weekNumber,
                phase: destWeekObj.phase,
                startDate: destWeekObj.startDate,
                endDate: destWeekObj.endDate,
                workouts: destWorkouts
            )
        }

        trainingPlan.savePlanVersion(
            source: "calendar",
            description: "Moved \(moved.type) from \(ref.sourceDay) to \(destDay) (Week \(ref.weekNumber)→\(destWeek))"
        )
        showToast("Moved to \(destDay)")
    }

    private func handleResetWeek(_ weekNumber: Int) {
        showToast("Reset coming soon")
    }

    private func showToast(_ message: String) {
        withAnimation {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                toastMessage = nil
            }
        }
    }
}

// MARK: - Week Section

private struct WeekSection: View {
    let week: TrainingWeek
    let isCurrentWeek: Bool
    let dayAbbrevs: [String]
    let onAddWorkout: (String) -> Void
    let onResetWeek: () -> Void
    let onMoveWorkout: (DraggedWorkoutRef, String) -> Void

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Week header
            weekHeader

            // Day rows
            VStack(spacing: 6) {
                ForEach(Array(dayAbbrevs.enumerated()), id: \.offset) { index, dayAbbrev in
                    let dayDate = dateForDayIndex(index, weekStart: week.startDate)
                    let workoutsForDay = week.workouts.filter { $0.day == dayAbbrev }

                    DayRow(
                        dayAbbrev: dayAbbrev,
                        weekNumber: week.weekNumber,
                        date: dayDate,
                        workouts: workoutsForDay,
                        onAdd: { onAddWorkout(dayAbbrev) },
                        onMoveWorkout: onMoveWorkout
                    )
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(AppTheme.cardCornerRadius)
        .shadow(color: Color.black.opacity(AppTheme.cardShadowOpacity), radius: AppTheme.cardShadowRadius, x: 0, y: 2)
    }

    private var weekHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            // Week title + dates
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Week \(week.weekNumber) · \(dateFormatter.string(from: week.startDate)) – \(dateFormatter.string(from: week.endDate))")
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
                            .background(Color.black)
                            .clipShape(Capsule())
                    }
                }

                Text(weekSummaryLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Reset") {
                onResetWeek()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var weekSummaryLabel: String {
        let workoutCount = week.workouts.filter {
            !$0.type.lowercased().contains("rest") && $0.duration != "-"
        }.count
        let totalMinutes = week.workouts.compactMap { parseWorkoutDuration($0.duration) }.reduce(0, +)
        if totalMinutes > 0 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            if mins == 0 {
                return "Total: \(hours)h · \(workoutCount) sessions"
            } else {
                return "Total: \(hours)h \(mins)m · \(workoutCount) sessions"
            }
        } else if workoutCount > 0 {
            return "\(workoutCount) workouts"
        } else {
            return "Rest week"
        }
    }

    private func dateForDayIndex(_ index: Int, weekStart: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
    }
}

// MARK: - Day Row

private struct DayRow: View {
    let dayAbbrev: String
    let weekNumber: Int
    let date: Date
    let workouts: [DayWorkout]
    let onAdd: () -> Void
    let onMoveWorkout: (DraggedWorkoutRef, String) -> Void

    @State private var isTargeted = false

    private let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Day label column
            VStack(spacing: 1) {
                Text(dayAbbrev.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(dayNumberFormatter.string(from: date))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Text(monthFormatter.string(from: date))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .frame(width: 38)

            // Workout cards (or rest placeholder)
            if workouts.isEmpty {
                restPlaceholder
            } else {
                VStack(spacing: 4) {
                    ForEach(workouts) { workout in
                        WorkoutCalendarCard(workout: workout)
                            .draggable(DraggedWorkoutRef(
                                weekNumber: weekNumber,
                                sourceDay: dayAbbrev,
                                workout: workout
                            ))
                    }
                }
            }

            Spacer(minLength: 0)

            // Add button
            Button {
                onAdd()
            } label: {
                Text("+ Add")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill))
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .dropDestination(for: DraggedWorkoutRef.self) { items, _ in
            guard let ref = items.first else { return false }
            onMoveWorkout(ref, dayAbbrev)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private var restPlaceholder: some View {
        Text("Rest")
            .font(.caption)
            .foregroundColor(Color(.tertiaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }
}

// MARK: - Workout Calendar Card

private struct WorkoutCalendarCard: View {
    let workout: DayWorkout

    var body: some View {
        HStack(spacing: 0) {
            // Colored left border
            Rectangle()
                .fill(AppTheme.sportColor(for: workout.type))
                .frame(width: 3)
                .cornerRadius(1.5)

            HStack(spacing: 6) {
                // Type and duration
                VStack(alignment: .leading, spacing: 1) {
                    Text(workout.type)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if workout.duration != "-" {
                        Text(workout.duration)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)

                // Schedule icon
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sportColor(for: workout.type).opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(AppTheme.sportColor(for: workout.type).opacity(0.08))
        .cornerRadius(6)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add Workout Sheet

private struct AddWorkoutSheet: View {
    let day: String
    let weekNumber: Int
    let onAdd: (DayWorkout) -> Void
    let onCancel: () -> Void

    private struct WorkoutOption {
        let type: String
        let label: String
        let icon: String
        let color: Color
    }

    private let options: [WorkoutOption] = [
        WorkoutOption(type: "Swim",     label: "Swim",     icon: "figure.open.water.swim", color: AppTheme.swim),
        WorkoutOption(type: "Bike",     label: "Bike",     icon: "bicycle",                color: AppTheme.bike),
        WorkoutOption(type: "Run",      label: "Run",      icon: "figure.run",             color: AppTheme.run),
        WorkoutOption(type: "Brick",    label: "Brick",    icon: "arrow.triangle.2.circlepath", color: AppTheme.brick),
        WorkoutOption(type: "Strength", label: "Strength", icon: "dumbbell.fill",          color: AppTheme.strength),
        WorkoutOption(type: "Rest",     label: "Rest",     icon: "moon.zzz.fill",          color: AppTheme.rest),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options, id: \.type) { option in
                        Button {
                            let newWorkout = DayWorkout(
                                day: day,
                                type: option.type,
                                duration: "45min",
                                zone: "Z2",
                                status: nil,
                                nutritionTarget: nil,
                                notes: nil
                            )
                            onAdd(newWorkout)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(option.color.opacity(0.15))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: option.icon)
                                        .font(.system(size: 17))
                                        .foregroundColor(option.color)
                                }

                                Text(option.label)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Add workout to \(day), Week \(weekNumber)")
                }
            }
            .navigationTitle("Add Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Toast View

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.label).opacity(0.85))
            .cornerRadius(20)
            .shadow(radius: 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TrainingCalendarView()
            .environmentObject(TrainingPlanManager())
    }
}
