import WidgetKit
import SwiftUI

// MARK: - Shared Data (must match main app's Codable structs)
struct SharedDayWorkout: Codable {
    let day: String
    let type: String
    let duration: String
    let zone: String
    let status: String?
    let nutritionTarget: String?
    let notes: String?
}

struct SharedTrainingWeek: Codable {
    let weekNumber: Int
    let phase: String
    let startDate: Date
    let endDate: Date
    let workouts: [SharedDayWorkout]
}

// MARK: - Widget Data Model
struct WidgetWorkout {
    let type: String
    let duration: String
    let zone: String
}

// MARK: - Training Plan Data
struct WidgetTrainingPlan {
    static let appGroupSuite = "group.com.brent.ironmantrainer"

    static let planStartDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 23
        return Calendar.current.date(from: components) ?? Date()
    }()

    static func currentWeekNumber() -> Int {
        let calendar = Calendar.current
        let daysSinceStart = calendar.dateComponents([.day], from: planStartDate, to: Date()).day ?? 0
        return max(1, min(17, (daysSinceStart / 7) + 1))
    }

    static func todayDayName() -> String {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday]
    }

    /// Try to load swapped weeks from App Group shared UserDefaults
    static func sharedWeeks() -> [SharedTrainingWeek]? {
        guard let defaults = UserDefaults(suiteName: appGroupSuite),
              let data = defaults.data(forKey: "swapped_weeks") else {
            return nil
        }
        do {
            return try JSONDecoder().decode([SharedTrainingWeek].self, from: data)
        } catch {
            // If decode fails, fall back to hardcoded data
            return nil
        }
    }

    static func workoutsForToday() -> [WidgetWorkout] {
        let week = currentWeekNumber()
        let day = todayDayName()

        // Prefer shared (swapped) data from the main app
        if let sharedWeeks = sharedWeeks(),
           let weekData = sharedWeeks.first(where: { $0.weekNumber == week }) {
            return weekData.workouts
                .filter { $0.day == day && $0.type != "Rest" }
                .map { WidgetWorkout(type: $0.type, duration: $0.duration, zone: $0.zone) }
        }

        // Fallback to hardcoded plan
        let weekData = allWeeks[week - 1]
        return weekData.filter { $0.0 == day && $0.1 != "Rest" }.map {
            WidgetWorkout(type: $0.1, duration: $0.2, zone: $0.3)
        }
    }

    static func phaseForWeek(_ week: Int) -> String {
        let phases = ["Ramp Up", "Ramp Up", "Ramp Up", "Recovery", "Build 1", "Build 1", "Build 1", "Recovery", "Build 2", "Sprint Tri", "Peak", "Recovery", "Dress Rehearsal", "Peak & Sharpen", "Last Hard", "Taper", "Race Week"]
        guard week >= 1 && week <= 17 else { return "" }
        return phases[week - 1]
    }

    // (day, type, duration, zone)
    static let allWeeks: [[(String, String, String, String)]] = [
        // Week 1
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:00","Z2"),("Tue","🏊 Swim","1,600yd","Z2"),("Wed","🏃 Run","40min","Z2"),("Thu","🚴 Bike","1:00","Z2"),("Fri","🏊 Swim","1,800yd","Z2"),("Sat","🏃 Run","50min","Z2"),("Sun","🚴 Bike","1:45","Z2")],
        // Week 2
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:00","Z2"),("Tue","🏊 Swim","1,800yd","Z2"),("Wed","🏃 Run","45min","Z2"),("Thu","🚴 Bike","1:15","Z2"),("Fri","🏊 Swim","2,000yd","Z2"),("Fri","🏃 Run","30min","Z2"),("Sat","🚴+🏃 Brick","2:15","Z2"),("Sun","🏃 Long Run","55min","Z2")],
        // Week 3
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:00","Z2"),("Tue","🏊 Swim","2,000yd","Z2"),("Wed","🏃 Run","45min","Z2"),("Thu","🚴 Bike + mini-brick","1:10","Z2"),("Fri","🏊 Swim","2,200yd","Z2"),("Sat","🚴+🏃 Brick","2:35","Z2"),("Sun","🏃 Long Run","60min","Z2")],
        // Week 4 — Recovery
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","45min","Z1-2"),("Tue","🏊 Swim","1,500yd","Z1-2"),("Wed","🏃 Run","30min","Z1-2"),("Thu","🚴 Bike","45min","Z1-2"),("Fri","🏊 Swim","1,500yd","Z1-2"),("Sat","🏃 Run","35min","Z1-2"),("Sun","Rest","-","-")],
        // Week 5
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:15","Z4"),("Tue","🏊 Swim","2,200yd","Z2"),("Wed","🏃 Run","50min","Z2"),("Thu","🚴 Bike","1:00","Z2"),("Fri","🏊 Swim","2,400yd","Z2-3"),("Sat","🚴+🏃 Brick","2:35","Z2-3"),("Sun","🏃 Long Run","70min","Z2")],
        // Week 6
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:15","Z4"),("Tue","🏊 Swim","2,400yd","Z2"),("Wed","🏃 Run","55min","Z2"),("Thu","🚴 Bike","1:00 + mini-brick","Z2-3"),("Fri","🏊 Swim","2,500yd","Z2-3"),("Sat","🚴+🏃 Brick","2:55","Z2-3"),("Sun","🏃 Long Run","75min","Z2")],
        // Week 7
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:15","Z4"),("Tue","🏊 Swim","2,800yd","Z2-3"),("Wed","🏃 Tempo Run","60min","Z2-3"),("Thu","🚴 Bike + mini-brick","1:15","Z2-3"),("Fri","🏊 Swim","2,800yd","Z2-3"),("Sat","🚴+🏃 Brick","3:35","Z2-3"),("Sun","🏃 Long Run","80min","Z2")],
        // Week 8 — Recovery
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","45min","Z1-2"),("Tue","🏊 Swim","1,800yd","Z1-2"),("Wed","🏃 Run","30min","Z1-2"),("Thu","🚴 Bike","45min","Z1-2"),("Fri","🏊 Swim","1,500yd","Z1-2"),("Sat","🏃 Run","35min","Z1-2"),("Sun","Rest","-","-")],
        // Week 9
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:15","Z3-4"),("Tue","🏊 Swim","2,500yd","Z2-3"),("Wed","🏃 Run","55min","Z2"),("Thu","🏃 Tempo Run","65min","Z2-3"),("Fri","🏊 Swim","2,800yd","Z2-3"),("Sat","🚴+🏃 Race Sim","3:25","Z2-3"),("Sun","🏃 Long Run","90min","Z2")],
        // Week 10
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:00","Z2"),("Tue","🏊 Swim","2,200yd","Z2-3"),("Wed","🏃 Run","40min","Z2"),("Thu","🚴 Bike","45min","Z2-3"),("Fri","🏊 Swim","1,500yd","Z2"),("Fri","🏃 Run","20min","Z1-2"),("Sat","★ SPRINT TRI","Race","-"),("Sun","🏃 Run","60min","Z2")],
        // Week 11 — Peak
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:15","Z3-4"),("Tue","🏊 Swim","3,000yd","Z2-3"),("Wed","🏃 Tempo Run","70min","Z2-3"),("Thu","🚴 Bike + mini-brick","1:15","Z2"),("Fri","🏊 Swim","2,800yd","Z2-3"),("Sat","🚴+🏃 KEY BRICK","3:50","Z2-3"),("Sun","🏃 LONGEST RUN","1:45","Z2")],
        // Week 12 — Recovery
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","45min","Z1-2"),("Tue","🏊 Swim","2,000yd","Z1-2"),("Wed","🏃 Run","30min","Z1-2"),("Thu","🚴 Bike","45min","Z1-2"),("Fri","🏊 Swim","1,500yd","Z1-2"),("Sat","🏃 Run","35min","Z1-2"),("Sun","Rest","-","-")],
        // Week 13
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:15","Z2-3"),("Tue","🏊 Swim","2,500yd","Z2-3"),("Wed","🏃 Run","55min","Z2"),("Thu","🏃 Run","60min","Z2-3"),("Fri","🏊 Swim","2,400yd","Z2-3"),("Sat","🚴+🏃 DRESS REHEARSAL","3:05","Z2-3"),("Sun","🏃 Long Run","75min","Z2")],
        // Week 14
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:00","Z2-3"),("Tue","🏊 Swim","2,200yd","Z2-3"),("Wed","🏃 Run","45min","Z2"),("Thu","🚴 Bike + mini-brick","55min","Z2-3"),("Fri","🏊 Swim","2,000yd","Z2-3"),("Sat","🚴+🏃 Brick","2:25","Z2-3"),("Sun","🏃 Run","60min","Z2")],
        // Week 15
        [("Mon","Rest","-","-"),("Tue","🚴 Bike","1:00","Z2-3"),("Tue","🏊 Swim","2,000yd","Z2-3"),("Wed","🏃 Tempo Run","50min","Z2-3"),("Thu","🚴 Bike","45min","Z2"),("Fri","🏊 Swim","1,800yd","Z2-3"),("Sat","🚴+🏃 Brick","2:05","Z2"),("Sun","🏃 Run","50min","Z2")],
        // Week 16 — Taper
        [("Mon","Rest","-","-"),("Tue","🏊 Swim","1,500yd","Z2"),("Tue","🚴 Bike","1:00","Z2-3"),("Wed","🏃 Run","35min","Z2"),("Thu","🚴 Bike","45min","Z2"),("Fri","🏊 Swim","1,200yd","Z1-2"),("Fri","🏃 Run","20min","Z1-2"),("Sat","Rest","-","-"),("Sun","Rest","-","-")],
        // Week 17 — Race Week
        [("Mon","✈️ Travel","Denver→Portland","-"),("Tue","🏊 Swim","1,000yd","Z2"),("Wed","🚴 Bike + 🏃 Run","40min + 15min","Z2"),("Thu","🏃 Easy Jog","20min","Z1"),("Fri","Rest","-","-"),("Sat","🏊 Shakeout Swim","15min","Z1"),("Sun","🏁 RACE DAY","~5:45-5:58","Race")]
    ]
}

