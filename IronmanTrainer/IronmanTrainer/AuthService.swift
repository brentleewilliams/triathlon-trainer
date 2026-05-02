import Foundation
import FirebaseAuth
import UserNotifications

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated: Bool = false
    @Published var currentUserID: String?
    @Published var currentUserEmail: String?
    @Published var isLoading: Bool = true

    private var stateListener: AuthStateDidChangeListenerHandle?

    @Published var onboardingComplete: Bool = false
    @Published var checkingPlan: Bool = false
    @Published var savedPlan: [TrainingWeek]?

    init() {
        // Firebase Auth stores credentials in Keychain, which survives app
        // uninstall/reinstall. Detect fresh install (UserDefaults wiped) and
        // sign out so the user starts clean.
        let hasLaunchedKey = "has_launched_before"
        if !UserDefaults.standard.bool(forKey: hasLaunchedKey) {
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
            clearKeychain()
            try? Auth.auth().signOut()
        }

        stateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isAuthenticated = user != nil
                self?.currentUserID = user?.uid
                self?.currentUserEmail = user?.email

                if let uid = user?.uid {
                    // Check if user already has a plan (returning user)
                    await self?.checkForExistingPlan(uid: uid)
                } else {
                    self?.onboardingComplete = false
                }

                self?.isLoading = false
            }
        }
    }

    /// Check Firestore for an existing plan — if found, skip onboarding
    func checkForExistingPlan(uid: String) async {
        checkingPlan = true
        defer { checkingPlan = false }

        print("[AuthService] checkForExistingPlan called for uid: \(uid)")

        // Try local plan cache first for instant startup
        if let plan = AuthPlanCache.read(uid: uid) {
            print("[AuthService] Local plan cache hit — loading plan instantly")
            savedPlan = plan
            onboardingComplete = true
            return
        }

        // Flag set but no decodable plan data — fall through to Firestore
        if AuthPlanCache.flagExists(uid: uid) {
            print("[AuthService] Onboarding complete flag set but no local plan, checking Firestore...")
        } else {
            print("[AuthService] No local cache, checking Firestore...")
        }

        // Fetch from Firestore (with timeout to avoid blocking on slow networks)
        do {
            let found = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask { [weak self] in
                    guard let self else { return false }
                    if let result = try await FirestoreService.shared.getTrainingPlan(for: uid) {
                        let plan = result.weeks
                        await MainActor.run {
                            self.savedPlan = plan
                            AuthPlanCache.write(uid: uid, plan: plan)
                        }
                        return true
                    }
                    return false
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
                    return false
                }
                if let first = try await group.next() {
                    group.cancelAll()
                    return first
                }
                return false
            }
            print("[AuthService] Firestore result: found=\(found)")
            if found {
                onboardingComplete = true
                AuthPlanCache.setFlag(uid: uid)
            }
        } catch {
            // Network error — fall back to local cache flag if present
            print("[AuthService] Firestore check failed: \(error)")
            if AuthPlanCache.flagExists(uid: uid) {
                print("[AuthService] Network error, using local onboarding flag (no plan)")
                onboardingComplete = true
            }
        }
    }

    func markOnboardingComplete(plan: [TrainingWeek]? = nil) {
        guard let uid = currentUserID else { return }
        // Record onboarding date and plan BEFORE flipping onboardingComplete so
        // the SwiftUI rebuild that instantiates ContentView sees fresh data.
        // Always update onboardingDate so re-onboarding re-anchors Week 1.
        OnboardingStore.onboardingDate = Date()

        if let plan {
            savedPlan = plan
            AuthPlanCache.write(uid: uid, plan: plan)
            Task {
                let metadata = PlanMetadata(
                    generatedAt: Date(),
                    generatedBy: "llm-generated",
                    raceId: nil,
                    approved: true
                )
                do {
                    try await FirestoreService.shared.saveTrainingPlan(plan, metadata: metadata, for: uid)
                } catch {
                    print("[AUTH] Failed to save plan to Firestore: \(error)")
                }
            }
        }

        // Flip last so SwiftUI rebuilds with all persisted state in place.
        AuthPlanCache.setFlag(uid: uid)
        onboardingComplete = true
    }

    deinit {
        if let handle = stateListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signOut() throws {
        // Clear in-memory published state immediately.
        self.isAuthenticated = false
        self.currentUserID = nil
        self.currentUserEmail = nil
        self.onboardingComplete = false
        self.savedPlan = nil

        // Wipe all local persistence. Static so unit tests can call it directly
        // with an isolated UserDefaults suite.
        AuthService.wipeLocalDefaults()

        // Nuke App Group shared data so the widget shows nothing until the
        // next user's data is written.
        AppGroupConstants.wipeAllSharedData()

        // Cancel all pending local notifications (morning check-in + workout reminders).
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        clearKeychain()
        try Auth.auth().signOut()
    }

    /// Wipes all UserDefaults for the given domain (defaults to the app's bundle ID).
    /// Extracted as a static so tests can inject an isolated suite and verify
    /// that no key from one user survives to the next.
    nonisolated static func wipeLocalDefaults(
        defaults: UserDefaults = .standard,
        bundleID: String = Bundle.main.bundleIdentifier ?? ""
    ) {
        defaults.removePersistentDomain(forName: bundleID)
        defaults.set(true, forKey: "has_launched_before")
    }

    private func clearKeychain() {
        for secClass in [kSecClassGenericPassword, kSecClassInternetPassword] {
            SecItemDelete([kSecClass: secClass] as CFDictionary)
        }
    }

    /// Permanently delete the account: Firestore data, local caches, and the
    /// Firebase Auth user. Throws `AuthError.reauthRequired` if Firebase
    /// rejects the delete because the sign-in is stale — caller should prompt
    /// the user to sign out and sign back in before retrying.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notSignedIn
        }
        let uid = user.uid

        // Attempt Auth deletion first — if the session is stale Firebase will
        // reject this with requiresRecentLogin before we touch any user data.
        do {
            try await user.delete()
        } catch let error as NSError {
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                throw AuthError.reauthRequired
            }
            throw error
        }

        // Auth user is gone — now wipe data.
        try await FirestoreService.shared.deleteUserData(uid: uid)

        self.isAuthenticated = false
        self.currentUserID = nil
        self.currentUserEmail = nil
        self.savedPlan = nil
        self.onboardingComplete = false

        AuthService.wipeLocalDefaults()
        AppGroupConstants.wipeAllSharedData()
        clearKeychain()
    }

    // MARK: - Email OTP

    private let functionsBaseURL = "https://us-central1-brents-trainer.cloudfunctions.net"

    func requestOTP(email: String) async throws {
        let url = URL(string: "\(functionsBaseURL)/requestOTP")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true else {
            let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw AuthError.otpSendFailed(errorMsg)
        }
    }

    func verifyOTP(email: String, code: String) async throws {
        let url = URL(string: "\(functionsBaseURL)/verifyOTP")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "code": code])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw AuthError.otpVerifyFailed(errorMsg)
        }
        try await Auth.auth().signIn(withCustomToken: token)
    }

    enum AuthError: LocalizedError {
        case otpSendFailed(_ message: String?)
        case otpVerifyFailed(_ message: String?)
        case notSignedIn
        case reauthRequired

        var errorDescription: String? {
            switch self {
            case .otpSendFailed(let msg):
                return msg ?? "Failed to send verification code."
            case .otpVerifyFailed(let msg):
                return msg ?? "Failed to verify code."
            case .notSignedIn:
                return "No signed-in user."
            case .reauthRequired:
                return "For security, please sign out and sign back in before deleting your account."
            }
        }
    }
}

// MARK: - Plan Cache

/// Pure UserDefaults helpers for the per-UID plan cache. Extracted so tests
/// can exercise cache logic without a live Firebase instance.
enum AuthPlanCache {
    static func read(uid: String, defaults: UserDefaults = .standard) -> [TrainingWeek]? {
        guard defaults.bool(forKey: flagKey(uid)),
              let data = defaults.data(forKey: planKey(uid)),
              let plan = try? JSONDecoder().decode([TrainingWeek].self, from: data)
        else { return nil }
        return plan
    }

    static func write(uid: String, plan: [TrainingWeek], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: planKey(uid))
        }
    }

    static func setFlag(uid: String, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: flagKey(uid))
    }

    static func flagExists(uid: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: flagKey(uid))
    }

    static func clear(uid: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: flagKey(uid))
        defaults.removeObject(forKey: planKey(uid))
    }

    static func flagKey(_ uid: String) -> String { "onboarding_complete_\(uid)" }
    static func planKey(_ uid: String) -> String { "saved_plan_\(uid)" }
}
