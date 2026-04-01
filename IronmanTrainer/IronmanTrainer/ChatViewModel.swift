import Foundation
import HealthKit

// MARK: - Chat ViewModel
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), isUser: Bool, text: String, timestamp: Date = Date()) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
    }
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var error: String?

    private let claudeService = ClaudeService.shared
    private(set) var lastSwap: SwapCommand? {
        didSet { saveLastSwap() }
    }
    var trainingPlan: TrainingPlanManager?
    var healthKit: HealthKitManager?

    init(skipHistory: Bool = false) {
        if !skipHistory {
            loadChatHistory()
            loadLastSwap()
        }
    }

    private func saveLastSwap() {
        if let swap = lastSwap, let data = try? JSONEncoder().encode(swap) {
            UserDefaults.standard.set(data, forKey: "last_swap_command")
        } else {
            UserDefaults.standard.removeObject(forKey: "last_swap_command")
        }
    }

    private func loadLastSwap() {
        guard let data = UserDefaults.standard.data(forKey: "last_swap_command"),
              let swap = try? JSONDecoder().decode(SwapCommand.self, from: data) else { return }
        lastSwap = swap
    }

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        await MainActor.run {
            messages.append(ChatMessage(isUser: true, text: text))
            saveChatHistory()
            isLoading = true
            error = nil
        }

        do {
            let context = getContextForClaude()
            let history = getWorkoutHistoryForClaude()

            // Include reschedule context for plan adaptation
            let updatedContext = context + "\n\n" + buildRescheduleContext()

            // Build conversation history from prior messages (exclude the message we just added)
            let priorMessages = messages.dropLast()
            let conversationHistory: [[String: String]] = priorMessages.map { msg in
                ["role": msg.isUser ? "user" : "assistant", "content": msg.text]
            }

            let response = try await claudeService.sendMessage(userMessage: text, trainingContext: updatedContext, workoutHistory: history, zoneBoundaries: healthKit?.zoneBoundaries, conversationHistory: conversationHistory)

            await MainActor.run {
                messages.append(ChatMessage(isUser: false, text: response))
                saveChatHistory()

                // Check for undo swap command
                if response.contains("[UNDO_SWAP]"), let prev = lastSwap {
                    let undoCommand = SwapCommand(weekNumber: prev.weekNumber, fromDay: prev.toDay, toDay: prev.fromDay)
                    if let result = executeSwap(undoCommand) {
                        lastSwap = nil
                        let confirmMsg = ChatMessage(isUser: false, text: "\u{21A9}\u{FE0F} Undid previous swap: \(result). Your training plan has been restored!")
                        messages.append(confirmMsg)
                        saveChatHistory()
                    }
                }
                // Check for swap command in response and execute it
                else if let command = parseSwapCommand(from: response),
                   let result = executeSwap(command) {
                    lastSwap = command
                    let confirmMsg = ChatMessage(isUser: false, text: "\u{2705} \(result). Your training plan has been updated!")
                    messages.append(confirmMsg)
                    saveChatHistory()
                }

                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func buildRescheduleContext() -> String {
        guard let trainingPlan = trainingPlan else { return "" }

        let allWeeks = trainingPlan.weeks.map { week in
            let workouts = week.workouts.map { "\($0.day): \($0.type) \($0.duration) \($0.zone)" }.joined(separator: ", ")
            return "Week \(week.weekNumber) (\(week.phase)): \(workouts)"
        }.joined(separator: "\n")

        return """
        FULL 17-WEEK TRAINING PLAN FOR RESCHEDULING:
        \(allWeeks)

        Current date: \(Formatters.fullDate.string(from: Date()))

        RESCHEDULE GUIDELINES:
        - BUILD PHASE (weeks 5-9): Prioritize long/key workouts, drop short secondary runs
        - TAPER (weeks 10-12): Reduce volume but keep pace work
        - RACE PREP (weeks 13-15): Keep race-pace sessions, drop easy work
        - Only reschedule FUTURE workouts, not past ones
        - When the user asks to swap days, confirm which days and week, then INCLUDE this exact tag in your response:
          [SWAP_DAYS:week=NUMBER:from=DAY:to=DAY]
          Example: [SWAP_DAYS:week=2:from=Tue:to=Wed]
          Valid days: Mon, Tue, Wed, Thu, Fri, Sat, Sun
        - The app will automatically perform the swap when it sees this tag
        - You can include the tag along with your coaching explanation
        - If the user asks to undo the last swap, include this exact tag: [UNDO_SWAP]
        \(lastSwap != nil ? "- LAST SWAP: Swapped \(lastSwap!.fromDay) and \(lastSwap!.toDay) in week \(lastSwap!.weekNumber). User can ask to undo this." : "- No recent swap to undo.")
        """
    }

    func parseSwapCommand(from response: String) -> SwapCommand? {
        // Parse [SWAP_DAYS:week=2:from=Tue:to=Wed] tag from Claude response
        guard let regex = try? NSRegularExpression(
            pattern: "\\[SWAP_DAYS:week=(\\d+):from=(Mon|Tue|Wed|Thu|Fri|Sat|Sun):to=(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\]",
            options: []
        ) else { return nil }

        let range = NSRange(response.startIndex..., in: response)
        guard let match = regex.firstMatch(in: response, options: [], range: range) else { return nil }

        guard let weekRange = Range(match.range(at: 1), in: response),
              let fromRange = Range(match.range(at: 2), in: response),
              let toRange = Range(match.range(at: 3), in: response),
              let weekNumber = Int(response[weekRange]) else { return nil }

        return SwapCommand(
            weekNumber: weekNumber,
            fromDay: String(response[fromRange]),
            toDay: String(response[toRange])
        )
    }

    func executeSwap(_ command: SwapCommand) -> String? {
        guard let trainingPlan = trainingPlan else { return nil }

        var updatedWeeks = trainingPlan.weeks
        guard let weekIdx = updatedWeeks.firstIndex(where: { $0.weekNumber == command.weekNumber }) else {
            return nil
        }

        var newWorkouts = updatedWeeks[weekIdx].workouts
        let fromWorkouts = newWorkouts.filter { $0.day == command.fromDay }
        let toWorkouts = newWorkouts.filter { $0.day == command.toDay }

        guard !fromWorkouts.isEmpty && !toWorkouts.isEmpty else { return nil }

        // Swap days
        newWorkouts = newWorkouts.map { workout in
            if workout.day == command.fromDay {
                return DayWorkout(day: command.toDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget)
            } else if workout.day == command.toDay {
                return DayWorkout(day: command.fromDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget)
            }
            return workout
        }

        updatedWeeks[weekIdx] = TrainingWeek(
            weekNumber: updatedWeeks[weekIdx].weekNumber,
            phase: updatedWeeks[weekIdx].phase,
            startDate: updatedWeeks[weekIdx].startDate,
            endDate: updatedWeeks[weekIdx].endDate,
            workouts: newWorkouts
        )

        trainingPlan.applyRescheduledPlan(
            updatedWeeks,
            source: "chat",
            description: "Swapped \(command.fromDay) and \(command.toDay) in week \(command.weekNumber)"
        )

        return "Swapped \(command.fromDay) and \(command.toDay) in week \(command.weekNumber)"
    }

    func saveChatHistory() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(messages) {
            UserDefaults.standard.set(data, forKey: "coaching_chat_history")
        }
    }

    func loadChatHistory() {
        guard let data = UserDefaults.standard.data(forKey: "coaching_chat_history") else { return }
        let decoder = JSONDecoder()
        if let saved = try? decoder.decode([ChatMessage].self, from: data) {
            messages = saved
        }
    }

    func clearChatHistory() {
        messages = []
        UserDefaults.standard.removeObject(forKey: "coaching_chat_history")
    }

    private func getContextForClaude() -> String {
        guard let plan = trainingPlan else {
            return "No training plan available"
        }

        let currentWeek = plan.getWeek(plan.currentWeekNumber) ?? plan.getWeek(1)

        let today = Date()
        var context = "TODAY'S DATE: \(Formatters.fullDate.string(from: today)) (\(Formatters.dayOfWeek.string(from: today)))\n\n"
        context += "CURRENT WEEK PLAN:\n"

        if let week = currentWeek {
            context += "Week \(week.weekNumber) (\(Formatters.fullDate.string(from: week.startDate)) - \(Formatters.fullDate.string(from: week.endDate))): \(week.phase)\n\n"

            let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            for day in dayOrder {
                let dayWorkouts = week.workouts.filter { $0.day == day }
                if !dayWorkouts.isEmpty {
                    let workoutTexts = dayWorkouts.map { workout in
                        var text = "\(workout.type) (\(workout.duration) \u{2022} \(workout.zone))"
                        if let nutrition = workout.nutritionTarget {
                            text += " [Nutrition: \(nutrition)]"
                        }
                        return text
                    }.joined(separator: " + ")
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
        // Look back to Feb 1, 2026 for full training context
        let historyStart = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? Date()

        // --- Accumulate summary stats ---
        var swimCount = 0, bikeCount = 0, runCount = 0
        var totalSwimYards = 0.0, totalBikeHours = 0.0, totalRunMinutes = 0.0
        var totalCalories = 0.0

        for workout in healthKit.workouts {
            guard workout.startDate >= historyStart else { continue }

            let durationHours = workout.duration / 3600
            let durationMinutes = workout.duration / 60

            if let energy = workout.totalEnergyBurned {
                totalCalories += energy.doubleValue(for: .kilocalorie())
            }

            switch workout.workoutActivityType {
            case .swimming:
                swimCount += 1
                if let distance = workout.totalDistance {
                    totalSwimYards += distance.doubleValue(for: .yard())
                } else {
                    totalSwimYards += durationHours * 1800
                }
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

        // --- Side-by-side planned vs actual for last 4 weeks ---
        var history = "WORKOUT REVIEW (Last 4 Weeks):\n\n"

        let today = Date()
        let currentWeek = trainingPlan?.currentWeekNumber ?? 1

        // Map workout type strings to HKWorkoutActivityType for matching
        func hkActivityType(for planType: String) -> HKWorkoutActivityType? {
            let lower = planType.lowercased()
            if lower.contains("swim") { return .swimming }
            if lower.contains("bike") || lower.contains("cycling") { return .cycling }
            if lower.contains("run") { return .running }
            return nil
        }

        // Emoji for planned workout type
        func typeEmoji(for planType: String) -> String {
            let lower = planType.lowercased()
            if lower.contains("swim") { return "\u{1F3CA}" } // swimmer emoji
            if lower.contains("bike") || lower.contains("cycling") { return "\u{1F6B4}" } // cyclist emoji
            if lower.contains("run") { return "\u{1F3C3}" } // runner emoji
            return ""
        }

        // HKWorkout type display name
        func hkTypeName(_ type: HKWorkoutActivityType) -> String {
            switch type {
            case .swimming: return "Swimming"
            case .cycling: return "Cycling"
            case .running: return "Running"
            default: return "Other"
            }
        }

        // Format an actual HKWorkout line
        func formatActual(_ workout: HKWorkout) -> String {
            let durationMins = Int(workout.duration / 60)
            var parts = ["\(hkTypeName(workout.workoutActivityType)) \(durationMins)min"]

            if let distance = workout.totalDistance {
                let miles = distance.doubleValue(for: .mile())
                if workout.workoutActivityType == .swimming {
                    let yards = distance.doubleValue(for: .yard())
                    if yards > 10 { parts.append("\(Int(yards))yd") }
                } else if miles > 0.1 {
                    parts.append("\(String(format: "%.1f", miles))mi")
                }
            }

            if let energy = workout.totalEnergyBurned {
                parts.append("\(Int(energy.doubleValue(for: .kilocalorie())))kcal")
            }

            // Append zone breakdown if cached (last 14 days)
            if let zones = healthKit.workoutZones[workout.uuid] {
                let significant = zones.filter { $0.value >= 5.0 }
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key): \(Int(round($0.value)))%" }
                if !significant.isEmpty {
                    parts.append("(\(significant.joined(separator: ", ")))")
                }
            }

            return parts.joined(separator: ", ")
        }

        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        // Determine which training weeks fall within the last 4 weeks
        let startWeek = max(1, currentWeek - 3)
        let endWeek = min(currentWeek, 17)

        for weekNum in startWeek...endWeek {
            guard let week = trainingPlan?.getWeek(weekNum) else { continue }

            let weekStartStr = Formatters.shortDate.string(from: week.startDate)
            let weekEndStr = Formatters.shortDate.string(from: week.endDate)
            history += "WEEK \(weekNum) (\(weekStartStr)-\(weekEndStr)):\n"

            for day in dayOrder {
                let dayWorkouts = week.workouts.filter { $0.day == day }
                guard !dayWorkouts.isEmpty else { continue }

                // Calculate the actual date for this day of the week
                let dayIndex = dayOrder.firstIndex(of: day) ?? 0
                // week.startDate is Monday (index 0)
                guard let dayDate = calendar.date(byAdding: .day, value: dayIndex, to: week.startDate) else { continue }

                // Skip future days -- no actual data expected
                if dayDate > today { continue }

                let dayStart = calendar.startOfDay(for: dayDate)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

                for planned in dayWorkouts {
                    // Skip rest days from comparison
                    if planned.type.lowercased() == "rest" { continue }

                    let plannedStr = "\(typeEmoji(for: planned.type)) \(planned.type) \(planned.duration) \(planned.zone)"

                    // Find matching HealthKit workout: same calendar day + same activity type
                    let matchingActivity = hkActivityType(for: planned.type)
                    let matchedWorkout = healthKit.workouts.first { hkWorkout in
                        let hkDay = calendar.startOfDay(for: hkWorkout.startDate)
                        return hkDay >= dayStart && hkDay < dayEnd && hkWorkout.workoutActivityType == matchingActivity
                    }

                    if let actual = matchedWorkout {
                        history += "- \(day): Planned: \(plannedStr) | Actual: \(formatActual(actual))\n"
                    } else {
                        history += "- \(day): Planned: \(plannedStr) | Actual: \u{26A0}\u{FE0F} MISSED\n"
                    }
                }
            }

            history += "\n"
        }

        // --- Training summary ---
        history += "TRAINING SUMMARY (since Feb 1, 2026):\n"
        history += "- Swimming: \(swimCount) sessions (\(Int(totalSwimYards)) total yards)\n"
        history += "- Cycling: \(bikeCount) sessions (\(String(format: "%.1f", totalBikeHours)) total hours)\n"
        history += "- Running: \(runCount) sessions (\(Int(totalRunMinutes)) total minutes)\n"
        history += "- Total Calories: \(Int(totalCalories)) kcal\n"
        history += "- TOTAL: \(healthKit.workouts.filter { $0.startDate >= historyStart }.count) completed workouts"

        return history
    }
}
