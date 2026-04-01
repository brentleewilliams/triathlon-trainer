import SwiftUI

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var chatViewModel = ChatViewModel(skipHistory: true)
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            OnboardingProgressBar(progress: viewModel.progressPercent, currentStep: viewModel.currentStep)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            // Content area
            TabView(selection: $viewModel.currentStep) {
                HealthKitPermissionStep(viewModel: viewModel)
                    .tag(OnboardingStep.healthKit)

                ProfileStep(viewModel: viewModel)
                    .tag(OnboardingStep.profile)

                RaceSearchStep(viewModel: viewModel)
                    .tag(OnboardingStep.raceSearch)

                GoalSettingStep(viewModel: viewModel)
                    .tag(OnboardingStep.goalSetting)

                FitnessChatStep(viewModel: viewModel, chatViewModel: chatViewModel)
                    .tag(OnboardingStep.fitnessChat)

                PlanReviewStep(viewModel: viewModel, onComplete: onComplete)
                    .tag(OnboardingStep.planReview)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: viewModel.currentStep)

            // Navigation buttons
            if viewModel.currentStep != .fitnessChat {
                OnboardingNavBar(viewModel: viewModel)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let progress: Double
    let currentStep: OnboardingStep

    private var stepLabel: String {
        switch currentStep {
        case .healthKit: return "Health Data"
        case .profile: return "Profile"
        case .raceSearch: return "Your Race"
        case .goalSetting: return "Goals"
        case .fitnessChat: return "Fitness Assessment"
        case .planReview: return "Your Plan"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)

            Text("Step \(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count): \(stepLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Navigation Bar

struct OnboardingNavBar: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private var canAdvance: Bool {
        switch viewModel.currentStep {
        case .healthKit:
            return viewModel.hkDataLoaded
        case .profile:
            return !viewModel.userName.trimmingCharacters(in: .whitespaces).isEmpty
        case .raceSearch:
            return viewModel.raceSearchResult != nil
        case .goalSetting:
            return true
        case .fitnessChat:
            return true
        case .planReview:
            return false // Plan review has its own buttons
        }
    }

    var body: some View {
        HStack {
            if viewModel.currentStep != .healthKit {
                Button {
                    viewModel.goBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.body.weight(.medium))
                }
                .disabled(viewModel.isProcessing)
            }

            Spacer()

            if viewModel.currentStep != .planReview {
                Button {
                    viewModel.advance()
                } label: {
                    HStack(spacing: 4) {
                        Text("Continue")
                        Image(systemName: "chevron.right")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(canAdvance ? Color.blue : Color(.systemGray4))
                    .clipShape(Capsule())
                }
                .disabled(!canAdvance || viewModel.isProcessing)
            }
        }
    }
}

// MARK: - Step 1: HealthKit Permission

struct HealthKitPermissionStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                Text("Let's analyze your training history")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("We'll pull your workout data from Apple Health to understand your current fitness level and training patterns.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 12) {
                    HKDataRow(icon: "figure.run", text: "Running, cycling, and swimming workouts")
                    HKDataRow(icon: "heart.fill", text: "Heart rate zones and resting HR")
                    HKDataRow(icon: "scalemass.fill", text: "Weight and body measurements")
                    HKDataRow(icon: "lungs.fill", text: "VO2 Max estimates")
                }
                .padding(.horizontal, 20)

                if viewModel.isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Analyzing your fitness data...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } else if viewModel.hkDataLoaded {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)

                        if let profile = viewModel.hkProfile {
                            let totalWorkouts = profile.recentWorkoutDetails.count + profile.monthlyTrends.reduce(0) { $0 + $1.swimSessions + $1.bikeSessions + $1.runSessions }
                            Text("Found \(totalWorkouts) workouts")
                                .font(.headline)

                            if !profile.monthlyTrends.isEmpty {
                                Text("\(profile.monthlyTrends.count) months of training data")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Health data connected")
                                .font(.headline)
                        }
                    }
                    .padding(.top, 8)
                } else {
                    Button {
                        Task {
                            await viewModel.loadHealthKitData()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "heart.fill")
                            Text("Connect HealthKit")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                }

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
}

