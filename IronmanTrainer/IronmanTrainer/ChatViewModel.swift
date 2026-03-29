import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    let timestamp: Date = Date()
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading = false
    @Published var error: String?

    private let claudeService = ClaudeService.shared
    var trainingPlan: TrainingPlanManager?
    var healthKit: HealthKitManager?

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        await MainActor.run {
            inputText = ""
            messages.append(ChatMessage(isUser: true, text: text))
            isLoading = true
            error = nil
        }

        do {
            let context = getContextForClaude()
            let history = getWorkoutHistoryForClaude()
            let response = try await claudeService.sendMessage(userMessage: text, trainingContext: context, workoutHistory: history)

            await MainActor.run {
                messages.append(ChatMessage(isUser: false, text: response))
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func getContextForClaude() -> String {
        guard let plan = trainingPlan else {
            return "No training plan available"
        }

        let currentWeek = plan.getWeek(plan.currentWeekNumber) ?? plan.getWeek(1)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone.current

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        dayFormatter.timeZone = TimeZone.current

        var context = "TODAY'S DATE: \(formatter.string(from: Date())) (\(dayFormatter.string(from: Date())))\n\n"
        context += "CURRENT WEEK PLAN:\n"

        if let week = currentWeek {
            context += "Week \(week.weekNumber) (\(formatter.string(from: week.startDate)) - \(formatter.string(from: week.endDate))): \(week.phase)\n\n"

            let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            for day in dayOrder {
                let dayWorkouts = week.workouts.filter { $0.day == day }
                if !dayWorkouts.isEmpty {
                    let workoutTexts = dayWorkouts.map { "\($0.type) (\($0.duration) • \($0.zone))" }.joined(separator: " + ")
                    context += "- \(day): \(workoutTexts)\n"
                }
            }
        }

        return context
    }

    private func getWorkoutHistoryForClaude() -> String {
        guard let healthKit = healthKit else {
            return "No workout history available"
        }

        let calendar = Calendar.current
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) ?? Date()

        var swimCount = 0
        var bikeCount = 0
        var runCount = 0
        var totalSwimYards = 0.0
        var totalBikeHours = 0.0
        var totalRunMinutes = 0.0

        for workout in healthKit.workouts {
            guard workout.startDate >= fourWeeksAgo else { continue }

            let durationHours = workout.duration / 3600
            let durationMinutes = workout.duration / 60

            switch workout.workoutActivityType {
            case .swimming:
                swimCount += 1
                totalSwimYards += durationHours * 1800
            case .cycling:
                bikeCount += 1
                totalBikeHours += durationHours
            case .running:
                runCount += 1
                totalRunMinutes += durationMinutes
            default:
                break
            }
        }

        var history = "LAST 4 WEEKS COMPLETED WORKOUTS:\n"
        history += "- Swimming: \(swimCount) sessions (\(Int(totalSwimYards)) total yards)\n"
        history += "- Cycling: \(bikeCount) sessions (\(String(format: "%.1f", totalBikeHours)) total hours)\n"
        history += "- Running: \(runCount) sessions (\(Int(totalRunMinutes)) total minutes)\n\n"
        history += "COMPLIANCE: \(healthKit.workouts.filter { $0.startDate >= fourWeeksAgo }.count) completed workouts in last 4 weeks"

        return history
    }
}
