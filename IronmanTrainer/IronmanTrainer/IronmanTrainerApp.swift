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
                    print("DEBUG: IronmanTrainerApp onAppear - syncing HealthKit workouts")
                    Task {
                        await healthKitManager.syncWorkouts()
                    }
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                print("DEBUG: App became active, syncing HealthKit workouts")
                Task {
                    await healthKitManager.syncWorkouts()
                }
            }
        }
    }
}
