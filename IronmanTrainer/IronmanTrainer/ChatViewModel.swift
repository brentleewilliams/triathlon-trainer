import Foundation
import HealthKit

// MARK: - Chat ViewModel
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let text: String
    let timestamp: Date
    let imageData: Data?

    init(id: UUID = UUID(), isUser: Bool, text: String, timestamp: Date = Date(), imageData: Data? = nil) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.imageData = imageData
    }
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var pendingProposal: PlanChangeProposal?

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

    // MARK: - Plan Change Parsing

    func parsePlanChanges(from response: String) -> PlanChangeProposal? {
        guard let startRange = response.range(of: "[PLAN_CHANGES]"),
              let endRange = response.range(of: "[/PLAN_CHANGES]") else { return nil }

        let jsonStart = startRange.upperBound
        let jsonEnd = endRange.lowerBound
        guard jsonStart < jsonEnd else { return nil }

        let jsonString = String(response[jsonStart..<jsonEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonString.data(using: .utf8) else { return nil }

        return try? JSONDecoder().decode(PlanChangeProposal.self, from: data)
    }

    func stripPlanChangesBlock(from response: String) -> String {
        var result = response

        // Remove [PLAN_CHANGES]...[/PLAN_CHANGES] block (or everything after [PLAN_CHANGES] if closing tag is missing/truncated)
        if let startRange = result.range(of: "[PLAN_CHANGES]") {
            if let endRange = result.range(of: "[/PLAN_CHANGES]") {
                result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                // Closing tag missing (likely truncated response) — strip everything from [PLAN_CHANGES] onward
                result.removeSubrange(startRange.lowerBound..<result.endIndex)
            }
        }

        // Remove stray JSON change objects the LLM may echo outside the tags
        if let regex = try? NSRegularExpression(
            pattern: #"\{"action"\s*:\s*"(?:add|drop|modify)"[^}]*\}\s*,?"#,
            options: []
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Remove stray JSON wrapper fragments ({"id":...,"summary":...,"changes":[ etc.)
        if let regex = try? NSRegularExpression(
            pattern: #"\{["\s]*id["\s]*:.*?"changes"\s*:\s*\["#,
            options: [.dotMatchesLineSeparators]
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Remove stray closing brackets/braces from truncated JSON
        if let regex = try? NSRegularExpression(pattern: #"^\s*[\]\}]\s*$"#, options: [.anchorsMatchLines]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Clean up leftover blank lines
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func executePlanChanges(_ proposal: PlanChangeProposal) {
        guard let trainingPlan = trainingPlan else { return }

        var updatedWeeks = trainingPlan.weeks
        var applied = 0
        var skipped: [String] = []

        for change in proposal.changes {
            guard let weekIdx = updatedWeeks.firstIndex(where: { $0.weekNumber == change.week }) else {
                skipped.append("Week \(change.week) not found for \(change.action.rawValue) \(change.type ?? "")")
                continue
            }

            var workouts = updatedWeeks[weekIdx].workouts

            switch change.action {
            case .add:
                guard let type = change.type else {
                    skipped.append("Missing type for add in week \(change.week)")
                    continue
                }
                let newWorkout = DayWorkout(
                    day: change.day,
                    type: type,
                    duration: change.duration ?? "-",
                    zone: change.zone ?? "-",
                    status: nil,
                    nutritionTarget: change.nutritionTarget,
                    notes: change.notes
                )
                workouts.append(newWorkout)
                applied += 1

            case .drop:
                guard let type = change.type else {
                    skipped.append("Missing type for drop in week \(change.week)")
                    continue
                }
                let before = workouts.count
                workouts.removeAll { $0.day == change.day && $0.type == type }
                if workouts.count < before {
                    applied += 1
                } else {
                    skipped.append("No \(type) on \(change.day) in week \(change.week) to drop")
                }

            case .modify:
                guard let type = change.type,
                      let field = change.field,
                      let toValue = change.to else {
                    skipped.append("Missing type/field/to for modify in week \(change.week)")
                    continue
                }
                guard let workoutIdx = workouts.firstIndex(where: { $0.day == change.day && $0.type == type }) else {
                    skipped.append("No \(type) on \(change.day) in week \(change.week) to modify")
                    continue
                }
                let old = workouts[workoutIdx]
                let modified: DayWorkout
                switch field {
                case "duration":
                    modified = DayWorkout(day: old.day, type: old.type, duration: toValue, zone: old.zone, status: old.status, nutritionTarget: old.nutritionTarget, notes: old.notes)
                case "zone":
                    modified = DayWorkout(day: old.day, type: old.type, duration: old.duration, zone: toValue, status: old.status, nutritionTarget: old.nutritionTarget, notes: old.notes)
                case "type":
                    modified = DayWorkout(day: old.day, type: toValue, duration: old.duration, zone: old.zone, status: old.status, nutritionTarget: old.nutritionTarget, notes: old.notes)
                case "notes":
                    modified = DayWorkout(day: old.day, type: old.type, duration: old.duration, zone: old.zone, status: old.status, nutritionTarget: old.nutritionTarget, notes: toValue)
                default:
                    skipped.append("Unknown field '\(field)' for modify in week \(change.week)")
                    continue
                }
                workouts[workoutIdx] = modified
                applied += 1
            }

            updatedWeeks[weekIdx] = TrainingWeek(
                weekNumber: updatedWeeks[weekIdx].weekNumber,
                phase: updatedWeeks[weekIdx].phase,
                startDate: updatedWeeks[weekIdx].startDate,
                endDate: updatedWeeks[weekIdx].endDate,
                workouts: workouts
            )
        }

        if applied > 0 {
            trainingPlan.applyRescheduledPlan(updatedWeeks, source: "chat", description: proposal.summary)
        }

        var confirmText = "\u{2705} Applied \(applied) change\(applied == 1 ? "" : "s") to your training plan."
        if !skipped.isEmpty {
            confirmText += "\n\u{26A0}\u{FE0F} Skipped \(skipped.count): \(skipped.joined(separator: "; "))"
        }
        messages.append(ChatMessage(isUser: false, text: confirmText))
        saveChatHistory()
        pendingProposal = nil
    }

    func dismissPlanChanges() {
        pendingProposal = nil
        let feedbackMsg = "I dismissed the proposed changes. Can you revise the plan?"
        messages.append(ChatMessage(isUser: true, text: feedbackMsg))
        saveChatHistory()
        Task {
            await sendMessage(feedbackMsg)
        }
    }

    func sendMessage(_ text: String, imageData: Data? = nil) async {
        let hasText = !text.trimmingCharacters(in: .whitespaces).isEmpty
        guard hasText || imageData != nil else { return }

        await MainActor.run {
            messages.append(ChatMessage(isUser: true, text: hasText ? text : "Sent a photo", imageData: imageData))
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
            let conversationHistory: [[String: Any]] = priorMessages.map { msg in
                // For history, only send text (don't re-send images)
                return ["role": msg.isUser ? "user" : "assistant", "content": msg.text]
            }

            let response = try await claudeService.sendMessage(userMessage: hasText ? text : "What do you see in this image?", trainingContext: updatedContext, workoutHistory: history, zoneBoundaries: healthKit?.zoneBoundaries, conversationHistory: conversationHistory, imageData: imageData)

            await MainActor.run {
                // Check for plan changes proposal first
                if response.contains("[PLAN_CHANGES]") {
                    let displayText = stripPlanChangesBlock(from: response)
                    messages.append(ChatMessage(isUser: false, text: displayText))
                    saveChatHistory()
                    pendingProposal = parsePlanChanges(from: response)
                } else {
                    // Strip any stray JSON even when no [PLAN_CHANGES] tag is present
                    let cleanResponse = stripPlanChangesBlock(from: response)
                    messages.append(ChatMessage(isUser: false, text: cleanResponse))
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

        \(PrepRacesManager.shared.contextString().map { "\n\($0)\n" } ?? "")

        RESCHEDULE GUIDELINES:
        - PREP RACE DAYS: Never schedule training on prep race day or the day before (mark as Rest)
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

        FOR CHANGES BEYOND SIMPLE DAY SWAPS (adding, dropping, or modifying workouts):
        Include a JSON block between [PLAN_CHANGES] and [/PLAN_CHANGES] tags.
        Format:
        [PLAN_CHANGES]
        {"id":"<generate-a-uuid>","summary":"<1-line description>","changes":[
          {"action":"add","week":5,"day":"Tue","type":"🏃 Interval Run","duration":"45min","zone":"Z4","notes":"6x800m intervals"},
          {"action":"drop","week":5,"day":"Wed","type":"🏃 Run"},
          {"action":"modify","week":6,"day":"Thu","type":"🚴 Bike","field":"duration","from":"1:00","to":"1:15"}
        ]}
        [/PLAN_CHANGES]
        Rules:
        - add: requires type, duration, zone. notes/nutritionTarget optional.
        - drop: requires type to identify which workout to remove.
        - modify: requires type (to find workout), field, from, to. field can be "duration", "zone", "type", or "notes".
        - Simple same-week day swaps → use [SWAP_DAYS] (auto-applied).
        - Everything else (add/drop/modify, multi-week changes) → use [PLAN_CHANGES] (requires user confirmation).
        - Always explain your reasoning in natural language OUTSIDE the tags.
        - IMPORTANT: Do NOT echo or repeat the raw JSON change objects in your natural language text. The app will render them in a nice UI card. Just describe the changes conversationally (e.g. "I'd suggest adding a strength session on Thursday and swapping your Tuesday bike for swim intervals").
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
                return DayWorkout(day: command.toDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget, notes: workout.notes)
            } else if workout.day == command.toDay {
                return DayWorkout(day: command.fromDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget, notes: workout.notes)
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

    private static let maxPersistedMessages = 50

    func saveChatHistory() {
        // Strip image data from persisted messages to avoid UserDefaults bloat
        let toSave = messages.suffix(Self.maxPersistedMessages).map { msg in
            ChatMessage(id: msg.id, isUser: msg.isUser, text: msg.text, timestamp: msg.timestamp, imageData: nil)
        }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(toSave) {
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

        // Include prep races context
        if let prepContext = PrepRacesManager.shared.contextString() {
            context += "\n\(prepContext)\n"
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
        var swimCount = 0, bikeCount = 0, runCount = 0, strengthCount = 0, hikeCount = 0
        var totalSwimYards = 0.0, totalBikeHours = 0.0, totalRunMinutes = 0.0
        var totalStrengthMinutes = 0.0, totalHikeMinutes = 0.0
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
            case .traditionalStrengthTraining, .functionalStrengthTraining:
                strengthCount += 1
                totalStrengthMinutes += durationMinutes
            case .hiking:
                hikeCount += 1
                totalHikeMinutes += durationMinutes
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
            if lower.contains("strength") { return .traditionalStrengthTraining }
            if lower.contains("hike") || lower.contains("hiking") { return .hiking }
            return nil
        }

        // Emoji for planned workout type
        func typeEmoji(for planType: String) -> String {
            let lower = planType.lowercased()
            if lower.contains("swim") { return "\u{1F3CA}" } // swimmer emoji
            if lower.contains("bike") || lower.contains("cycling") { return "\u{1F6B4}" } // cyclist emoji
            if lower.contains("run") { return "\u{1F3C3}" } // runner emoji
            if lower.contains("strength") { return "\u{1F3CB}" } // weight lifter emoji
            if lower.contains("hike") || lower.contains("hiking") { return "\u{1F97E}" } // hiking boot emoji
            return ""
        }

        // HKWorkout type display name
        func hkTypeName(_ type: HKWorkoutActivityType) -> String {
            switch type {
            case .swimming: return "Swimming"
            case .cycling: return "Cycling"
            case .running: return "Running"
            case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
            case .hiking: return "Hiking"
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

                    // Compliance marker
                    let compliance = calculateCompliance(for: planned, on: dayDate, from: healthKit.workouts, today: today)
                    let complianceEmoji: String
                    switch compliance.level {
                    case .green: complianceEmoji = "\u{2705}"  // ✅
                    case .over: complianceEmoji = "\u{26A0}\u{FE0F} OVER"  // ⚠️ overtraining
                    case .under: complianceEmoji = "\u{26A0}\u{FE0F} UNDER"  // ⚠️ undertraining
                    case .missed: complianceEmoji = "\u{274C}"  // ❌ missed
                    case .future: complianceEmoji = "\u{23F3}"  // ⏳
                    }

                    if let actual = matchedWorkout {
                        history += "- \(day): \(complianceEmoji) Planned: \(plannedStr) | Actual: \(formatActual(actual))\n"
                    } else {
                        history += "- \(day): \(complianceEmoji) Planned: \(plannedStr) | Actual: \u{26A0}\u{FE0F} MISSED\n"
                    }
                }
            }

            // Weekly compliance percentage
            if let pct = calculateWeekCompliance(week: week, hkWorkouts: healthKit.workouts, today: today) {
                history += "  WEEK COMPLIANCE: \(Int(pct))%\n"
            }
            history += "\n"
        }

        // --- Training summary ---
        history += "TRAINING SUMMARY (since Feb 1, 2026):\n"
        history += "- Swimming: \(swimCount) sessions (\(Int(totalSwimYards)) total yards)\n"
        history += "- Cycling: \(bikeCount) sessions (\(String(format: "%.1f", totalBikeHours)) total hours)\n"
        history += "- Running: \(runCount) sessions (\(Int(totalRunMinutes)) total minutes)\n"
        if strengthCount > 0 {
            history += "- Strength: \(strengthCount) sessions (\(Int(totalStrengthMinutes)) total minutes)\n"
        }
        if hikeCount > 0 {
            history += "- Hiking: \(hikeCount) sessions (\(Int(totalHikeMinutes)) total minutes)\n"
        }
        history += "- Total Calories: \(Int(totalCalories)) kcal\n"
        history += "- TOTAL: \(healthKit.workouts.filter { $0.startDate >= historyStart }.count) completed workouts"

        return history
    }
}
