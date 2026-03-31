import SwiftUI
import Foundation
import HealthKit
import CoreData
import UserNotifications

extension Notification.Name {
    static let navigateToWeek = Notification.Name("navigateToWeek")
}

// MARK: - Shared Formatters
private enum Formatters {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.timeZone = TimeZone.current
        return f
    }()
    static let dayOfWeek: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.timeZone = TimeZone.current
        return f
    }()
    static let shortDayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.timeZone = TimeZone.current
        return f
    }()
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone.current
        return f
    }()
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()
    static let iso8601 = ISO8601DateFormatter()
}

// MARK: - Secrets & Configuration
struct Secrets {
    static let anthropicAPIKey: String = {
        // Load from Config.plist
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath),
           let key = config["ANTHROPIC_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ""
    }()

    static let langsmithAPIKey: String = {
        // Load from Config.plist
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath),
           let key = config["LANGSMITH_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ""
    }()
}

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
        case "Rainy": return "🌧️"
        case "Drizzle": return "🌦️"
        case "Showers": return "🌦️"
        case "Cloudy": return "☁️"
        case "Partly Cloudy": return "⛅"
        case "Mostly Sunny": return "🌤️"
        case "Sunny": return "☀️"
        case "Fair": return "🌤️"
        case "Sunny & Warm": return "☀️"
        case "Sunny & Hot": return "🔥"
        case "Hot & Sunny": return "🔥"
        case "Clear": return "☀️"
        default: return "🌤️"
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
        container.loadPersistentStores { _, error in
            if let error = error {
                print("[COREDATA] Load error: \(error)")
            } else {
                print("[COREDATA] Successfully loaded")
            }
        }
        return container
    }()

    init() {
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
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,600yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "40min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,800yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🏃 Run", duration: "50min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "🚴 Bike", duration: "1:45", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 2 gels + 1 bottle sport drink/hr")
            ],
            // Week 2 — Mar 30 (~8 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,800yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:15", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,000yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏃 Run", duration: "30min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:15", zone: "Z2", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil)
            ],
            // Week 3 — Apr 6 (~8.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,000yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike + mini-brick", duration: "1:10", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,200yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:35", zone: "Z2", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "60min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 4 — Apr 13 — RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "30min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🏃 Run", duration: "35min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
            ],
            // Week 5 — Apr 20 (~9 hrs) - Build 1
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,200yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "50min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,400yd", zone: "Z2-Z3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:35", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "70min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 6 — Apr 27 (~9.5 hrs) - Build 1
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,400yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "1:00 + mini-brick", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,500yd", zone: "Z2-Z3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:55", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "75min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 7 — May 4 (~10 hrs) - Build 1 KEY WEEK
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Tempo Run", duration: "60min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink"),
                DayWorkout(day: "Thu", type: "🚴 Bike + mini-brick", duration: "1:15", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,800yd", zone: "Z2-Z3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "3:35", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60-80g carbs/hr, Run: 30-45g/hr. Add real food for 3+ hr ride"),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "80min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 8 — May 11 — RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,800yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "30min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🏃 Run", duration: "35min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
            ],
            // Week 9 — May 18 (~10.5 hrs) - Build 2 / Race Specificity
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z3-4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,500yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🏃 Tempo Run", duration: "65min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink"),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Race Sim", duration: "3:25", zone: "Z2-3", status: nil, nutritionTarget: "Race simulation: Bike 60-80g carbs/hr, Run 30-45g/hr. Full race nutrition rehearsal"),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "90min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 10 — May 25 - SPRINT TRI TUNE-UP
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,200yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "40min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,500yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏃 Run", duration: "20min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "★ SPRINT TRI", duration: "Race", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "🏃 Run", duration: "60min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 11 — Jun 1 - PEAK WEEK (~11-12 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z3-4", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "3,000yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Tempo Run", duration: "70min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink"),
                DayWorkout(day: "Thu", type: "🚴 Bike + mini-brick", duration: "1:15", zone: "Z2", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 KEY BRICK", duration: "3:50", zone: "Z2-3", status: nil, nutritionTarget: "Race simulation: Bike 60-80g carbs/hr, Run 30-45g/hr. Full race nutrition rehearsal"),
                DayWorkout(day: "Sun", type: "🏃 LONGEST RUN", duration: "1:45", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink, practice race-day intake")
            ],
            // Week 12 — Jun 8 - RECOVERY (~5.5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,000yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "30min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,500yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🏃 Run", duration: "35min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
            ],
            // Week 13 — Jun 15 (~9.5 hrs) - DRESS REHEARSAL
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:15", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,500yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "55min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🏃 Run", duration: "60min", zone: "Z2-3", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink"),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,400yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 DRESS REHEARSAL", duration: "3:05", zone: "Z2-3", status: nil, nutritionTarget: "Race simulation: Bike 60-80g carbs/hr, Run 30-45g/hr. Full race nutrition rehearsal"),
                DayWorkout(day: "Sun", type: "🏃 Long Run", duration: "75min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 14 — Jun 22 (~8.5 hrs) - Peak & Sharpen
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,200yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike + mini-brick", duration: "55min", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "2,000yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:25", zone: "Z2-3", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "🏃 Run", duration: "60min", zone: "Z2", status: nil, nutritionTarget: "30-45g carbs/hr: 1 gel per 30min + electrolyte drink")
            ],
            // Week 15 — Jun 29 (~8 hrs) - Last hard week
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "2,000yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🏃 Tempo Run", duration: "50min", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,800yd", zone: "Z2-3", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🚴+🏃 Brick", duration: "2:05", zone: "Z2", status: nil, nutritionTarget: "Bike: 60g carbs/hr, Run: 30-45g/hr. Practice T2 nutrition handoff"),
                DayWorkout(day: "Sun", type: "🏃 Run", duration: "50min", zone: "Z2", status: nil, nutritionTarget: nil)
            ],
            // Week 16 — Jul 6 - TAPER (~5 hrs)
            [
                DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,500yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🚴 Bike", duration: "1:00", zone: "Z2-3", status: nil, nutritionTarget: "60g carbs/hr: 1 gel + sport drink per 30min"),
                DayWorkout(day: "Wed", type: "🏃 Run", duration: "35min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🚴 Bike", duration: "45min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏊 Swim", duration: "1,200yd", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "🏃 Run", duration: "20min", zone: "Z1-2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
            ],
            // Week 17 — Jul 13 - RACE WEEK
            [
                DayWorkout(day: "Mon", type: "✈️ Travel", duration: "Denver→Portland", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Tue", type: "🏊 Swim", duration: "1,000yd", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Wed", type: "🚴 Bike + 🏃 Run", duration: "40min + 15min", zone: "Z2", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Thu", type: "🏃 Easy Jog", duration: "20min", zone: "Z1", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Fri", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sat", type: "🏊 Shakeout Swim", duration: "15min", zone: "Z1", status: nil, nutritionTarget: nil),
                DayWorkout(day: "Sun", type: "🏁 RACE DAY", duration: "~5:45-5:58", zone: "Race", status: nil, nutritionTarget: nil)
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

// MARK: - HealthKit Manager
class HealthKitManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = HealthKitManager()

    @Published var isAuthorized = false
    @Published var isSyncing = false
    @Published var syncError: String?
    @Published var workouts: [HKWorkout] = []
    @Published var workoutZones: [UUID: [String: Double]] = [:]

    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        checkAuthorization()
        // Auto-request authorization on app open
        Task {
            await self.requestAuthorization()
        }
    }

    func checkAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            syncError = "HealthKit not available"
            return
        }

        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let dobType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        let typesToRead: Set<HKObjectType> = [workoutType, heartRateType, dobType]

        healthStore.getRequestStatusForAuthorization(toShare: [], read: typesToRead) { status, _ in
            DispatchQueue.main.async {
                self.isAuthorized = (status == .unnecessary)
            }
        }
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run {
                syncError = "HealthKit not available"
            }
            return
        }

        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let dobType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        let typesToRead: Set<HKObjectType> = [workoutType, heartRateType, dobType]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            await MainActor.run {
                self.isAuthorized = true
                self.syncError = nil
            }
        } catch {
            await MainActor.run {
                self.isAuthorized = false
                self.syncError = error.localizedDescription
            }
        }
    }

    func syncWorkouts() async {
        await MainActor.run {
            isSyncing = true
            syncError = nil
        }

        // Run sync on background thread to avoid blocking UI
        let result = await Task.detached(priority: .background) { () -> (success: Bool, error: String?) in
            if !self.isAuthorized {
                await self.requestAuthorization()
                if !self.isAuthorized {
                    return (false, "HealthKit permission denied")
                }
            }

            // Only fetch workouts from last 30 days to avoid freezing
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: .strictStartDate)

            let workoutType = HKObjectType.workoutType()
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            return await withCheckedContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: workoutType,
                    predicate: predicate,
                    limit: 100, // Limit to 100 most recent workouts
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(returning: (false, error.localizedDescription))
                        return
                    }

                    if let workouts = results as? [HKWorkout] {
                        DispatchQueue.main.async {
                            self.workouts = workouts
                            self.fetchZonesForRecentWorkouts()
                        }
                    }

                    continuation.resume(returning: (true, nil))
                }

                self.healthStore.execute(query)
            }
        }.value

        await MainActor.run {
            isSyncing = false
            if !result.success {
                syncError = result.error ?? "Unknown error"
            } else {
                syncError = nil
            }
        }
    }

    // MARK: - HR Zone Analysis

    private var cachedAge: Int?

    func getUserAge() -> Int {
        if let cached = cachedAge {
            return cached
        }

        do {
            let dateOfBirth = try healthStore.dateOfBirth()
            let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 38
            cachedAge = age
            return age
        } catch {
            print("Could not read date of birth from HealthKit: \(error)")
            return 38  // Fallback to default age
        }
    }

    var maxHeartRate: Int {
        220 - getUserAge()
    }

    /// BPM zone boundaries derived from maxHeartRate using %maxHR thresholds.
    /// Single source of truth for both analytics and Claude coaching.
    var zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int) {
        let maxHR = Double(maxHeartRate)
        return (
            z2: Int(round(maxHR * 0.69)),
            z3: Int(round(maxHR * 0.79)),
            z4: Int(round(maxHR * 0.85)),
            z5: Int(round(maxHR * 0.92))
        )
    }

    func calculateZoneBreakdown(startDate: Date, endDate: Date, onComplete: @escaping ([String: Double]) -> Void) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            onComplete(["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        var zones: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]

        let bounds = zoneBoundaries

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, results, error in
            if error != nil {
                onComplete(zones)
                return
            }

            guard let samples = results as? [HKQuantitySample] else {
                onComplete(zones)
                return
            }

            for sample in samples {
                let bpm = Int(round(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))))

                let zone: String
                if bpm < bounds.z2 {
                    zone = "Z1"
                } else if bpm < bounds.z3 {
                    zone = "Z2"
                } else if bpm < bounds.z4 {
                    zone = "Z3"
                } else if bpm < bounds.z5 {
                    zone = "Z4"
                } else {
                    zone = "Z5"
                }

                zones[zone] = zones[zone]! + 1
            }

            onComplete(zones)
        }

        healthStore.execute(query)
    }

    func getWorkoutZoneBreakdown(workout: HKWorkout, completion: @escaping ([String: Double]) -> Void) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion([:])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let bounds = zoneBoundaries

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, results, error in
            var zones: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]

            guard let samples = results as? [HKQuantitySample], !samples.isEmpty else {
                completion(zones)
                return
            }

            for sample in samples {
                let bpm = Int(round(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))))
                let zone: String
                if bpm < bounds.z2 { zone = "Z1" }
                else if bpm < bounds.z3 { zone = "Z2" }
                else if bpm < bounds.z4 { zone = "Z3" }
                else if bpm < bounds.z5 { zone = "Z4" }
                else { zone = "Z5" }
                zones[zone] = zones[zone]! + 1
            }

            // Convert counts to percentages
            let total = samples.count
            var percentages: [String: Double] = [:]
            for (zone, count) in zones {
                percentages[zone] = (count / Double(total)) * 100
            }

            completion(percentages)
        }

        healthStore.execute(query)
    }

    func fetchZonesForRecentWorkouts() {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recent = workouts.filter { $0.startDate >= twoWeeksAgo }
        for workout in recent {
            getWorkoutZoneBreakdown(workout: workout) { zones in
                DispatchQueue.main.async {
                    self.workoutZones[workout.uuid] = zones
                }
            }
        }
    }
}


