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
    let isCompleted: Bool
}

struct WidgetReadiness {
    let score: Int
    let swimPercent: Int
    let bikePercent: Int
    let runPercent: Int
    /// Which sports are relevant for this user's race. Empty means show all (backwards compat).
    let raceSports: [String]

    static let preview = WidgetReadiness(score: 72, swimPercent: 85, bikePercent: 91, runPercent: 78, raceSports: ["swim", "bike", "run"])

    static func load(from defaults: UserDefaults?) -> WidgetReadiness? {
        guard let defaults,
              let data = defaults.data(forKey: "widget_readiness"),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let score = dict["readinessScore"] as? Int else { return nil }
        let sports = defaults.stringArray(forKey: "race_sports") ?? []
        return WidgetReadiness(
            score: score,
            swimPercent: dict["swimPercent"] as? Int ?? 0,
            bikePercent: dict["bikePercent"] as? Int ?? 0,
            runPercent: dict["runPercent"] as? Int ?? 0,
            raceSports: sports
        )
    }

    func shows(_ sport: String) -> Bool {
        raceSports.isEmpty || raceSports.contains(sport)
    }

    var levelLabel: String {
        switch score {
        case 80...: return "Race Ready"
        case 60..<80: return "Fresh"
        case 40..<60: return "In Training"
        case 20..<40: return "Tired"
        default: return "Overreached"
        }
    }

    var levelColor: Color {
        switch score {
        case 80...: return Color(red: 0.2, green: 0.9, blue: 0.5)
        case 60..<80: return Color(red: 0.4, green: 0.85, blue: 0.4)
        case 40..<60: return Color(red: 0.95, green: 0.85, blue: 0.2)
        case 20..<40: return Color(red: 1.0, green: 0.55, blue: 0.1)
        default: return Color(red: 0.95, green: 0.3, blue: 0.3)
        }
    }
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
        let completed = todayCompletedTypes()
        return week.workouts
            .filter { $0.day == day && !$0.type.contains("Rest") }
            .map { WidgetWorkout(type: $0.type, duration: $0.duration, zone: $0.zone, isCompleted: completed.contains($0.type)) }
    }

    static func todayCompletedTypes() -> Set<String> {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "completed_today"),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dateStr = dict["date"] as? String,
              let types = dict["types"] as? [String] else { return [] }
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        return dateStr == today ? Set(types) : []
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
    let readiness: WidgetReadiness?
}

// MARK: - Timeline Provider
struct WorkoutTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutEntry {
        WorkoutEntry(date: Date(), weekNumber: 1, phase: "Base", dayName: "Mon", workouts: [
            WidgetWorkout(type: "🏃 Run", duration: "45min", zone: "Z2", isCompleted: false)
        ], daysUntilRace: 90, weather: WidgetWeather(icon: "⛅", highTemp: 64), readiness: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        if context.isPreview {
            completion(WorkoutEntry(
                date: Date(), weekNumber: 3, phase: "Build",
                dayName: "Tue",
                workouts: [WidgetWorkout(type: "🏃 Run", duration: "50min", zone: "Z2", isCompleted: false)],
                daysUntilRace: 75,
                weather: WidgetWeather(icon: "☀️", highTemp: 68),
                readiness: .preview
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
            weather: WidgetWeather.forecast(for: Date()),
            readiness: WidgetReadiness.load(from: WidgetTrainingPlan.sharedDefaults)
        )
    }
}

// MARK: - Shared Helpers
fileprivate enum WorkoutIcon {
    static func from(_ type: String) -> String {
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
}

// MARK: - Discipline Circle (medium widget)
private struct DisciplineCircle: View {
    let icon: String
    let percent: Int

    private var ringColor: Color {
        switch percent {
        case 90...: return Color(red: 0.2, green: 0.9, blue: 0.5)
        case 70..<90: return Color(red: 0.95, green: 0.85, blue: 0.2)
        default: return Color(red: 1.0, green: 0.55, blue: 0.1)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3)
                    .frame(width: 30, height: 30)
                Circle()
                    .trim(from: 0, to: CGFloat(min(percent, 100)) / 100.0)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(-90))
                Text(icon)
                    .font(.system(size: 11))
            }
            Text("\(percent)%")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
        }
    }
}