// MARK: - Widget Weather
struct WidgetWeather {
    let icon: String
    let highTemp: Int

    static func forecast(for date: Date) -> WidgetWeather {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let seed = UInt32(day)

        let (baseTempHigh, baseTempVariance, conditions): (Int, Int, [(String, String)]) = {
            switch month {
            case 3: return (56, 8, [("🌧️","Rainy"),("☁️","Cloudy"),("🌦️","Drizzle"),("⛅","Partly Cloudy")])
            case 4: return (64, 10, [("⛅","Partly Cloudy"),("☀️","Sunny"),("☁️","Cloudy"),("🌦️","Showers")])
            case 5: return (72, 8, [("☀️","Sunny"),("🌤️","Mostly Sunny"),("⛅","Partly Cloudy"),("🌤️","Fair")])
            case 6: return (80, 7, [("☀️","Sunny"),("🌤️","Mostly Sunny"),("🌤️","Fair"),("☀️","Sunny")])
            case 7: return (87, 6, [("🔥","Hot"),("🔥","Hot"),("☀️","Clear"),("☀️","Sunny")])
            default: return (70, 10, [("⛅","Partly Cloudy"),("☀️","Sunny"),("☁️","Cloudy")])
            }
        }()

        let tempVariation = Int(seed % UInt32(baseTempVariance + 1)) - baseTempVariance / 2
        let conditionIndex = Int(seed % UInt32(conditions.count))

        return WidgetWeather(icon: conditions[conditionIndex].0, highTemp: baseTempHigh + tempVariation)
    }
}

