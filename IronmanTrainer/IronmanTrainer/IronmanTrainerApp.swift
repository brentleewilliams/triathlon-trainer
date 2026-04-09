import SwiftUI
import FirebaseCore

@main
struct Race1App: App {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var authService = AuthService.shared
    @Environment(\.scenePhase) var scenePhase

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isLoading || authService.checkingPlan {
                    ProgressView("Loading...")
                } else if !authService.isAuthenticated {
                    SignInView()
                } else if !authService.onboardingComplete {
                    OnboardingView(onComplete: { plan in
                        authService.markOnboardingComplete(plan: plan)
                    })
                    .environmentObject(authService)
                    .environmentObject(healthKitManager)
                } else {
                    ContentView()
                        .environmentObject(healthKitManager)
                        .onAppear {
                            healthKitManager.checkAuthorization()
                            Task {
                                print("[App] ContentView appeared, syncing workouts...")
                                await healthKitManager.syncWorkouts()
                                print("[App] Workout sync complete, found \(healthKitManager.workouts.count) workouts")
                            }
                        }
                        .onOpenURL { url in
                            if url.scheme == "race1",
                               url.host == "week",
                               let weekStr = url.pathComponents.last,
                               let week = Int(weekStr) {
                                NotificationCenter.default.post(name: .navigateToWeek, object: nil, userInfo: ["week": week])
                            }
                        }
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && authService.onboardingComplete {
                Task {
                    await healthKitManager.syncWorkouts()
                }
            }
        }
    }
}
