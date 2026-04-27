import Foundation
import HealthKit

// MARK: - Chat ViewModel

/// Classifies a ChatMessage so the UI (and analytics) can filter between the
/// main coaching chat and the Morning Check-In thread. Persisted with the
/// message so the filter survives across launches.
enum ChatMessageKind: String, Codable {
    case general
    case checkIn = "check_in"
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let text: String
    let timestamp: Date
    let imageData: Data?
    let kind: ChatMessageKind

    init(id: UUID = UUID(), isUser: Bool, text: String, timestamp: Date = Date(), imageData: Data? = nil, kind: ChatMessageKind = .general) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.imageData = imageData
        self.kind = kind
    }

    // Back-compat decoder: older persisted messages have no `kind` field.
    enum CodingKeys: String, CodingKey { case id, isUser, text, timestamp, imageData, kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.isUser = try c.decode(Bool.self, forKey: .isUser)
        self.text = try c.decode(String.self, forKey: .text)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        self.kind = (try? c.decodeIfPresent(ChatMessageKind.self, forKey: .kind)) ?? .general
    }
}

// MARK: - Plan Negotiation State

enum NegotiationPhase: Equatable {
    case idle
    case reviewing(PlanChangeProposal)
    case modifying(PlanChangeProposal)
    case applying

