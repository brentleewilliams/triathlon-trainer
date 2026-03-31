import SwiftUI

// MARK: - Week Navigation Header (Shared)
struct WeekNavigationHeader: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @Binding var selectedWeek: Int
    var completionText: String? = nil
    @State private var showWeekPicker = false

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    var formattedDateRange: String {
        guard let week = currentWeek else { return "" }
        let startStr = Formatters.shortDate.string(from: week.startDate)
        let endStr = Formatters.shortDate.string(from: week.endDate)
        return "\(startStr) - \(endStr), 2026"
    }

    var isCurrentWeek: Bool {
        guard let week = currentWeek else { return false }
        let today = Date()
        let endOfWeek = Calendar.current.date(byAdding: .day, value: 1, to: week.endDate) ?? week.endDate
        return today >= week.startDate && today < endOfWeek
    }

    var body: some View {
        Button(action: { showWeekPicker = true }) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Week \(selectedWeek) - \(currentWeek?.phase ?? "")")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        if isCurrentWeek {
                            Text("Current")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(formattedDateRange)
                            .font(.caption)
                            .foregroundColor(.gray)

                        if let completion = completionText {
                            Text("(\(completion))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width < -30 && selectedWeek < 17 {
                        withAnimation { selectedWeek += 1 }
                    } else if value.translation.width > 30 && selectedWeek > 1 {
                        withAnimation { selectedWeek -= 1 }
                    }
                }
        )
        .sheet(isPresented: $showWeekPicker) {
            WeekPickerSheet(selectedWeek: $selectedWeek, trainingPlan: trainingPlan)
        }
    }
}

// MARK: - Week Picker Sheet
struct WeekPickerSheet: View {
    @Binding var selectedWeek: Int
    let trainingPlan: TrainingPlanManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(trainingPlan.weeks.sorted(by: { $0.weekNumber < $1.weekNumber }), id: \.weekNumber) { week in
                    Button(action: {
                        withAnimation { selectedWeek = week.weekNumber }
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Week \(week.weekNumber)")
                                        .fontWeight(.semibold)
                                    Text("- \(week.phase)")
                                        .foregroundColor(.secondary)
                                }

                                let startStr = Formatters.shortDate.string(from: week.startDate)
                                let endStr = Formatters.shortDate.string(from: week.endDate)
                                Text("\(startStr) - \(endStr)")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                let workoutCount = week.workouts.filter { $0.type != "Rest" }.count
                                Text("\(workoutCount) workouts")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if week.weekNumber == selectedWeek {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }

                            if isCurrentWeek(week) {
                                Text("Current")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(week.weekNumber == selectedWeek ? Color.blue.opacity(0.08) : Color.clear)
                }
            }
            .navigationTitle("Select Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isCurrentWeek(_ week: TrainingWeek) -> Bool {
        let today = Date()
        return today >= week.startDate && today <= Calendar.current.date(byAdding: .day, value: 1, to: week.endDate)!
    }
}
