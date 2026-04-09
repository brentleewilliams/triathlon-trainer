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
    static let appGroupSuite = "group.com.brent.race1"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupSuite)
    }

    static func todayDayName() -> String {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday]
    }

    static func sharedWeeks() -> [SharedTrainingWeek]? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "swapped_weeks") else { return nil }
        return try? JSONDecoder().decode([SharedTrainingWeek].self, from: data)
    }

    /// Find which week contains today based on actual startDate/endDate
    static func currentWeek(from weeks: [SharedTrainingWeek]) -> SharedTrainingWeek? {
        let today = Calendar.current.startOfDay(for: Date())
        // First try exact match
        if let match = weeks.first(where: {
            today >= Calendar.current.startOfDay(for: $0.startDate) &&
            today <= Calendar.current.startOfDay(for: $0.endDate)
        }) { return match }
        // If before plan start, return first week
        if let first = weeks.first, today < Calendar.current.startOfDay(for: first.startDate) {
            return first
        }
        // If after plan end, return last week
        return weeks.last
    }

    static func raceDate() -> Date {
        if let saved = sharedDefaults?.object(forKey: "race_date") as? Double {
            return Date(timeIntervalSince1970: saved)
        }
        // Fallback — far future so countdown is never negative for new users
        var comps = DateComponents()
        comps.year = 2099; comps.month = 1; comps.day = 1
        return Calendar.current.date(from: comps) ?? Date()
    }

    static func workoutsForToday() -> [WidgetWorkout] {
        guard let weeks = sharedWeeks(), let week = currentWeek(from: weeks) else { return [] }
        let day = todayDayName()
        return week.workouts
            .filter { $0.day == day && !$0.type.contains("Rest") }
            .map { WidgetWorkout(type: $0.type, duration: $0.duration, zone: $0.zone) }
    }
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
        WorkoutEntry(date: Date(), weekNumber: 1, phase: "Base", dayName: "Mon", workouts: [
            WidgetWorkout(type: "🏃 Run", duration: "45min", zone: "Z2")
        ], daysUntilRace: 90, weather: WidgetWeather(icon: "⛅", highTemp: 64))
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        if context.isPreview {
            completion(WorkoutEntry(
                date: Date(), weekNumber: 3, phase: "Build",
                dayName: "Tue",
                workouts: [WidgetWorkout(type: "🏃 Run", duration: "50min", zone: "Z2")],
                daysUntilRace: 75,
                weather: WidgetWeather(icon: "☀️", highTemp: 68)
            ))
        } else {
            completion(makeEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        let entry = makeEntry()
        let tomorrow = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        let timeline = Timeline(entries: [entry], policy: .after(tomorrow))
        completion(timeline)
    }

    private func makeEntry() -> WorkoutEntry {
        let weeks = WidgetTrainingPlan.sharedWeeks() ?? []
        let currentWeek = WidgetTrainingPlan.currentWeek(from: weeks)
        let weekNumber = currentWeek?.weekNumber ?? 1
        let phase = currentWeek?.phase ?? ""
        let day = WidgetTrainingPlan.todayDayName()
        let workouts = WidgetTrainingPlan.workoutsForToday()
        let raceDate = WidgetTrainingPlan.raceDate()
        let daysUntilRace = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: raceDate)).day ?? 0

        return WorkoutEntry(
            date: Date(),
            weekNumber: weekNumber,
            phase: phase,
            dayName: day,
            workouts: workouts,
            daysUntilRace: daysUntilRace,
            weather: WidgetWeather.forecast(for: Date())
        )
    }
}

// MARK: - Widget View
struct Race1WidgetView: View {
    var entry: WorkoutEntry

    private func workoutIcon(_ type: String) -> String {
        if type.contains("Bike") || type.contains("🚴") { return "🚴" }
        if type.contains("Swim") || type.contains("🏊") { return "🏊" }
        if type.contains("Run") || type.contains("🏃") { return "🏃" }
        if type.contains("Brick") { return "🚴🏃" }
        if type.contains("RACE") || type.contains("🏁") { return "🏁" }
        if type.contains("Travel") || type.contains("✈️") { return "✈️" }
        if type.contains("Strength") || type.contains("💪") { return "💪" }
        if type.contains("Yoga") { return "🧘" }
        return "🏋️"
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
                if entry.daysUntilRace > 0 {
                    Text("\(entry.daysUntilRace)d to race")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                } else if entry.daysUntilRace == 0 {
                    Text("Race Day! 🏁")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
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
        .widgetURL(URL(string: "race1://week/\(entry.weekNumber)"))
    }
}

// MARK: - Widget Configuration
struct Race1Widget: Widget {
    let kind: String = "Race1Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutTimelineProvider()) { entry in
            Race1WidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Training")
        .description("See your daily workout at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct Race1WidgetBundle: WidgetBundle {
    var body: some Widget {
        Race1Widget()
    }
}
