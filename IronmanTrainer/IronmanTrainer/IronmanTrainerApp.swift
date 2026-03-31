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
                .onOpenURL { url in
                    if url.scheme == "ironmantrainer",
                       url.host == "week",
                       let weekStr = url.pathComponents.last,
                       let week = Int(weekStr) {
                        NotificationCenter.default.post(name: .navigateToWeek, object: nil, userInfo: ["week": week])
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
