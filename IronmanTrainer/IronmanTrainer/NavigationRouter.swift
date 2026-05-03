import SwiftUI

/// Central navigation state for sheet presentation across the app.
/// Views call router methods instead of posting NotificationCenter events,
/// making navigation explicit and cross-platform portable.
@MainActor
final class NavigationRouter: ObservableObject {
    static let shared = NavigationRouter()

    @Published var showCheckIn = false
    @Published var showChat = false
    @Published var showSettings = false
    @Published var showCalendar = false
    @Published var showLogWorkout = false

    /// Seed text pre-filled into the chat input when opening via a nudge or insight.
    @Published var chatSeed: String = ""

    func openCheckIn() { showCheckIn = true }
    func openChat(seed: String = "") { chatSeed = seed; showChat = true }
    func openSettings() { showSettings = true }
    func openCalendar() { showCalendar = true }
    func openLogWorkout() { showLogWorkout = true }
}