// MARK: - Small Widget View
struct Race1WidgetView: View {
    var entry: WorkoutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Week + days to race
            HStack {
                Text("Wk \(entry.weekNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                if entry.daysUntilRace > 0 {
                    Text("\(entry.daysUntilRace)d to race")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                } else if entry.daysUntilRace == 0 {
                    Text("Race Day! 🏁")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Row 2: Day + weather
            HStack {
                Text(entry.dayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("\(entry.weather.icon)\(entry.weather.highTemp)°")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            if entry.workouts.isEmpty {
                Spacer()
                Text("Rest Day")
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Spacer(minLength: 2)
                ForEach(Array(entry.workouts.prefix(3).enumerated()), id: \.offset) { _, workout in
                    HStack(spacing: 2) {
                        Text(WorkoutIcon.from(workout.type))
                            .font(.body)
                        Text(" \(workout.duration)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(workout.isCompleted ? .white.opacity(0.5) : .white)
                            .lineLimit(1)
                        Spacer()
                        if workout.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
                if entry.workouts.count > 3 {
                    Text("+\(entry.workouts.count - 3) more")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Medium Widget View
struct Race1MediumWidgetView: View {
    var entry: WorkoutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Full-width header
            HStack(spacing: 6) {
                Text("Wk \(entry.weekNumber)")
                    .font(.caption).fontWeight(.bold).foregroundColor(.white)
                if entry.daysUntilRace > 0 {
                    Text("·").font(.caption).foregroundColor(.white.opacity(0.25))
                    Text("\(entry.daysUntilRace)d to race")
                        .font(.caption).foregroundColor(.white.opacity(0.45))
                } else if entry.daysUntilRace == 0 {
                    Text("· Race Day! 🏁")
                        .font(.caption).foregroundColor(.orange)
                }
                Spacer()
                Text(entry.dayName)
                    .font(.caption).foregroundColor(.white.opacity(0.5))
                Text("\(entry.weather.icon)\(entry.weather.highTemp)°")
                    .font(.caption).foregroundColor(.white.opacity(0.7))
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)

            // Two-column content
            HStack(alignment: .top, spacing: 12) {
                // Left: today's workouts
                VStack(alignment: .leading, spacing: 5) {
                    if entry.workouts.isEmpty {
                        Spacer()
                        Text("Rest Day")
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    } else {
                        ForEach(Array(entry.workouts.prefix(3).enumerated()), id: \.offset) { _, workout in
                            HStack(spacing: 4) {
                                Text(WorkoutIcon.from(workout.type)).font(.body)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(workout.duration)
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(workout.isCompleted ? .white.opacity(0.45) : .white)
                                    Text(workout.zone)
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                                if workout.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green).font(.caption)
                                }
                            }
                        }
                        if entry.workouts.count > 3 {
                            Text("+\(entry.workouts.count - 3) more")
                                .font(.caption).foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Vertical divider
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 0.5)
                    .frame(maxHeight: .infinity)

                // Right: readiness panel
                if let r = entry.readiness {
                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(r.score)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(r.levelColor)
                            Text("/100")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        Text(r.levelLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        HStack(spacing: 10) {
                            if r.shows("swim") {
                                DisciplineCircle(icon: "🏊", percent: r.swimPercent)
                            }
                            if r.shows("bike") {
                                DisciplineCircle(icon: "🚴", percent: r.bikePercent)
                            }
                            if r.shows("run") {
                                DisciplineCircle(icon: "🏃", percent: r.runPercent)
                            }
                        }
                    }
                    .frame(minWidth: 110)
                } else {
                    VStack(spacing: 4) {
                        Text("—")
                            .font(.title2).foregroundColor(.white.opacity(0.25))
                        Text("Open app to\nload readiness")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                    .frame(minWidth: 110)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Widget Configurations
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

struct Race1MediumWidget: Widget {
    let kind: String = "Race1MediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutTimelineProvider()) { entry in
            Race1MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Training Dashboard")
        .description("Today's workouts with training readiness and race-readiness by discipline.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct Race1WidgetBundle: WidgetBundle {
    var body: some Widget {
        Race1Widget()
        Race1MediumWidget()
    }
}
