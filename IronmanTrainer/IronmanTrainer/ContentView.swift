import SwiftUI

struct ContentView: View {
    @StateObject private var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var checkInManager = CheckInManager.shared
    @StateObject private var trainingStatus = TrainingStatusService(healthKit: HealthKitManager.shared)
    @StateObject private var router = NavigationRouter.shared
    @State private var selectedTab = 0
    @State private var showLogWorkoutSheet = false
    @State private var showHKDeniedAlert = false

    init() {
        let plan = AuthService.shared.savedPlan
        _trainingPlan = StateObject(wrappedValue: TrainingPlanManager(weeks: plan))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .environmentObject(trainingStatus)
                .environmentObject(router)
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(0)

            PlanView()
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .environmentObject(router)
                .tabItem {
                    Label("Plan", systemImage: "calendar.badge.clock")
                }
                .tag(1)

            ActivitiesView()
                .environmentObject(healthKit)
                .environmentObject(trainingPlan)
                .environmentObject(router)
                .tabItem {
                    Label("Workouts", systemImage: "list.bullet")
                }
                .tag(2)

            AnalyticsView()
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .environmentObject(trainingStatus)
                .environmentObject(router)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }
                .tag(3)
        }
        .onAppear {
            chatViewModel.trainingPlan = trainingPlan
            chatViewModel.healthKit = healthKit
            chatViewModel.trainingStatus = trainingStatus
            Task { await trainingStatus.compute() }
        }
        // Check-in comes from the system notification delegate in IronmanTrainerApp —
        // keep as NotificationCenter since UNUserNotificationCenterDelegate cannot
        // call router directly without a reference.
        .onReceive(NotificationCenter.default.publisher(for: .openCheckIn)) { _ in
            router.openCheckIn()
        }
        // Apply chat seed before the sheet appears
        .onChange(of: router.showChat) { _, isShowing in
            if isShowing && !router.chatSeed.isEmpty {
                chatViewModel.pendingInputText = router.chatSeed
                router.chatSeed = ""
            }
        }
        .sheet(isPresented: $router.showCheckIn) {
            CheckInView(viewModel: chatViewModel, checkIn: checkInManager)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .environmentObject(trainingStatus)
        }
        .sheet(isPresented: $router.showChat) {
            ChatView(viewModel: chatViewModel)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
        }
        .sheet(isPresented: $router.showCalendar) {
            NavigationStack {
                TrainingCalendarView()
                    .environmentObject(trainingPlan)
            }
        }
        .onChange(of: router.showLogWorkout) { _, isShowing in
            guard isShowing else { return }
            router.showLogWorkout = false
            if healthKit.canWriteWorkouts {
                showLogWorkoutSheet = true
            } else {
                showHKDeniedAlert = true
            }
        }
        .sheet(isPresented: $showLogWorkoutSheet) {
            LogWorkoutSheet(
                prefilledType: .running,
                prefilledDate: Date(),
                onSave: { activityType, minutes, end in
                    showLogWorkoutSheet = false
                    Task {
                        let start = end.addingTimeInterval(-Double(minutes * 60))
                        try? await healthKit.saveWorkout(activityType: activityType, start: start, end: end)
                        try? await Task.sleep(nanoseconds: 750_000_000)
                        await healthKit.syncWorkouts()
                    }
                }
            )
        }
        .alert("Health Access Required", isPresented: $showHKDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To log workouts, enable Health access in Settings → Privacy & Security → Health → Race1 Trainer.")
        }
    }
}

#Preview {
    ContentView()
}
