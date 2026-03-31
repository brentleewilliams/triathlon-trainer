import SwiftUI

// MARK: - Plan View
struct PlanView: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager

    var body: some View {
        NavigationStack {
            VStack {
                Text("17-Week Training Plan")
                    .font(.headline)
                    .padding()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(1...17, id: \.self) { week in
                            WeekCard(weekNumber: week, isCurrentWeek: week == trainingPlan.currentWeekNumber)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct WeekCard: View {
    let weekNumber: Int
    let isCurrentWeek: Bool
    @EnvironmentObject var trainingPlan: TrainingPlanManager

    var phase: String {
        trainingPlan.getWeek(weekNumber)?.phase ?? ""
    }

    var startDate: String {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 23
        let start = Calendar.current.date(from: components) ?? Date()
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .weekOfYear, value: weekNumber - 1, to: start)!
        return Formatters.shortDate.string(from: weekStart)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week \(weekNumber)")
                    .fontWeight(.bold)

                Text(phase)
                    .font(.caption)
                    .foregroundColor(.gray)

                Text(startDate)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            if isCurrentWeek {
                Text("NOW")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
        }
        .padding(12)
        .background(isCurrentWeek ? Color(.systemGray5) : Color(.systemBackground))
        .border(isCurrentWeek ? Color.green : Color.clear, width: isCurrentWeek ? 2 : 0)
        .cornerRadius(8)
    }
}
