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
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                            .foregroundColor(.secondary)
                    }
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
                Section(header: Text("Tune-up Races")) {
                    PrepRacesSettingsSection()
                }

                Section(header: Text("Swim Drills")) {
                    NavigationLink {
                        DrillsDetailView()
                    } label: {
                        HStack {
                            Image(systemName: "figure.pool.swim")
                                .foregroundColor(.blue)
                            Text("Drill Sets A, B & C")
                        }
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

// MARK: - Drills Detail View

struct DrillsDetailView: View {
    var body: some View {
        List {
            Section(header: drillSetHeader("A", subtitle: "Catch Focus")) {
                drillRow("Catch-Up", reps: "4x50", description: "One hand stays extended at the front until the other hand catches up. Builds hand entry timing and catch mechanics.")
                drillRow("Fingertip Drag", reps: "4x50", description: "Drag fingertips along the water surface during recovery. Develops high elbow recovery and shoulder mobility.")
            }

            Section(header: drillSetHeader("B", subtitle: "Kick & Bilateral")) {
                drillRow("6-Kick Switch", reps: "4x50", description: "Six kicks on your side, then switch to the other side with one stroke. Builds kick-to-stroke coordination and body rotation.")
                drillRow("Side Kick", reps: "4x50", description: "Kick on your side with bottom arm extended, top arm at your hip. Develops balance, body position, and bilateral breathing.")
            }

            Section(header: drillSetHeader("C", subtitle: "Advanced Stroke")) {
                drillRow("Single-Arm", reps: "4x50 alternating", description: "Swim with one arm while the other stays at your side. Isolates each arm's pull pattern to identify imbalances.")
                drillRow("3-Stroke Glide", reps: "4x50", description: "Take three strokes then glide in streamline. Emphasizes distance per stroke, catch power, and streamlined body position.")
            }

            Section(header: Text("Progression")) {
                VStack(alignment: .leading, spacing: 8) {
                    progressionRow("Weeks 1-4", "Sets A & B rotating — build foundation")
                    progressionRow("Weeks 5-8", "A, B & C mixed — add advanced drills")
                    progressionRow("Weeks 9-12", "Drill volume decreases, race-pace increases")
                    progressionRow("Weeks 13-17", "Minimal drills, race-specific sharpening")
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Swim Drills")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func drillSetHeader(_ letter: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Text("Set \(letter)")
                .fontWeight(.bold)
            Text("—")
            Text(subtitle)
        }
    }

    private func drillRow(_ name: String, reps: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .fontWeight(.semibold)
                Spacer()
                Text(reps)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func progressionRow(_ weeks: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(weeks)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)
            Text(detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Prep Races Settings Section

struct PrepRacesSettingsSection: View {
    @ObservedObject private var prepRaces = PrepRacesManager.shared
    @State private var showAddSheet = false

    var body: some View {
        if prepRaces.races.isEmpty {
            Button {
                showAddSheet = true
            } label: {
                HStack {
                    Image(systemName: "flag.2.crossed")
                        .foregroundColor(.orange)
                    Text("Add a Tune-up Race")
                }
            }
        } else {
            ForEach(prepRaces.races) { race in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(race.name)
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 6) {
                            Text(race.distance)
                            Text(Formatters.fullDate.string(from: race.date))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    if race.isPast {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            .onDelete { offsets in
                prepRaces.remove(at: offsets)
            }

            Button {
                showAddSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add Another")
                }
                .font(.subheadline)
            }
        }

        EmptyView()
            .sheet(isPresented: $showAddSheet) {
                AddPrepRaceSheet { race in
                    prepRaces.add(race)
                }
            }
    }
}
