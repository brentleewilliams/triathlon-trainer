import Foundation
import Combine
import SwiftUI

// MARK: - Readiness Level

enum ReadinessLevel: String, Codable {
    case green          // Ready — full effort
    case yellow         // Caution — consider easing
    case red            // Recover — reduce or rest
    case unknown        // Insufficient signals

    var emoji: String {
        switch self {
        case .green: return "🟢"
        case .yellow: return "🟡"
        case .red: return "🔴"
        case .unknown: return "⚪️"
        }
    }

    var label: String {
        switch self {
        case .green: return "Ready"
        case .yellow: return "Caution"
        case .red: return "Recover"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Readiness Calculation

/// Pure scoring function that converts a ReadinessSnapshot into a ReadinessLevel
/// plus a human-readable list of flags that justify the score.
///
/// Heuristics (each produces one "flag"):
///   - sleepHours < 6.0  → red flag "Low sleep"
///   - sleepHours < 7.0  → yellow flag "Short sleep"
///   - HRV > 20% below baseline → red flag "HRV suppressed"
///   - HRV 10–20% below baseline → yellow flag "HRV low"
///   - RHR > 8 bpm above baseline → red flag "RHR elevated"
///   - RHR 4–7 bpm above baseline → yellow flag "RHR slightly elevated"
///
/// Aggregate:
///   - Any red flag → .red
///   - 2+ yellow flags → .red
///   - 1 yellow flag → .yellow
///   - No flags + all metrics present → .green
///   - Too little data → .unknown
struct ReadinessScore: Equatable {
    var level: ReadinessLevel
    var flags: [String]          // e.g. ["Low sleep", "HRV suppressed"]
    var positives: [String]      // e.g. ["8.1h sleep", "HRV normal"]
}

enum ReadinessScorer {
    static func score(_ s: ReadinessSnapshot) -> ReadinessScore {
        var redFlags: [String] = []
        var yellowFlags: [String] = []
        var positives: [String] = []
        var dataPoints = 0

        // Sleep
        if let hours = s.sleepHours {
            dataPoints += 1
            if hours < 6.0 {
                redFlags.append("Low sleep (\(fmt(hours))h)")
            } else if hours < 7.0 {
                yellowFlags.append("Short sleep (\(fmt(hours))h)")
            } else {
                positives.append("\(fmt(hours))h sleep")
            }
        }

        // HRV
        if let hrv = s.hrvMs, let base = s.hrvBaselineMs, base > 0 {
            dataPoints += 1
            let pctChange = (hrv - base) / base * 100.0
            if pctChange < -20.0 {
                redFlags.append("HRV suppressed (\(Int(round(pctChange)))%)")
            } else if pctChange < -10.0 {
                yellowFlags.append("HRV low (\(Int(round(pctChange)))%)")
            } else {
                positives.append("HRV \(Int(round(hrv)))ms")
            }
        } else if let hrv = s.hrvMs {
            dataPoints += 1
            positives.append("HRV \(Int(round(hrv)))ms")
        }

        // Resting HR
        if let rhr = s.restingHR, let base = s.restingHRBaseline {
            dataPoints += 1
            let diff = rhr - base
            if diff > 8 {
                redFlags.append("RHR elevated (+\(diff) bpm)")
            } else if diff >= 4 {
                yellowFlags.append("RHR slightly elevated (+\(diff) bpm)")
            } else {
                positives.append("RHR \(rhr) bpm")
            }
        } else if let rhr = s.restingHR {
            dataPoints += 1
            positives.append("RHR \(rhr) bpm")
        }

        // Aggregate
        let level: ReadinessLevel
        if dataPoints == 0 {
            level = .unknown
        } else if !redFlags.isEmpty || yellowFlags.count >= 2 {
            level = .red
        } else if yellowFlags.count == 1 {
            level = .yellow
        } else {
            level = dataPoints >= 2 ? .green : .unknown
        }

        return ReadinessScore(
            level: level,
            flags: redFlags + yellowFlags,
            positives: positives
        )
    }

    private static func fmt(_ d: Double) -> String {
        String(format: "%.1f", d)
    }
}

// MARK: - Daily Check-In

struct DailyCheckIn: Codable, Equatable {
    let date: Date                       // Midnight of the day this check-in belongs to
    let readinessLevel: ReadinessLevel
    let flags: [String]
    let positives: [String]
    let snapshot: ReadinessSnapshot
    let workoutSummary: String?          // Today's planned workout (e.g. "Run 45min · Z2")
    var coachMessage: String?            // Pre-generated greeting from Claude
    let generatedAt: Date

    /// True if this check-in was generated for today's calendar date.
    func isFreshFor(date now: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }
}

// MARK: - Check-In Manager

@MainActor
class CheckInManager: ObservableObject {
    static let shared = CheckInManager()

    @Published private(set) var todayCheckIn: DailyCheckIn?
    @Published var isGenerating = false

    private let storageKey = "daily_checkin_latest"

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// Primary entrypoint: builds (or returns cached) today's check-in.
    /// Call from background refresh or when the notification is tapped.
    ///
    /// - Parameters:
    ///   - healthKit: Used for the readiness snapshot.
    ///   - trainingPlan: Used for today's workout summary.
    ///   - forceRegenerate: Bypass the same-day cache.
    ///   - generateCoachMessage: If true, invokes Claude via LLMProxy to draft
    ///     a contextual greeting. Safe to pass false in quick-path scenarios.
    func generateCheckIn(
        healthKit: HealthKitManager,
        trainingPlan: TrainingPlanManager,
        forceRegenerate: Bool = false,
        generateCoachMessage: Bool = true
    ) async -> DailyCheckIn {
        if !forceRegenerate, let existing = todayCheckIn, existing.isFreshFor(date: Date()) {
            return existing
        }

        isGenerating = true
        defer { isGenerating = false }

        let snapshot = await healthKit.fetchReadinessSnapshot()
        let score = ReadinessScorer.score(snapshot)
        let workoutSummary = Self.todaysWorkoutSummary(plan: trainingPlan)

        var checkIn = DailyCheckIn(
            date: Calendar.current.startOfDay(for: Date()),
            readinessLevel: score.level,
            flags: score.flags,
            positives: score.positives,
            snapshot: snapshot,
            workoutSummary: workoutSummary,
            coachMessage: nil,
            generatedAt: Date()
        )

        // Persist baseline immediately so the notification can read it even
        // if the coach-message call fails.
        self.todayCheckIn = checkIn
        saveToDisk()

        if generateCoachMessage {
            if let message = await Self.generateCoachGreeting(
                checkIn: checkIn,
                healthKit: healthKit,
                trainingPlan: trainingPlan
            ) {
                checkIn.coachMessage = message
                self.todayCheckIn = checkIn
                saveToDisk()
            }
        }

        return checkIn
    }

    // MARK: - Helpers

    /// Returns a one-line summary of today's workout (or "Rest day" / nil if none).
    static func todaysWorkoutSummary(plan: TrainingPlanManager, date: Date = Date()) -> String? {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let weekdayIndex = (Calendar.current.component(.weekday, from: date) + 5) % 7  // Mon=0..Sun=6
        let dayName = dayOrder[weekdayIndex]

        guard let week = plan.getWeek(plan.currentWeekNumber),
              case let todaysWorkouts = week.workouts.filter({ $0.day == dayName }),
              !todaysWorkouts.isEmpty else {
            return nil
        }

        let nonRest = todaysWorkouts.filter { $0.type.lowercased() != "rest" }
        if nonRest.isEmpty { return "Rest day" }
        return nonRest.map { "\($0.type) \($0.duration) · \($0.zone)" }.joined(separator: " + ")
    }

    /// Builds a short, contextual greeting via the coaching LLM.
    /// Returns nil on failure; callers should fall back to the default
    /// notification copy in that case.
    static func generateCoachGreeting(
        checkIn: DailyCheckIn,
        healthKit: HealthKitManager,
        trainingPlan: TrainingPlanManager
    ) async -> String? {
        // Assemble readiness context for the LLM.
        var context = "MORNING CHECK-IN READINESS:\n"
        context += "- Level: \(checkIn.readinessLevel.emoji) \(checkIn.readinessLevel.label)\n"
        if let hours = checkIn.snapshot.sleepHours {
            context += "- Sleep: \(String(format: "%.1f", hours))h\n"
        }
        if let hrv = checkIn.snapshot.hrvMs {
            if let base = checkIn.snapshot.hrvBaselineMs {
                let pct = Int(round((hrv - base) / base * 100.0))
                context += "- HRV: \(Int(round(hrv)))ms (\(pct >= 0 ? "+" : "")\(pct)% vs 7-day avg)\n"
            } else {
                context += "- HRV: \(Int(round(hrv)))ms\n"
            }
        }
        if let rhr = checkIn.snapshot.restingHR {
            if let base = checkIn.snapshot.restingHRBaseline {
                let diff = rhr - base
                context += "- Resting HR: \(rhr) bpm (\(diff >= 0 ? "+" : "")\(diff) vs 7-day avg)\n"
            } else {
                context += "- Resting HR: \(rhr) bpm\n"
            }
        }
        if !checkIn.flags.isEmpty {
            context += "- Flags: \(checkIn.flags.joined(separator: ", "))\n"
        }
        if let summary = checkIn.workoutSummary {
            context += "- Today's workout: \(summary)\n"
        }

        let userMessage = """
        Write a 2-3 sentence morning check-in greeting. Be warm, specific, and actionable based on the readiness data above. \
        If flags are present, suggest a concrete adjustment (easier pace, shorter duration, or a rest day). \
        If readiness is green, affirm the plan. Start with a brief greeting — no headers, no lists.
        """

        let traceUserId = AuthService.shared.currentUserID
        let traceContext = LangSmithTracer.shared.startCoachingTrace(
            userId: traceUserId,
            userMessage: "[morning_checkin] \(checkIn.readinessLevel.label)"
        )

        do {
            let response = try await LLMProxyService.shared.sendCoachingMessage(
                userMessage: userMessage,
                trainingContext: context,
                workoutHistory: "",
                zoneBoundaries: healthKit.zoneBoundaries,
                conversationHistory: [],
                imageData: nil,
                traceContext: traceContext
            )
            LangSmithTracer.shared.endCoachingTrace(
                traceContext,
                response: response.text,
                error: nil,
                toolCallMade: false
            )
            let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            LangSmithTracer.shared.endCoachingTrace(traceContext, response: nil, error: error.localizedDescription)
            return nil
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode(DailyCheckIn.self, from: data) {
            self.todayCheckIn = decoded
        }
    }

    private func saveToDisk() {
        guard let checkIn = todayCheckIn else { return }
        if let data = try? JSONEncoder().encode(checkIn) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Expose a value-safe copy readable from background contexts (e.g. the
    /// notification scheduler), since `@Published` access requires the main actor.
    nonisolated static func latestPersistedCheckIn() -> DailyCheckIn? {
        guard let data = UserDefaults.standard.data(forKey: "daily_checkin_latest") else { return nil }
        return try? JSONDecoder().decode(DailyCheckIn.self, from: data)
    }
}
