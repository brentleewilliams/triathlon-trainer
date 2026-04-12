import SwiftUI

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Step Background Colors & Illustration Data

extension OnboardingStep {
    var gradientColors: [Color] {
        switch self {
        case .healthKit: return [Color(hex: "8DC4E8"), Color(hex: "B8D9F0")]
        case .profile: return [Color(hex: "F2A99A"), Color(hex: "F9C5B5")]
        case .raceSearch: return [Color(hex: "3A3D8A"), Color(hex: "4A4DA0")]
        case .goalSetting: return [Color(hex: "6DBF5E"), Color(hex: "8FD17A")]
        case .tutorial: return [Color(hex: "3DBFB4"), Color(hex: "5ECFC4")]
        case .planReview: return [Color(hex: "EDB870"), Color(hex: "F5CC8A")]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
    }

    // Saturated version of the step color for use as text/icon accent on white backgrounds
    var accentColor: Color {
        switch self {
        case .healthKit: return Color(hex: "4A90D9")
        case .profile: return Color(hex: "D9706A")
        case .raceSearch: return Color(hex: "3A3D8A")
        case .goalSetting: return Color(hex: "3DA832")
        case .tutorial: return Color(hex: "00A89E")
        case .planReview: return Color(hex: "C88A30")
        }
    }

    var illustrationName: String {
        switch self {
        case .healthKit: return "onboarding-profile"
        case .profile: return "onboarding-health"
        case .raceSearch: return "onboarding-race"
        case .goalSetting: return "onboarding-goals"
        case .tutorial: return "onboarding-chat"
        case .planReview: return "onboarding-plan"
        }
    }

    var illustrationTitle: String {
        switch self {
        case .healthKit: return "Let's see where you are"
        case .profile: return "A little about you"
        case .raceSearch: return "Pick your race"
        case .goalSetting: return "What does success look like?"
        case .tutorial: return "Meet your AI coach"
        case .planReview: return "Your plan is ready"
        }
    }

    var illustrationSubtitle: String {
        switch self {
        case .healthKit: return "We'll pull your workouts and heart rate history to build your starting point"
        case .profile: return "Height, weight, and location help us dial in your zones and plan for your climate"
        case .raceSearch: return "We'll pull the course, elevation, weather, and build your plan around it"
        case .goalSetting: return "Finish strong, hit a time goal, or tell us in your own words"
        case .tutorial: return "Powered by Claude AI — your coach learns your schedule, injuries, and gear to build the perfect plan"
        case .planReview: return ""
        }
    }
}

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    var onComplete: ([TrainingWeek]) -> Void

    // Sub-screen state for steps that split into intro → form
    @State private var profileShowingForm = false
    @State private var goalsShowingForm = false

    /// Whether the current view is showing its gradient background (vs white form)
    private var isOnGradient: Bool {
        switch viewModel.currentStep {
        case .profile: return !profileShowingForm
        case .goalSetting: return !goalsShowingForm
        default: return true
        }
    }

    var body: some View {
        ZStack {
            // Dynamic background
            if isOnGradient {
                viewModel.currentStep.gradient
                    .ignoresSafeArea()
            } else {
                Color(.systemBackground)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Progress bar
                OnboardingProgressBar(
                    progress: viewModel.progressPercent,
                    currentStep: viewModel.currentStep,
                    isOnGradient: isOnGradient
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Content area
                Group {
                    switch viewModel.currentStep {
                    case .healthKit:
                        HealthKitPermissionStep(viewModel: viewModel)
                    case .profile:
                        ProfileStep(viewModel: viewModel, showingForm: $profileShowingForm)
                    case .raceSearch:
                        RaceSearchStep(viewModel: viewModel)
                    case .goalSetting:
                        GoalSettingStep(viewModel: viewModel, showingForm: $goalsShowingForm)
                    case .tutorial:
                        TutorialStep(viewModel: viewModel)
                    case .planReview:
                        PlanReviewStep(viewModel: viewModel, onComplete: onComplete)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

                // Navigation buttons
                OnboardingNavBar(
                    viewModel: viewModel,
                    isOnGradient: isOnGradient,
                    onAdvance: handleAdvance,
                    onBack: handleBack
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.3), value: isOnGradient)
        .onChange(of: viewModel.currentStep) { _, _ in
            profileShowingForm = false
            goalsShowingForm = false
        }
    }

    private func handleAdvance() {
        switch viewModel.currentStep {
        case .profile:
            if !profileShowingForm {
                withAnimation { profileShowingForm = true }
                return
            }
        case .goalSetting:
            if !goalsShowingForm {
                withAnimation { goalsShowingForm = true }
                return
            }
        default: break
        }
        viewModel.advance()
    }

    private func handleBack() {
        switch viewModel.currentStep {
        case .profile:
            if profileShowingForm {
                withAnimation { profileShowingForm = false }
                return
            }
        case .goalSetting:
            if goalsShowingForm {
                withAnimation { goalsShowingForm = false }
                return
            }
        default: break
        }
        viewModel.goBack()
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let progress: Double
    let currentStep: OnboardingStep
    var isOnGradient: Bool = false

    private var stepLabel: String {
        switch currentStep {
        case .healthKit: return "Health Data"
        case .profile: return "Profile"
        case .raceSearch: return "Your Race"
        case .goalSetting: return "Goals"
        case .tutorial: return "Getting Started"
        case .planReview: return "Your Plan"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOnGradient ? Color.white.opacity(0.3) : Color(.systemGray5))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOnGradient ? Color.white : Color.blue)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)

            Text("Step \(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count): \(stepLabel)")
                .font(.caption)
                .foregroundStyle(isOnGradient ? .white.opacity(0.7) : .secondary)
        }
    }
}

// MARK: - Navigation Bar

struct OnboardingNavBar: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var isOnGradient: Bool = false
    var onAdvance: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil

    private var canAdvance: Bool {
        switch viewModel.currentStep {
        case .healthKit:
            return viewModel.hkDataLoaded
        case .profile:
            return true
        case .raceSearch:
            return viewModel.raceSearchResult != nil
        case .goalSetting:
            // On the intro screen (gradient) the user can always advance to the form;
            // on the form screen they need all skill levels selected.
            return isOnGradient ? true : viewModel.allSkillsSelected
        case .tutorial:
            return viewModel.minimumWeeksLoaded
        case .planReview:
            return false
        }
    }

    var body: some View {
        HStack {
            if viewModel.currentStep != .healthKit {
                Button {
                    (onBack ?? viewModel.goBack)()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(isOnGradient ? .white : viewModel.currentStep.accentColor)
                }
                .disabled(viewModel.isProcessing)
            }

            Spacer()

            // Step dots
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == viewModel.currentStep
                              ? (isOnGradient ? Color.white : viewModel.currentStep.accentColor)
                              : (isOnGradient ? Color.white.opacity(0.4) : Color(.systemGray4)))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            if viewModel.currentStep != .planReview && viewModel.currentStep != .tutorial {
                Button {
                    (onAdvance ?? viewModel.advance)()
                } label: {
                    HStack(spacing: 4) {
                        Text("Continue")
                        Image(systemName: "chevron.right")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isOnGradient ? (canAdvance ? viewModel.currentStep.accentColor : .gray) : .white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(isOnGradient
                                ? (canAdvance ? Color.white : Color.white.opacity(0.3))
                                : (canAdvance ? viewModel.currentStep.accentColor : Color(.systemGray4)))
                    .clipShape(Capsule())
                }
                .disabled(!canAdvance || viewModel.isProcessing)
            }
        }
    }
}
