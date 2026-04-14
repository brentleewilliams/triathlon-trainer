import SwiftUI
import FirebaseCore
import UserNotifications

@main
struct Race1App: App {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var authService = AuthService.shared
    @StateObject private var checkInPresenter = CheckInPresenter.shared
    @Environment(\.scenePhase) var scenePhase

    init() {
        FirebaseApp.configure()
        // Register the background task handler before the first UI event loop.
        CheckInScheduler.registerBackgroundTask()
        // Install notification delegate so taps on the morning check-in
        // notification surface the CheckInView rather than silently opening the app.
        UNUserNotificationCenter.current().delegate = NotificationTapForwarder.shared
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
                        // First-time setup for morning check-in refresh.
                        CheckInScheduler.scheduleNext()
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
                            // Ensure the check-in refresh stays queued on every
                            // cold launch (iOS drops pending tasks on uninstall).
                            CheckInScheduler.scheduleNext()
                        }
                        .onOpenURL { url in
                            if url.scheme == "race1",
                               url.host == "week",
                               let weekStr = url.pathComponents.last,
                               let week = Int(weekStr) {
                                NotificationCenter.default.post(name: .navigateToWeek, object: nil, userInfo: ["week": week])
                            }
                        }
                        .fullScreenCover(item: $checkInPresenter.activeCheckIn) { checkIn in
                            CheckInView(
                                checkIn: checkIn,
                                onDismiss: { checkInPresenter.activeCheckIn = nil },
                                onTalkToCoach: {
                                    checkInPresenter.activeCheckIn = nil
                                    NotificationCenter.default.post(name: .openChatTab, object: nil)
                                }
                            )
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
            if newPhase == .background {
                CheckInScheduler.scheduleNext()
            }
        }
    }
}

// MARK: - Check-In Presenter

/// Holds the currently-presenting check-in for fullScreenCover binding.
/// `DailyCheckIn` is Identifiable via its `generatedAt` timestamp.
extension DailyCheckIn: Identifiable {
    var id: TimeInterval { generatedAt.timeIntervalSince1970 }
}

@MainActor
final class CheckInPresenter: ObservableObject {
    static let shared = CheckInPresenter()
    @Published var activeCheckIn: DailyCheckIn?
    private init() {}
}

// MARK: - Notification Tap Forwarder

/// Converts a tap on the morning check-in notification into a presented
/// CheckInView. If we have a cached check-in on disk it's shown immediately;
/// otherwise the app opens normally and the user can request one from Home.
final class NotificationTapForwarder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTapForwarder()

    // Show banner + sound even when app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let type = response.notification.request.content.userInfo["type"] as? String
        if type == "morning_checkin", let cached = CheckInManager.latestPersistedCheckIn() {
            Task { @MainActor in
                CheckInPresenter.shared.activeCheckIn = cached
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let openChatTab = Notification.Name("openChatTab")
}