// MARK: - LangSmith Tracer
class LangSmithTracer {
    static let shared = LangSmithTracer()

    private let langsmithAPIKey: String
    private let baseURL = "https://api.smith.langchain.com/runs"
    private let sessionName = "IronmanTrainer"

    init() {
        // Load API key from Secrets (Config.xcconfig)
        self.langsmithAPIKey = Secrets.langsmithAPIKey
    }

    func isEnabled() -> Bool {
        !langsmithAPIKey.isEmpty
    }

    func startRun(systemPrompt: String, userMessage: String) -> String {
        guard isEnabled() else { return "" }

        // LangSmith expects lowercase UUID format without dashes
        let runID = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let now = Formatters.iso8601.string(from: Date())

        let inputs: [String: Any] = [
            "system_prompt": systemPrompt,
            "user_message": userMessage
        ]

        let body: [String: Any] = [
            "id": runID,
            "name": "IronmanCoach",
            "run_type": "llm",
            "inputs": inputs,
            "start_time": now,
            "session_name": sessionName
        ]

        Task {
            await logRunToLangSmith(body)
        }

        return runID
    }

    func endRun(runID: String, response: String) {
        guard isEnabled() && !runID.isEmpty else { return }

        let now = Formatters.iso8601.string(from: Date())

        let outputs: [String: Any] = [
            "response": response
        ]

        let body: [String: Any] = [
            "outputs": outputs,
            "end_time": now
        ]

        Task {
            await updateRunInLangSmith(runID: runID, body: body)
        }
    }

