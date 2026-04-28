import SwiftUI
import FirebaseCore
import UserNotifications

@main
struct Race1App: App {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var authService = AuthService.shared
    @StateObject private var checkInManager = CheckInManager.shared
    @Environment(\.scenePhase) var scenePhase

    // MARK: - Notification delegate
    // Handles taps on both FCM pushes and local UN notifications. When the
    // payload contains kind="check_in", posts .openCheckIn so the content
    // view can surface CheckInView.
    private let notificationDelegate = CheckInNotificationDelegate()

    init() {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = notificationDelegate
        // FCM device token registration is not yet wired up; v1 falls back to
        // local UNUserNotificationCenter scheduling via
        // CheckInManager.scheduleLocalFallbackNotification().
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
                        .environmentObject(checkInManager)
                        .onAppear {
                            healthKitManager.checkAuthorization()
                            Task {
                                print("[App] ContentView appeared, syncing workouts...")
                                await healthKitManager.syncWorkouts()
                                print("[App] Workout sync complete, found \(healthKitManager.workouts.count) workouts")
                            }
                            // Backfill primary-race name/venue for users who
                            // onboarded before those fields were persisted
                            // locally. Cheap (single Firestore read) and self-
                            // skipping when the local store is already populated.
                            if let uid = authService.currentUserID {
                                Task { await RaceProfileStore.backfillFromFirestoreIfNeeded(uid: uid) }
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

// MARK: - Notification Delegate (Morning Check-In v1)
//
// Routes notification taps. FCM and local notifications share the payload
// convention: `kind = "check_in"` → post `.openCheckIn`. Any other payload is
// a no-op so the existing workout-reminder flow is unaffected.
final class CheckInNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let kind = userInfo["kind"] as? String, kind == "check_in" {
            NotificationCenter.default.post(name: .openCheckIn, object: nil, userInfo: userInfo)
        }
        completionHandler()
    }

    // Suppress the OS notification banner when app is foregrounded; the
    // check-in should instead be surfaced as a sheet via .openCheckIn.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let kind = userInfo["kind"] as? String, kind == "check_in" {
            NotificationCenter.default.post(name: .openCheckIn, object: nil, userInfo: userInfo)
            completionHandler([]) // suppress banner
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
