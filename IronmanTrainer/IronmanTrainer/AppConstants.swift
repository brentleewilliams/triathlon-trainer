import Foundation
import WidgetKit

extension Notification.Name {
    static let navigateToWeek = Notification.Name("navigateToWeek")
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
