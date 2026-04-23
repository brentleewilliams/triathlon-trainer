import SwiftUI

struct WeekdayWorkoutRow: View {
    let day: String
    let type: String
    let duration: String
    let zone: String
    var isCompleted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(day)
                .fontWeight(.bold)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(type)
                    .fontWeight(.semibold)
                Text("\(duration) \u{2022} \(zone)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Day Groups View
struct DayGroupsView: View {
    let dayGroups: [(day: String, workouts: [DayWorkout])]
    let week: TrainingWeek?
    @ObservedObject var healthKit: HealthKitManager
    let parent: HomeView
    @Binding var draggedWorkout: DayWorkout?
    @Binding var draggedFromDay: String?
    let selectedWeek: Int

    var body: some View {
        if let week = week, !dayGroups.isEmpty {
            VStack(spacing: 12) {
                ForEach(dayGroups, id: \.day) { dayGroup in
                    DayRowView(
                        dayGroup: dayGroup,
                        weekStartDate: week.startDate,
                        parent: parent,
                        draggedWorkout: $draggedWorkout,
                        draggedFromDay: $draggedFromDay,
                        week: week,
                        healthKit: healthKit,
                        selectedWeek: selectedWeek
                    )
                }
            }
            .padding()
        } else {
            VStack(spacing: 12) {
                Text("No workouts planned for this week")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
    }
}

// MARK: - Day Row View
struct DayRowView: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView
    @Binding var draggedWorkout: DayWorkout?
    @Binding var draggedFromDay: String?
    let week: TrainingWeek?
    @ObservedObject var healthKit: HealthKitManager
    let selectedWeek: Int

    var isRestDay: Bool {
        dayGroup.workouts.allSatisfy { $0.type.contains("Rest") }
    }

    var isSecondaryRaceDay: Bool {
        dayGroup.workouts.allSatisfy { $0.status == "secondary_race" }
    }

    var isPreOnboardingDay: Bool {
        dayGroup.workouts.allSatisfy { $0.status == "pre_onboarding" }
    }

    var body: some View {
        if isPreOnboardingDay {
            PreOnboardingRow(dayGroup: dayGroup, weekStartDate: weekStartDate)
        } else if isSecondaryRaceDay {
            SecondaryRaceRow(dayGroup: dayGroup, weekStartDate: weekStartDate)
        } else if isRestDay {
            RestDayRow(dayGroup: dayGroup, weekStartDate: weekStartDate, parent: parent, week: week, healthKit: healthKit)
        } else {
            WorkoutDayRows(
                dayGroup: dayGroup,
                weekStartDate: weekStartDate,
                parent: parent,
                week: week,
                draggedWorkout: $draggedWorkout,
                draggedFromDay: $draggedFromDay,
                hideHeader: false,
                selectedWeek: selectedWeek
            )
        }
    }
}

// MARK: - Secondary Race Row
struct SecondaryRaceRow: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var dayDate: String {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: mondayOfWeek(weekStartDate)) ?? weekStartDate
        return Formatters.monthDay.string(from: date)
    }

    var body: some View {
        let race = dayGroup.workouts.first

        VStack(alignment: .leading, spacing: 8) {
            // Day header
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(dayGroup.day)
                        .fontWeight(.bold)
                    Text(dayDate)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(width: 50)
                Spacer()
            }
            .padding(.horizontal, 12)

            // Race card
            HStack(spacing: 14) {
                Text("\u{1F3C5}")
                    .font(.title)

                VStack(alignment: .leading, spacing: 3) {
                    Text(race?.type.replacingOccurrences(of: "\u{1F3C5} ", with: "") ?? "Race")
                        .font(.subheadline.weight(.semibold))
                    Text(race?.duration ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let raceNotes = race?.notes, !raceNotes.isEmpty {
                        Text(raceNotes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "flag.checkered")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.orange.opacity(0.12), Color.yellow.opacity(0.08)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Rest Day Row
// MARK: - Pre-Onboarding Row
struct PreOnboardingRow: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var dayDate: String {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: mondayOfWeek(weekStartDate)) ?? weekStartDate
        return Formatters.monthDay.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(dayGroup.day)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Text(dayDate)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(width: 50)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.secondary)
                Text("Before you started the plan")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(12)
            .background(Color(.systemGray6).opacity(0.6))
            .cornerRadius(8)
        }
    }
}

struct RestDayRow: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView
    let week: TrainingWeek?
    @ObservedObject var healthKit: HealthKitManager

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var dayDate: String {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: mondayOfWeek(weekStartDate)) ?? weekStartDate
        return Formatters.monthDay.string(from: date)
    }

    var body: some View {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: mondayOfWeek(weekStartDate)) ?? weekStartDate

        let calendar = Calendar.current
        let today = Date()
        let daysUntil = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        let showWeather = daysUntil < 0 || daysUntil <= 7

        let unplannedCount: Int = {
            guard daysUntil <= 0 else { return 0 }
            return findUnplannedWorkouts(
                on: date,
                plannedWorkouts: dayGroup.workouts,
                hkWorkouts: healthKit.workouts
            ).count
        }()

        return VStack(alignment: .leading, spacing: 8) {
            // Day header
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(dayGroup.day)
                        .fontWeight(.bold)
                    Text(dayDate)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(width: 50)

                if showWeather {
                    let weather = WeatherForecast.forecast(for: date)
                    HStack(spacing: 4) {
                        Text(weather.icon)
                            .font(.title3)
                        Text("\(weather.highTemp)\u{00B0}")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if unplannedCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("\(unplannedCount) bonus")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Rest card — tappable to show detail (including any unplanned workouts)
            NavigationLink(destination: DayDetailView(
                day: dayGroup.workouts[0],
                week: week ?? TrainingWeek(weekNumber: 1, phase: "", startDate: Date(), endDate: Date(), workouts: []),
                healthKit: healthKit
            )) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("\u{1F6CC}")
                            .font(.title3)
                        Text("Rest")
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }

                    Spacer()

                    if parent.isRestDayCompleted(for: dayGroup.workouts[0]) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        }
    }
}
