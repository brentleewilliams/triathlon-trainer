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

    private let coachingService = LLMProxyService.shared
    var trainingPlan: TrainingPlanManager?
    var healthKit: HealthKitManager?

    init(skipHistory: Bool = false) {
        if !skipHistory {
            loadChatHistory()
        }
    }

    // MARK: - Plan Change Execution

    func executePlanChanges(_ proposal: PlanChangeProposal) {
        guard let trainingPlan = trainingPlan else { return }

        var updatedWeeks = trainingPlan.weeks
        var applied = 0
        var skipped: [String] = []

        for change in proposal.changes {
            guard let weekIdx = updatedWeeks.firstIndex(where: { $0.weekNumber == change.week }) else {
                skipped.append("Week \(change.week) not found")
                continue
            }

            var workouts = updatedWeeks[weekIdx].workouts

            switch change.action {
            case .add:
                guard let day = change.day, let type = change.type else {
                    skipped.append("Missing day/type for add in week \(change.week)")
                    continue
                }
                let newWorkout = DayWorkout(
                    day: day,
                    type: type,
                    duration: change.duration ?? "-",
                    zone: change.zone ?? "-",
                    status: nil,
                    nutritionTarget: nil,
                    notes: change.notes
                )
                workouts.append(newWorkout)
                applied += 1

            case .drop:
                guard let day = change.day else {
                    skipped.append("Missing day for drop in week \(change.week)")
                    continue
                }
                // Remove ALL workouts on this day — empty day becomes Rest
                let before = workouts.count
                workouts.removeAll { $0.day == day }
                if workouts.count < before {
                    applied += 1
                } else {
                    skipped.append("No workouts on \(day) in week \(change.week) to drop")
                }

            case .swap:
                guard let fromDay = change.fromDay, let toDay = change.toDay else {
                    skipped.append("Missing from_day/to_day for swap in week \(change.week)")
                    continue
                }
                // Move all workouts from fromDay to toDay and vice versa
                workouts = workouts.map { workout in
                    if workout.day == fromDay {
                        return DayWorkout(day: toDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget, notes: workout.notes)
                    } else if workout.day == toDay {
                        return DayWorkout(day: fromDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget, notes: workout.notes)
                    }
                    return workout
                }
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

        var confirmText = "\u{2705} Applied \(applied) change\(applied == 1 ? "" : "s") to your training plan.\n\(proposal.summary)"
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

        let traceUserId = await MainActor.run { AuthService.shared.currentUserID }
        let traceContext = LangSmithTracer.shared.startCoachingTrace(
            userId: traceUserId,
            userMessage: hasText ? text : "Sent a photo"
        )

        do {
            let context = getContextForClaude()
            let history = getWorkoutHistoryForClaude()

            // Include reschedule context (plan data + tool instructions)
            let updatedContext = context + "\n\n" + buildRescheduleContext()

            // Build conversation history from prior messages (exclude the message we just added)
            let priorMessages = messages.dropLast()
            let conversationHistory: [[String: Any]] = priorMessages.map { msg in
                return ["role": msg.isUser ? "user" : "assistant", "content": msg.text]
            }

            let coachingResponse = try await coachingService.sendCoachingMessage(
                userMessage: hasText ? text : "What do you see in this image?",
                trainingContext: updatedContext,
                workoutHistory: history,
                zoneBoundaries: healthKit?.zoneBoundaries,
                conversationHistory: conversationHistory,
                imageData: imageData,
                traceContext: traceContext
            )
            LangSmithTracer.shared.endCoachingTrace(
                traceContext,
                response: coachingResponse.text,
                error: nil,
                toolCallMade: coachingResponse.proposedChanges != nil
            )

            await MainActor.run {
                messages.append(ChatMessage(isUser: false, text: coachingResponse.text))
                saveChatHistory()
                if let proposal = coachingResponse.proposedChanges {
                    pendingProposal = proposal
                }
                isLoading = false
            }
        } catch {
            LangSmithTracer.shared.endCoachingTrace(traceContext, response: nil, error: error.localizedDescription)
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
        ====== PLAN CHANGE RULES (FOLLOW THESE EXACTLY) ======

        When the user wants any workout change: call propose_plan_change IMMEDIATELY.
        Do NOT say "let me know if you want to apply this" or ask for confirmation — the app shows a confirmation dialog automatically.
        Do NOT describe the change in text and wait. Call the tool first, then explain if needed.
        If the user says "yes", "yea", "sure", "do it", or confirms a previously described change — call the tool NOW with those changes.
        Only target future workouts. Changes are additive — only touch what the user explicitly mentioned.

        ====== TRAINING PLAN DATA ======

        FULL 17-WEEK TRAINING PLAN:
        \(allWeeks)

        Current date: \(Formatters.fullDate.string(from: Date()))

        \(PrepRacesManager.shared.contextString().map { "\n\($0)\n" } ?? "")

        RESCHEDULE NOTES:
        - Dropping all workouts on a day leaves it as Rest.
        - PREP RACE DAYS: Never schedule training on prep race day or the day before.
        """
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

                // Collect all HK workouts for this day
                let dayHKWorkouts = healthKit.workouts.filter { hkWorkout in
                    let hkDay = calendar.startOfDay(for: hkWorkout.startDate)
                    return hkDay >= dayStart && hkDay < dayEnd
                }
                var matchedHKWorkoutIDs = Set<UUID>()

                let isRestDay = dayWorkouts.allSatisfy { $0.type.lowercased() == "rest" }

                for planned in dayWorkouts {
                    // Skip rest days from comparison
                    if planned.type.lowercased() == "rest" { continue }

                    let plannedStr = "\(typeEmoji(for: planned.type)) \(planned.type) \(planned.duration) \(planned.zone)"

                    // Find matching HealthKit workout: same calendar day + same activity type
                    let matchingActivity = hkActivityType(for: planned.type)
                    let matchedWorkout = dayHKWorkouts.first { hkWorkout in
                        !matchedHKWorkoutIDs.contains(hkWorkout.uuid) &&
                        hkWorkout.workoutActivityType == matchingActivity
                    }

                    if let actual = matchedWorkout {
                        matchedHKWorkoutIDs.insert(actual.uuid)
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

                // Report unmatched HK workouts (extra workouts not in the plan)
                let unmatchedWorkouts = dayHKWorkouts.filter { !matchedHKWorkoutIDs.contains($0.uuid) }
                for extra in unmatchedWorkouts {
                    let label = isRestDay ? "REST DAY" : "EXTRA"
                    history += "- \(day): \u{1F4AA} \(label) — Actual: \(formatActual(extra))\n"
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
