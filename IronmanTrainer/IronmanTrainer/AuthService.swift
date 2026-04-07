import Foundation
import FirebaseAuth
import AuthenticationServices

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
        if UserDefaults.standard.bool(forKey: "onboarding_complete_\(uid)") {
            if let data = UserDefaults.standard.data(forKey: "saved_plan_\(uid)"),
               let plan = try? JSONDecoder().decode([TrainingWeek].self, from: data) {
                print("[AuthService] Local plan cache hit — loading plan instantly")
                savedPlan = plan
                onboardingComplete = true
                return
            }
            // Cache flag set but no plan data — fall through to Firestore
            print("[AuthService] Onboarding complete flag set but no local plan, checking Firestore...")
        } else {
            print("[AuthService] No local cache, checking Firestore...")
        }

        // Fetch from Firestore (with timeout to avoid blocking on slow networks)
        do {
            let found = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask { [weak self] in
                    if let result = try await FirestoreService.shared.getTrainingPlan(for: uid) {
                        let plan = result.weeks
                        await MainActor.run {
                            self?.savedPlan = plan
                            // Cache plan locally for fast future startups
                            if let data = try? JSONEncoder().encode(plan) {
                                UserDefaults.standard.set(data, forKey: "saved_plan_\(uid)")
                            }
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
                UserDefaults.standard.set(true, forKey: "onboarding_complete_\(uid)")
            }
        } catch {
            // Network error — fall back to local cache flag if present
            print("[AuthService] Firestore check failed: \(error)")
            if UserDefaults.standard.bool(forKey: "onboarding_complete_\(uid)") {
                print("[AuthService] Network error, using local onboarding flag (no plan)")
                onboardingComplete = true
            }
        }
    }

    func markOnboardingComplete(plan: [TrainingWeek]? = nil) {
        guard let uid = currentUserID else { return }
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboarding_complete_\(uid)")

        if let plan {
            savedPlan = plan
            // Cache locally for instant future startups
            if let data = try? JSONEncoder().encode(plan) {
                UserDefaults.standard.set(data, forKey: "saved_plan_\(uid)")
            }
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
    }

    deinit {
        if let handle = stateListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, nonce: String) async throws {
        guard let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.missingToken
        }

        let oauthCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        let result = try await Auth.auth().signIn(with: oauthCredential)
        self.currentUserID = result.user.uid
        self.isAuthenticated = true
    }

    func signOut() throws {
        try Auth.auth().signOut()
        self.isAuthenticated = false
        self.currentUserID = nil
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
        case missingToken
        case otpSendFailed(_ message: String?)
        case otpVerifyFailed(_ message: String?)

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "Unable to retrieve Apple ID token."
            case .otpSendFailed(let msg):
                return msg ?? "Failed to send verification code."
            case .otpVerifyFailed(let msg):
                return msg ?? "Failed to verify code."
            }
        }
    }
}
