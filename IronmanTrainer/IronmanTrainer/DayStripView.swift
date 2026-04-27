import SwiftUI

// MARK: - Per-week data passed in by the parent

struct WeekStripData: Equatable {
    let mondayDate: Date
    /// 7 entries, Mon..Sun. workouts may be empty for rest/missing days.
    let workoutsByDay: [DayStripWorkouts]

    static func == (lhs: WeekStripData, rhs: WeekStripData) -> Bool {
        lhs.mondayDate == rhs.mondayDate
    }
}

struct DayStripWorkouts: Equatable {
    let day: String
    let workouts: [DayWorkout]
}

// MARK: - DayStripView
//
// Runna-style horizontal week strip:
//   • MON–SUN column labels are fixed at the top.
//   • Date rows live inside a paged horizontal ScrollView, one page per week.
//   • Drag follows the finger (you see adjacent week's dates revealing under
//     the same MON–SUN labels), then snaps to the nearest week on release.
//   • selectedWeek binding is wired to scrollPosition so the gesture is the
//     source of truth — no manual offset/threshold math.

struct DayStripView: View {
    @Binding var selectedDayIndex: Int
    @Binding var selectedWeek: Int

    /// Inclusive range of valid week numbers (e.g. -8...17 for 8 weeks of
    /// pre-plan history plus a 17-week plan).
    let weekRange: ClosedRange<Int>

    /// Data lookup for any week number in `weekRange`.
    let weekData: (Int) -> WeekStripData

    /// Used to render the "today" ring on the matching date cell, regardless
    /// of which week is currently scrolled into view.
    let today: Date

    var onTapDay: (Int) -> Void = { _ in }

    private let dayAbbrevs = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    /// scrollPosition expects an Optional binding; bridge to our non-optional
    /// selectedWeek and clamp to the valid range so a stray nil doesn't strand
    /// us off the strip.
    private var scrollWeekBinding: Binding<Int?> {
        Binding(
            get: { selectedWeek },
            set: { newVal in
                guard let v = newVal else { return }
                let clamped = min(max(v, weekRange.lowerBound), weekRange.upperBound)
                if clamped != selectedWeek { selectedWeek = clamped }
            }
        )
    }

    /// Floating "Today" pill — shown when the user has scrolled away from
    /// today's day. Tapping returns to today.
    var todayPill: some View {
        let cal = Calendar.current
        let todayMonday = mondayOfWeek(today)
        let displayedMonday = weekData(selectedWeek).mondayDate
        let onTodayWeek = cal.isDate(todayMonday, inSameDayAs: displayedMonday)
        let todayIdx = todayDayIndex(of: today, calendar: cal)
        let onTodayDay = onTodayWeek && selectedDayIndex == todayIdx

        return Group {
            if !onTodayDay {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedWeek = weekNumberForDate(today)
                        selectedDayIndex = todayIdx
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
        VStack(spacing: 6) {
            // Fixed MON–SUN labels — never scroll, never reflow during drag.
            HStack(spacing: 0) {
                ForEach(dayAbbrevs, id: \.self) { abbrev in
                    Text(abbrev)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(.systemGray))
                        .frame(maxWidth: .infinity)
                }
            }

            // Paged scroll of week pages. iOS 17 paging behavior gives us
            // drag-follow + snap on release without managing offsets manually.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(weekRange), id: \.self) { weekNum in
                        weekPage(weekNum: weekNum)
                            .containerRelativeFrame(.horizontal)
                            .id(weekNum)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: scrollWeekBinding)
            .frame(height: 56)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Per-week page

    @ViewBuilder
    private func weekPage(weekNum: Int) -> some View {
        let data = weekData(weekNum)
        let cal = Calendar.current
        let isCurrentWeek = weekNum == selectedWeek

        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { idx in
                let date = cal.date(byAdding: .day, value: idx, to: data.mondayDate) ?? data.mondayDate
                let workouts = data.workoutsByDay[safe: idx]?.workouts ?? []
                let isSelected = isCurrentWeek && idx == selectedDayIndex
                let isToday = cal.isDate(date, inSameDayAs: today)

                Button {
                    // Tapping a day always selects that day. If it's on a
                    // non-current page, also pull that week into focus.
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if !isCurrentWeek { selectedWeek = weekNum }
                        onTapDay(idx)
                    }
                } label: {
                    dayCell(date: date, workouts: workouts, isSelected: isSelected, isToday: isToday)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func dayCell(date: Date, workouts: [DayWorkout], isSelected: Bool, isToday: Bool) -> some View {
        VStack(spacing: 4) {
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

                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? Color(.systemBackground) : .primary)
                    .monospacedDigit()
            }
            .frame(width: 32, height: 32)

            workoutDots(workouts: workouts)
                .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func workoutDots(workouts: [DayWorkout]) -> some View {
        let real = workouts.filter { !$0.type.lowercased().contains("rest") }
        HStack(spacing: 3) {
            ForEach(real.prefix(3)) { workout in
                if workout.type.lowercased().contains("brick") {
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

    // MARK: - Helpers

    private func mondayOfWeek(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    private func todayDayIndex(of date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date) // 1=Sun, 2=Mon, ..., 7=Sat
        return (weekday + 5) % 7
    }

    /// Walks `weekRange` looking for the week whose Monday matches the Monday
    /// of `date`. Falls back to `selectedWeek` when nothing matches (e.g. the
    /// date is outside the range entirely).
    private func weekNumberForDate(_ date: Date) -> Int {
        let target = mondayOfWeek(date)
        for n in weekRange {
            if Calendar.current.isDate(weekData(n).mondayDate, inSameDayAs: target) {
                return n
            }
        }
        return selectedWeek
    }
}

// MARK: - Array safe-subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
