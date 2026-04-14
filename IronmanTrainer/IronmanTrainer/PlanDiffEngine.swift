import Foundation

// MARK: - Plan Diff Models

enum DayDiffStatus {
    case unchanged
    case modified   // yellow — workout replaced or intensity changed
    case dropped    // red — workout(s) removed
    case added      // blue — new workout added
    case swapped    // orange — workouts moved between days
}

struct DayDiff: Identifiable {
    let day: String
    let status: DayDiffStatus
    let currentWorkouts: [DayWorkout]
    let proposedWorkouts: [DayWorkout]
    let isKeySession: Bool
    let rationale: String?

    var id: String { day }
}

struct WeekDiff: Identifiable {
    let weekNumber: Int
    let phase: String
    let dayDiffs: [DayDiff]
    let originalMinutes: Int
    let proposedMinutes: Int

    var id: Int { weekNumber }

    var volumeChangeMinutes: Int { proposedMinutes - originalMinutes }
}

struct EnrichedProposal {
    let proposal: PlanChangeProposal
    let weekDiffs: [WeekDiff]
    let originalTotalMinutes: Int
    let proposedTotalMinutes: Int

    var volumeChangeMinutes: Int { proposedTotalMinutes - originalTotalMinutes }
}

// MARK: - Enrichment Engine

enum PlanDiffEngine {

    static func enrich(_ proposal: PlanChangeProposal, plan: TrainingPlanManager) -> EnrichedProposal {
        // Group changes by week
        let changesByWeek = Dictionary(grouping: proposal.changes, by: { $0.week })

        // Build diffs for each affected week
        let affectedWeekNumbers = Set(proposal.changes.map { $0.week })
        var weekDiffs: [WeekDiff] = []
        var totalOriginal = 0
        var totalProposed = 0

        for weekNum in affectedWeekNumbers.sorted() {
            guard let week = plan.weeks.first(where: { $0.weekNumber == weekNum }) else { continue }
            let changes = changesByWeek[weekNum] ?? []
            let weekDiff = buildWeekDiff(week: week, changes: changes)
            weekDiffs.append(weekDiff)
            totalOriginal += weekDiff.originalMinutes
            totalProposed += weekDiff.proposedMinutes
        }

        return EnrichedProposal(
            proposal: proposal,
            weekDiffs: weekDiffs,
            originalTotalMinutes: totalOriginal,
            proposedTotalMinutes: totalProposed
        )
    }

    // MARK: - Week Diff

    private static func buildWeekDiff(week: TrainingWeek, changes: [PlanChange]) -> WeekDiff {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let proposedWorkouts = simulateChanges(changes, on: week)
        let affectedDays = buildAffectedDays(changes)

        var dayDiffs: [DayDiff] = []

        for day in dayOrder {
            let current = week.workouts.filter { $0.day == day }
            let proposed = proposedWorkouts.filter { $0.day == day }

            // Determine status
            let status: DayDiffStatus
            if affectedDays[day] != nil {
                status = affectedDays[day]!
            } else {
                status = .unchanged
            }

            // Find rationale from change that affects this day
            let rationale = changes.first(where: {
                $0.day == day || $0.fromDay == day || $0.toDay == day
            })?.rationale

            let isKey = current.contains(where: { isKeySession($0, weekPhase: week.phase) }) ||
                        proposed.contains(where: { isKeySession($0, weekPhase: week.phase) })

            dayDiffs.append(DayDiff(
                day: day,
                status: status,
                currentWorkouts: current,
                proposedWorkouts: proposed,
                isKeySession: isKey,
                rationale: rationale
            ))
        }

        let originalMinutes = week.workouts.compactMap { durationMinutes($0.duration) }.reduce(0, +)
        let proposedMinutes = proposedWorkouts.compactMap { durationMinutes($0.duration) }.reduce(0, +)

        return WeekDiff(
            weekNumber: week.weekNumber,
            phase: week.phase,
            dayDiffs: dayDiffs,
            originalMinutes: originalMinutes,
            proposedMinutes: proposedMinutes
        )
    }