    private func logRunToLangSmith(_ body: [String: Any]) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(langsmithAPIKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 202 {
                    print("✅ LangSmith run logged")
                } else {
                    if let errorText = String(data: data, encoding: .utf8) {
                        print("⚠️ LangSmith error \(httpResponse.statusCode): \(errorText)")
                    } else {
                        print("⚠️ LangSmith error: \(httpResponse.statusCode)")
                    }
                }
            }
        } catch {
            print("❌ LangSmith logging failed: \(error)")
        }
    }

    private func updateRunInLangSmith(runID: String, body: [String: Any]) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        let updateURL = "\(baseURL)/\(runID)"
        var request = URLRequest(url: URL(string: updateURL)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(langsmithAPIKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 202 {
                    print("✅ LangSmith run completed")
                } else {
                    print("⚠️ LangSmith update error: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("❌ LangSmith update failed: \(error)")
        }
    }
}

// MARK: - Claude Service
class ClaudeService: NSObject, ObservableObject {
    static let shared = ClaudeService()

    private let apiKey: String
    private let model = "claude-opus-4-6"
    private let baseURL = "https://api.anthropic.com/v1/messages"

    override init() {
        // Load API key from Secrets (Config.xcconfig)
        self.apiKey = Secrets.anthropicAPIKey
        super.init()
    }

    func sendMessage(userMessage: String, trainingContext: String, workoutHistory: String, zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)? = nil) async throws -> String {
        let systemPrompt = buildSystemPrompt(context: trainingContext, history: workoutHistory, zoneBoundaries: zoneBoundaries)

        // Start LangSmith run
        let runID = LangSmithTracer.shared.startRun(systemPrompt: systemPrompt, userMessage: userMessage)

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": userMessage
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw ClaudeServiceError.invalidRequest
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeServiceError.networkError
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let responseBody = try decoder.decode(ClaudeResponse.self, from: data)
            if let content = responseBody.content.first?.text {
                // End LangSmith run with response
                LangSmithTracer.shared.endRun(runID: runID, response: content)
                return content
            }
            throw ClaudeServiceError.invalidResponse
        case 401:
            throw ClaudeServiceError.invalidAPIKey
        case 429:
            throw ClaudeServiceError.rateLimitExceeded
        default:
            // Return more detailed error info
            if let errorData = String(data: data, encoding: .utf8) {
                print("API Error: \(httpResponse.statusCode) - \(errorData)")
            }
            throw ClaudeServiceError.serverError
        }
    }

    private func buildSystemPrompt(context: String, history: String, zoneBoundaries: (z2: Int, z3: Int, z4: Int, z5: Int)? = nil) -> String {
        let z2 = zoneBoundaries?.z2 ?? 126
        let z3 = zoneBoundaries?.z3 ?? 144
        let z4 = zoneBoundaries?.z4 ?? 155
        let z5 = zoneBoundaries?.z5 ?? 167
        return """
        You are a personal triathlon coaching assistant for Brent, training for Ironman 70.3 Oregon (Jul 19, 2026, Salem OR).

        TRAINING PLAN: 17-week program (Mar 23 - Jul 19, 2026)
        ATHLETE: VO2 Max 57.8, 8-10 hrs/wk available
        HR ZONES: Z1 <\(z2)bpm (recovery) | Z2 \(z2)-\(z3)bpm (endurance) | Z3 \(z3)-\(z4)bpm (tempo) | Z4 \(z4)-\(z5)bpm (threshold) | Z5 \(z5)+bpm (VO2max)
        RACE GOAL: Sub-6:00 finish (Swim 38-42m | Bike 3:00-3:10 | Run 1:55-2:02)

        TRAINING CONTEXT:
        \(context)

        RECENT WORKOUTS:
        \(history)

        Give specific coaching advice based on Brent's training plan, zones, and race strategy.
        """
    }
}

enum ClaudeServiceError: LocalizedError {
    case invalidRequest
    case networkError
    case invalidResponse
    case invalidAPIKey
    case rateLimitExceeded
    case serverError

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid request format"
        case .networkError:
            return "Network connection failed"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .serverError:
            return "Server error"
        }
    }
}

struct ClaudeResponse: Codable {
    struct Content: Codable {
        let text: String
    }

    let content: [Content]
}

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

    init() {
        loadChatHistory()
        loadLastSwap()
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

            let response = try await claudeService.sendMessage(userMessage: text, trainingContext: updatedContext, workoutHistory: history, zoneBoundaries: healthKit?.zoneBoundaries)

            await MainActor.run {
                messages.append(ChatMessage(isUser: false, text: response))
                saveChatHistory()

                // Check for undo swap command
                if response.contains("[UNDO_SWAP]"), let prev = lastSwap {
                    let undoCommand = SwapCommand(weekNumber: prev.weekNumber, fromDay: prev.toDay, toDay: prev.fromDay)
                    if let result = executeSwap(undoCommand) {
                        lastSwap = nil
                        let confirmMsg = ChatMessage(isUser: false, text: "↩️ Undid previous swap: \(result). Your training plan has been restored!")
                        messages.append(confirmMsg)
                        saveChatHistory()
                    }
                }
                // Check for swap command in response and execute it
                else if let command = parseSwapCommand(from: response),
                   let result = executeSwap(command) {
                    lastSwap = command
                    let confirmMsg = ChatMessage(isUser: false, text: "✅ \(result). Your training plan has been updated!")
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
                        var text = "\(workout.type) (\(workout.duration) • \(workout.zone))"
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

                // Skip future days — no actual data expected
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

struct ContentView: View {
    @StateObject private var trainingPlan = TrainingPlanManager()
    @EnvironmentObject var healthKit: HealthKitManager
    @StateObject private var chatViewModel = ChatViewModel()
    var body: some View {
        TabView {
            HomeView()
                .environmentObject(trainingPlan)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            AnalyticsView()
                .environmentObject(trainingPlan)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }

            ChatView(viewModel: chatViewModel)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }

            SettingsView()
                .environmentObject(healthKit)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .onAppear {
            NotificationManager.shared.setTrainingPlan(trainingPlan)
        }
        .onAppear {
            chatViewModel.trainingPlan = trainingPlan
            chatViewModel.healthKit = healthKit
        }
    }
}

// MARK: - Week Navigation Header (Shared)
struct WeekNavigationHeader: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @Binding var selectedWeek: Int
    var completionText: String? = nil
    @State private var showWeekPicker = false

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    var formattedDateRange: String {
        guard let week = currentWeek else { return "" }
        let startStr = Formatters.shortDate.string(from: week.startDate)
        let endStr = Formatters.shortDate.string(from: week.endDate)
        return "\(startStr) - \(endStr), 2026"
    }

    var isCurrentWeek: Bool {
        guard let week = currentWeek else { return false }
        let today = Date()
        let endOfWeek = Calendar.current.date(byAdding: .day, value: 1, to: week.endDate) ?? week.endDate
        return today >= week.startDate && today < endOfWeek
    }

    var body: some View {
        Button(action: { showWeekPicker = true }) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Week \(selectedWeek) - \(currentWeek?.phase ?? "")")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        if isCurrentWeek {
                            Text("Current")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(formattedDateRange)
                            .font(.caption)
                            .foregroundColor(.gray)

                        if let completion = completionText {
                            Text("(\(completion))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width < -30 && selectedWeek < 17 {
                        withAnimation { selectedWeek += 1 }
                    } else if value.translation.width > 30 && selectedWeek > 1 {
                        withAnimation { selectedWeek -= 1 }
                    }
                }
        )
        .sheet(isPresented: $showWeekPicker) {
            WeekPickerSheet(selectedWeek: $selectedWeek, trainingPlan: trainingPlan)
        }
    }
}

// MARK: - Week Picker Sheet
struct WeekPickerSheet: View {
    @Binding var selectedWeek: Int
    let trainingPlan: TrainingPlanManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(trainingPlan.weeks.sorted(by: { $0.weekNumber < $1.weekNumber }), id: \.weekNumber) { week in
                    Button(action: {
                        withAnimation { selectedWeek = week.weekNumber }
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Week \(week.weekNumber)")
                                        .fontWeight(.semibold)
                                    Text("- \(week.phase)")
                                        .foregroundColor(.secondary)
                                }

                                let startStr = Formatters.shortDate.string(from: week.startDate)
                                let endStr = Formatters.shortDate.string(from: week.endDate)
                                Text("\(startStr) - \(endStr)")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                let workoutCount = week.workouts.filter { $0.type != "Rest" }.count
                                Text("\(workoutCount) workouts")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if week.weekNumber == selectedWeek {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }

                            if isCurrentWeek(week) {
                                Text("Current")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(week.weekNumber == selectedWeek ? Color.blue.opacity(0.08) : Color.clear)
                }
            }
            .navigationTitle("Select Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isCurrentWeek(_ week: TrainingWeek) -> Bool {
        let today = Date()
        return today >= week.startDate && today <= Calendar.current.date(byAdding: .day, value: 1, to: week.endDate)!
    }
}

// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @State private var selectedWeek: Int = 1
    @State private var hasAppearedOnce = false
    @State private var draggedFromDay: String?
    @State private var draggedWorkout: DayWorkout?

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    var formattedDateRange: String {
        guard let week = currentWeek else { return "" }
        let startStr = Formatters.shortDate.string(from: week.startDate)
        let endStr = Formatters.shortDate.string(from: week.endDate)
        return "\(startStr) - \(endStr), 2026"
    }

    var daysUntilRace: Int {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 19
        guard let raceDate = calendar.date(from: comps) else { return 0 }
        let today = calendar.startOfDay(for: Date())
        let race = calendar.startOfDay(for: raceDate)
        return calendar.dateComponents([.day], from: today, to: race).day ?? 0
    }

