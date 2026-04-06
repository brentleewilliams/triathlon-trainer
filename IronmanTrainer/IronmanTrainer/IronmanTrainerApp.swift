import SwiftUI
import FirebaseCore

@main
struct IronmanTrainerApp: App {
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
