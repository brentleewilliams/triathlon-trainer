import Foundation
import Combine
import UserNotifications

// MARK: - Cached Opening Message

/// Persisted opening message for the Morning Check-In. Cached for up to the
/// configured freshness window (default 6h) to avoid regenerating on every
/// tap. See PRD §3.6.1 / §3.7 tier 2.
struct CachedOpeningMessage: Codable, Equatable {
    /// Short notification body (what shows in the push).
    let notificationBody: String
    /// Longer opening message shown inside CheckInView.
    let openingMessage: String
    /// Timestamp the message was generated. Staleness is computed from this.
    let generatedAt: Date
    /// Optional summary of today's planned workout at generation time, so
    /// consumers can invalidate the cache if the plan changed.
    let workoutSummary: String?
}

// MARK: - Check-In Manager

/// Orchestrates the Morning Check-In v1 flow.
///
/// v1 scope (see PRD §11.1):
///  - Live-regeneration only (tier 2). No `BGAppRefreshTask`.
///  - Generates opening message on tap when cache is stale (>6h) or missing.
///  - Static fallback (tier 3) ships as `staticFallbackMessage` for when live
///    regeneration fails.
///  - Check-in messages are tagged `.checkIn` via `ChatViewModel` so the Chat
///    tab filter chip can surface them.
///
/// v2 (deferred): `BGAppRefreshTask`, HRV/resting HR signals, foreground
/// banner, sleep-stage display.
@MainActor
final class CheckInManager: ObservableObject {
    // Swift 6 strict-concurrency: `shared` is MainActor-isolated because the
    // class itself is. Callers must already be on the main actor.
    static let shared = CheckInManager()

    // MARK: Published state

    /// True when CheckInView is presented.
    @Published var isCheckInActive: Bool = false
    /// True while `generateOpeningMessage` is running a live call.
    @Published var isGeneratingOpeningMessage: Bool = false
    /// Last error from generation. Nil on success or when fallback was used.
    @Published var lastError: String?

    // MARK: User preferences