// MARK: - Timeline Entry
struct WorkoutEntry: TimelineEntry {
    let date: Date
    let weekNumber: Int
    let phase: String
    let dayName: String
    let workouts: [WidgetWorkout]
    let daysUntilRace: Int
    let weather: WidgetWeather
}

// MARK: - Timeline Provider
struct WorkoutTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutEntry {
        WorkoutEntry(date: Date(), weekNumber: 2, phase: "Ramp Up", dayName: "Tue", workouts: [
            WidgetWorkout(type: "🚴 Bike", duration: "1:00", zone: "Z2"),
            WidgetWorkout(type: "🏊 Swim", duration: "1,800yd", zone: "Z2")
        ], daysUntilRace: 111, weather: WidgetWeather(icon: "⛅", highTemp: 52))
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        if context.isPreview {
            // Show realistic preview data in widget gallery
            completion(WorkoutEntry(
                date: Date(),
                weekNumber: 2,
                phase: "Ramp Up",
                dayName: "Tue",
                workouts: [
                    WidgetWorkout(type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2"),
                    WidgetWorkout(type: "\u{1F3CA} Swim", duration: "1,800yd", zone: "Z2")
                ],
                daysUntilRace: 108,
                weather: WidgetWeather(icon: "\u{2600}\u{FE0F}", highTemp: 62)
            ))
        } else {
            completion(makeEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh at midnight
        let tomorrow = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        let timeline = Timeline(entries: [entry], policy: .after(tomorrow))
        completion(timeline)
    }

    private func makeEntry() -> WorkoutEntry {
        let week = WidgetTrainingPlan.currentWeekNumber()
        let day = WidgetTrainingPlan.todayDayName()
        let workouts = WidgetTrainingPlan.workoutsForToday()

        var raceDateComponents = DateComponents()
        raceDateComponents.year = 2026
        raceDateComponents.month = 7
        raceDateComponents.day = 19
        let raceDate = Calendar.current.date(from: raceDateComponents) ?? Date()
        let daysUntilRace = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: raceDate).day ?? 0

        return WorkoutEntry(
            date: Date(),
            weekNumber: week,
            phase: WidgetTrainingPlan.phaseForWeek(week),
            dayName: day,
            workouts: workouts,
            daysUntilRace: daysUntilRace,
            weather: WidgetWeather.forecast(for: Date())
        )
    }
}

// MARK: - Widget View
struct IronmanTrainerWidgetView: View {
    var entry: WorkoutEntry

