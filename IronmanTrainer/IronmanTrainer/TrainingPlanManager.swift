import Foundation
import CoreData

// MARK: - Training Plan Data
struct TrainingWeek: Codable, Equatable {
    let weekNumber: Int
    let phase: String
    let startDate: Date
    let endDate: Date
    let workouts: [DayWorkout]

    /// Monday of the week containing `date` (using ISO 8601: Monday is the
    /// first day of the week). Falls back to `date` if the calendar math fails.
    static func mondayOfWeek(for date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        cal.timeZone = .current
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start) // Mon=2 … Sun=1
        let daysFromMonday = (weekday == 1) ? 6 : (weekday - 2)
        return cal.date(byAdding: .day, value: -daysFromMonday, to: start) ?? start
    }

    /// Snaps each week's startDate to the Monday of its own week and endDate
    /// to the following Sunday. Idempotent and preserves the plan's temporal
    /// positioning — safe to call any time.
    static func snapToMondaySunday(_ weeks: [TrainingWeek]) -> [TrainingWeek] {
        let cal = Calendar.current
        return weeks.map { week in
            let start = mondayOfWeek(for: week.startDate)
            let end = cal.date(byAdding: .day, value: 6, to: start) ?? week.endDate
            return TrainingWeek(
                weekNumber: week.weekNumber,
                phase: week.phase,
                startDate: start,
                endDate: end,
                workouts: week.workouts
            )
        }
    }

    /// Shifts every week so week 1 starts on the Monday of `anchor`'s week
    /// and subsequent weeks follow at 7-day intervals. Use when loading a
    /// newly-generated plan so Week 1 contains the onboarding day.
    static func anchorWeek1(to anchor: Date, weeks: [TrainingWeek]) -> [TrainingWeek] {
        guard !weeks.isEmpty else { return weeks }
        let sorted = weeks.sorted { $0.weekNumber < $1.weekNumber }
        let firstWeekNumber = sorted.first!.weekNumber
        let week1Monday = mondayOfWeek(for: anchor)
        let cal = Calendar.current
        return sorted.map { week in
            let offsetWeeks = week.weekNumber - firstWeekNumber
            let start = cal.date(byAdding: .day, value: offsetWeeks * 7, to: week1Monday) ?? week.startDate
            let end = cal.date(byAdding: .day, value: 6, to: start) ?? week.endDate
            return TrainingWeek(
                weekNumber: week.weekNumber,
                phase: week.phase,
                startDate: start,
                endDate: end,
                workouts: week.workouts
            )
        }
    }

    /// Deprecated alias kept for compatibility with older call sites.
    static func normalizeToMondaySunday(weeks: [TrainingWeek], anchor: Date) -> [TrainingWeek] {
        anchorWeek1(to: anchor, weeks: weeks)
    }
}

struct DayWorkout: Equatable, Codable, Identifiable, Hashable {
    let day: String
    let type: String
    let duration: String
    let zone: String
    let status: String?
    let nutritionTarget: String?
    let notes: String?

    var id: String {
        "\(day)-\(type)-\(duration)-\(zone)"
    }

    // Convenience init without notes for backward compatibility
    init(day: String, type: String, duration: String, zone: String, status: String?, nutritionTarget: String?, notes: String? = nil) {
        self.day = day
        self.type = type
        self.duration = duration
        self.zone = zone
        self.status = status
        self.nutritionTarget = nutritionTarget
        self.notes = notes
    }
}

struct SwapCommand: Codable {
    let weekNumber: Int
    let fromDay: String
    let toDay: String
}

// MARK: - Plan Change Models (add/drop/swap with user confirmation)

enum PlanChangeAction: String, Codable { case add, drop, swap, replace }

struct PlanChange: Codable, Identifiable {
    let id: UUID
    let action: PlanChangeAction
    let week: Int
    let day: String?       // required for add, drop, replace; nil for swap
    let type: String?      // new workout type — for add and replace
    let duration: String?  // for add and replace
    let zone: String?      // for add and replace
    let notes: String?     // for add
    let fromDay: String?   // for swap: source day
    let toDay: String?     // for swap: destination day
    let fromType: String?  // for replace: existing workout type to replace (keyword, e.g. "Run")
    let rationale: String? // why this change was made (from Claude)

    enum CodingKeys: String, CodingKey {
        case action, week, day, type, duration, zone, notes, rationale
        case fromDay = "from_day"
        case toDay = "to_day"
        case fromType = "from_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.action = try container.decode(PlanChangeAction.self, forKey: .action)
        self.week = try container.decode(Int.self, forKey: .week)
        self.day = try container.decodeIfPresent(String.self, forKey: .day)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.duration = try container.decodeIfPresent(String.self, forKey: .duration)
        self.zone = try container.decodeIfPresent(String.self, forKey: .zone)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.fromDay = try container.decodeIfPresent(String.self, forKey: .fromDay)
        self.toDay = try container.decodeIfPresent(String.self, forKey: .toDay)
        self.fromType = try container.decodeIfPresent(String.self, forKey: .fromType)
        self.rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
    }