    var currentPhase: String {
        switch selectedWeek {
        case 1...4: return "Base Building"
        case 5...8: return "Build Phase"
        case 9...12: return "Peak Training"
        case 13...15: return "Race Specific"
        case 16...17: return "Taper"
        default: return "Training"
        }
    }

    private var completionCounts: (total: Int, completed: Int) {
        guard let week = currentWeek else { return (0, 0) }

        let calendar = Calendar.current
        let todayStartOfDay = calendar.startOfDay(for: Date())
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let grouped = Dictionary(grouping: week.workouts, by: { $0.day })

        var total = 0
        var completed = 0

        for day in dayOrder {
            guard let dayWorkouts = grouped[day] else { continue }
            let sampleWorkout = dayWorkouts[0]
            let dayDate = getDateForDay(sampleWorkout)
            let dayStartOfDay = calendar.startOfDay(for: dayDate)
            guard dayStartOfDay <= todayStartOfDay else { continue }

            if let restWorkout = dayWorkouts.first(where: { $0.type.contains("Rest") }) {
                if isRestDayCompleted(for: restWorkout) {
                    total += 1
                    completed += 1
                }
            } else {
                for workout in dayWorkouts {
                    total += 1
                    if isWorkoutCompleted(workout) {
                        completed += 1
                    }
                }
            }
        }

        return (total, completed)
    }

    var todaysTotalWorkouts: Int { completionCounts.total }
    var todaysCompletedWorkouts: Int { completionCounts.completed }

    var workoutsByDay: [(day: String, workouts: [DayWorkout])] {
        guard let week = currentWeek else { return [] }

        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let grouped = Dictionary(grouping: week.workouts, by: { $0.day })

        return dayOrder.compactMap { day in
            guard let workouts = grouped[day] else { return nil }
            return (day: day, workouts: workouts)
        }
    }

    func isWorkoutCompleted(_ workout: DayWorkout) -> Bool {
        // Check if there's a matching HealthKit workout with duration tolerance
        let workoutType = extractWorkoutType(from: workout.type)
        let plannedDurationMinutes = parseDuration(workout.duration)
        let toleranceMinutes = 15
        let targetDate = getDateForDay(workout)

        return healthKit.workouts.contains { hkWorkout in
            let calendar = Calendar.current
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let targetStartOfDay = calendar.startOfDay(for: targetDate)

            // Date and type match (required)
            guard workoutDate == targetStartOfDay &&
                   workoutTypeMatches(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType) else {
                return false
            }

            // Duration match (±15 min tolerance) — skip if planned duration is distance-based
            if let plannedMin = plannedDurationMinutes {
                let hkDurationMinutes = Int(hkWorkout.duration / 60)
                let durationDiff = abs(hkDurationMinutes - plannedMin)

                return durationDiff <= toleranceMinutes
            }

            // If planned duration is distance-based (yd), skip duration check and just match type
            return true
        }
    }

    func isRestDayCompleted(for workout: DayWorkout) -> Bool {
        // Rest day is "completed" if no non-yoga/walking workouts were done
        let targetDate = getDateForDay(workout)
        let calendar = Calendar.current
        let targetStartOfDay = calendar.startOfDay(for: targetDate)

        return !healthKit.workouts.contains { hkWorkout in
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let isTargetDay = workoutDate == targetStartOfDay

            // Exclude yoga and walking
            let isYogaOrWalking = hkWorkout.workoutActivityType == .yoga ||
                                   hkWorkout.workoutActivityType == .walking

            return isTargetDay && !isYogaOrWalking
        }
    }

    func getDateForDay(_ workout: DayWorkout) -> Date {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayIndex = dayOrder.firstIndex(of: workout.day) ?? 0

        let calendar = Calendar.current
        let weekStart = currentWeek?.startDate ?? Date()
        let daysToAdd = dayIndex

        return calendar.date(byAdding: .day, value: daysToAdd, to: weekStart) ?? weekStart
    }

    func workoutTypeMatches(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool {
        let planned = plannedType.lowercased()
        switch healthKitType {
        case .cycling:
            return planned == "bike"
        case .swimming:
            return planned == "swim"
        case .running:
            return planned == "run"
        case .walking:
            return planned == "walk"
        default:
            return false
        }
    }

    func extractWorkoutType(from typeString: String) -> String {
        if typeString.contains("🚴") { return "Bike" }
        if typeString.contains("🏊") { return "Swim" }
        if typeString.contains("🏃") { return "Run" }
        if typeString.contains("🏁") { return "Run" }
        return typeString
    }

    func parseDuration(_ durationStr: String) -> Int? {
        // Parse "60 min" → 60, "1.5 hrs" → 90, "1:00" → 60, "1,800yd" → nil, "Rest" → nil
        let lowercased = durationStr.lowercased()

        // Skip distance-based or rest days
        if lowercased.contains("yd") || lowercased.contains("rest") {
            return nil
        }

        // Handle H:MM format first (e.g., "1:00" → 60 minutes, "1:45" → 105 minutes)
        if let regex = try? NSRegularExpression(pattern: "^(\\d+):(\\d{2})", options: []) {
            if let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased)) {
                if let hoursRange = Range(match.range(at: 1), in: lowercased),
                   let minutesRange = Range(match.range(at: 2), in: lowercased),
                   let hours = Int(lowercased[hoursRange]),
                   let minutes = Int(lowercased[minutesRange]) {
                    return hours * 60 + minutes
                }
            }
        }