struct HKDataRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Step 2: Profile

struct ProfileStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private let sexOptions = ["Male", "Female", "Other"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text("Complete Your Profile")
                    .font(.title2.weight(.bold))

                VStack(spacing: 16) {
                    OnboardingTextField(label: "Name", text: $viewModel.userName, placeholder: "Your name")

                    OnboardingTextField(label: "Home City", text: $viewModel.homeCity, placeholder: "e.g. Denver, CO")

                    if viewModel.hkHasDOB {
                        HKProvidedRow(label: "Date of Birth", value: Formatters.fullDate.string(from: viewModel.userDOB))
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Date of Birth")
                                .font(.subheadline.weight(.medium))
                            DatePicker("", selection: $viewModel.userDOB, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }

                    if viewModel.hkHasSex {
                        HKProvidedRow(label: "Biological Sex", value: viewModel.userSex)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Biological Sex")
                                .font(.subheadline.weight(.medium))
                            Picker("", selection: $viewModel.userSex) {
                                Text("Select...").tag("")
                                ForEach(sexOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    if viewModel.hkHasHeight {
                        HKProvidedRow(label: "Height", value: String(format: "%.0f cm", viewModel.userHeightCm ?? 0))
                    } else {
                        OnboardingNumberField(label: "Height (cm)", value: $viewModel.userHeightCm, placeholder: "175")
                    }

                    if viewModel.hkHasWeight {
                        HKProvidedRow(label: "Weight", value: String(format: "%.1f kg", viewModel.userWeightKg ?? 0))
                    } else {
                        OnboardingNumberField(label: "Weight (kg)", value: $viewModel.userWeightKg, placeholder: "75")
                    }

                    if viewModel.hkHasRestingHR {
                        HKProvidedRow(label: "Resting HR", value: "\(viewModel.userRestingHR ?? 0) bpm")
                    } else {
                        OnboardingIntField(label: "Resting Heart Rate (bpm)", value: $viewModel.userRestingHR, placeholder: "60")
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

struct HKProvidedRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
            Text("from Health")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct OnboardingTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.medium))
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct OnboardingNumberField: View {
    let label: String
    @Binding var value: Double?
    let placeholder: String

    @State private var textValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.medium))
            TextField(placeholder, text: $textValue)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .onChange(of: textValue) { _, newVal in
                    value = Double(newVal)
                }
                .onAppear {
                    if let v = value { textValue = String(format: "%.0f", v) }
                }
        }
    }
}

struct OnboardingIntField: View {
    let label: String
    @Binding var value: Int?
    let placeholder: String

    @State private var textValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.medium))
            TextField(placeholder, text: $textValue)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .onChange(of: textValue) { _, newVal in
                    value = Int(newVal)
                }
                .onAppear {
                    if let v = value { textValue = "\(v)" }
                }
        }
    }
}

// MARK: - Step 3: Race Search