    private func workoutIcon(_ type: String) -> String {
        if type.contains("Bike") || type.contains("🚴") { return "🚴" }
        if type.contains("Swim") || type.contains("🏊") { return "🏊" }
        if type.contains("Run") || type.contains("🏃") { return "🏃" }
        if type.contains("Brick") { return "🚴🏃" }
        if type.contains("RACE") || type.contains("🏁") { return "🏁" }
        if type.contains("Travel") || type.contains("✈️") { return "✈️" }
        return "💪"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Text("Wk \(entry.weekNumber)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                Text("\(entry.weather.icon)\(entry.weather.highTemp)°")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }

            HStack {
                Text(entry.dayName)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("\(entry.daysUntilRace)d to race")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }

            if entry.workouts.isEmpty {
                Spacer()
                Text("Rest Day")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(entry.workouts.prefix(3).enumerated()), id: \.offset) { _, workout in
                    HStack(spacing: 0) {
                        Text(workoutIcon(workout.type))
                            .font(.caption2)
                        Text(" \(workout.duration)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }

                if entry.workouts.count > 3 {
                    Text("+\(entry.workouts.count - 3) more")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.15, blue: 0.25), Color(red: 0.02, green: 0.08, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.15, blue: 0.25), Color(red: 0.02, green: 0.08, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(URL(string: "ironmantrainer://week/\(entry.weekNumber)"))
    }
}

// MARK: - Widget Configuration
struct IronmanTrainerWidget: Widget {
    let kind: String = "IronmanTrainerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutTimelineProvider()) { entry in
            IronmanTrainerWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Training")
        .description("See your daily workout at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct IronmanTrainerWidgetBundle: WidgetBundle {
    var body: some Widget {
        IronmanTrainerWidget()
    }
}
