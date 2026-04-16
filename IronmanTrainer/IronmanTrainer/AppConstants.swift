import Foundation
import WidgetKit

// MARK: - Release build print suppression
// In non-Debug builds, override print() with a no-op so debug logs don't ship.
// Zero call-site changes needed — all existing print() calls are silenced automatically.
#if !DEBUG
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

extension Notification.Name {
    static let navigateToWeek = Notification.Name("navigateToWeek")
    /// Posted when the user taps a Morning Check-In push (FCM or local) so the
    /// app can route to CheckInView.
    static let openCheckIn = Notification.Name("openCheckIn")
}

// MARK: - Onboarding Date Store
/// Tracks the date the user completed onboarding. Days before this date are
/// "pre-plan" — the plan existed in the data model but the user didn't have
/// the app yet, so we don't count them against compliance or flag as missed.
enum OnboardingStore {
    private static let key = "onboarding_date_global"

    static var onboardingDate: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: key)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let d = newValue {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// True if `date` is strictly before the user's onboarding date.
    /// Returns false when no onboarding date is recorded (legacy users pre-2026-04-12).
    static func isPrePlan(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let od = onboardingDate else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: od)
    }
}

// MARK: - App Group Shared Data
enum AppGroupConstants {
    static let suiteName = "group.com.brent.race1"
    static let swappedWeeksKey = "swapped_weeks"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// Write all current weeks to shared UserDefaults so the widget can read swapped data
    static func syncWeeksToWidget(_ weeks: [TrainingWeek]) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(weeks) {
            defaults.set(data, forKey: swappedWeeksKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sync race date to App Group so widget can show correct countdown
    static func syncRaceDateToWidget(_ date: Date) {
        sharedDefaults?.set(date.timeIntervalSince1970, forKey: "race_date")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Day Name Helpers
/// Single source of truth for the app's `"Mon","Tue",...` convention used by
/// `DayWorkout.day`, HomeView, CheckInManager and NotificationManager.
enum DayNames {
    /// Indexed by `Calendar`'s weekday component (1 = Sunday … 7 = Saturday).
    /// Returns the short 3-letter name (or empty string for out-of-range input).
    static func fromWeekday(_ weekday: Int) -> String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names.indices.contains(weekday) ? names[weekday] : ""
    }

    /// Convenience: the short day name for the given `Date` in the current calendar.
    static func from(_ date: Date, calendar: Calendar = .current) -> String {
        fromWeekday(calendar.component(.weekday, from: date))
    }
}

// MARK: - Shared Formatters
enum Formatters {
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
        // Primary: read from Info.plist (populated by xcconfig build settings)
        if let key = Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        // Fallback: read from Config.plist (used by CI-generated bundles)
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath),
           let key = config["ANTHROPIC_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ""
    }()

    static let openAIAPIKey: String = {
        if let key = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath),
           let key = config["OPENAI_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ""
    }()

    static let langsmithAPIKey: String = {
        // Primary: read from Info.plist (populated by xcconfig build settings)
        if let key = Bundle.main.infoDictionary?["LANGSMITH_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        // Fallback: read from Config.plist (used by CI-generated bundles)
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath),
           let key = config["LANGSMITH_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ""
    }()
}
