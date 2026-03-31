import SwiftUI

struct ContentView: View {
    @StateObject private var trainingPlan = TrainingPlanManager()
    @EnvironmentObject var healthKit: HealthKitManager
    @StateObject private var chatViewModel = ChatViewModel()
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
                .environmentObject(healthKit)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .onAppear {
            NotificationManager.shared.setTrainingPlan(trainingPlan)
        }
        .onAppear {
            chatViewModel.trainingPlan = trainingPlan
            chatViewModel.healthKit = healthKit
        }
    }
}

#Preview {
    ContentView()
}