    init(action: PlanChangeAction, week: Int, day: String? = nil, type: String? = nil, duration: String? = nil, zone: String? = nil, notes: String? = nil, fromDay: String? = nil, toDay: String? = nil, fromType: String? = nil, rationale: String? = nil) {
        self.id = UUID()
        self.action = action
        self.week = week
        self.day = day
        self.type = type
        self.duration = duration
        self.zone = zone
        self.notes = notes
        self.fromDay = fromDay
        self.toDay = toDay
        self.fromType = fromType
        self.rationale = rationale
    }
}

struct PlanChangeProposal: Codable, Identifiable {
    let id: UUID
    let summary: String
    let changes: [PlanChange]

    init(id: UUID = UUID(), summary: String, changes: [PlanChange]) {
        self.id = id
        self.summary = summary
        self.changes = changes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id is optional in tool call output — generate one if missing
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.summary = try container.decode(String.self, forKey: .summary)
        self.changes = try container.decode([PlanChange].self, forKey: .changes)
    }

    enum CodingKeys: String, CodingKey { case id, summary, changes }
}

struct WeatherForecast {
    let highTemp: Int // °F
    let lowTemp: Int
    let condition: String
    let windMph: Int
    let humidity: Int

    var icon: String {
        switch condition {
        case "Rainy": return "\u{1F327}\u{FE0F}"
        case "Drizzle": return "\u{1F326}\u{FE0F}"
        case "Showers": return "\u{1F326}\u{FE0F}"
        case "Cloudy": return "\u{2601}\u{FE0F}"
        case "Partly Cloudy": return "\u{26C5}"
        case "Mostly Sunny": return "\u{1F324}\u{FE0F}"
        case "Sunny": return "\u{2600}\u{FE0F}"
        case "Fair": return "\u{1F324}\u{FE0F}"
        case "Sunny & Warm": return "\u{2600}\u{FE0F}"
        case "Sunny & Hot": return "\u{1F525}"
        case "Hot & Sunny": return "\u{1F525}"
        case "Clear": return "\u{2600}\u{FE0F}"
        default: return "\u{1F324}\u{FE0F}"
        }
    }

    static func forecast(for date: Date) -> WeatherForecast {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        // Use day-of-month to generate deterministic variation
        // Same date always gives same forecast, different dates vary
        let seed = UInt32(day)

        // Base conditions for the month
        let (baseTempHigh, baseTempLow, baseTempVariance, baseConditions, baseHumidity): (Int, Int, Int, [String], Int) = {
            switch month {
            case 3: // March - Cool and wet (56°F avg)
                return (56, 44, 8, ["Rainy", "Cloudy", "Drizzle", "Partly Cloudy"], 70)
            case 4: // April - Warming up (64°F avg)
                return (64, 48, 10, ["Partly Cloudy", "Sunny", "Cloudy", "Showers"], 60)
            case 5: // May - Spring conditions (72°F avg)
                return (72, 54, 8, ["Sunny", "Mostly Sunny", "Partly Cloudy", "Fair"], 55)
            case 6: // June - Warm (80°F avg)
                return (80, 62, 7, ["Sunny", "Mostly Sunny", "Fair", "Sunny & Warm"], 48)
            case 7: // July - Hot (87°F avg, race is July 19)
                return (87, 68, 6, ["Sunny & Hot", "Hot & Sunny", "Clear", "Sunny"], 42)
            default:
                return (70, 55, 10, ["Partly Cloudy", "Sunny", "Cloudy"], 60)
            }
        }()

        // Generate variation based on day of month (deterministic)
        let tempVariation = Int(seed % UInt32(baseTempVariance + 1)) - baseTempVariance / 2
        let high = baseTempHigh + tempVariation
        let low = baseTempLow + tempVariation

        let conditionIndex = Int(seed % UInt32(baseConditions.count))
        let condition = baseConditions[conditionIndex]

        let windVariation = Int(seed % 8) + 4 // 4-11 mph
        let humidityVariation = Int((seed * 7) % 15) - 7 // ±7% variation
        let humidity = max(30, min(85, baseHumidity + humidityVariation))

        return WeatherForecast(
            highTemp: high,
            lowTemp: low,
            condition: condition,
            windMph: windVariation,
            humidity: humidity
        )
    }
}