    static func == (lhs: NegotiationPhase, rhs: NegotiationPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.applying, .applying): return true
        case (.reviewing(let a), .reviewing(let b)): return a.id == b.id
        case (.modifying(let a), .modifying(let b)): return a.id == b.id
        default: return false
        }
    }
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var negotiationState: NegotiationPhase = .idle

    /// Backward-compatible accessor for the pending proposal.
    var pendingProposal: PlanChangeProposal? {
        switch negotiationState {
        case .reviewing(let p), .modifying(let p): return p
        default: return nil
        }
    }

    var isNegotiating: Bool {
        if case .modifying = negotiationState { return true }
        return false
    }

    var coachingService: CoachingServiceProtocol = LLMProxyService.shared
    var trainingPlan: TrainingPlanManager?
    var healthKit: HealthKitManager?
    var trainingStatus: TrainingStatusService?

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

            case .replace:
                guard let day = change.day, let fromType = change.fromType, let toType = change.type else {
                    skipped.append("Missing day/from_type/type for replace in week \(change.week)")
                    continue
                }
                // Find workout by keyword match on fromType (handles "Run", "run", "🏃 Run" etc.)
                if let idx = workouts.firstIndex(where: { $0.day == day && workoutTypeMatches($0.type, keyword: fromType) }) {
                    let old = workouts[idx]
                    workouts[idx] = DayWorkout(
                        day: day,
                        type: toType,
                        duration: change.duration ?? old.duration,
                        zone: change.zone ?? old.zone,
                        status: nil,
                        nutritionTarget: nil,
                        notes: change.notes ?? old.notes
                    )
                    applied += 1
                } else {
                    skipped.append("No \(fromType) workout on \(day) in week \(change.week)")
                }
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
        negotiationState = .idle
    }

    /// Returns true if `workoutType` (e.g. "🏃 Run") matches a user/LLM keyword (e.g. "run", "running", "Run").
    /// Used by `.replace` to find a specific workout on a day that has multiple workouts.
    func workoutTypeMatches(_ workoutType: String, keyword: String) -> Bool {
        let haystack = workoutType.lowercased()
        let needle = keyword.lowercased()
        if haystack.contains(needle) || needle.contains(haystack) { return true }
        // Keyword aliases
        let aliases: [String: [String]] = [
            "run": ["run", "running", "jog", "🏃"],
            "bike": ["bike", "cycling", "cycle", "ride", "🚴"],
            "swim": ["swim", "swimming", "pool", "🏊"],
            "brick": ["brick", "🧱"],
            "strength": ["strength", "gym", "lift", "weights", "🏋"],
            "yoga": ["yoga", "stretch", "🧘"],
            "rest": ["rest"],
        ]
        for (_, words) in aliases {
            if words.contains(where: { haystack.contains($0) }) &&
               words.contains(where: { needle.contains($0) }) {
                return true
            }
        }
        return false
    }

    func dismissPlanChanges() {
        negotiationState = .idle
        let feedbackMsg = "I dismissed the proposed changes. Can you revise the plan?"
        messages.append(ChatMessage(isUser: true, text: feedbackMsg))
        saveChatHistory()
        Task {
            await sendMessage(feedbackMsg)
        }
    }

    // MARK: - Plan Negotiation Actions

    func acceptAllChanges(_ proposal: PlanChangeProposal) {
        negotiationState = .applying
        executePlanChanges(proposal)
    }

    func rejectProposal() {
        negotiationState = .idle
        let feedbackMsg = "I rejected the proposed changes. Can you suggest alternatives?"
        messages.append(ChatMessage(isUser: true, text: feedbackMsg))
        saveChatHistory()
        Task {
            await sendMessage(feedbackMsg)
        }
    }

    func startModification() {
        guard case .reviewing(let proposal) = negotiationState else { return }
        negotiationState = .modifying(proposal)
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
            let context = await getContextForClaude()
            let history = getWorkoutHistoryForClaude()

            // Detect wide intent before building context
            let isWide = isWidePlanRequest(text)
            let planScope = isWide ? "wide" : "local"

            // Include reschedule context (plan data + tool instructions)
            var updatedContext = context + "\n\n" + buildRescheduleContext()

            // Append compact full-plan summary only for wide requests
            if isWide {
                let summary = buildFullPlanSummary()
                if !summary.isEmpty { updatedContext += "\n\n" + summary }
            }

            // Inject Race Course Intelligence context (phase-dependent).
            let courseContext = await MainActor.run { buildCourseContext() }
            if !courseContext.isEmpty {
                updatedContext += "\n\n" + courseContext
                // Append the threshold-capture tool instructions so Claude
                // knows how to emit a capture when the athlete shares numbers.
                updatedContext += "\n\n" + Self.thresholdToolInstructions
            }

            // Build conversation history from prior messages (exclude the message we just added)
            let priorMessages = messages.dropLast()
            let conversationHistory: [[String: Any]] = priorMessages.map { msg in
                return ["role": msg.isUser ? "user" : "assistant", "content": msg.text]
            }

            var baseMessage = hasText ? text : "What do you see in this image?"

            // In modification mode, prepend the current proposal so Claude knows what to revise
            if case .modifying(let currentProposal) = await MainActor.run(body: { negotiationState }) {
                let changesJSON = currentProposal.changes.map { c in
                    "action=\(c.action), week=\(c.week), day=\(c.day ?? "-")"
                }.joined(separator: "; ")
                baseMessage = "[User is modifying a pending proposal: \"\(currentProposal.summary)\" with changes: \(changesJSON)]\n\nUser's revision request: \(baseMessage)"
                await MainActor.run { negotiationState = .idle }
            }

            let coachingResponse = try await coachingService.sendCoachingMessage(
                userMessage: baseMessage,
                trainingContext: updatedContext,
                workoutHistory: history,
                zoneBoundaries: healthKit?.zoneBoundaries,
                conversationHistory: conversationHistory,
                imageData: imageData,
                planScope: planScope,
                traceContext: traceContext
            )
            LangSmithTracer.shared.endCoachingTrace(
                traceContext,
                response: coachingResponse.text,
                error: nil,
                toolCallMade: coachingResponse.proposedChanges != nil
            )

            await MainActor.run {
                // Opportunistic threshold capture (§4.4.5). Scan the raw
                // response for a `capture_threshold` payload before the
                // text is displayed / persisted.
                applyThresholdCaptureIfPresent(in: coachingResponse.text)

                // Only append an assistant bubble if there's real text.
                // When the model responds with only a tool call (e.g. after a
                // "yes, apply" confirmation), accumulated text is empty and we
                // would otherwise render a blank bubble.
                let trimmed = coachingResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    messages.append(ChatMessage(isUser: false, text: coachingResponse.text))
                    saveChatHistory()
                }
                if let proposal = coachingResponse.proposedChanges {
                    negotiationState = .reviewing(proposal)
                }
                isLoading = false
            }
        } catch {
            func isRetryable(_ e: Error) -> Bool {
                if let svcError = e as? ClaudeServiceError {
                    return svcError == .serverError || svcError == .networkError
                }
                return (e as NSError).domain == NSURLErrorDomain
            }

            guard isRetryable(error) else {
                LangSmithTracer.shared.endCoachingTrace(traceContext, response: nil, error: error.localizedDescription)
                await MainActor.run { self.error = error.localizedDescription; isLoading = false }
                return
            }

            // Retry once after 1s — rebuilds context and repeats the API call without re-adding the user message.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                let context = await getContextForClaude()
                let history = getWorkoutHistoryForClaude()
                let isWide = isWidePlanRequest(text)
                var updatedContext = context + "\n\n" + buildRescheduleContext()
                if isWide {
                    let summary = buildFullPlanSummary()
                    if !summary.isEmpty { updatedContext += "\n\n" + summary }
                }
                let courseContext = await MainActor.run { buildCourseContext() }
                if !courseContext.isEmpty {
                    updatedContext += "\n\n" + courseContext
                    updatedContext += "\n\n" + Self.thresholdToolInstructions
                }
                let priorMessages = messages.dropLast()
                let conversationHistory: [[String: Any]] = priorMessages.map { msg in
                    ["role": msg.isUser ? "user" : "assistant", "content": msg.text]
                }
                let baseMessage = hasText ? text : "What do you see in this image?"
                let retryResponse = try await coachingService.sendCoachingMessage(
                    userMessage: baseMessage,
                    trainingContext: updatedContext,
                    workoutHistory: history,
                    zoneBoundaries: healthKit?.zoneBoundaries,
                    conversationHistory: conversationHistory,
                    imageData: imageData,
                    planScope: isWide ? "wide" : "local",
                    traceContext: traceContext
                )
                LangSmithTracer.shared.endCoachingTrace(traceContext, response: retryResponse.text, error: nil, toolCallMade: retryResponse.proposedChanges != nil)
                await MainActor.run {
                    applyThresholdCaptureIfPresent(in: retryResponse.text)
                    let trimmed = retryResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        messages.append(ChatMessage(isUser: false, text: retryResponse.text))
                        saveChatHistory()
                    }
                    if let proposal = retryResponse.proposedChanges { negotiationState = .reviewing(proposal) }
                    isLoading = false
                }
            } catch {
                LangSmithTracer.shared.endCoachingTrace(traceContext, response: nil, error: error.localizedDescription)
                await MainActor.run { self.error = error.localizedDescription; isLoading = false }
            }
        }
    }

    // MARK: - Course Context (§4.5)

    /// Builds the phase-dependent Race Course Intelligence block for the
    /// system prompt. Returns an empty string if no profile is loaded.
    /// Phase tiers (always / +5wk / +2wk) per §4.5.
    @MainActor
    func buildCourseContext() -> String {
        let service = RaceCourseService.shared
        let profile = service.currentProfile ?? service.loadDefaultProfile()
        guard let profile = profile else { return "" }
        let weeksToRace = computeWeeksToRace(profile: profile)
        let body = service.getPhaseContext(weeksToRace: weeksToRace, profile: profile)
        guard !body.isEmpty else { return "" }
        return "====== RACE COURSE INTELLIGENCE ======\n\n\(body)"
    }

    @MainActor
    private func computeWeeksToRace(profile: RaceCourseProfile) -> Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: profile.raceDate).day ?? 0
        if days <= 0 { return 0 }
        return max(0, Int((Double(days) / 7.0).rounded(.up)))
    }

    // MARK: - Threshold Capture (§4.4.5)

    /// Parses Claude's response text for a `capture_threshold` tool-call
    /// payload and persists it on the user profile. Also returns the
    /// captured thresholds for tests / UI confirmation.
    ///
    /// Two accepted sentinel forms (either is tolerated so the server
    /// side doesn't have to know about this yet):
    ///   `[CAPTURE_THRESHOLD:{...}]`
    ///   `[TOOL_CALL:capture_threshold:{...}]`
    @discardableResult
    func applyThresholdCaptureIfPresent(in text: String) -> PerformanceThresholds? {
        guard let payload = extractThresholdPayload(from: text) else { return nil }
        return PerformanceThresholdsStore.merge(
            ftpWatts: payload.ftpWatts,
            thresholdPaceSecondsPerMile: payload.thresholdPaceSecondsPerMile,
            cssSecondsPer100yd: payload.cssSecondsPer100yd
        )
    }

    /// Raw parse of the `capture_threshold` payload. Exposed (internal) so
    /// tests can assert parsing independently of the persistence layer.
    struct CaptureThresholdPayload: Equatable {
        var ftpWatts: Int?
        var thresholdPaceSecondsPerMile: Int?
        var cssSecondsPer100yd: Int?
    }

    func extractThresholdPayload(from text: String) -> CaptureThresholdPayload? {
        let markers = ["[CAPTURE_THRESHOLD:", "[TOOL_CALL:capture_threshold:"]
        for marker in markers {
            guard let range = text.range(of: marker) else { continue }
            let remaining = text[range.upperBound...]
            // Find matching closing ']' — payload is a JSON object.
            guard let closingBrace = remaining.firstIndex(of: "}") else { continue }
            let jsonEnd = remaining.index(after: closingBrace)
            let jsonStr = String(remaining[..<jsonEnd])
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            var p = CaptureThresholdPayload()
            // Accept both snake_case (tool schema) and camelCase (robustness).
            p.ftpWatts = (obj["ftp_watts"] as? Int) ?? (obj["ftpWatts"] as? Int)
            p.thresholdPaceSecondsPerMile =
                (obj["threshold_pace_seconds_per_mile"] as? Int)
                ?? (obj["thresholdPaceSecondsPerMile"] as? Int)
            p.cssSecondsPer100yd =
                (obj["css_seconds_per_100yd"] as? Int)
                ?? (obj["cssSecondsPer100yd"] as? Int)
            // At least one field must be present.
            if p.ftpWatts != nil || p.thresholdPaceSecondsPerMile != nil || p.cssSecondsPer100yd != nil {
                return p
            }
        }
        return nil
    }

    // MARK: - Wide Plan Request Detection

    /// Returns true if the user's message requests a change spanning multiple weeks.
    /// Used to decide whether to include the full plan summary in context.
    func isWidePlanRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        let patterns: [String] = [
            #"next \d+ weeks?"#,
            #"rest of (the )?plan"#,
            #"every (monday|tuesday|wednesday|thursday|friday|saturday|sunday)"#,
            #"every week"#,
            #"(reduce|cut|increase|lower|raise|drop) .{0,30}(volume|mileage|hours?)"#,
            #"no (running|swimming|biking|cycling|swim|bike|run) for"#,
            #"shift everything"#,
            #"move everything"#,
            #"all (my )?(remaining )?(weeks?|workouts?|runs?|rides?|swims?)"#,
            #"through (race|week|the end)"#,
            #"weeks? \d+ (through|to|-) \d+"#,
            #"for (the )?(next|remaining) (few )?\d"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                return true
            }
        }
        return false
    }

    /// Compact one-line-per-week summary of the full plan (all weeks).
    /// Sent to Claude only when a wide plan request is detected (~300 tokens for 17 weeks).
    func buildFullPlanSummary() -> String {
        guard let plan = trainingPlan, !plan.weeks.isEmpty else { return "" }

        var lines = ["====== FULL PLAN OVERVIEW (\(plan.weeks.count) weeks) ======"]
        for week in plan.weeks {
            var swimYards = 0
            var bikeMinutes = 0
            var runMinutes = 0

            for workout in week.workouts {
                let lower = workout.type.lowercased()
                if lower.contains("swim") {
                    let dur = workout.duration.lowercased()
                    if dur.contains("yd") {
                        swimYards += Int(dur.filter { $0.isNumber }) ?? 0
                    } else if let mins = PlanDiffEngine.durationMinutes(workout.duration) {
                        swimYards += mins * 30
                    }
                } else if lower.contains("bike") || lower.contains("cycling") {
                    bikeMinutes += PlanDiffEngine.durationMinutes(workout.duration) ?? 0
                } else if lower.contains("run") {
                    runMinutes += PlanDiffEngine.durationMinutes(workout.duration) ?? 0
                } else if lower.contains("brick") {
                    if let mins = PlanDiffEngine.durationMinutes(workout.duration) {
                        bikeMinutes += mins * 3 / 4
                        runMinutes += mins / 4
                    }
                }
            }

            var parts: [String] = []
            if swimYards > 0 { parts.append("Swim ~\(swimYards)yd") }
            if bikeMinutes > 0 { parts.append("Bike ~\(planFormatHours(bikeMinutes))") }
            if runMinutes > 0 { parts.append("Run ~\(planFormatHours(runMinutes))") }
            let summary = parts.isEmpty ? "Rest week" : parts.joined(separator: ", ")
            lines.append("Week \(week.weekNumber) (\(week.phase)): \(summary)")
        }
        return lines.joined(separator: "\n")
    }

    private func planFormatHours(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    func buildRescheduleContext() -> String {
        guard let trainingPlan = trainingPlan else { return "" }

        // Only include current week ± 2 to keep context small and tool-call rules prominent
        let currentWeekNum = trainingPlan.currentWeekNumber
        let relevantWeeks = trainingPlan.weeks.filter { abs($0.weekNumber - currentWeekNum) <= 2 }
        let weeksSummary = relevantWeeks.map { week in
            let workouts = week.workouts.map { "\($0.day): \($0.type) \($0.duration) \($0.zone)" }.joined(separator: ", ")
            let marker = week.weekNumber == currentWeekNum ? " ← CURRENT WEEK" : ""
            return "Week \(week.weekNumber) (\(week.phase))\(marker): \(workouts)"
        }.joined(separator: "\n")

        return """
        ====== PLAN CHANGE RULES (FOLLOW THESE EXACTLY) ======

        When the user wants any workout change: call propose_plan_change IMMEDIATELY.
        Do NOT say "let me know if you want to apply this" or ask for confirmation — the app shows a confirmation dialog automatically.
        Do NOT describe the change in text and wait. Call the tool first, then explain if needed.
        If the user says "yes", "yea", "sure", "do it", or confirms a previously described change — call the tool NOW with those changes.
        You CAN modify past workouts too (e.g. logging an unplanned workout the user did, correcting a missed day, or editing history). Operate on whatever week/day the user references — past or future.
        Changes are additive — only touch what the user explicitly mentioned.
        SWAP: swap MOVES existing workouts between two days. Never invent new workouts during a swap. If one day is Rest, the swap still works — the existing workouts move to the Rest day and the originally-scheduled day becomes Rest. Do NOT substitute a different workout type (e.g. do NOT turn a Run into a Brick during a swap).

        ====== TRAINING PLAN (current week ± 2) ======

        \(weeksSummary)

        Current date: \(Formatters.fullDate.string(from: Date()))

        \(PrepRacesManager.shared.contextString().map { "\n\($0)\n" } ?? "")

        RESCHEDULE NOTES:
        - Dropping all workouts on a day leaves it as Rest.
        - PREP RACE DAYS: Never schedule training on prep race day or the day before.
        """
    }

    /// Tool-use instructions emitted when course intelligence is active.
    /// Claude is asked to append a sentinel line when the athlete shares a
    /// threshold number in chat. The client (see
    /// `applyThresholdCaptureIfPresent`) extracts it and persists to
    /// `PerformanceThresholdsStore`.
    ///
    /// The sentinel form is `[CAPTURE_THRESHOLD:{...}]` — self-contained so
    /// it works without a server-side tool schema change (that ships in v2).
    static let thresholdToolInstructions: String = """
    ====== THRESHOLD CAPTURE (capture_threshold tool) ======

    When the athlete responds with a specific number for FTP (watts), threshold
    run pace (as minutes:seconds per mile), or swim CSS (seconds per 100yd),
    emit a single sentinel line AT THE END of your response so the app can
    persist it:

    [CAPTURE_THRESHOLD:{"ftp_watts": 215}]
    [CAPTURE_THRESHOLD:{"threshold_pace_seconds_per_mile": 450}]
    [CAPTURE_THRESHOLD:{"css_seconds_per_100yd": 95}]

    Rules:
    - Only emit when the athlete gave a concrete number (not a range/guess).
    - Convert paces to integer seconds (7:30/mi = 450).
    - Multiple fields may be combined in one payload.
    - If the athlete declines or doesn't know, do NOT ask again this session.
    """

    private static let maxPersistedMessages = 50

    func saveChatHistory() {
        // Strip image data from persisted messages to avoid UserDefaults bloat
        let toSave = messages.suffix(Self.maxPersistedMessages).map { msg in
            ChatMessage(id: msg.id, isUser: msg.isUser, text: msg.text, timestamp: msg.timestamp, imageData: nil, kind: msg.kind)
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

    @MainActor
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

        if let ts = trainingStatus?.status {
            context += "\n\n" + ts.contextString(brief: false)
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
