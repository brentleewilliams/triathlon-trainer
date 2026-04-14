import Foundation
import BackgroundTasks
import UIKit

/// Schedules + handles the morning check-in pre-generation via BGAppRefreshTask.
///
/// Flow:
///   1. At app launch (post-onboarding) we register the background task
///      identifier and schedule the first refresh.
///   2. iOS wakes the app ~30m before the user's notification time (best
///      effort — iOS controls exact timing).
///   3. `handle(task:)` pulls a fresh readiness snapshot, pre-generates the
///      coach greeting, then updates the scheduled notification payload so it
///      fires with contextual copy instead of a generic title.
///
/// The registered identifier must match an entry in the app's Info.plist under
/// `BGTaskSchedulerPermittedIdentifiers`.
enum CheckInScheduler {
    static let taskIdentifier = "com.brent.race1.morningCheckIn"

    /// Register the handler exactly once at app launch (before `application(_:didFinishLaunching…)` returns).
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: refreshTask)
        }
    }

    /// Schedules the next check-in refresh. Target time is ~30 minutes before
    /// the user's configured reminder time. Safe to call repeatedly — the
    /// system replaces any pending request with the new one.
    static func scheduleNext(reminderTime: Date = NotificationManager.shared.reminderTime,
                             reference: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = nextRefreshDate(reminderTime: reminderTime, reference: reference)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[CheckInScheduler] Scheduled refresh at \(request.earliestBeginDate?.description ?? "nil")")
        } catch {
            print("[CheckInScheduler] Failed to schedule: \(error)")
        }
    }

    /// Returns the next Date at which iOS should try to wake the app.
    /// Always in the future, and ~30m before today/tomorrow's reminder time.
    static func nextRefreshDate(reminderTime: Date, reference: Date) -> Date {
        let cal = Calendar.current
        let reminderComps = cal.dateComponents([.hour, .minute], from: reminderTime)
        guard let hour = reminderComps.hour, let minute = reminderComps.minute else {
            return reference.addingTimeInterval(60 * 60 * 4)
        }

        var candidateComps = cal.dateComponents([.year, .month, .day], from: reference)
        candidateComps.hour = hour
        candidateComps.minute = minute
        guard var reminder = cal.date(from: candidateComps) else {
            return reference.addingTimeInterval(60 * 60 * 4)
        }

        // Target = 30 minutes before the reminder
        var candidate = reminder.addingTimeInterval(-30 * 60)
        if candidate <= reference {
            // Already past — schedule for tomorrow.
            reminder = cal.date(byAdding: .day, value: 1, to: reminder) ?? reminder
            candidate = reminder.addingTimeInterval(-30 * 60)
        }
        return candidate
    }

    /// Main background-refresh handler. Must complete quickly (iOS allows ~30s).
    private static func handle(task: BGAppRefreshTask) {
        // Always schedule the next refresh before doing work — iOS won't
        // re-queue automatically, and losing the chain leaves the user without
        // morning check-ins.
        scheduleNext()

        let work = Task { @MainActor in
            let healthKit = HealthKitManager.shared
            guard let plan = await findTrainingPlanForBackgroundWork() else {
                task.setTaskCompleted(success: false)
                return
            }

            let checkIn = await CheckInManager.shared.generateCheckIn(
                healthKit: healthKit,
                trainingPlan: plan,
                forceRegenerate: true,
                generateCoachMessage: true
            )

            // Update the morning notification with contextual copy.
            NotificationManager.shared.updateMorningNotification(with: checkIn)

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// We don't have a shared TrainingPlanManager singleton; the background
    /// handler builds one from AuthService's saved plan (same source as
    /// `ContentView.init`).
    @MainActor
    private static func findTrainingPlanForBackgroundWork() async -> TrainingPlanManager? {
        let weeks = AuthService.shared.savedPlan
        guard let weeks = weeks, !weeks.isEmpty else { return nil }
        return TrainingPlanManager(weeks: weeks)
    }
}
