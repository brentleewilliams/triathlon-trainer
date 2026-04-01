import SwiftUI
import UserNotifications

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
    @ObservedObject var authService = AuthService.shared
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var showSignOutAlert = false
    @State private var showReOnboardAlert = false
    @State private var showRestorePlanAlert = false
    @EnvironmentObject var trainingPlan: TrainingPlanManager

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
                Section(header: Text("Training Plan")) {
                    Button("Generate New Plan") {
                        showReOnboardAlert = true
                    }
                    .foregroundColor(.blue)

                    Button("Restore Original Plan") {
                        showRestorePlanAlert = true
                    }
                    .foregroundColor(.orange)
                }

                Section(header: Text("Account")) {
                    if let uid = authService.currentUserID {
                        HStack {
                            Text("User ID")
                            Spacer()
                            Text(String(uid.prefix(12)) + "...")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

                    Button("Sign Out") {
                        showSignOutAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Generate New Plan?", isPresented: $showReOnboardAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    authService.onboardingComplete = false
                    if let uid = authService.currentUserID {
                        UserDefaults.standard.set(false, forKey: "onboarding_complete_\(uid)")
                    }
                }
            } message: {
                Text("This will take you through onboarding to create a new AI-generated training plan. Your current plan will be saved as a backup.")
            }
            .alert("Sign Out?", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    try? authService.signOut()
                }
            }
            .alert("Restore Original Plan?", isPresented: $showRestorePlanAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Restore") {
                    trainingPlan.restoreHardcodedPlan()
                }
            } message: {
                Text("This will replace your current plan with the original Ironman 70.3 Oregon 17-week training plan.")
            }
        }
    }
}
