import SwiftUI
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @StateObject private var authService = AuthService.shared
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var currentNonce: String?

    // Email OTP state
    @State private var showEmailFlow = false
    @State private var email = ""
    @State private var otpCode = ""
    @State private var otpSent = false
    @State private var isLoadingOTP = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("Ironman Trainer")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your AI-powered triathlon coach")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    let nonce = randomNonceString()
                    currentNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = sha256(nonce)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                            errorMessage = "Unexpected credential type."
                            showError = true
                            return
                        }
                        guard let nonce = currentNonce else {
                            errorMessage = "Missing nonce. Please try again."
                            showError = true
                            return
                        }
                        Task {
                            do {
                                try await authService.signInWithApple(credential: appleIDCredential, nonce: nonce)
                            } catch {
                                print("[AUTH] Apple Sign In failed: \(error)")
                                errorMessage = "\(error)"
                                showError = true
                            }
                        }
                    case .failure(let error):
                        print("[AUTH] Apple authorization failed: \(error)")
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            errorMessage = "\(error)"
                            showError = true
                        }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)

                // Divider
                HStack {
                    Rectangle().fill(Color(.separator)).frame(height: 1)
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color(.separator)).frame(height: 1)
                }

                // Email OTP button
                Button {
                    withAnimation { showEmailFlow = true }
                } label: {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("Sign in with Email")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 60)
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showEmailFlow) {
            EmailOTPSheet(
                email: $email,
                otpCode: $otpCode,
                otpSent: $otpSent,
                isLoading: $isLoadingOTP,
                onRequestOTP: { requestOTP() },
                onVerifyOTP: { verifyOTP() },
                onDismiss: {
                    showEmailFlow = false
                    resetEmailFlow()
                }
            )
        }
    }

    // MARK: - Email OTP

    private func requestOTP() {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoadingOTP = true
        Task {
            do {
                try await authService.requestOTP(email: email.trimmingCharacters(in: .whitespaces).lowercased())
                await MainActor.run {
                    otpSent = true
                    isLoadingOTP = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    showEmailFlow = false
                    isLoadingOTP = false
                }
            }
        }
    }

    private func verifyOTP() {
        guard !otpCode.isEmpty, !isLoadingOTP else { return }
        isLoadingOTP = true
        Task {
            do {
                try await authService.verifyOTP(
                    email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                    code: otpCode
                )
                await MainActor.run {
                    showEmailFlow = false
                    resetEmailFlow()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoadingOTP = false
                }
            }
        }
    }

    private func resetEmailFlow() {
        email = ""
        otpCode = ""
        otpSent = false
        isLoadingOTP = false
    }

    // MARK: - Nonce Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Email OTP Sheet

struct EmailOTPSheet: View {
    @Binding var email: String
    @Binding var otpCode: String
    @Binding var otpSent: Bool
    @Binding var isLoading: Bool
    var onRequestOTP: () -> Void
    var onVerifyOTP: () -> Void
    var onDismiss: () -> Void

    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if !otpSent {
                    // Step 1: Enter email
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)

                        Text("Enter your email")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("We'll send you a 6-digit verification code")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        TextField("email@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                            .focused($emailFocused)
                            .padding(.horizontal)
                            .onSubmit { onRequestOTP() }

                        Button {
                            onRequestOTP()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            } else {
                                Text("Send Code")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                        .padding(.horizontal)
                    }
                    .onAppear { emailFocused = true }
                } else {
                    // Step 2: Enter OTP code
                    VStack(spacing: 16) {
                        Image(systemName: "lock.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        Text("Check your email")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Enter the 6-digit code sent to\n\(email)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        TextField("000000", text: $otpCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .tracking(8)
                            .textFieldStyle(.roundedBorder)
                            .focused($codeFocused)
                            .padding(.horizontal, 60)
                            .onChange(of: otpCode) {
                                // Auto-verify when 6 digits entered
                                if otpCode.count == 6 {
                                    onVerifyOTP()
                                }
                            }

                        Button {
                            onVerifyOTP()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            } else {
                                Text("Verify")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(otpCode.count != 6 || isLoading)
                        .padding(.horizontal)

                        Button("Resend Code") {
                            otpCode = ""
                            onRequestOTP()
                        }
                        .font(.subheadline)
                        .disabled(isLoading)
                    }
                    .onAppear { codeFocused = true }
                }

                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }
}

#Preview {
    SignInView()
}
