import SwiftUI

struct ContentView: View {
    @StateObject private var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var checkInManager = CheckInManager.shared
    @StateObject private var trainingStatus = TrainingStatusService(healthKit: HealthKitManager.shared)
    @State private var showCheckIn = false
    @State private var selectedTab = 0

    init() {
        let plan = AuthService.shared.savedPlan
        _trainingPlan = StateObject(wrappedValue: TrainingPlanManager(weeks: plan))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .environmentObject(trainingPlan)
                .environmentObject(trainingStatus)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            AnalyticsView()
                .environmentObject(trainingPlan)
                .environmentObject(trainingStatus)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }
                .tag(1)

            ChatView(viewModel: chatViewModel)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(2)

            SettingsView()
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .tabItem {
                    Label("Settings", systemImage: "gear")
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
            selectedTab = 2
        }
        .sheet(isPresented: $showCheckIn) {
            CheckInView(viewModel: chatViewModel, checkIn: checkInManager)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .environmentObject(trainingStatus)
        }
    }
}

#Preview {
    ContentView()
}