    /// Whether the user has enabled Morning Check-Ins.
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }

    /// Configured local check-in time. Only the hour/minute components are
    /// used; the date portion is ignored.
    @Published var checkInTime: Date {
        didSet { UserDefaults.standard.set(checkInTime.timeIntervalSince1970, forKey: Keys.checkInTime) }
    }

    // MARK: Configuration

    /// How long a cached message is considered fresh (default 6h per §3.7).
    var freshnessWindow: TimeInterval = 6 * 60 * 60

    /// Injected LLM call. Returns (notificationBody, openingMessage).
    /// Default uses `LLMProxyService`. Tests can inject a stub.
    var generateOpeningMessageCall: (_ context: String) async throws -> (String, String) = { context in
        // Delegate to LLMProxyService coaching endpoint. Tagged via the
        // user message prefix so LangSmith traces show `check_in`.
        // TODO(v1): once LangSmith prompt `check-in-system` ships, route
        // through a dedicated Cloud Function case instead of reusing the
        // coaching endpoint.
        let response = try await LLMProxyService.shared.sendCoachingMessage(
            userMessage: "[check_in] Generate my morning check-in opening. Start with one specific observation, then ask one question. <=100 words.",
            trainingContext: context,
            workoutHistory: ""
        )
        let opening = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reuse the opening as the notification body, truncated.
        let body = String(opening.prefix(120))
        return (body, opening)
    }

    // MARK: Persistence keys

    private enum Keys {
        static let enabled = "checkIn.enabled"
        static let checkInTime = "checkIn.time"
        static let cachedMessage = "checkIn.cachedOpeningMessage"
    }

    // MARK: Init

    init() {
        self.enabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? false
        let savedTime = UserDefaults.standard.double(forKey: Keys.checkInTime)
        if savedTime > 0 {
            self.checkInTime = Date(timeIntervalSince1970: savedTime)
        } else {
            // Default 7:00 AM local.
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = 7
            comps.minute = 0
            self.checkInTime = Calendar.current.date(from: comps) ?? Date()
        }
    }

    // MARK: - Cached opening message

    /// Returns the cached opening message if it is still within the freshness
    /// window. Returns nil if missing, corrupt, or expired.
    func loadCachedOpeningMessage(now: Date = Date()) -> CachedOpeningMessage? {
        guard let data = UserDefaults.standard.data(forKey: Keys.cachedMessage) else {
            return nil
        }
        let cached: CachedOpeningMessage
        do {
            cached = try JSONDecoder().decode(CachedOpeningMessage.self, from: data)
        } catch {
            print("[CheckInManager] Failed to decode cached opening message: \(error). Dropping cache.")
            UserDefaults.standard.removeObject(forKey: Keys.cachedMessage)
            return nil
        }
        if now.timeIntervalSince(cached.generatedAt) > freshnessWindow {
            return nil
        }
        return cached
    }

    /// Writes a cached opening message. Exposed for tests and for the
    /// live-regeneration path.
    func saveCachedOpeningMessage(_ message: CachedOpeningMessage) {
        do {
            let data = try JSONEncoder().encode(message)
            UserDefaults.standard.set(data, forKey: Keys.cachedMessage)
        } catch {
            print("[CheckInManager] Failed to encode cached opening message: \(error)")
        }
    }

    /// Removes the cached opening message. Useful on sign-out / plan reset.
    func clearCachedOpeningMessage() {
        UserDefaults.standard.removeObject(forKey: Keys.cachedMessage)
    }

    // MARK: - Context gathering

    /// Gathers v1 check-in context: today's plan, yesterday's workout, sleep.
    /// Returns a plain-text blob suitable for feeding to the LLM.
    func prepareCheckInContext(
        trainingPlan: TrainingPlanManager?,
        healthKit: HealthKitManager?,
        now: Date = Date()
    ) async -> String {
        var out = "MORNING CHECK-IN CONTEXT\n"
        out += "Date: \(Formatters.fullDate.string(from: now))\n\n"

        if let plan = trainingPlan {
            out += "TODAY'S PLAN:\n"
            let today = todayWorkouts(plan: plan, date: now)
            if today.isEmpty {
                out += "- Rest / no workouts scheduled\n"
            } else {
                for w in today {
                    out += "- \(w.type) \(w.duration) \(w.zone)\n"
                }
            }
        }

        if let hk = healthKit, let sleep = await hk.fetchSleepData(for: now) {
            let hrs = Double(sleep.totalSleepMinutes) / 60.0
            out += "\nSLEEP LAST NIGHT: \(String(format: "%.1f", hrs))h (source: \(sleep.source))\n"
        }

        return out
    }

    /// Fallback message (tier 3) when LLM generation fails.
    func staticFallbackMessage(trainingPlan: TrainingPlanManager?, now: Date = Date()) -> String {
        let todays = todayWorkouts(plan: trainingPlan, date: now)
        if todays.isEmpty {
            return "Rest day today — how are you feeling?"
        }
        let summary = todays.map { "\($0.type) \($0.duration) \($0.zone)" }.joined(separator: " + ")
        return "\(summary) today. How are you feeling?"
    }

    // MARK: - Generate opening message

    /// Runs the live-regeneration tier-2 path. Caches on success, logs a
    /// LangSmith trace tagged `check_in`, falls back to tier-3 static text
    /// on failure.
    @discardableResult
    func generateOpeningMessage(
        trainingPlan: TrainingPlanManager?,
        healthKit: HealthKitManager?,
        now: Date = Date()
    ) async -> CachedOpeningMessage {
        isGeneratingOpeningMessage = true
        defer { isGeneratingOpeningMessage = false }

        let context = await prepareCheckInContext(trainingPlan: trainingPlan, healthKit: healthKit, now: now)
        let workoutSummary = todayWorkouts(plan: trainingPlan, date: now).map { $0.type }.joined(separator: "+")

        do {
            let (body, opening) = try await generateOpeningMessageCall(context)
            let cached = CachedOpeningMessage(
                notificationBody: body,
                openingMessage: opening,
                generatedAt: now,
                workoutSummary: workoutSummary
            )
            saveCachedOpeningMessage(cached)
            lastError = nil
            return cached
        } catch {
            lastError = error.localizedDescription
            let fallback = staticFallbackMessage(trainingPlan: trainingPlan, now: now)
            return CachedOpeningMessage(
                notificationBody: fallback,
                openingMessage: fallback,
                generatedAt: now,
                workoutSummary: workoutSummary
            )
        }
    }

    // MARK: - Local notification (v1 fallback)

    /// Schedules a daily local `UNUserNotificationCenter` notification as a
    /// fallback for when FCM is unavailable. The FCM push is the primary
    /// delivery mechanism (see `functions/index.js` `scheduleCheckInNotifications`).
    func scheduleLocalFallbackNotification() {
        guard enabled else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["morning-checkin-local"])
            return
        }
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: checkInTime)
        let minute = cal.component(.minute, from: checkInTime)

        let content = UNMutableNotificationContent()
        content.title = "Morning Check-In"
        content.body = loadCachedOpeningMessage()?.notificationBody ?? "How are you feeling today?"
        content.sound = .default
        content.userInfo = ["kind": "check_in"]

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "morning-checkin-local", content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: ["morning-checkin-local"])
        center.add(req)
    }

    // MARK: - Complete

    /// Marks the check-in complete. `accepted` indicates the user accepted
    /// Claude's adjustment (vs "Keep as Planned"). Tagging of chat messages
    /// happens upstream via `ChatMessageKind.checkIn` when messages are
    /// persisted.
    func completeCheckIn(accepted: Bool) {
        isCheckInActive = false
    }

    // MARK: - Helpers

    private func todayWorkouts(plan: TrainingPlanManager?, date: Date) -> [DayWorkout] {
        guard let plan = plan else { return [] }
        let name = DayNames.from(date)
        guard let week = plan.getWeek(plan.currentWeekNumber) else { return [] }
        return week.workouts.filter { $0.day == name && $0.type.lowercased() != "rest" }
    }
}
