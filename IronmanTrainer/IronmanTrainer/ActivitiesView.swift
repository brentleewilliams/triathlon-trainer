import SwiftUI
import HealthKit

// MARK: - Activity Filter Type

enum ActivityFilterType: String, CaseIterable {
    case all      = "All"
    case swim     = "Swim"
    case bike     = "Bike"
    case run      = "Run"
    case strength = "Strength"

    func matches(_ type: HKWorkoutActivityType) -> Bool {
        switch self {
        case .all:      return true
        case .swim:     return type == .swimming
        case .bike:     return type == .cycling
        case .run:      return type == .running
        case .strength: return [.functionalStrengthTraining,
                                .traditionalStrengthTraining,
                                .coreTraining].contains(type)
        }
    }

    var themeColor: Color {
        switch self {
        case .all:      return .primary
        case .swim:     return AppTheme.swim
        case .bike:     return AppTheme.bike
        case .run:      return AppTheme.run
        case .strength: return AppTheme.strength
        }
    }
}

// MARK: - Activity Type Label (file-level, shared with CompletedWorkoutDetailView)

func activityTypeLabel(_ type: HKWorkoutActivityType) -> String {
    switch type {
    case .swimming:                    return "Swim"
    case .cycling:                     return "Bike"
    case .running:                     return "Run"
    case .functionalStrengthTraining,
         .traditionalStrengthTraining,
         .coreTraining:                return "Strength"
    default:                           return "Workout"
    }
}

// MARK: - Duration Formatting (file-level)

func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = Int(seconds)
    let h = totalSeconds / 3600
    let m = (totalSeconds % 3600) / 60
    let s = totalSeconds % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Grouped Month Model

private struct MonthGroup: Identifiable {
    let id: String          // "2026-04"
    let month: Int
    let year: Int
    let workouts: [HKWorkout]

    var title: String {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        var comps = DateComponents()
        comps.month = month
        comps.year = year
        comps.day = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        return df.string(from: date)
    }

    var totalDistance: Double {
        workouts.reduce(0) { $0 + ($1.totalDistance?.doubleValue(for: .mile()) ?? 0) }
    }

    var totalSeconds: TimeInterval {
        workouts.reduce(0) { $0 + $1.duration }
    }

    var formattedTotalTime: String {
        formatDuration(totalSeconds)
    }
}

// MARK: - ActivitiesView

