import Foundation
import CoreData

// MARK: - Training Plan Data
struct TrainingWeek: Codable, Equatable {
    let weekNumber: Int
    let phase: String
    let startDate: Date
    let endDate: Date
    let workouts: [DayWorkout]
}

struct DayWorkout: Equatable, Codable, Identifiable, Hashable {
    let day: String
    let type: String
    let duration: String
    let zone: String
    let status: String?
    let nutritionTarget: String?

    var id: String {
        "\(day)-\(type)-\(duration)-\(zone)"
    }
}

struct SwapCommand: Codable {
    let weekNumber: Int
    let fromDay: String
    let toDay: String
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

    private let planStartDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 23
        return Calendar.current.date(from: components) ?? Date()
    }()

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
    }

    func calculateCurrentWeek() {
        let calendar = Calendar.current
        let today = Date()

        let daysSinceStart = calendar.dateComponents([.day], from: planStartDate, to: today).day ?? 0
        let weekNumber = (daysSinceStart / 7) + 1

        // Clamp between 1 and 17
        currentWeekNumber = max(1, min(17, weekNumber))
    }

    func getWeek(_ weekNumber: Int) -> TrainingWeek? {
        return weeks.first { $0.weekNumber == weekNumber }
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
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,600yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "40min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,800yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F3C3} Run", duration: "50min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "\u{1F6B4} Bike", duration: "1:45", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 2 gels + 1 bottle sport drink/hr")
            ],
            // Week 2 — Mar 30 (~8 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,800yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3C3} Run", duration: "30min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:15", zone: "Z2", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil)
            ],
            // Week 3 — Apr 6 (~8.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike + mini-brick", duration: "1:10", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,200yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:35", zone: "Z2", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "60min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 4 — Apr 13 — RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "30min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F3C3} Run", duration: "35min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
            ],
            // Week 5 — Apr 20 (~9 hrs) - Build 1
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,200yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "50min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,400yd", zone: "Z2-Z3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:35", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "70min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 6 — Apr 27 (~9.5 hrs) - Build 1
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,400yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "1:00 + mini-brick", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,500yd", zone: "Z2-Z3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:55", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "75min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 7 — May 4 (~10 hrs) - Build 1 KEY WEEK
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Tempo Run", duration: "60min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink"),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike + mini-brick", duration: "1:15", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,800yd", zone: "Z2-Z3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "3:35", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60-80g carbs/hr, Run: 30-45g/hr. Add real food for 3+ hr ride"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "80min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 8 — May 11 — RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,800yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "30min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F3C3} Run", duration: "35min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
            ],
            // Week 9 — May 18 (~10.5 hrs) - Build 2 / Race Specificity
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z3-4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,500yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F3C3} Tempo Run", duration: "65min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Race Sim", duration: "3:25", zone: "Z2-3", status: nil, nutritionTarget: "Race simulation: Bike 60-80g carbs/hr, Run 30-45g/hr. Full race nutrition rehearsal"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "90min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 10 — May 25 - SPRINT TRI TUNE-UP
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,200yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "40min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3C3} Run", duration: "20min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{2605} SPRINT TRI", duration: "Race", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Run", duration: "60min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 11 — Jun 1 - PEAK WEEK (~11-12 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z3-4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "3,000yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Tempo Run", duration: "70min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink"),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike + mini-brick", duration: "1:15", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} KEY BRICK", duration: "3:50", zone: "Z2-3", status: nil, nutritionTarget: "Race simulation: Bike 60-80g carbs/hr, Run 30-45g/hr. Full race nutrition rehearsal"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} LONGEST RUN", duration: "1:45", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink, practice race-day intake")
            ],
            // Week 12 — Jun 8 - RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "30min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F3C3} Run", duration: "35min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
            ],
            // Week 13 — Jun 15 (~9.5 hrs) - DRESS REHEARSAL
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:15", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,500yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F3C3} Run", duration: "60min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink"),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,400yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} DRESS REHEARSAL", duration: "3:05", zone: "Z2-3", status: nil, nutritionTarget: "Race simulation: Bike 60-80g carbs/hr, Run 30-45g/hr. Full race nutrition rehearsal"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Long Run", duration: "75min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 14 — Jun 22 (~8.5 hrs) - Peak & Sharpen
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,200yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike + mini-brick", duration: "55min", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:25", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Run", duration: "60min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 15 — Jun 29 (~8 hrs) - Last hard week
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "2,000yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Tempo Run", duration: "50min", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F6B4}+\u{1F3C3} Brick", duration: "2:05", zone: "Z2", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "\u{1F3C3} Run", duration: "50min", zone: "Z2", status: nil, nutritionTarget: nil)
            ],
            // Week 16 — Jul 6 - TAPER (~5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,500yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Wed", type: "\u{1F3C3} Run", duration: "35min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F6B4} Bike", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3CA} Swim", duration: "1,200yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "\u{1F3C3} Run", duration: "20min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
            ],
            // Week 17 — Jul 13 - RACE WEEK
            [
                DayWorkout(day: "Mon", type: "\u{2708}\u{FE0F} Travel", duration: "Denver\u{2192}Portland", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "\u{1F3CA} Swim", duration: "1,000yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "\u{1F6B4} Bike + \u{1F3C3} Run", duration: "40min + 15min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "\u{1F3C3} Easy Jog", duration: "20min", zone: "Z1", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "\u{1F3CA} Shakeout Swim", duration: "15min", zone: "Z1", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "\u{1F3C1} RACE DAY", duration: "~5:45-5:58", zone: "Race", status: nil, nutritionTarget: nil)
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
                        // Check if restored data is stale (missing nutritionTarget field added later)
                        let hasNutritionData = restoredWeeks.flatMap(\.workouts).contains { $0.nutritionTarget != nil }
                        if hasNutritionData {
                            self.weeks = restoredWeeks
                            print("[COREDATA] Restored current plan version from Core Data")
                        } else {
                            // Stale data from before nutrition targets — use fresh plan data
                            // Re-save so future loads have the updated schema
                            savePlanVersion(source: "schema_migration", description: "Added nutrition targets")
                            print("[COREDATA] Skipped stale Core Data restore (missing nutrition targets), using fresh plan")
                        }
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