    /// Build a map of day → DayDiffStatus from the changes.
    private static func buildAffectedDays(_ changes: [PlanChange]) -> [String: DayDiffStatus] {
        var affected: [String: DayDiffStatus] = [:]
        for change in changes {
            switch change.action {
            case .add:
                if let day = change.day { affected[day] = .added }
            case .drop:
                if let day = change.day { affected[day] = .dropped }
            case .swap:
                if let from = change.fromDay { affected[from] = .swapped }
                if let to = change.toDay { affected[to] = .swapped }
            case .replace:
                if let day = change.day { affected[day] = .modified }
            }
        }
        return affected
    }

    // MARK: - Simulate Changes

    /// Apply changes to a copy of the week's workouts without persisting.
    static func simulateChanges(_ changes: [PlanChange], on week: TrainingWeek) -> [DayWorkout] {
        var workouts = week.workouts

        for change in changes {
            switch change.action {
            case .add:
                guard let day = change.day, let type = change.type else { continue }
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

            case .drop:
                guard let day = change.day else { continue }
                workouts.removeAll { $0.day == day }

            case .swap:
                guard let fromDay = change.fromDay, let toDay = change.toDay else { continue }
                workouts = workouts.map { w in
                    if w.day == fromDay {
                        return DayWorkout(day: toDay, type: w.type, duration: w.duration, zone: w.zone,
                                          status: w.status, nutritionTarget: w.nutritionTarget, notes: w.notes)
                    } else if w.day == toDay {
                        return DayWorkout(day: fromDay, type: w.type, duration: w.duration, zone: w.zone,
                                          status: w.status, nutritionTarget: w.nutritionTarget, notes: w.notes)
                    }
                    return w
                }

            case .replace:
                guard let day = change.day, let fromType = change.fromType else { continue }
                if let idx = workouts.firstIndex(where: { $0.day == day && typeMatches($0.type, keyword: fromType) }) {
                    workouts[idx] = DayWorkout(
                        day: day,
                        type: change.type ?? workouts[idx].type,
                        duration: change.duration ?? workouts[idx].duration,
                        zone: change.zone ?? workouts[idx].zone,
                        status: nil,
                        nutritionTarget: nil,
                        notes: change.notes ?? workouts[idx].notes
                    )
                }
            }
        }

        return workouts
    }

    // MARK: - Key Session Detection

    /// Determines if a workout is a "key session" that should be protected during negotiation.
    static func isKeySession(_ workout: DayWorkout, weekPhase: String) -> Bool {
        let type = workout.type.lowercased()
        let phase = weekPhase.lowercased()

        // Rest days are never key
        if type.contains("rest") || type == "-" { return false }

        // Brick workouts are always key
        if type.contains("brick") || type.contains("race sim") { return true }

        // Taper and race week — everything is key
        if phase.contains("taper") || phase.contains("race") { return true }

        // High-intensity sessions (Z4+) are key
        let zone = workout.zone.lowercased()
        if zone.contains("z4") || zone.contains("z5") || zone.contains("vo2") || zone.contains("threshold") {
            return true
        }

        // Long workouts are key
        if let minutes = durationMinutes(workout.duration) {
            if type.contains("run") && minutes >= 90 { return true }
            if type.contains("bike") && minutes >= 120 { return true }
            if type.contains("swim") && minutes >= 75 { return true }
        }

        return false
    }

    // MARK: - Duration Parsing

    /// Parse a workout duration string into minutes. Returns nil for yard-based or rest entries.
    static func durationMinutes(_ durationStr: String) -> Int? {
        return parseWorkoutDuration(durationStr)
    }

    // MARK: - Helpers

    /// Lightweight type matching (same logic as ChatViewModel.workoutTypeMatches).
    private static func typeMatches(_ workoutType: String, keyword: String) -> Bool {
        let haystack = workoutType.lowercased()
        let needle = keyword.lowercased()
        if haystack.contains(needle) || needle.contains(haystack) { return true }
        let aliases: [String: [String]] = [
            "run": ["run", "running", "jog"],
            "bike": ["bike", "cycling", "cycle", "ride"],
            "swim": ["swim", "swimming", "pool"],
            "brick": ["brick"],
            "strength": ["strength", "gym", "lift", "weights"],
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

    // MARK: - Formatting Helpers

    static func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    static func formatVolumeChange(_ change: Int) -> String {
        if change > 0 { return "+\(formatMinutes(change))" }
        if change < 0 { return "-\(formatMinutes(abs(change)))" }
        return "no change"
    }
}
