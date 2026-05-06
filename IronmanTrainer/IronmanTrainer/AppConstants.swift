import Foundation
import WidgetKit

// MARK: - Feature flags

enum FeatureFlags {
    static var includeHealthKitInAIContext: Bool {
        guard UserDefaults.standard.object(forKey: "shareWorkoutDataWithCoach") != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: "shareWorkoutDataWithCoach")
    }
}

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
    /// Posted when any view wants to navigate the root TabView to the Chat tab (index 2).
    static let navigateToChat = Notification.Name("navigateToChat")
    /// Posted when any view wants to open the Settings sheet.
    static let openSettings = Notification.Name("openSettings")
    /// Posted when any view wants to open the Training Calendar sheet.
    static let openCalendar = Notification.Name("openCalendar")
    /// Posted when any view wants to open the manual workout-log sheet.
    static let openLogWorkout = Notification.Name("openLogWorkout")
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

// MARK: - Primary Race Store
/// Persists the user's primary race (name, venue, date) so the home and plan
/// views can show *their* race in the header instead of the bundled course
/// profile fallback. Onboarding writes here on completion; SettingsView
/// updates it when the race is changed.
enum RaceProfileStore {
    private static let nameKey  = "race_primary_name"
    private static let venueKey = "race_primary_venue"
    // race_date already exists as a top-level UserDefaults key — read it
    // through the existing call sites; we don't shadow it here.

    static var raceName: String? {
        get { UserDefaults.standard.string(forKey: nameKey) }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: nameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: nameKey)
            }
        }
    }

    static var raceVenue: String? {
        get { UserDefaults.standard.string(forKey: venueKey) }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: venueKey)
            } else {
                UserDefaults.standard.removeObject(forKey: venueKey)
            }
        }
    }

    /// One-time migration for users who completed onboarding before name +
    /// venue were persisted locally. Reads the user's primary Race from
    /// Firestore and writes it into the local store. No-op when local values
    /// already exist or when there is no race in Firestore (so it'll retry
    /// on the next launch instead of pinning a stale negative result).
    static func backfillFromFirestoreIfNeeded(uid: String) async {
        let needsSports = (UserDefaults.standard.array(forKey: "race_sports") as? [String]) == nil
        let needsNameVenue = raceName == nil || raceVenue == nil
        let needsDate = UserDefaults.standard.double(forKey: "race_date") == 0
        guard needsSports || needsNameVenue || needsDate else { return }
        do {
            if let race = try await FirestoreService.shared.getRace(for: uid) {
                if raceName  == nil { raceName  = race.name }
                if raceVenue == nil { raceVenue = race.location }
                if needsDate {
                    UserDefaults.standard.set(race.date.timeIntervalSince1970, forKey: "race_date")
                    AppGroupConstants.syncRaceDateToWidget(race.date)
                }
                if needsSports {
                    let sports = race.type.relevantSports
                    UserDefaults.standard.set(sports, forKey: "race_sports")
                    AppGroupConstants.syncRaceSportsToWidget(sports)
                }
            } else if needsDate {
                // No race doc in Firestore — derive date from the plan's last week
                // so the countdown shows the correct date rather than a hardcoded fallback.
                if let plan = try await FirestoreService.shared.getTrainingPlan(for: uid),
                   let lastWeek = plan.weeks.sorted(by: { $0.weekNumber < $1.weekNumber }).last {
                    UserDefaults.standard.set(lastWeek.endDate.timeIntervalSince1970, forKey: "race_date")
                    AppGroupConstants.syncRaceDateToWidget(lastWeek.endDate)
                }
            }
        } catch {
            print("[RaceProfileStore] backfill failed: \(error)")
        }
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

    /// Sync today's completed workout types so the widget can show checkmarks
    static func syncTodayCompletedToWidget(completedTypes: Set<String>) {
        guard let defaults = sharedDefaults else { return }
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        let payload: [String: Any] = ["date": today, "types": Array(completedTypes)]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            defaults.set(data, forKey: "completed_today")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sync race date to App Group so widget can show correct countdown
    static func syncRaceDateToWidget(_ date: Date) {
        sharedDefaults?.set(date.timeIntervalSince1970, forKey: "race_date")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sync readiness score and per-discipline volume percents so the medium widget can display them
    static func syncReadinessToWidget(score: Int, swimPercent: Int, bikePercent: Int, runPercent: Int) {
        guard let defaults = sharedDefaults else { return }
        let payload: [String: Any] = [
            "readinessScore": score,
            "swimPercent": swimPercent,
            "bikePercent": bikePercent,
            "runPercent": runPercent
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            defaults.set(data, forKey: "widget_readiness")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sync which sports are relevant for this user's race so the widget filters discipline circles.
    /// Pass the same array as OnboardingViewModel.relevantSports (e.g. ["run"] for marathon).
    static func syncRaceSportsToWidget(_ sports: [String]) {
        sharedDefaults?.set(sports, forKey: "race_sports")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Remove race-specific keys from the App Group on sign-out so a new user
    /// starts with a clean slate before their onboarding writes fresh values.
    static func clearRaceData() {
        sharedDefaults?.removeObject(forKey: "race_date")
        sharedDefaults?.removeObject(forKey: "race_sports")
        sharedDefaults?.removeObject(forKey: "widget_readiness")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Nuclear wipe of the entire App Group suite — called on sign-out so no
    /// data from one user is ever visible to the next. Widget timelines are
    /// reloaded so the widget shows a blank/placeholder state.
    static func wipeAllSharedData() {
        sharedDefaults?.removePersistentDomain(forName: suiteName)
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