        // Handle "number min/hr" format (with or without space)
        if let regex = try? NSRegularExpression(pattern: "([\\d.]+)\\s*(min|hr)", options: []) {
            if let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased)) {
                if let numberRange = Range(match.range(at: 1), in: lowercased),
                   let unitRange = Range(match.range(at: 2), in: lowercased),
                   let value = Double(lowercased[numberRange]) {
                    let unit = String(lowercased[unitRange])
                    if unit == "hr" {
                        return Int(value * 60)
                    } else if unit == "min" {
                        return Int(value)
                    }
                }
            }
        }

        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Race Countdown Banner
                HStack {
                    if daysUntilRace > 0 {
                        HStack(spacing: 4) {
                            Text("\(daysUntilRace)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("DAYS TO RACE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                    } else if daysUntilRace == 0 {
                        Text("RACE DAY!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    } else {
                        Text("RACE COMPLETE")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Text("Week \(selectedWeek) \u{00B7} \(currentPhase)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(10)

                // Week Navigation Header with Completion Count and Undo
                HStack {
                    WeekNavigationHeader(selectedWeek: $selectedWeek, completionText: "\(todaysCompletedWorkouts)/\(todaysTotalWorkouts)")

                    if trainingPlan.previousPlanVersion != nil {
                        Button(action: {
                            _ = trainingPlan.rollbackToPreviousVersion()
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    }
                }

                // Sync Error Display
                if let error = healthKit.syncError {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Sync Error")
                                .font(.headline)
                        }
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                ScrollView {
                    DayGroupsView(
                        dayGroups: workoutsByDay,
                        week: currentWeek,
                        healthKit: healthKit,
                        parent: self,
                        draggedWorkout: $draggedWorkout,
                        draggedFromDay: $draggedFromDay,
                        selectedWeek: selectedWeek
                    )
                }
                .onDrop(of: [.plainText], isTargeted: nil) { _ in
                    print("[DROP] ScrollView catch-all onDrop fired, clearing drag state")
                    draggedFromDay = nil
                    draggedWorkout = nil
                    return false
                }
                .onTapGesture {
                    if draggedFromDay != nil {
                        print("[DRAG] Tap detected, clearing draggedFromDay=\(draggedFromDay ?? "nil")")
                        draggedFromDay = nil
                        draggedWorkout = nil
                    }
                }
                .onChange(of: selectedWeek) { _, _ in
                    draggedFromDay = nil
                    draggedWorkout = nil
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < -50 && selectedWeek < 17 {
                            withAnimation { selectedWeek += 1 }
                        } else if value.translation.width > 50 && selectedWeek > 1 {
                            withAnimation { selectedWeek -= 1 }
                        }
                    }
            )
            .onAppear {
                if !hasAppearedOnce {
                    selectedWeek = trainingPlan.currentWeekNumber
                    hasAppearedOnce = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToWeek)) { notification in
                if let week = notification.userInfo?["week"] as? Int {
                    withAnimation { selectedWeek = week }
                }
            }
        }
    }
}

// MARK: - Day Detail View
struct DayDetailView: View {
    let day: DayWorkout
    let week: TrainingWeek
    @ObservedObject var healthKit: HealthKitManager
    @State private var note: String = ""
    @Environment(\.dismiss) var dismiss

    private var noteKey: String {
        "workout_note_w\(week.weekNumber)_\(day.day)_\(day.type)"
    }

    var dayName: String {
        let dayMap = ["Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday",
                      "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"]
        return dayMap[day.day] ?? day.day
    }

    var navTitle: String {
        return "\(dayName), \(Formatters.shortDate.string(from: getDateForDay()))"
    }

    var matchingHealthKitWorkouts: [HKWorkout] {
        let workoutType = extractWorkoutType(from: day.type)
        let targetDate = getDateForDay()

        return healthKit.workouts.filter { hkWorkout in
            let calendar = Calendar.current
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let targetStartOfDay = calendar.startOfDay(for: targetDate)

            return workoutDate == targetStartOfDay &&
                   workoutTypeMatches(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType)
        }
    }

    func getDateForDay() -> Date {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayIndex = dayOrder.firstIndex(of: day.day) ?? 0

        let calendar = Calendar.current
        let weekStart = week.startDate
        let daysToAdd = dayIndex

        return calendar.date(byAdding: .day, value: daysToAdd, to: weekStart) ?? weekStart
    }

    func workoutTypeMatches(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool {
        let planned = plannedType.lowercased()
        switch healthKitType {
        case .cycling:
            return planned == "bike"
        case .swimming:
            return planned == "swim"
        case .running:
            return planned == "run"
        case .walking:
            return planned == "walk"
        default:
            return false
        }
    }

    func getWorkoutTypeName(_ workoutType: HKWorkoutActivityType) -> String {
        switch workoutType {
        case .cycling:
            return "Cycling"
        case .swimming:
            return "Swimming"
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        default:
            return "Workout"
        }
    }

    func extractWorkoutType(from typeString: String) -> String {
        if typeString.contains("🚴") { return "Bike" }
        if typeString.contains("🏊") { return "Swim" }
        if typeString.contains("🏃") { return "Run" }
        if typeString.contains("🏁") { return "Run" }
        return typeString
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Planned Workout
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Planned Workout")
                                .font(.headline)
                            Spacer()
                            if matchingHealthKitWorkouts.count > 0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }

                        if day.type.contains("Rest") {
                            Text("Rest Day")
                                .font(.title3)
                                .fontWeight(.semibold)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Type:")
                                    Spacer()
                                    Text(day.type)
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Duration:")
                                    Spacer()
                                    Text(day.duration)
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Zone:")
                                    Spacer()
                                    Text(day.zone)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Nutrition Target
                    if let nutrition = day.nutritionTarget {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Nutrition Target", systemImage: "fork.knife")
                                .font(.headline)
                            Text(nutrition)
                                .font(.body)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Weather - show for past days and up to 7 days ahead
                    let dayDate = getDateForDay()
                    let calendar = Calendar.current
                    let today = Date()
                    let daysUntil = calendar.dateComponents([.day], from: today, to: dayDate).day ?? 0
                    let isPastDay = daysUntil < 0

                    if isPastDay || daysUntil <= 7 {
                        let weather = WeatherForecast.forecast(for: dayDate)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(isPastDay ? "Weather" : "Expected Weather")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Conditions:")
                                    Spacer()
                                    Text(weather.condition)
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Temperature:")
                                    Spacer()
                                    Text("\(weather.lowTemp)°F - \(weather.highTemp)°F")
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Wind:")
                                    Spacer()
                                    Text("\(weather.windMph) mph")
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Humidity:")
                                    Spacer()
                                    Text("\(weather.humidity)%")
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBlue).opacity(0.1))
                        .cornerRadius(12)
                    }

                    // HealthKit Workouts
                    if !matchingHealthKitWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Completed Workouts")
                                .font(.headline)

                            ForEach(matchingHealthKitWorkouts, id: \.uuid) { workout in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(getWorkoutTypeName(workout.workoutActivityType))
                                        .fontWeight(.semibold)
                                    HStack {
                                        Text("Duration:")
                                        Spacer()
                                        Text(String(format: "%.0f", workout.duration / 60) + " min")
                                    }
                                    .font(.caption)
                                    if let energy = workout.totalEnergyBurned {
                                        HStack {
                                            Text("Calories:")
                                            Spacer()
                                            Text(String(format: "%.0f", energy.doubleValue(for: .kilocalorie())) + " kcal")
                                        }
                                        .font(.caption)
                                    }
                                }
                                .padding(10)
                                .background(Color(.systemGreen).opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    } else if !day.type.contains("Rest") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.orange)
                                Text("No completed workouts")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    // Notes Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: $note)
                            .frame(height: 120)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                note = UserDefaults.standard.string(forKey: noteKey) ?? ""
            }
            .onChange(of: note) { _, newValue in
                if newValue.isEmpty {
                    UserDefaults.standard.removeObject(forKey: noteKey)
                } else {
                    UserDefaults.standard.set(newValue, forKey: noteKey)
                }
            }
        }
    }
}

struct WeekdayWorkoutRow: View {
    let day: String
    let type: String
    let duration: String
    let zone: String
    var isCompleted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(day)
                .fontWeight(.bold)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(type)
                    .fontWeight(.semibold)
                Text("\(duration) • \(zone)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Day Groups View
struct DayGroupsView: View {
    let dayGroups: [(day: String, workouts: [DayWorkout])]
    let week: TrainingWeek?
    @ObservedObject var healthKit: HealthKitManager
    let parent: HomeView
    @Binding var draggedWorkout: DayWorkout?
    @Binding var draggedFromDay: String?
    let selectedWeek: Int

    var body: some View {
        if let week = week, !dayGroups.isEmpty {
            VStack(spacing: 12) {
                ForEach(dayGroups, id: \.day) { dayGroup in
                    DayRowView(
                        dayGroup: dayGroup,
                        weekStartDate: week.startDate,
                        parent: parent,
                        draggedWorkout: $draggedWorkout,
                        draggedFromDay: $draggedFromDay,
                        week: week,
                        healthKit: healthKit,
                        selectedWeek: selectedWeek
                    )
                }
            }
            .padding()
        } else {
            VStack(spacing: 12) {
                Text("No workouts planned for this week")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
    }
}

// MARK: - Day Row View
struct DayRowView: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView
    @Binding var draggedWorkout: DayWorkout?
    @Binding var draggedFromDay: String?
    let week: TrainingWeek?
    @ObservedObject var healthKit: HealthKitManager
    let selectedWeek: Int

    var isRestDay: Bool {
        dayGroup.workouts.allSatisfy { $0.type.contains("Rest") }
    }

    var body: some View {
        if isRestDay {
            RestDayRow(dayGroup: dayGroup, weekStartDate: weekStartDate, parent: parent)
        } else {
            // Workouts without any NavigationLink wrapping - test if drag works
            WorkoutDayRows(
                dayGroup: dayGroup,
                weekStartDate: weekStartDate,
                parent: parent,
                week: week,
                draggedWorkout: $draggedWorkout,
                draggedFromDay: $draggedFromDay,
                hideHeader: false,
                selectedWeek: selectedWeek
            )
        }
    }
}

// MARK: - Rest Day Row
struct RestDayRow: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var dayDate: String {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate
        return Formatters.monthDay.string(from: date)
    }

    var body: some View {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate

        // Show weather for past days and up to 7 days ahead
        let calendar = Calendar.current
        let today = Date()
        let daysUntil = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        let showWeather = daysUntil < 0 || daysUntil <= 7

        return VStack(alignment: .leading, spacing: 8) {
            // Day header - separate from card
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(dayGroup.day)
                        .fontWeight(.bold)
                    Text(dayDate)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(width: 50)

                if showWeather {
                    let weather = WeatherForecast.forecast(for: date)
                    HStack(spacing: 4) {
                        Text(weather.icon)
                            .font(.title3)
                        Text("\(weather.highTemp)°")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Rest card
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("🛌")
                        .font(.title3)
                    Text("Rest")
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                Spacer()

                if parent.isRestDayCompleted(for: dayGroup.workouts[0]) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Workout Day Rows
struct WorkoutDayRows: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView
    let week: TrainingWeek?
    @Binding var draggedWorkout: DayWorkout?
    @Binding var draggedFromDay: String?
    var hideHeader: Bool = false
    let selectedWeek: Int

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var dayDate: String {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate
        return Formatters.monthDay.string(from: date)
    }

    var trainingPlan: TrainingPlanManager {
        parent.trainingPlan
    }

    func isWorkoutCompleted(_ workout: DayWorkout) -> Bool {
        parent.isWorkoutCompleted(workout)
    }

    var body: some View {
        let date = Calendar.current.date(byAdding: .day, value: Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0, to: weekStartDate) ?? weekStartDate

        // Show weather for past days and up to 7 days ahead
        let calendar = Calendar.current
        let today = Date()
        let daysUntil = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        let showWeather = daysUntil < 0 || daysUntil <= 7

        return VStack(alignment: .leading, spacing: 8) {
            // Day header - separate from cards
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(dayGroup.day)
                        .fontWeight(.bold)
                    Text(dayDate)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(width: 50)

                if showWeather {
                    let weather = WeatherForecast.forecast(for: date)
                    HStack(spacing: 4) {
                        Text(weather.icon)
                            .font(.title3)
                        Text("\(weather.highTemp)°")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Workout cards - draggable as a group
            VStack(spacing: 8) {
                ForEach(dayGroup.workouts, id: \.duration) { workout in
                    NavigationLink(destination: DayDetailView(day: workout, week: week ?? TrainingWeek(weekNumber: 1, phase: "", startDate: Date(), endDate: Date(), workouts: []), healthKit: parent.healthKit)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.type)
                                    .fontWeight(.semibold)
                                Text("\(workout.duration) • \(workout.zone)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            if parent.isWorkoutCompleted(workout) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title3)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                                    .font(.title3)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
        }
        // Opacity feedback when dragging this entire day
        .opacity(draggedFromDay == dayGroup.day ? 0.5 : 1.0)
        // Drag the entire day as one unit
        .onDrag {
            draggedFromDay = dayGroup.day
            draggedWorkout = nil
            print("[DRAG] Started dragging day=\(dayGroup.day), draggedFromDay is now=\(draggedFromDay ?? "nil")")
            // Auto-clear after 2 seconds if drop never completes (cancelled drag)
            let dragDay = dayGroup.day
            let binding = $draggedFromDay
            let workoutBinding = $draggedWorkout
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if binding.wrappedValue == dragDay {
                    binding.wrappedValue = nil
                    workoutBinding.wrappedValue = nil
                    print("[DRAG] Auto-cleared stale drag state for \(dragDay)")
                }
            }
            return NSItemProvider(object: dayGroup.day as NSString)
        }
        .onDrop(of: [.plainText], delegate: WorkoutDropDelegate(
            targetDay: dayGroup.day,
            selectedWeek: selectedWeek,
            trainingPlan: trainingPlan,
            getDraggedFromDay: {
                draggedFromDay
            },
            isCompleted: { dayToCheck in
                guard let week = parent.trainingPlan.getWeek(selectedWeek) else { return false }
                let workoutsForDay = week.workouts.filter { $0.day == dayToCheck }
                return workoutsForDay.allSatisfy { parent.isWorkoutCompleted($0) }
            },
            clearDragState: {
                draggedFromDay = nil
                draggedWorkout = nil
                print("[DROP] Drag state cleared")
            }
        ))
    }
}

// MARK: - Analytics View
struct AnalyticsView: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var selectedWeek: Int = 1
    @State private var hasAppearedOnce = false
    @State private var actualZoneData: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
    @State private var actualZonePercentages: [String: Double] = [:]
    @State private var isLoadingZones = false
    @State private var cachedVolume: (swim: Double, bike: Double, run: Double) = (0, 0, 0)
    @State private var cachedPlannedVolume: (swim: Double, bike: Double, run: Double) = (0, 0, 0)
    @State private var cachedZonePercentages: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    func recalculateAnalytics() {
        guard let week = currentWeek else {
            cachedVolume = (0, 0, 0)
            cachedPlannedVolume = (0, 0, 0)
            cachedZonePercentages = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
            return
        }

        // Actual volume from HealthKit (single pass)
        let calendar = Calendar.current
        let weekStart = calendar.startOfDay(for: week.startDate)
        let weekEnd = calendar.startOfDay(for: week.endDate)
        var swimH: Double = 0, bikeH: Double = 0, runH: Double = 0

        for hkWorkout in healthKit.workouts {
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            guard workoutDate >= weekStart && workoutDate <= weekEnd else { continue }
            let hours = hkWorkout.duration / 3600
            switch hkWorkout.workoutActivityType {
            case .swimming: swimH += hours
            case .cycling: bikeH += hours
            case .running: runH += hours
            default: break
            }
        }
        cachedVolume = (swimH, bikeH, runH)

        // Planned volume + zone distribution (single pass over workouts)
        var pSwim: Double = 0, pBike: Double = 0, pRun: Double = 0
        var zoneHours: [String: Double] = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]

        for workout in week.workouts {
            if workout.type.contains("Rest") { continue }
            let hours = parseWorkoutDuration(workout.duration)

            // Planned volume
            if workout.type.contains("🏊") {
                pSwim += hours
            } else if workout.type.contains("🚴") && !workout.type.contains("🏃") {
                pBike += hours
            } else if workout.type.contains("🏃") && !workout.type.contains("🚴") {
                pRun += hours
            } else if workout.type.contains("🚴") && workout.type.contains("🏃") {
                pBike += hours * 0.6
                pRun += hours * 0.4
            }

            // Zone distribution
            let zones = parseZone(workout.zone)
            for z in zones {
                zoneHours[z, default: 0] += hours / Double(zones.count)
            }
        }
        cachedPlannedVolume = (pSwim, pBike, pRun)

        // Zone percentages
        let total = zoneHours.values.reduce(0, +)
        if total > 0 {
            cachedZonePercentages = zoneHours.mapValues { ($0 / total) * 100 }
        } else {
            cachedZonePercentages = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
        }
    }

    func parseWorkoutDuration(_ duration: String) -> Double {
        let trimmed = duration.trimmingCharacters(in: .whitespaces)

        // Handle "min" format (e.g., "40min")
        if trimmed.contains("min") {
            let value = trimmed.replacingOccurrences(of: "min", with: "").trimmingCharacters(in: .whitespaces)
            return (Double(value) ?? 0) / 60
        }

        // Handle "H:MM" format (e.g., "1:00", "2:30")
        if trimmed.contains(":") {
            let components = trimmed.split(separator: ":")
            if components.count == 2,
               let hours = Double(components[0]),
               let minutes = Double(components[1]) {
                return hours + (minutes / 60)
            }
        }

        // Handle yard format for swimming (approximate 1 yard = 1 minute in pool)
        if trimmed.contains("yd") {
            let value = trimmed.replacingOccurrences(of: "yd", with: "").trimmingCharacters(in: .whitespaces)
            let cleanValue = value.replacingOccurrences(of: ",", with: "")
            if let yardage = Double(cleanValue) {
                return yardage / 1800 // ~1800 yards per hour
            }
        }

        // Handle "Race" or other text
        if trimmed.lowercased() == "race" {
            return 3.0 // Assume sprint tri is ~3 hours
        }

        return 0
    }

    func parseZone(_ zone: String) -> [String] {
        let trimmed = zone.trimmingCharacters(in: .whitespaces)

        if trimmed.contains("-") {
            // Split zones like "Z2-3" or "Z1-2"
            let parts = trimmed.split(separator: "-")
            if parts.count == 2 {
                if let firstNum = parts[0].last, let secondNum = parts[1].last {
                    let first = Int(String(firstNum)) ?? 2
                    let second = Int(String(secondNum)) ?? 2
                    return Array(first...second).map { "Z\($0)" }
                }
            }
        }

        // Single zone like "Z2"
        return [trimmed]
    }

    func fetchActualZoneData() {
        guard let week = currentWeek else { return }
        isLoadingZones = true

        HealthKitManager.shared.calculateZoneBreakdown(
            startDate: week.startDate,
            endDate: week.endDate
        ) { zoneData in
            DispatchQueue.main.async {
                self.actualZoneData = zoneData
                // Convert zone counts to percentages
                let totalSamples = zoneData.values.reduce(0, +)
                if totalSamples > 0 {
                    self.actualZonePercentages = zoneData.mapValues { ($0 / totalSamples) * 100 }
                } else {
                    self.actualZonePercentages = ["Z1": 0, "Z2": 0, "Z3": 0, "Z4": 0, "Z5": 0]
                }
                self.isLoadingZones = false
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Week Navigation Header (Shared)
                WeekNavigationHeader(selectedWeek: $selectedWeek)

                // Volume Summary
                VStack(spacing: 12) {
                    Text("Volume Summary")
                        .font(.headline)

                    HStack(spacing: 20) {
                        VolumeCard(label: "Swim", hours: cachedVolume.swim, planned: cachedPlannedVolume.swim, color: .blue)
                        VolumeCard(label: "Bike", hours: cachedVolume.bike, planned: cachedPlannedVolume.bike, color: .orange)
                        VolumeCard(label: "Run", hours: cachedVolume.run, planned: cachedPlannedVolume.run, color: .green)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Zone Distribution
                VStack(spacing: 12) {
                    Text("Zone Distribution (Week \(selectedWeek))")
                        .font(.headline)

                    if isLoadingZones {
                        HStack {
                            ProgressView()
                            Text("Loading zone data...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else {
                        // Legend
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(.black)
                                    .frame(width: 8, height: 8)
                                Text("Planned")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(.black.opacity(0.5))
                                    .frame(width: 8, height: 8)
                                Text("Actual")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.bottom, 4)

                        HStack(spacing: 20) {
                            ZoneBar(zone: "Z1", plannedPercent: cachedZonePercentages["Z1"] ?? 0, actualPercent: actualZonePercentages["Z1"] ?? 0, color: .gray)
                            ZoneBar(zone: "Z2", plannedPercent: cachedZonePercentages["Z2"] ?? 0, actualPercent: actualZonePercentages["Z2"] ?? 0, color: .green)
                            ZoneBar(zone: "Z3", plannedPercent: cachedZonePercentages["Z3"] ?? 0, actualPercent: actualZonePercentages["Z3"] ?? 0, color: .yellow)
                            ZoneBar(zone: "Z4", plannedPercent: cachedZonePercentages["Z4"] ?? 0, actualPercent: actualZonePercentages["Z4"] ?? 0, color: .orange)
                            ZoneBar(zone: "Z5", plannedPercent: cachedZonePercentages["Z5"] ?? 0, actualPercent: actualZonePercentages["Z5"] ?? 0, color: .red)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < -50 && selectedWeek < 17 {
                            withAnimation { selectedWeek += 1 }
                        } else if value.translation.width > 50 && selectedWeek > 1 {
                            withAnimation { selectedWeek -= 1 }
                        }
                    }
            )
            .onAppear {
                if !hasAppearedOnce {
                    selectedWeek = trainingPlan.currentWeekNumber
                    hasAppearedOnce = true
                }
                recalculateAnalytics()
                fetchActualZoneData()
            }
            .onChange(of: selectedWeek) { _, _ in
                recalculateAnalytics()
                fetchActualZoneData()
            }
        }
    }
}

struct VolumeCard: View {
    let label: String
    let hours: Double
    let planned: Double
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)

            Text("\(String(format: "%.1f", hours))h")
                .font(.headline)
                .foregroundColor(color)

            Text("plan: \(String(format: "%.1f", planned))h")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ZoneBar: View {
    let zone: String
    let plannedPercent: Double
    let actualPercent: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(zone)
                .font(.caption)
                .fontWeight(.semibold)

            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Planned zone bar (solid color)
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(color)
                            .frame(height: geometry.size.height * (plannedPercent / 100))
                    }

                    // Actual zone bar overlay (semi-transparent, darker)
                    if actualPercent > 0 {
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(color.opacity(0.5))
                                .frame(height: geometry.size.height * (actualPercent / 100))
                        }
                    }
                }
            }
            .frame(height: 80)

            VStack(spacing: 2) {
                Text("\(Int(plannedPercent))%")
                    .font(.caption2)
                if actualPercent > 0 {
                    Text("\(Int(actualPercent))%")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - Workout Drop Delegate
struct WorkoutDropDelegate: DropDelegate {
    let targetDay: String
    let selectedWeek: Int
    let trainingPlan: TrainingPlanManager
    let getDraggedFromDay: () -> String?
    let isCompleted: (String) -> Bool
    let clearDragState: () -> Void

    func dropEntered(info: DropInfo) {
        if let from = getDraggedFromDay() {
            print("[DROP] Entered target day: \(targetDay) from: \(from)")
        }
    }

    func dropExited(info: DropInfo) {
        print("[DROP] Exited target day: \(targetDay)")
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedFromDay = getDraggedFromDay() else {
            print("[DROP] performDrop: No draggedFromDay")
            return false
        }

        print("[DROP] performDrop: from=\(draggedFromDay) to=\(targetDay) week=\(selectedWeek)")

        guard draggedFromDay != targetDay else {
            print("[DROP] Same day, clearing state")
            clearDragState()
            return false
        }

        // Swap workouts in the plan
        var updatedWeeks = trainingPlan.weeks
        if let weekIdx = updatedWeeks.firstIndex(where: { $0.weekNumber == selectedWeek }) {
            var newWorkouts = updatedWeeks[weekIdx].workouts

            // Count workouts for each day (some days have multiple)
            let fromDayWorkouts = newWorkouts.filter { $0.day == draggedFromDay }
            let toDayWorkouts = newWorkouts.filter { $0.day == targetDay }

            guard !fromDayWorkouts.isEmpty && !toDayWorkouts.isEmpty else {
                print("[DROP] One of the days has no workouts")
                return false
            }

            print("[DROP] Swapping \(fromDayWorkouts.count) workout(s) from \(draggedFromDay) with \(toDayWorkouts.count) workout(s) from \(targetDay)")

            // Swap days: change all draggedFromDay to targetDay and vice versa
            newWorkouts = newWorkouts.map { workout in
                if workout.day == draggedFromDay {
                    // Change draggedFromDay workouts to targetDay
                    return DayWorkout(day: targetDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget)
                } else if workout.day == targetDay {
                    // Change targetDay workouts to draggedFromDay
                    return DayWorkout(day: draggedFromDay, type: workout.type, duration: workout.duration, zone: workout.zone, status: workout.status, nutritionTarget: workout.nutritionTarget)
                } else {
                    return workout
                }
            }

            // Create new TrainingWeek with updated workouts
            updatedWeeks[weekIdx] = TrainingWeek(
                weekNumber: updatedWeeks[weekIdx].weekNumber,
                phase: updatedWeeks[weekIdx].phase,
                startDate: updatedWeeks[weekIdx].startDate,
                endDate: updatedWeeks[weekIdx].endDate,
                workouts: newWorkouts
            )

            let workoutTypes = fromDayWorkouts.map { $0.type }.joined(separator: ", ")

            print("[DROP] Applying rescheduled plan: [\(workoutTypes)]")

            // Update plan
            trainingPlan.applyRescheduledPlan(
                updatedWeeks,
                source: "drag",
                description: "Swapped \(draggedFromDay) and \(targetDay)"
            )

            // Clear drag state immediately
            clearDragState()
            print("[DROP] Drop completed successfully")
            return true
        } else {
            print("[DROP] Could not find week with number \(selectedWeek)")
            return false
        }
    }
}

// MARK: - Chat View
struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isLoading {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { i in
                                    Circle()
                                        .fill(Color.gray.opacity(0.6))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.leading, 16)
                            .padding(.vertical, 8)
                        }

                        if let error = viewModel.error {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: viewModel.messages.count) {
                    withAnimation {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ChatInputBar(viewModel: viewModel)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            viewModel.clearChatHistory()
                        } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

struct ChatInputBar: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 0) {
                TextField("Message your coach...", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.trailing, 36)
                    .focused($isFocused)
                    .disabled(viewModel.isLoading)
                    .onSubmit { if canSend { send() } }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(canSend ? Color.blue : Color(.systemGray4))
                        )
                }
                .disabled(!canSend)
                .padding(.trailing, 6)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isFocused = false
                }
            }
        }
    }

    private func send() {
        let message = text
        text = ""
        isFocused = false
        Task {
            await viewModel.sendMessage(message)
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()

                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            } else {
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(16)

                Spacer()
            }
        }
    }
}

// MARK: - Plan View
struct PlanView: View {
    @EnvironmentObject var trainingPlan: TrainingPlanManager

    var body: some View {
        NavigationStack {
            VStack {
                Text("17-Week Training Plan")
                    .font(.headline)
                    .padding()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(1...17, id: \.self) { week in
                            WeekCard(weekNumber: week, isCurrentWeek: week == trainingPlan.currentWeekNumber)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct WeekCard: View {
    let weekNumber: Int
    let isCurrentWeek: Bool
    @EnvironmentObject var trainingPlan: TrainingPlanManager

    var phase: String {
        trainingPlan.getWeek(weekNumber)?.phase ?? ""
    }

    var startDate: String {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 23
        let start = Calendar.current.date(from: components) ?? Date()
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .weekOfYear, value: weekNumber - 1, to: start)!
        return Formatters.shortDate.string(from: weekStart)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week \(weekNumber)")
                    .fontWeight(.bold)

                Text(phase)
                    .font(.caption)
                    .foregroundColor(.gray)

                Text(startDate)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            if isCurrentWeek {
                Text("NOW")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
        }
        .padding(12)
        .background(isCurrentWeek ? Color(.systemGray5) : Color(.systemBackground))
        .border(isCurrentWeek ? Color.green : Color.clear, width: isCurrentWeek ? 2 : 0)
        .cornerRadius(8)
    }
}

// MARK: - Notification Manager
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var morningWorkoutReminder: Bool {
        didSet {
            UserDefaults.standard.set(morningWorkoutReminder, forKey: "morningWorkoutReminder")
            if morningWorkoutReminder {
                requestPermissionAndSchedule()
            } else {
                cancelAllNotifications()
            }
        }
    }

    @Published var reminderTime: Date {
        didSet {
            UserDefaults.standard.set(reminderTime.timeIntervalSince1970, forKey: "reminderTime")
            if morningWorkoutReminder {
                scheduleWorkoutNotifications()
            }
        }
    }

    @Published var isAuthorized = false

    private var trainingPlan: TrainingPlanManager?

    init() {
        self.morningWorkoutReminder = UserDefaults.standard.bool(forKey: "morningWorkoutReminder")
        let savedTime = UserDefaults.standard.double(forKey: "reminderTime")
        if savedTime > 0 {
            self.reminderTime = Date(timeIntervalSince1970: savedTime)
        } else {
            // Default to 6:30 AM
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = 6
            components.minute = 30
            self.reminderTime = Calendar.current.date(from: components) ?? Date()
        }
        checkAuthorizationStatus()
    }

    func setTrainingPlan(_ plan: TrainingPlanManager) {
        self.trainingPlan = plan
        if morningWorkoutReminder {
            scheduleWorkoutNotifications()
        }
    }

    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    private func requestPermissionAndSchedule() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if granted {
                    self.scheduleWorkoutNotifications()
                } else {
                    self.morningWorkoutReminder = false
                }
            }
        }
    }

    func scheduleWorkoutNotifications() {
        guard let plan = trainingPlan else { return }

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: reminderTime)
        let minute = calendar.component(.minute, from: reminderTime)
        let today = calendar.startOfDay(for: Date())

        // Schedule for next 14 days
        for dayOffset in 0..<14 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }

            let dayOfWeek = calendar.component(.weekday, from: date)
            let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dayName = dayNames[dayOfWeek]

            // Find the week this date falls in
            let planStart = plan.weeks.first?.startDate ?? today
            let weekIndex = calendar.dateComponents([.weekOfYear], from: planStart, to: date).weekOfYear ?? 0
            let weekNumber = weekIndex + 1

            guard weekNumber >= 1 && weekNumber <= 17,
                  let week = plan.getWeek(weekNumber) else { continue }

            let dayWorkouts = week.workouts.filter { $0.day == dayName && $0.type != "Rest" }
            guard !dayWorkouts.isEmpty else { continue }

            let workoutSummary = dayWorkouts.map { "\($0.type) \($0.duration)" }.joined(separator: ", ")

            let content = UNMutableNotificationContent()
            content.title = "Today's Training"
            content.body = workoutSummary
            content.sound = .default

            var triggerComponents = calendar.dateComponents([.year, .month, .day], from: date)
            triggerComponents.hour = hour
            triggerComponents.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let request = UNNotificationRequest(identifier: "workout-\(dayOffset)", content: content, trigger: trigger)

            center.add(request)
        }

        print("[NOTIFICATIONS] Scheduled workout reminders for next 14 days")
    }

    private func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("[NOTIFICATIONS] Cancelled all reminders")
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var notificationManager = NotificationManager.shared
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Notifications")) {
                    Toggle("Morning Workout Reminder", isOn: $notificationManager.morningWorkoutReminder)

                    if notificationManager.morningWorkoutReminder {
                        DatePicker("Reminder Time", selection: $notificationManager.reminderTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section(header: Text("Health"), footer: Text("Max HR is used to calculate your training zones. Derived from age: 220 - age.")) {
                    HStack {
                        Text("Max Heart Rate")
                        Spacer()
                        Text("\(healthKit.maxHeartRate) bpm")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Age")
                        Spacer()
                        Text("\(healthKit.getUserAge())")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("HR Zones")) {
                    let zones = healthKit.zoneBoundaries
                    HStack { Text("Z1"); Spacer(); Text("< \(zones.z2) bpm").foregroundColor(.secondary) }
                    HStack { Text("Z2"); Spacer(); Text("\(zones.z2)-\(zones.z3 - 1) bpm").foregroundColor(.secondary) }
                    HStack { Text("Z3"); Spacer(); Text("\(zones.z3)-\(zones.z4 - 1) bpm").foregroundColor(.secondary) }
                    HStack { Text("Z4"); Spacer(); Text("\(zones.z4)-\(zones.z5 - 1) bpm").foregroundColor(.secondary) }
                    HStack { Text("Z5"); Spacer(); Text("> \(zones.z5) bpm").foregroundColor(.secondary) }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Race")
                        Spacer()
                        Text("Ironman 70.3 Oregon")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Race Date")
                        Spacer()
                        Text("July 19, 2026")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Goal")
                        Spacer()
                        Text("Sub 6:00")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
