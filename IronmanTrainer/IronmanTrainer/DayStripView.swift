import SwiftUI

struct DayStripView: View {
    @Binding var selectedDayIndex: Int
    let weekWorkouts: [(day: String, workouts: [DayWorkout])]
    let weekStartDate: Date
    var todayDayIndex: Int
    var onTapDay: (Int) -> Void

    private let dayAbbrevs = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    // Expose for the caller to position (e.g. pinned above tab bar)
    var todayPill: some View {
        Group {
            if selectedDayIndex != todayDayIndex {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onTapDay(todayDayIndex)
                    }
                } label: {
                    Text("Today")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color.primary)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let date = dayDate(for: index)
                let workouts = workouts(for: index)
                let isSelected = selectedDayIndex == index
                let isToday = todayDayIndex == index

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onTapDay(index)
                    }
                } label: {
                    VStack(spacing: 4) {
                        // Day abbreviation
                        Text(dayAbbrevs[index])
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(.systemGray))

                        // Date number with selection ring/fill
                        ZStack {
                            if isSelected {
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 32, height: 32)
                            } else if isToday {
                                Circle()
                                    .stroke(Color.primary.opacity(0.35), lineWidth: 1.5)
                                    .frame(width: 32, height: 32)
                            }

                            Text("\(dayNumber(from: date))")
                                .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? Color(.systemBackground) : .primary)
                                .monospacedDigit()
                        }
                        .frame(width: 32, height: 32)

                        // Workout dots
                        workoutDots(workouts: workouts)
                            .frame(height: 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width < -20 && selectedDayIndex < 6 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onTapDay(selectedDayIndex + 1)
                        }
                    } else if value.translation.width > 20 && selectedDayIndex > 0 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onTapDay(selectedDayIndex - 1)
                        }
                    }
                }
        )
    }

    // MARK: - Private helpers

    private func dayDate(for index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: weekStartDate) ?? weekStartDate
    }

    private func dayNumber(from date: Date) -> Int {
        Calendar.current.component(.day, from: date)
    }

    private func workouts(for index: Int) -> [DayWorkout] {
        guard index < weekWorkouts.count else { return [] }
        return weekWorkouts[index].workouts.filter { !$0.type.lowercased().contains("rest") }
    }

    @ViewBuilder
    private func workoutDots(workouts: [DayWorkout]) -> some View {
        HStack(spacing: 3) {
            ForEach(workouts.prefix(3)) { workout in
                if workout.type.lowercased().contains("brick") {
                    // Brick = small square to distinguish from circles
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppTheme.sportColor(for: workout.type))
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(AppTheme.sportColor(for: workout.type))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}
