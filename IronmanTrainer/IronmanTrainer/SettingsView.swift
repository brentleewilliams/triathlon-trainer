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

            let dayName = DayNames.from(date, calendar: calendar)

            // Find the week this date falls in
            let planStart = plan.weeks.first?.startDate ?? today
            let weekIndex = calendar.dateComponents([.weekOfYear], from: planStart, to: date).weekOfYear ?? 0
            let weekNumber = weekIndex + 1

            guard weekNumber >= 1 && weekNumber <= plan.weeks.count,
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
    @ObservedObject var checkIn = CheckInManager.shared
    @ObservedObject var courseService = RaceCourseService.shared
    @ObservedObject var authService = AuthService.shared
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var showSignOutAlert = false
    @State private var showReOnboardAlert = false
    @State private var showRestorePlanAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showReauthAlert = false
    @State private var isRegeneratingPlan = false
    @State private var regenerateError: String?
    @State private var storedThresholds: PerformanceThresholds = PerformanceThresholdsStore.load() ?? .empty
    @State private var homeZip: String = ""
    @State private var zipSaveTask: Task<Void, Never>?
    @EnvironmentObject var trainingPlan: TrainingPlanManager

    var raceDateDisplay: String {
        let savedInterval = UserDefaults.standard.double(forKey: "race_date")
        guard savedInterval > 0 else { return "Not set" }
        let date = Date(timeIntervalSince1970: savedInterval)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Notifications")) {
                    Toggle("Morning Workout Reminder", isOn: $notificationManager.morningWorkoutReminder)

                    if notificationManager.morningWorkoutReminder {
                        DatePicker("Reminder Time", selection: $notificationManager.reminderTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section(
                    header: Text("Morning Check-In"),
                    footer: Text("A short conversational check-in with your coach delivered via push. Default 7:00 AM.")
                ) {
                    Toggle("Enable Morning Check-In", isOn: $checkIn.enabled)
                        .onChange(of: checkIn.enabled) { _, _ in
                            checkIn.scheduleLocalFallbackNotification()
                        }

                    if checkIn.enabled {
                        DatePicker(
                            "Check-In Time",
                            selection: $checkIn.checkInTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: checkIn.checkInTime) { _, _ in
                            checkIn.scheduleLocalFallbackNotification()
                        }
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

                Section(
                    header: Text("Training Environment"),
                    footer: Text("Used to calibrate altitude and heat guidance. Inferred from your location on first launch; edit here anytime.")
                ) {
                    HStack {
                        Text("Training Zip")
                        Spacer()
                        TextField("e.g. 97401", text: $homeZip)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .foregroundColor(.secondary)
                            .onChange(of: homeZip) { _, newValue in
                                zipSaveTask?.cancel()
                                zipSaveTask = Task {
                                    try? await Task.sleep(nanoseconds: 700_000_000)
                                    guard !Task.isCancelled,
                                          let uid = authService.currentUserID else { return }
                                    try? await FirestoreService.shared.updateHomeZip(newValue, for: uid)
                                }
                            }
                    }

                    HStack {
                        Text("Elevation")
                        Spacer()
                        TextField("feet", value: envBinding(\.trainingElevationFeet), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("ft")
                            .foregroundColor(.secondary)
                    }

                    Picker("Climate", selection: envBinding(\.trainingClimate)) {
                        ForEach(AthleteEnvironment.defaultClimateOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }

                    Toggle("Pool access", isOn: envBinding(\.poolAccess))
                    Toggle("Open-water access", isOn: envBinding(\.openWaterAccess))
                    Toggle("Indoor trainer access", isOn: envBinding(\.trainerAccess))
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
                        Text("Race Date")
                        Spacer()
                        Text(raceDateDisplay)
                            .foregroundColor(.secondary)
                    }
                }
                Section(header: Text("Secondary Races")) {
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

                    Button {
                        regeneratePlan()
                    } label: {
                        HStack {
                            Text("Regenerate Plan")
                            Spacer()
                            if isRegeneratingPlan {
                                ProgressView()
                            }
                        }
                    }
                    .foregroundColor(.blue)
                    .disabled(isRegeneratingPlan)

                    if let error = regenerateError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button("Restore Original Plan") {
                        showRestorePlanAlert = true
                    }
                    .foregroundColor(.orange)
                }

                Section(header: Text("Advanced")) {
                    DisclosureGroup("Performance Thresholds") {
                        HStack {
                            Text("FTP")
                            Spacer()
                            Text(storedThresholds.ftpWatts.map { "\($0) W" } ?? "—")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Threshold Pace")
                            Spacer()
                            Text(storedThresholds.thresholdPaceSecondsPerMile.map { paceString(seconds: $0) + "/mi" } ?? "—")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Swim CSS")
                            Spacer()
                            Text(storedThresholds.cssSecondsPer100yd.map { paceString(seconds: $0) + "/100yd" } ?? "—")
                                .foregroundColor(.secondary)
                        }
                        if let capturedAt = storedThresholds.capturedAt {
                            HStack {
                                Text("Captured")
                                Spacer()
                                Text(Formatters.fullDate.string(from: capturedAt))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        if storedThresholds.hasAnyValue {
                            Button("Clear") {
                                PerformanceThresholdsStore.clear()
                                storedThresholds = .empty
                            }
                            .foregroundColor(.red)
                        } else {
                            Text("No thresholds captured. Claude will ask once in chat if a specific number is needed.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Account")) {
                    if let email = authService.currentUserEmail {
                        HStack {
                            Text("Signed in as")
                            Spacer()
                            Text(email)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

                    Button("Sign Out") {
                        showSignOutAlert = true
                    }
                    .foregroundColor(.red)

                    Button {
                        showDeleteAccountAlert = true
                    } label: {
                        HStack {
                            Text("Delete Account")
                            Spacer()
                            if isDeletingAccount {
                                ProgressView()
                            }
                        }
                    }
                    .foregroundColor(.red)
                    .disabled(isDeletingAccount)

                    if let error = deleteAccountError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard let uid = authService.currentUserID,
                      let profile = try? await FirestoreService.shared.getUserProfile(uid: uid) else { return }
                homeZip = profile.homeZip ?? ""
            }
            .alert("Generate New Plan?", isPresented: $showReOnboardAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    // Wipe persisted plan state so re-onboarding starts clean.
                    // Without this, cached saved_plan + Core Data WorkoutPlanVersion
                    // from the prior onboarding leak through and overwrite the
                    // freshly generated plan.
                    if let uid = authService.currentUserID {
                        UserDefaults.standard.set(false, forKey: "onboarding_complete_\(uid)")
                        UserDefaults.standard.removeObject(forKey: "saved_plan_\(uid)")
                    }
                    OnboardingStore.onboardingDate = nil
                    // Clear the primary-race header info too, so the new
                    // onboarding flow doesn't briefly show the previous race.
                    RaceProfileStore.raceName = nil
                    RaceProfileStore.raceVenue = nil
                    UserDefaults.standard.removeObject(forKey: "race_date")
                    authService.savedPlan = nil
                    trainingPlan.clearAllPlanVersions()
                    authService.onboardingComplete = false
                }
            } message: {
                Text("This will take you through onboarding to create a new AI-generated training plan. Your current plan will be saved as a backup.")
            }
            .alert("Sign Out?", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    trainingPlan.clearAllData()
                    try? authService.signOut()
                }
            }
            .alert("Sign In Required", isPresented: $showReauthAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out Now", role: .destructive) {
                    trainingPlan.clearAllData()
                    try? authService.signOut()
                }
            } message: {
                Text("For security, please sign out and sign back in before deleting your account. Your data has not been deleted.")
            }
            .alert("Restore Original Plan?", isPresented: $showRestorePlanAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Restore") {
                    trainingPlan.restoreHardcodedPlan()
                }
            } message: {
                Text("This will replace your current plan with the original Ironman 70.3 Oregon 17-week training plan.")
            }
            .alert("Delete Account?", isPresented: $showDeleteAccountAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("This permanently deletes your account, training plan, and all data. This cannot be undone.")
            }
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        deleteAccountError = nil
        Task {
            do {
                try await authService.deleteAccount()
                await MainActor.run {
                    trainingPlan.clearAllPlanVersions()
                    isDeletingAccount = false
                }
            } catch AuthService.AuthError.reauthRequired {
                await MainActor.run {
                    isDeletingAccount = false
                    showReauthAlert = true
                }
            } catch {
                await MainActor.run {
                    deleteAccountError = error.localizedDescription
                    isDeletingAccount = false
                }
            }
        }
    }

    private func paceString(seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Produces a `Binding` to a single field on `courseService.athleteEnvironment`
    /// that persists the whole struct via `saveEnvironment` on every mutation.
    /// Keeps the Training Environment section from needing one custom Binding per field.
    private func envBinding<Value>(_ keyPath: WritableKeyPath<AthleteEnvironment, Value>) -> Binding<Value> {
        Binding(
            get: { courseService.athleteEnvironment[keyPath: keyPath] },
            set: { newValue in
                var env = courseService.athleteEnvironment
                env[keyPath: keyPath] = newValue
                courseService.saveEnvironment(env)
            }
        )
    }

    private func regeneratePlan() {
        guard let savedInput = PlanGenerationInput.load() else {
            regenerateError = "No saved onboarding data. Use 'Generate New Plan' instead."
            return
        }
        isRegeneratingPlan = true
        regenerateError = nil
        Task {
            let taskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            do {
                let plan = try await LLMProxyService.shared.generatePlan(input: savedInput)
                await MainActor.run {
                    trainingPlan.loadPlan(plan)
                    if let uid = authService.currentUserID {
                        let metadata = PlanMetadata(
                            generatedAt: Date(),
                            generatedBy: "llm-generated",
                            raceId: nil,
                            approved: true
                        )
                        Task {
                            try? await FirestoreService.shared.saveTrainingPlan(plan, metadata: metadata, for: uid)
                        }
                    }
                    isRegeneratingPlan = false
                }
            } catch {
                await MainActor.run {
                    regenerateError = error.localizedDescription
                    isRegeneratingPlan = false
                }
            }
            UIApplication.shared.endBackgroundTask(taskID)
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

// MARK: - Secondary Races Settings Section

struct PrepRacesSettingsSection: View {
    @ObservedObject private var prepRaces = PrepRacesManager.shared
    @EnvironmentObject private var trainingPlan: TrainingPlanManager
    @State private var showAddSheet = false
    @State private var isRegeneratingPlan = false
    @State private var regenerateError: String?

    var body: some View {
        Group {
            if isRegeneratingPlan {
                HStack {
                    ProgressView()
                        .padding(.trailing, 6)
                    Text("Rebuilding surrounding weeks…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = regenerateError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if prepRaces.races.isEmpty {
                Button {
                    showAddSheet = true
                } label: {
                    HStack {
                        Image(systemName: "flag.2.crossed")
                            .foregroundColor(.orange)
                        Text("Add a Secondary Race")
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
        }
        .sheet(isPresented: $showAddSheet) {
            AddPrepRaceSheet { race, wantsAdjustment in
                prepRaces.add(race)
                trainingPlan.insertSecondaryRaceCard(race)
                if wantsAdjustment, let input = PlanGenerationInput.load() {
                    isRegeneratingPlan = true
                    regenerateError = nil
                    Task {
                        do {
                            let newWeeks = try await PlanGenerationService.shared.regenerateSurroundingWeeks(
                                race: race,
                                allWeeks: trainingPlan.weeks,
                                input: input
                            )
                            await MainActor.run {
                                trainingPlan.replaceWeeks(newWeeks)
                                // Re-insert race card in case regeneration overwrote it
                                trainingPlan.insertSecondaryRaceCard(race)
                                isRegeneratingPlan = false
                            }
                        } catch {
                            await MainActor.run {
                                regenerateError = "Plan adjustment failed. Race added, plan unchanged."
                                isRegeneratingPlan = false
                            }
                        }
                    }
                }
            }
        }
    }
}