class TrainingPlanManager: ObservableObject {
    @Published var weeks: [TrainingWeek] = []
    @Published var currentWeekNumber: Int = 1
    @Published var currentPlanVersion: NSManagedObject?
    @Published var previousPlanVersion: NSManagedObject?

    private var planStartDate: Date {
        if let firstStart = weeks.first?.startDate {
            return firstStart
        }
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 23
        return Calendar.current.date(from: components) ?? Date()
    }

    private lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "IronmanTrainer")
        if useInMemoryStore {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }
        container.loadPersistentStores { _, error in
            if let error = error {
                print("[COREDATA] Load error: \(error)")
            } else {
                print("[COREDATA] Successfully loaded")
            }
        }
        return container
    }()

    private let useInMemoryStore: Bool

    init(useInMemoryStore: Bool = false) {
        self.useInMemoryStore = useInMemoryStore
        setupTrainingPlan()
        calculateCurrentWeek()
        loadPlanVersions()
        // Sync to widget on every launch so it always has current data
        AppGroupConstants.syncWeeksToWidget(weeks)
    }

    init(weeks externalWeeks: [TrainingWeek]?, useInMemoryStore: Bool = false) {
        self.useInMemoryStore = useInMemoryStore
        if let externalWeeks, !externalWeeks.isEmpty {
            // Always anchor Week 1 to the Monday of the onboarding week so
            // today lands inside Week 1 and weeks render Mon–Sun — even if
            // the LLM or a cached plan carried non-Monday startDates.
            let anchor = OnboardingStore.onboardingDate ?? Date()
            let normalized = TrainingWeek.anchorWeek1(to: anchor, weeks: externalWeeks)
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            if let first = normalized.first {
                print("[PLAN INIT] anchor=\(fmt.string(from: anchor)) W1=\(fmt.string(from: first.startDate))–\(fmt.string(from: first.endDate)) (\(normalized.count) weeks) rawFirst=\(fmt.string(from: externalWeeks.sorted { $0.weekNumber < $1.weekNumber }.first!.startDate))")
            }
            self.weeks = normalized
            insertAllSecondaryRaceCards()
            calculateCurrentWeek()
            // Start with the generated plan, then let any saved Core Data version
            // (from prior chat modifications) override it so changes persist across launches.
            loadPlanVersions()
        } else {
            setupTrainingPlan()
            calculateCurrentWeek()
            loadPlanVersions()
        }
        AppGroupConstants.syncWeeksToWidget(weeks)
    }

    func calculateCurrentWeek() {
        guard !weeks.isEmpty else {
            currentWeekNumber = 1
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sorted = weeks.sorted { $0.weekNumber < $1.weekNumber }

        // 1. Find the week whose [startDate, endDate] range contains today.
        if let match = sorted.first(where: { week in
            let start = calendar.startOfDay(for: week.startDate)
            let end = calendar.startOfDay(for: week.endDate)
            return today >= start && today <= end
        }) {
            currentWeekNumber = match.weekNumber
            return
        }

        // 2. Before the plan starts → week 1. After the plan ends → last week.
        let firstStart = calendar.startOfDay(for: sorted.first!.startDate)
        let lastEnd = calendar.startOfDay(for: sorted.last!.endDate)
        if today < firstStart {
            currentWeekNumber = sorted.first!.weekNumber
        } else if today > lastEnd {
            currentWeekNumber = sorted.last!.weekNumber
        } else {
            // Gap between weeks — pick the closest prior week.
            let prior = sorted.last(where: { calendar.startOfDay(for: $0.startDate) <= today })
            currentWeekNumber = prior?.weekNumber ?? sorted.first!.weekNumber
        }
    }

    func getWeek(_ weekNumber: Int) -> TrainingWeek? {
        return weeks.first { $0.weekNumber == weekNumber }
    }

    /// Restore the original hardcoded 17-week Ironman 70.3 Oregon plan
    func restoreHardcodedPlan() {
        weeks = []
        setupTrainingPlan()
        AppGroupConstants.syncWeeksToWidget(weeks)
    }

    /// Replace current plan with externally generated weeks.
    /// Automatically re-inserts secondary race cards so they survive regeneration.
    func loadPlan(_ newWeeks: [TrainingWeek]) {
        let anchor = OnboardingStore.onboardingDate ?? Date()
        weeks = TrainingWeek.anchorWeek1(to: anchor, weeks: newWeeks)
        insertAllSecondaryRaceCards()
        calculateCurrentWeek()
        AppGroupConstants.syncWeeksToWidget(weeks)
    }

    /// Insert race cards for all known secondary races. Safe to call multiple times.
    func insertAllSecondaryRaceCards() {
        for race in PrepRacesManager.shared.races {
            insertSecondaryRaceCard(race)
        }
    }

    /// Insert a secondary race card on the race day, replacing any existing workouts for that day.
    func insertSecondaryRaceCard(_ race: PrepRace) {
        let calendar = Calendar.current
        let raceDay = calendar.startOfDay(for: race.date)
        let dayAbbrevs = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        guard let weekIdx = weeks.firstIndex(where: { week in
            calendar.startOfDay(for: week.startDate) <= raceDay &&
            calendar.startOfDay(for: week.endDate) >= raceDay
        }) else { return }

        let week = weeks[weekIdx]
        // Compute Monday of the week (startDate may not be exactly Monday for generated plans)
        var mondayCal = Calendar(identifier: .gregorian)
        mondayCal.firstWeekday = 2
        let mondayComps = mondayCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: week.startDate)
        let weekMonday = mondayCal.date(from: mondayComps) ?? week.startDate
        let weekStart = calendar.startOfDay(for: weekMonday)
        let dayOffset = calendar.dateComponents([.day], from: weekStart, to: raceDay).day ?? 0
        guard dayOffset >= 0 && dayOffset < 7 else { return }
        let dayAbbrev = dayAbbrevs[dayOffset]

        let raceCard = DayWorkout(
            day: dayAbbrev,
            type: "\u{1F3C5} \(race.name)",
            duration: race.distance,
            zone: "Race",
            status: "secondary_race",
            nutritionTarget: nil,
            notes: race.notes
        )

        // Remove any existing secondary race card for this race across ALL days (handles AI-injected duplicates)
        var updatedWorkouts = week.workouts.filter { workout in
            !(workout.status == "secondary_race" && workout.type.contains(race.name))
        }
        // Also remove any non-race workouts on the target day
        updatedWorkouts = updatedWorkouts.filter { $0.day != dayAbbrev }
        updatedWorkouts.append(raceCard)
        updatedWorkouts.sort {
            (dayAbbrevs.firstIndex(of: $0.day) ?? 0) < (dayAbbrevs.firstIndex(of: $1.day) ?? 0)
        }

        weeks[weekIdx] = TrainingWeek(
            weekNumber: week.weekNumber,
            phase: week.phase,
            startDate: week.startDate,
            endDate: week.endDate,
            workouts: updatedWorkouts
        )
        AppGroupConstants.syncWeeksToWidget(weeks)
    }

    /// Replace specific weeks by weekNumber (used after surrounding-plan regeneration).
    func replaceWeeks(_ newWeeks: [TrainingWeek]) {
        for newWeek in newWeeks {
            if let idx = weeks.firstIndex(where: { $0.weekNumber == newWeek.weekNumber }) {
                weeks[idx] = newWeek
            }
        }
        AppGroupConstants.syncWeeksToWidget(weeks)
    }

    /// Drag-and-drop swap/move within a single week.
    /// - If the destination day already has a non-rest workout, the two
    ///   workouts swap days (true swap).
    /// - If the destination day is empty/rest, the source moves there.
    /// Persists a plan version so the change is undoable.
    func swapOrMoveWorkout(weekNumber: Int, source: DayWorkout, sourceDay: String, destDay: String) {
        guard sourceDay != destDay else { return }
        guard let weekIdx = weeks.firstIndex(where: { $0.weekNumber == weekNumber }) else { return }
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let week = weeks[weekIdx]
        var workouts = week.workouts

        guard let srcIdx = workouts.firstIndex(where: { $0 == source }) else { return }

        // Find a non-rest workout on the destination day to swap with, if any.
        let destIdx = workouts.firstIndex(where: {
            $0.day == destDay && !$0.type.lowercased().contains("rest")
        })

        // Rebuild source on the new day.
        let movedSrc = DayWorkout(
            day: destDay,
            type: source.type,
            duration: source.duration,
            zone: source.zone,
            status: source.status,
            nutritionTarget: source.nutritionTarget,
            notes: source.notes
        )
        workouts[srcIdx] = movedSrc

        let isSwap: Bool
        if let dIdx = destIdx {
            let dest = workouts[dIdx]
            workouts[dIdx] = DayWorkout(
                day: sourceDay,
                type: dest.type,
                duration: dest.duration,
                zone: dest.zone,
                status: dest.status,
                nutritionTarget: dest.nutritionTarget,
                notes: dest.notes
            )
            isSwap = true
        } else {
            isSwap = false
        }

        workouts.sort {
            (dayOrder.firstIndex(of: $0.day) ?? 0) < (dayOrder.firstIndex(of: $1.day) ?? 0)
        }
        weeks[weekIdx] = TrainingWeek(
            weekNumber: week.weekNumber,
            phase: week.phase,
            startDate: week.startDate,
            endDate: week.endDate,
            workouts: workouts
        )
        let verb = isSwap ? "Swapped" : "Moved"
        savePlanVersion(source: "drag", description: "\(verb) \(sourceDay) ↔ \(destDay) (Week \(weekNumber))")
        AppGroupConstants.syncWeeksToWidget(weeks)
    }

    private func setupTrainingPlan() {
        let phaseNames = ["Ramp Up", "Ramp Up", "Ramp Up", "Ramp Up", "Build 1", "Build 1", "Build 2", "Build 2", "Build 3", "Taper", "Taper", "Taper", "Race Prep", "Race Prep", "Race Prep", "Rest", "Race Week"]

        for week in 1...17 {
            let weekStartDate = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: planStartDate) ?? planStartDate
            let weekEndDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate

            weeks.append(TrainingWeek(
                weekNumber: week,
                phase: phaseNames[week - 1],
                startDate: weekStartDate,
                endDate: weekEndDate,
                workouts: workoutsForWeek(week)
            ))
        }

        // Sort by week number
        weeks.sort { $0.weekNumber < $1.weekNumber }
    }

    private func workoutsForWeek(_ weekNumber: Int) -> [DayWorkout] {
        // 100% Accurate workouts from IRONMAN_703_Oregon_Sub6_Plan_FINAL.pdf
        let baseWorkouts: [[DayWorkout]] = [
            // Week 1 — Mar 23 (~7.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,600yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 6x100 Z2 (15s rest) + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "40min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "Shoulder prehab 15min after ride"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,800yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 800 Z2 continuous + 300 CD. Catch + bilateral drill focus."),
                DayWorkout(day: "Sat", type: "\u{1F3C3} Run", duration: "50min", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Long run"),
                DayWorkout(day: "Sun", type: "\u{1F6B4} Bike", duration: "1:45", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 2 gels + 1 bottle sport drink/hr", notes: "Long ride")
            ],
            // Week 2 — Mar 30 (~8 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,800yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 8x100 Z2 (15s rest) + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:15", zone: "Z2", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff", notes: "Bike 2:00 Z2 + Brick Run 15min @ 9:15 pace. First brick. Practice T2."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 1000 continuous Z2 + 300 CD"),
                DayWorkout(day: "Fri", type: "\u{1F3C3} Run", duration: "30min", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Double day — easy effort"),
                DayWorkout(day: "Sat", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "Shoulder prehab after ride"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil)
            ],
            // Week 3 — Apr 6 (~8.5 hrs) — Add 3rd bike
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil, notes: "Optional: 20min Drill Set C practice (4x50 Single-Arm, 4x50 3-Stroke Glide)"),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 6x150 Z2 (15s rest) + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike + mini-brick", duration: "1:10", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "Bike 1:00 Z2 + mini-brick run 10min @ 9:15 pace. Midweek mini-brick starts. Prehab after."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,200yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 4x200 Z2 (20s rest) + 200 CD. OWS if weather allows."),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:35", zone: "Z2", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff", notes: "Bike 2:15 Z2 + Brick Run 20min @ 9:00-9:15 pace"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "60min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 4 — Apr 13 — RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "200 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 600 easy + 300 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "30min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "Prehab after ride"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "200 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 600 easy + 300 CD"),
                DayWorkout(day: "Sat", type: "\u{1F3C3} Run", duration: "35min", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "No brick this week"),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil, notes: "Full recovery day")
            ],
            // Week 5 — Apr 20 (~9 hrs) - Build 1
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "WU 15min, 5x5min Z4 w/ 3min recovery intervals, CD. Key bike intensity session."),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,200yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 6x100 descend (15s rest) + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "50min", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Z2 with 4x20s strides"),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "Z2 + mini-brick run 10min @ 9:00 pace. Prehab after."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,400yd", zone: "Z2-Z3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 4x200 Z2/Z3 alternating (20s rest) + 200 CD"),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:35", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff", notes: "Bike 2:30 Z2 + Brick Run 25min (10min @ 9:15, 15min @ 8:45-9:00). Gut training: 50-60g carbs/hr."),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "70min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink", notes: "Back-to-back fatigue training. Optional: 1,000yd easy swim after.")
            ],
            // Week 6 — Apr 27 (~9.5 hrs) - Build 1
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "WU 15min, 4x7min Z4 w/ 3min recovery intervals, CD"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,400yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 4x150 descend + 4x50 fast + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Z2 with 4x20s strides"),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "1:00 + mini-brick", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "Bike 1:00 Z2 + mini-brick run 12min @ 8:50-9:00 pace. Prehab after."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,500yd", zone: "Z2-Z3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 800 continuous Z2 + 4x100 Z3 + 200 CD"),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:55", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff", notes: "Bike 2:45 Z2 + Brick Run 30min (10min @ 9:15, 15min @ 8:45, 5min @ 8:30 if HR ok). Gut training: 60g carbs/hr."),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "75min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 7 — May 4 (~10 hrs) - Build 1 KEY WEEK
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "WU 15min, 3x10min Z4 w/ 4min recovery intervals, CD. Key bike week."),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set C (4x50 Single-Arm alternating, 4x50 3-Stroke Glide) + 6x150 descend + 200 fast + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Tempo Run", duration: "60min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink", notes: "WU 15min, 25min @ 8:15 Denver pace, CD 20min. Key run session."),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike + mini-brick", duration: "1:15", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "Bike 1:00 Z2 + mini-brick run 15min @ 8:50 pace. Prehab after."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,800yd", zone: "Z2-Z3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 5x200 Z2/Z3 alternating + 4x50 sprint + 200 CD"),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "3:35", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60-80g carbs/hr, Run: 30-45g/hr. Add real food for 3+ hr ride", notes: "Bike 3:00 Z2 + Brick Run 35min (10min @ 9:15, 20min @ 8:45, 5min @ 8:15 if HR<155). Gut training: 70g carbs/hr."),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "80min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 8 — May 11 — RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,800yd", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "200 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 800 easy + 400 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "30min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "Prehab after ride"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "Easy swim"),
                DayWorkout(day: "Sat", type: "\u{1F3C3} Run", duration: "35min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil, notes: "Sleep 8+ hours")
            ],
            // Week 9 — May 18 (~10.5 hrs) - Build 2 / Race Specificity
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z3-4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "2x15min Z3-4 w/ 5min recovery intervals"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,500yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 3x300 race-pace (30s rest) + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Z2 with strides"),
                DayWorkout(day: "Thu", type: "\u{1F3C3} Tempo Run", duration: "65min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink", notes: "WU 15min, 30min @ 8:15 Denver pace, CD 20min. Key run + midweek brick: bike 1:00 Z2 + run 10min @ 9:00. Prehab after."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 800 race-pace + 4x100 Z3 + 200 CD"),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Race Sim", duration: "3:25", zone: "Z2-3", status: nil, nutritionTarget: "Race simulation: Bike 60-80g carbs/hr, Run 30-45g/hr. Full race nutrition rehearsal", notes: "Bike 2:45 (last 60min @ 135-145 HR) + Brick Run 40min (15min @ 9:15, 15min @ 8:45, 10min @ 8:30). Gut training: 80g/hr. Lock in race products."),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "90min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink", notes: "Midday run in heat — heat protocol starts")
            ],
            // Week 10 — May 25 - SPRINT TRI TUNE-UP (~9 hrs + race)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "Reduced volume pre-race"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,200yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 4x200 Z2/Z3 (20s rest) + 200 CD. Reduced volume pre-race."),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "40min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "Include 4x30s openers. Prehab after."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Easy swim with 4x50 race-pace. Pre-race activation."),
                DayWorkout(day: "Fri", type: "\u{1F3C3} Run", duration: "20min", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "Shakeout run — pre-race activation"),
                DayWorkout(day: "Sat", type: "\u{2605} SPRINT TRI", duration: "Race", zone: "-", status: nil, nutritionTarget: nil, notes: "Practice transitions, pacing, and nutrition strategy"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Run", duration: "60min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink", notes: "Or rest if fatigued from race")
            ],
            // Week 11 — Jun 1 - PEAK WEEK (~11-12 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z3-4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "3x12min Z3-4 w/ 4min recovery intervals"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "3,000yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set C (4x50 Single-Arm alternating, 4x50 3-Stroke Glide) + 4x300 race-pace (30s rest) + 4x50 sprint + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Tempo Run", duration: "70min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink", notes: "WU 15min, 35min @ 8:15 Denver pace, CD 20min. Key run week."),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike + mini-brick", duration: "1:15", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "Bike 1:00 Z2 + mini-brick run 15min @ 8:45-9:00. Prehab after."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "OWS if possible: race-pace 1000 continuous"),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} KEY BRICK", duration: "3:50", zone: "Z2-3", status: nil, nutritionTarget: "Race simulation: Bike 60-80g carbs/hr, Run 30-45g/hr. Full race nutrition rehearsal", notes: "Bike 3:00 @ race effort + Run 50min (15min @ 9:15, 25min @ 8:45, 10min @ 8:30). Full nutrition: 80-100g/hr. Take gel immediately off bike."),
                DayWorkout(day: "Sun", type: "\u{1F3C3} LONGEST RUN", duration: "1:45", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink, practice race-day intake", notes: "Time on feet — not fast. Longest run of the plan.")
            ],
            // Week 12 — Jun 8 - RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "200 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 1000 easy + 400 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "30min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "Prehab after ride"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "Easy swim"),
                DayWorkout(day: "Sat", type: "\u{1F3C3} Run", duration: "35min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil, notes: "HRV should recover to baseline")
            ],
            // Week 13 — Jun 15 (~9.5 hrs) - DRESS REHEARSAL
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "2x12min @ race HR 135-145"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,500yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 3x300 race-pace (30s rest) + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F3C3} Run", duration: "60min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink", notes: "WU 15min, 5mi @ 8:15-8:30 pace, CD. Then mini-brick: bike 45min + run 10min @ 9:00. Prehab after."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,400yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set C (4x50 Single-Arm alternating, 4x50 3-Stroke Glide) + 600 race-pace + 4x100 Z3 + 200 CD"),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} DRESS REHEARSAL", duration: "3:05", zone: "Z2-3", status: nil, nutritionTarget: "Race simulation: Bike 60-80g carbs/hr, Run 30-45g/hr. Full race nutrition rehearsal", notes: "Bike 2:30 @ race effort + Run 35min (9:15 -> 8:45 -> 8:30). Full nutrition rehearsal. Time T1/T2."),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "75min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 14 — Jun 22 (~8.5 hrs) - Peak & Sharpen
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "2x10min @ race HR. Volume down 15%."),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,200yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 4x200 race-pace (20s rest) + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike + mini-brick", duration: "55min", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "Bike 45min Z2 + mini-brick run 10min @ 8:50. Prehab after."),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 500 race-pace + 200 CD"),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:25", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff", notes: "Bike 2:00 @ race effort + Brick Run 25min (8:45-9:00 pace)"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Run", duration: "60min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 15 — Jun 29 (~8 hrs) - Last hard week
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "15min @ race HR"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set A (4x50 Catch-Up, 4x50 Fingertip Drag) + 3x200 race-pace (20s rest) + 200 CD"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Tempo Run", duration: "50min", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "WU 15min, 3mi @ 8:15-8:30 pace, CD. Last tempo run."),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Prehab after ride"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil, notes: "300 WU + Drill Set B (4x50 6-Kick Switch, 4x50 Side Kick) + 400 race-pace + 200 CD"),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:05", zone: "Z2", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff", notes: "Bike 1:45 (30min @ race effort) + Brick Run 20min @ 8:45. Last real brick."),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Run", duration: "50min", zone: "Z2", status: nil, nutritionTarget: nil)
            ],
            // Week 16 — Jul 6 - TAPER (~5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Include 4x100 fast"),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min", notes: "Include 15min Z3-4 openers"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "35min", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Include 2mi @ 8:45 pace"),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,200yd", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "Easy swim"),
                DayWorkout(day: "Fri", type: "\u{1F3C3} Run", duration: "20min", zone: "Z1-2", status: nil, nutritionTarget: nil, notes: "Shakeout run"),
                DayWorkout(day: "Sat", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil, notes: "Sleep 8+. Carb-load begins."),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
            ],
            // Week 17 — Jul 13 - RACE WEEK
            [
                DayWorkout(day: "Mon", type: "\u{2708}\u{FE0F} Travel", duration: "Denver\u{2192}Portland", zone: "-", status: nil, nutritionTarget: nil, notes: "Fly Denver to Portland, drive to Salem. Build bike, walk transitions."),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,000yd", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Include 4x50 race-pace openers. OWS in Willamette if allowed."),
                DayWorkout(day: "Wed", type: "\u{1F6B4} Bike + \u{1F3C3} Run", duration: "40min + 15min", zone: "Z2", status: nil, nutritionTarget: nil, notes: "Bike 40min w/ 10min Z3 openers + Run 15min shakeout"),
                DayWorkout(day: "Thu", type: "\u{1F3C3} Easy Jog", duration: "20min", zone: "Z1", status: nil, nutritionTarget: nil, notes: "Athlete briefing. Walk T1/T2. Lay out kit."),
                DayWorkout(day: "Fri", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil, notes: "Rack bike. Prep nutrition. Carb-load. Sleep early."),
                DayWorkout(day: "Sat", type: "\u{1F3CA} Shakeout Swim", duration: "15min", zone: "Z1", status: nil, nutritionTarget: nil, notes: "15min shakeout jog + 10min easy swim. Prep race morning bag. Early bed."),
                DayWorkout(day: "Sun", type: "\u{1F3C1} RACE DAY", duration: "~5:45-5:58", zone: "Race", status: nil, nutritionTarget: nil, notes: "Alarm 3 AM. Eat 3:30. Arrive 5:00. Execute. Swim: sight every 6-8 strokes. Bike: 135-145 HR, no surges. Run: 9:00-9:15 start, negative split to 8:15-8:30.")
            ]
        ]

        guard weekNumber >= 1 && weekNumber <= baseWorkouts.count else {
            return []
        }

        return baseWorkouts[weekNumber - 1]
    }

    func savePlanVersion(source: String, description: String?) {
        let context = container.viewContext

        // Serialize current weeks to JSON
        let encoder = JSONEncoder()
        do {
            let weeksData = try encoder.encode(weeks)

            // Create new WorkoutPlanVersion
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "WorkoutPlanVersion")
            fetchRequest.predicate = NSPredicate(format: "isCurrent == true")

            // Mark old current version as previous
            if let oldVersion = try context.fetch(fetchRequest).first as? NSManagedObject {
                oldVersion.setValue(false, forKey: "isCurrent")
            }

            // Create new version
            let newVersion = NSEntityDescription.insertNewObject(forEntityName: "WorkoutPlanVersion", into: context)
            newVersion.setValue(UUID(), forKey: "id")
            newVersion.setValue(Date(), forKey: "createdAt")
            newVersion.setValue(source, forKey: "source")
            newVersion.setValue(weeksData, forKey: "weeklyPlanData")
            newVersion.setValue(description ?? "Rescheduled workouts", forKey: "changeDescription")
            newVersion.setValue(true, forKey: "isCurrent")

            try context.save()

            // Update in-memory references
            self.previousPlanVersion = self.currentPlanVersion
            self.currentPlanVersion = newVersion

            print("[SAVE] Plan version saved: source=\(source)")
        } catch {
            print("[SAVE] Failed to save plan version: \(error)")
        }
    }

    func applyRescheduledPlan(_ newWeeks: [TrainingWeek], source: String = "chat", description: String? = nil) {
        // Update in-memory weeks
        self.weeks = newWeeks

        print("[PLAN] Applied rescheduled plan from source: \(source)")
        savePlanVersion(source: source, description: description)

        // Sync to widget via App Group
        AppGroupConstants.syncWeeksToWidget(newWeeks)
    }

    func rollbackToPreviousVersion() -> Bool {
        guard let previousVersion = previousPlanVersion,
              let data = previousVersion.value(forKey: "weeklyPlanData") as? Data else {
            print("[ROLLBACK] No previous version available")
            return false
        }

        let decoder = JSONDecoder()
        do {
            let restoredWeeks = try decoder.decode([TrainingWeek].self, from: data)
            self.weeks = restoredWeeks

            self.currentPlanVersion = previousVersion
            self.previousPlanVersion = nil

            print("[ROLLBACK] Successfully restored previous version")
            return true
        } catch {
            print("[ROLLBACK] Failed: \(error)")
            return false
        }
    }

    /// Wipes every persisted WorkoutPlanVersion so re-onboarding doesn't inherit
    /// stale chat-edited plan data from the prior onboarding.
    func clearAllPlanVersions() {
        let context = container.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "WorkoutPlanVersion")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        do {
            try context.execute(deleteRequest)
            try context.save()
            self.currentPlanVersion = nil
            self.previousPlanVersion = nil
            print("[COREDATA] Cleared all WorkoutPlanVersion rows")
        } catch {
            print("[COREDATA] Failed to clear plan versions: \(error)")
        }
    }

    func loadPlanVersions() {
        let context = container.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "WorkoutPlanVersion")
        fetchRequest.predicate = NSPredicate(format: "isCurrent == true")

        do {
            let results = try context.fetch(fetchRequest)
            if let currentVersion = results.first as? NSManagedObject {
                self.currentPlanVersion = currentVersion

                // Restore weeks from the saved version
                if let data = currentVersion.value(forKey: "weeklyPlanData") as? Data {
                    let decoder = JSONDecoder()
                    if let restoredWeeks = try? decoder.decode([TrainingWeek].self, from: data) {
                        // Snap to Mon–Sun but preserve saved positioning —
                        // the user's prior edits shouldn't jump in time.
                        self.weeks = TrainingWeek.snapToMondaySunday(restoredWeeks)
                        print("[COREDATA] Restored current plan version from Core Data")
                    }
                }
            }

            // Don't load previous version on app startup - only set it during plan modifications
            // This prevents the undo button from showing when there's no actual recent change
            self.previousPlanVersion = nil
            print("[COREDATA] Loaded current plan version")
        } catch {
            print("[COREDATA] Failed to load versions: \(error)")
        }
    }
}