struct ActivitiesView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var trainingPlan: TrainingPlanManager

    @State private var filterType: ActivityFilterType = .all
    @State private var selectedWorkout: HKWorkout? = nil

    // MARK: Computed — filtered & grouped workouts

    private var filteredWorkouts: [HKWorkout] {
        healthKit.workouts.filter { filterType.matches($0.workoutActivityType) }
    }

    private var monthGroups: [MonthGroup] {
        let cal = Calendar.current
        var groups: [String: [HKWorkout]] = [:]
        for w in filteredWorkouts {
            let comps = cal.dateComponents([.year, .month], from: w.startDate)
            let key = "\(comps.year ?? 0)-\(String(format: "%02d", comps.month ?? 0))"
            groups[key, default: []].append(w)
        }
        return groups
            .map { key, workouts in
                let parts = key.split(separator: "-")
                let year  = Int(parts[0]) ?? 0
                let month = Int(parts[1]) ?? 0
                return MonthGroup(id: key, month: month, year: year,
                                  workouts: workouts.sorted { $0.startDate > $1.startDate })
            }
            .sorted { $0.year != $1.year ? $0.year > $1.year : $0.month > $1.month }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top nav
                PersistentTopNavView(
                    title: "Workouts",
                    onProfile:  { NotificationCenter.default.post(name: .openSettings, object: nil) },
                    onChat:     { NotificationCenter.default.post(name: .navigateToChat, object: nil) },
                    onCalendar: { NotificationCenter.default.post(name: .openCalendar, object: nil) },
                    onAddWorkout: { NotificationCenter.default.post(name: .openLogWorkout, object: nil) }
                )

                // Filter chips
                filterChipsRow

                // Workout list
                if filteredWorkouts.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(monthGroups) { group in
                                monthSection(group)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(item: $selectedWorkout) { workout in
                CompletedWorkoutDetailView(workout: workout)
                    .environmentObject(healthKit)
            }
        }
    }

    // MARK: Sub-views

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFilterType.allCases, id: \.self) { type in
                    filterChip(type)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    private func filterChip(_ type: ActivityFilterType) -> some View {
        let isSelected = filterType == type
        return Button {
            filterType = type
        } label: {
            Text(type.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected
                    ? (type == .all ? Color(.systemBackground) : .white)
                    : (type == .all ? .primary : type.themeColor))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? (type == .all ? Color(.label) : type.themeColor)
                              : Color.clear)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected
                                      ? Color.clear
                                      : (type == .all ? Color(.systemGray3) : type.themeColor.opacity(0.5)),
                                      lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func monthSection(_ group: MonthGroup) -> some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text(group.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(group.workouts.count) \(group.workouts.count == 1 ? "activity" : "activities")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        if group.totalDistance > 0 {
                            Text(String(format: "%.1f mi", group.totalDistance))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("·")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        Text(group.formattedTotalTime)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)

            // Workout rows
            ForEach(group.workouts, id: \.uuid) { workout in
                WorkoutRow(workout: workout) {
                    selectedWorkout = workout
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "figure.run.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(filterType == .all
                 ? "No workouts found"
                 : "No \(filterType.rawValue) workouts found")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Sync your workouts from HealthKit")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Workout Row Card

private struct WorkoutRow: View {
    let workout: HKWorkout
    let onTap: () -> Void

    private var label: String { activityTypeLabel(workout.workoutActivityType) }
    private var borderColor: Color { AppTheme.sportColor(for: label) }

    private var distanceMiles: Double {
        workout.totalDistance?.doubleValue(for: .mile()) ?? 0
    }

    private var dateString: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy · h:mm a"
        return df.string(from: workout.startDate)
    }

    private var durationString: String {
        formatDuration(workout.duration)
    }

    // Returns a pace/speed string appropriate for the sport, or nil for strength
    private var paceString: String? {
        switch workout.workoutActivityType {
        case .running:
            guard distanceMiles > 0 else { return nil }
            let secPerMile = workout.duration / distanceMiles
            let m = Int(secPerMile) / 60
            let s = Int(secPerMile) % 60
            return String(format: "%d:%02d /mi", m, s)
        case .cycling:
            guard workout.duration > 0, distanceMiles > 0 else { return nil }
            let mph = distanceMiles / (workout.duration / 3600)
            return String(format: "%.1f mph", mph)
        case .swimming:
            // Pace per 100yd — convert miles to yards (1 mi = 1760 yd)
            let yards = distanceMiles * 1760
            guard yards > 0 else { return nil }
            let secPer100yd = workout.duration / (yards / 100)
            let m = Int(secPer100yd) / 60
            let s = Int(secPer100yd) % 60
            return String(format: "%d:%02d /100yd", m, s)
        default:
            return nil
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Left sport-color border
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 4)
                    .cornerRadius(2, corners: [.topLeft, .bottomLeft])

                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(dateString)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        if distanceMiles > 0.01 {
                            statPill(String(format: "%.2f mi", distanceMiles))
                        }
                        statPill(durationString)
                        if let pace = paceString {
                            statPill(pace)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 12)
            }
            .background(Color(.systemBackground))
            .cornerRadius(AppTheme.cardCornerRadius)
            .shadow(color: .black.opacity(AppTheme.cardShadowOpacity),
                    radius: AppTheme.cardShadowRadius, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func statPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
    }
}

// MARK: - Corner radius helper

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

private struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