struct RaceSearchStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: "flag.checkered")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("What race are you training for?")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Search for your race and we'll pull in all the details automatically.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                // Search field
                HStack {
                    TextField("e.g. Ironman 70.3 Oregon 2026", text: $viewModel.raceSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isSearchingRace)

                    Button {
                        Task { await viewModel.searchRace() }
                    } label: {
                        if viewModel.isSearchingRace {
                            ProgressView()
                                .frame(width: 44, height: 36)
                        } else {
                            Text("Search")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(viewModel.raceSearchQuery.isEmpty ? Color(.systemGray4) : Color.blue)
                                .clipShape(Capsule())
                        }
                    }
                    .disabled(viewModel.raceSearchQuery.isEmpty || viewModel.isSearchingRace)
                }
                .padding(.horizontal, 16)

                // Results
                if let result = viewModel.raceSearchResult {
                    RaceResultCard(result: result)
                        .padding(.horizontal, 16)

                    Button {
                        viewModel.raceSearchResult = nil
                        viewModel.raceSearchQuery = ""
                    } label: {
                        Text("Search again")
                            .font(.subheadline)
                    }
                }

                if let error = viewModel.error {
                    VStack(spacing: 8) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)

                        Text("You can try a different search or enter details manually later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

struct RaceResultCard: View {
    let result: RaceSearchResult

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: result.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.orange)
                Text(result.name)
                    .font(.headline)
            }

            Divider()

            RaceDetailRow(icon: "calendar", label: "Date", value: dateString)
            RaceDetailRow(icon: "mappin.and.ellipse", label: "Location", value: result.location)
            RaceDetailRow(icon: "figure.mixed.cardio", label: "Type", value: result.type.capitalized)
            RaceDetailRow(icon: "road.lanes", label: "Course", value: result.courseType.capitalized)

            // Distances
            if !result.distances.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Distances")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(result.distances.keys.sorted()), id: \.self) { key in
                        if let dist = result.distances[key] {
                            Text("\(key.capitalized): \(String(format: "%.1f", dist)) mi")
                                .font(.subheadline)
                        }
                    }
                }
            }

            if let elevation = result.elevationGainM {
                RaceDetailRow(icon: "mountain.2.fill", label: "Elevation Gain", value: "\(Int(elevation))m")
            }

            if let weather = result.historicalWeather {
                RaceDetailRow(icon: "cloud.sun.fill", label: "Typical Weather", value: weather)
            }

            // Confirmation
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Race details confirmed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RaceDetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Step 4: Goal Setting

