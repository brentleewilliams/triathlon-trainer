import SwiftUI

@main
struct IronmanTrainerApp: App {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .onAppear {
                    Task {
                        await healthKitManager.syncWorkouts()
                    }
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                Task {
                    await healthKitManager.syncWorkouts()
                }
            }
        }
    }
}
