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

    init() {
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

        // First check local cache
        if UserDefaults.standard.bool(forKey: "onboarding_complete_\(uid)") {
            onboardingComplete = true
            return
        }

        // Then check Firestore (with timeout to avoid blocking on slow networks)
        do {
            let result = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    if let _ = try await FirestoreService.shared.getTrainingPlan(for: uid) {
                        return true
                    }
                    return false
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second timeout
                    throw CancellationError()
                }
                let first = try await group.next() ?? false
                group.cancelAll()
                return first
            }
            if result {
                onboardingComplete = true
                UserDefaults.standard.set(true, forKey: "onboarding_complete_\(uid)")
            }
        } catch {
            // Timeout or error — proceed to onboarding
            onboardingComplete = false
        }
    }

    func markOnboardingComplete() {
        guard let uid = currentUserID else { return }
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboarding_complete_\(uid)")
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