struct GoalSettingStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: "target")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("What's your goal?")
                    .font(.title2.weight(.bold))

                Text("This helps us tailor your training plan intensity and pacing strategy.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                VStack(spacing: 16) {
                    // Time Target card
                    GoalCard(
                        icon: "stopwatch.fill",
                        title: "Finish Time Goal",
                        subtitle: "I have a specific time I want to hit",
                        isSelected: viewModel.goalType == .timeTarget
                    ) {
                        viewModel.goalType = .timeTarget
                    }

                    // Just Complete card
                    GoalCard(
                        icon: "flag.fill",
                        title: "Just Complete It",
                        subtitle: "I want to finish strong and have fun",
                        isSelected: viewModel.goalType == .justComplete
                    ) {
                        viewModel.goalType = .justComplete
                    }
                }
                .padding(.horizontal, 16)

                // Time picker (only if time target selected)
                if viewModel.goalType == .timeTarget {
                    VStack(spacing: 8) {
                        Text("Target Finish Time")
                            .font(.subheadline.weight(.medium))

                        HStack(spacing: 4) {
                            Picker("Hours", selection: $viewModel.targetHours) {
                                ForEach(3...12, id: \.self) { h in
                                    Text("\(h)h").tag(h)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 80, height: 120)
                            .clipped()

                            Text(":")
                                .font(.title2.weight(.bold))

                            Picker("Minutes", selection: $viewModel.targetMinutes) {
                                ForEach(0..<60, id: \.self) { m in
                                    Text(String(format: "%02dm", m)).tag(m)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 80, height: 120)
                            .clipped()
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
}

struct GoalCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .blue)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.blue : Color(.systemGray5))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .padding(16)
            .background(isSelected ? Color.blue.opacity(0.08) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 5: Fitness Chat

// Quick reply option for fitness chat
struct QuickReply: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct FitnessChatStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @ObservedObject var chatViewModel: ChatViewModel
    @State private var showPlanButton = false
    @State private var quickReplies: [QuickReply] = []

    var body: some View {
        VStack(spacing: 0) {
            // Intro header
            VStack(spacing: 8) {
                Text("Fitness Assessment")
                    .font(.headline)
                Text("Chat with your AI coach to assess your fitness and build your plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chatViewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if chatViewModel.isLoading {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Circle()
                                        .fill(Color.gray.opacity(0.6))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.leading, 16)
                            .padding(.vertical, 8)
                        }

                        if let error = chatViewModel.error {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }

                        // Quick reply buttons
                        if !quickReplies.isEmpty && !chatViewModel.isLoading {
                            QuickReplyButtons(replies: quickReplies) { reply in
                                selectQuickReply(reply)
                            }
                            .id("quickReplies")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: chatViewModel.messages.count) {
                    withAnimation {
                        proxy.scrollTo("quickReplies", anchor: .bottom)
                    }
                    if chatViewModel.messages.count >= 4 {
                        withAnimation { showPlanButton = true }
                    }
                }
            }

            // Input and plan button
            VStack(spacing: 0) {
                if showPlanButton {
                    Button {
                        viewModel.advance()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("I'm ready to see my plan")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ChatInputBar(viewModel: chatViewModel)
            }
        }
        .onAppear {
            if chatViewModel.messages.isEmpty {
                let _ = OnboardingChatHelper.buildOnboardingSystemPrompt(
                    profile: viewModel.hkProfile,
                    userName: viewModel.userName,
                    race: viewModel.buildRace(),
                    goal: goalTypeFromSelection()
                )
                let name = viewModel.userName.isEmpty ? "there" : viewModel.userName
                let greeting = ChatMessage(
                    isUser: false,
                    text: "Hi \(name)! I'm your AI coach. Let's assess your current fitness so I can build the perfect training plan.\n\nBased on your Health data, I can see your recent training. Let me ask a few questions to fine-tune your plan.\n\nHow many hours per week can you dedicate to training?",
                    timestamp: Date()
                )
                chatViewModel.messages.append(greeting)
                quickReplies = Self.hoursReplies
            }
        }
    }

    private func selectQuickReply(_ reply: QuickReply) {
        // Clear buttons immediately
        withAnimation { quickReplies = [] }

        // Add user message
        let userMsg = ChatMessage(isUser: true, text: reply.value, timestamp: Date())
        chatViewModel.messages.append(userMsg)

        // Store answer on view model for plan review
        let userMsgCount = chatViewModel.messages.filter { $0.isUser }.count
        switch userMsgCount {
        case 1: viewModel.fitnessHours = reply.value
        case 2: viewModel.fitnessExperience = reply.value
        case 3: viewModel.fitnessInjuries = reply.value
        case 4: viewModel.fitnessEquipment = reply.value
        default: break
        }

        // Determine next question based on conversation state
        let messageCount = chatViewModel.messages.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if messageCount <= 3 {
                // After hours answer → ask experience level
                let msg = ChatMessage(
                    isUser: false,
                    text: "Got it — \(reply.value). That's a great foundation.\n\nHow would you describe your current endurance experience?",
                    timestamp: Date()
                )
                chatViewModel.messages.append(msg)
                withAnimation { quickReplies = Self.experienceReplies }
            } else if messageCount <= 5 {
                // After experience → ask injury history
                let msg = ChatMessage(
                    isUser: false,
                    text: "Thanks! That helps me calibrate your plan.\n\nAny current injuries or limitations I should know about?",
                    timestamp: Date()
                )
                chatViewModel.messages.append(msg)
                withAnimation { quickReplies = Self.injuryReplies }
            } else if messageCount <= 7 {
                // After injury → ask equipment
                let msg = ChatMessage(
                    isUser: false,
                    text: "Noted.\n\nWhat equipment do you have access to?",
                    timestamp: Date()
                )
                chatViewModel.messages.append(msg)
                withAnimation { quickReplies = Self.equipmentReplies }
            } else {
                // Done with quick questions → open it up
                let msg = ChatMessage(
                    isUser: false,
                    text: "I've got a great picture of where you are. Anything else you'd like me to factor into your plan? If not, tap \"I'm ready to see my plan\" below!",
                    timestamp: Date()
                )
                chatViewModel.messages.append(msg)
                withAnimation { showPlanButton = true }
            }
        }
    }

    private func goalTypeFromSelection() -> GoalType? {
        switch viewModel.goalType {
        case .timeTarget:
            return .timeTarget(TimeInterval(viewModel.targetHours * 3600 + viewModel.targetMinutes * 60))
        case .justComplete:
            return .justComplete
        }
    }

    // MARK: - Quick Reply Options

    static let hoursReplies = [
        QuickReply(label: "5–7 hrs/wk", value: "5–7 hours per week (light)"),
        QuickReply(label: "8–10 hrs/wk", value: "8–10 hours per week (moderate)"),
        QuickReply(label: "10–14 hrs/wk", value: "10–14 hours per week (solid)"),
        QuickReply(label: "15–20 hrs/wk", value: "15–20 hours per week (high volume)"),
        QuickReply(label: "20+ hrs/wk", value: "20+ hours per week (elite)"),
    ]

    static let experienceReplies = [
        QuickReply(label: "Beginner", value: "Beginner — new to endurance sports"),
        QuickReply(label: "Some experience", value: "Some experience — done a few races"),
        QuickReply(label: "Intermediate", value: "Intermediate — race regularly"),
        QuickReply(label: "Advanced", value: "Advanced — multiple years of structured training"),
        QuickReply(label: "Elite", value: "Elite / competitive — podium finisher"),
    ]

    static let injuryReplies = [
        QuickReply(label: "No injuries", value: "No current injuries or limitations"),
        QuickReply(label: "Minor niggles", value: "Minor niggles but can train through them"),
        QuickReply(label: "Recovering", value: "Recovering from an injury — need modifications"),
        QuickReply(label: "Chronic issue", value: "Chronic issue that limits some activities"),
    ]

    static let equipmentReplies = [
        QuickReply(label: "Full setup", value: "Full setup — bike trainer, pool access, gym, outdoor routes"),
        QuickReply(label: "Basics", value: "Basics — bike, running shoes, pool access"),
        QuickReply(label: "Minimal", value: "Minimal — running shoes and a gym membership"),
        QuickReply(label: "Home only", value: "Home only — treadmill/trainer, no pool"),
    ]
}

struct QuickReplyButtons: View {
    let replies: [QuickReply]
    let onSelect: (QuickReply) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(replies) { reply in
                Button {
                    onSelect(reply)
                } label: {
                    Text(reply.label)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 16)
    }
}

// MARK: - Step 6: Plan Review

struct PlanReviewStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var onComplete: () -> Void

    private var weeksUntilRace: Int {
        guard let race = viewModel.raceSearchResult else { return 0 }
        return max(0, Calendar.current.dateComponents([.weekOfYear], from: Date(), to: race.date).weekOfYear ?? 0)
    }

    private var chatAnswers: [String: String] {
        var answers: [String: String] = [:]
        if !viewModel.fitnessHours.isEmpty { answers["hours"] = viewModel.fitnessHours }
        if !viewModel.fitnessExperience.isEmpty { answers["experience"] = viewModel.fitnessExperience }
        if !viewModel.fitnessInjuries.isEmpty { answers["injuries"] = viewModel.fitnessInjuries }
        if !viewModel.fitnessEquipment.isEmpty { answers["equipment"] = viewModel.fitnessEquipment }
        return answers
    }

    private var planPhases: [(name: String, weeks: String, description: String, color: Color)] {
        let total = weeksUntilRace
        guard total > 0 else { return [] }
        let taper = min(2, max(1, total / 8))
        let peak = min(3, max(1, total / 6))
        let build = min(total / 3, max(2, (total - taper - peak) / 2))
        let base = total - build - peak - taper
        var phases: [(String, String, String, Color)] = []
        if base > 0 { phases.append(("Base Building", "Weeks 1–\(base)", "Aerobic foundation, technique, and consistency", .blue)) }
        if build > 0 { phases.append(("Build", "Weeks \(base+1)–\(base+build)", "Progressive volume and intensity", .orange)) }
        if peak > 0 { phases.append(("Peak", "Weeks \(base+build+1)–\(base+build+peak)", "Race-specific workouts at target effort", .red)) }
        if taper > 0 { phases.append(("Taper", "Weeks \(total-taper+1)–\(total)", "Volume reduction, sharpening for race day", .green)) }
        return phases
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 12)

                // Race header
                if let race = viewModel.raceSearchResult {
                    VStack(spacing: 6) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)

                        Text(race.name)
                            .font(.title3.weight(.bold))

                        HStack(spacing: 16) {
                            Label({
                                let f = DateFormatter()
                                f.dateStyle = .medium
                                return f.string(from: race.date)
                            }(), systemImage: "calendar")

                            Label(race.location, systemImage: "mappin")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if weeksUntilRace > 0 {
                            Text("\(weeksUntilRace) weeks of training")
                                .font(.headline)
                                .foregroundStyle(.blue)
                                .padding(.top, 2)
                        }
                    }
                } else {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    Text("Your Training Plan")
                        .font(.title3.weight(.bold))
                }

                // Goal card
                PlanSummaryCard {
                    HStack {
                        Image(systemName: "target")
                            .foregroundStyle(.green)
                            .font(.title3)
                        switch viewModel.goalType {
                        case .timeTarget:
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Time Target")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(viewModel.targetHours)h \(String(format: "%02d", viewModel.targetMinutes))m")
                                    .font(.title3.weight(.semibold))
                            }
                        case .justComplete:
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Goal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Complete the race")
                                    .font(.title3.weight(.semibold))
                            }
                        }
                        Spacer()
                    }
                }

                // Athlete profile card
                if !chatAnswers.isEmpty {
                    PlanSummaryCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your Profile")
                                .font(.subheadline.weight(.semibold))

                            if let hours = chatAnswers["hours"] {
                                PlanDetailRow(icon: "clock.fill", label: "Weekly volume", value: hours)
                            }
                            if let exp = chatAnswers["experience"] {
                                PlanDetailRow(icon: "chart.bar.fill", label: "Experience", value: exp)
                            }
                            if let injury = chatAnswers["injuries"] {
                                PlanDetailRow(icon: "cross.circle.fill", label: "Injuries", value: injury)
                            }
                            if let equip = chatAnswers["equipment"] {
                                PlanDetailRow(icon: "bicycle", label: "Equipment", value: equip)
                            }
                        }
                    }
                }

                // Plan phases
                PlanSummaryCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Training Phases")
                            .font(.subheadline.weight(.semibold))

                        ForEach(Array(planPhases.enumerated()), id: \.offset) { _, phase in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(phase.color)
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(phase.name)
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Text(phase.weeks)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(phase.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Weekly structure preview
                PlanSummaryCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Typical Week")
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 0) {
                            WeekDayBlock(day: "M", activity: "Swim", color: .cyan)
                            WeekDayBlock(day: "T", activity: "Run", color: .orange)
                            WeekDayBlock(day: "W", activity: "Bike", color: .green)
                            WeekDayBlock(day: "T", activity: "Run", color: .orange)
                            WeekDayBlock(day: "F", activity: "Swim", color: .cyan)
                            WeekDayBlock(day: "S", activity: "Bike", color: .green)
                            WeekDayBlock(day: "S", activity: "Rest", color: .gray.opacity(0.3))
                        }
                    }
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        viewModel.planApproved = true
                        onComplete()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Start Training")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        viewModel.goBack()
                    } label: {
                        Text("Go Back & Adjust")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 16)
        }
    }
}

struct PlanSummaryCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
    }
}

struct PlanDetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
            }
        }
    }
}

struct WeekDayBlock: View {
    let day: String
    let activity: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(day)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(height: 28)
                .overlay {
                    Text(activity)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white)
                }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PlanPhaseRow: View {
    let phase: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(phase)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
