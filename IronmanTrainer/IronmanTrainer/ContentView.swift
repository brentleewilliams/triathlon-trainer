import SwiftUI

struct ContentView: View {
    @StateObject private var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var checkInManager = CheckInManager.shared
    @StateObject private var trainingStatus = TrainingStatusService(healthKit: HealthKitManager.shared)
    @State private var showCheckIn = false
    @State private var showChat = false
    @State private var showSettings = false
    @State private var selectedTab = 0

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
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(0)

            PlanView()
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .tabItem {
                    Label("Plan", systemImage: "calendar.badge.clock")
                }
                .tag(1)

            ActivitiesView()
                .environmentObject(healthKit)
                .environmentObject(trainingPlan)
                .tabItem {
                    Label("Workouts", systemImage: "list.bullet")
                }
                .tag(2)

            AnalyticsView()
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .environmentObject(trainingStatus)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }
                .tag(3)
        }
        .onAppear {
            // Inject the plan into NotificationManager and chatViewModel in a
            // single lifecycle pass. Both assignments are order-independent —
            // they target different managers and neither reads the other.
            NotificationManager.shared.setTrainingPlan(trainingPlan)
            chatViewModel.trainingPlan = trainingPlan
            chatViewModel.healthKit = healthKit
            chatViewModel.trainingStatus = trainingStatus
            Task { await trainingStatus.compute() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCheckIn)) { _ in
            showCheckIn = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToChat)) { _ in
            showChat = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showCheckIn) {
            CheckInView(viewModel: chatViewModel, checkIn: checkInManager)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .environmentObject(trainingStatus)
        }
        .sheet(isPresented: $showChat) {
            ChatView(viewModel: chatViewModel)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
        }
    }
}

#Preview {
    ContentView()
}
