import SwiftUI

struct ContentView: View {
    @StateObject private var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var checkInManager = CheckInManager.shared
    @State private var showCheckIn = false

    init() {
        let plan = AuthService.shared.savedPlan
        _trainingPlan = StateObject(wrappedValue: TrainingPlanManager(weeks: plan))
    }

    var body: some View {
        TabView {
            HomeView()
                .environmentObject(trainingPlan)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            AnalyticsView()
                .environmentObject(trainingPlan)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }

            ChatView(viewModel: chatViewModel)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }

            SettingsView()
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .onAppear {
            chatViewModel.trainingPlan = trainingPlan
            chatViewModel.healthKit = healthKit
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCheckIn)) { _ in
            showCheckIn = true
        }
        .sheet(isPresented: $showCheckIn) {
            CheckInView(viewModel: chatViewModel, checkIn: checkInManager)
                .environmentObject(trainingPlan)
                .environmentObject(healthKit)
        }
    }
}

#Preview {
    ContentView()
}
