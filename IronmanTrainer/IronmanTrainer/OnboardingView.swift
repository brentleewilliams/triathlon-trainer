import SwiftUI

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var chatViewModel = ChatViewModel(skipHistory: true)
    var onComplete: ([TrainingWeek]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            OnboardingProgressBar(progress: viewModel.progressPercent, currentStep: viewModel.currentStep)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            // Content area — no swipe between steps, button-only navigation
            Group {
                switch viewModel.currentStep {
                case .healthKit:
                    HealthKitPermissionStep(viewModel: viewModel)
                case .profile:
                    ProfileStep(viewModel: viewModel)
                case .raceSearch:
                    RaceSearchStep(viewModel: viewModel)
                case .goalSetting:
                    GoalSettingStep(viewModel: viewModel)
                case .fitnessChat:
                    FitnessChatStep(viewModel: viewModel, chatViewModel: chatViewModel)
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

            // Navigation buttons (hidden during fitness chat which has its own input bar)
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
        case .tutorial: return "Getting Started"
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
            return true
        case .raceSearch:
            return viewModel.raceSearchResult != nil
        case .goalSetting:
            return viewModel.allSkillsSelected
        case .fitnessChat:
            return true
        case .tutorial:
            return viewModel.minimumWeeksLoaded
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
    @EnvironmentObject var authService: AuthService

    private let sexOptions = ["Male", "Female", "Other"]

    // Imperial input state for height (feet + inches)
    @State private var heightFeet: String = ""
    @State private var heightInches: String = ""
    // Imperial input state for weight (lbs)
    @State private var weightLbs: String = ""
    // Track which HK fields user has tapped to edit
    @State private var editing: Set<String> = []

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
                    if let email = authService.currentUserEmail, !email.isEmpty {
                        HKProvidedRow(label: "Account", value: email)
                    }

                    // Home Training Area
                    if viewModel.hkHasLocation && !editing.contains("location") {
                        TappableHKRow(label: "Home Training Area", value: viewModel.homeZip) {
                            editing.insert("location")
                        }
                    } else {
                        OnboardingTextField(label: "Home Training Area (zip code)", text: $viewModel.homeZip, placeholder: "e.g. 80202")
                    }

                    // Date of Birth
                    if viewModel.hkHasDOB && !editing.contains("dob") {
                        TappableHKRow(label: "Date of Birth", value: Formatters.fullDate.string(from: viewModel.userDOB)) {
                            editing.insert("dob")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Date of Birth")
                                .font(.subheadline.weight(.medium))
                            DatePicker("", selection: $viewModel.userDOB, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }

                    // Biological Sex
                    if viewModel.hkHasSex && !editing.contains("sex") {
                        TappableHKRow(label: "Biological Sex", value: viewModel.userSex) {
                            editing.insert("sex")
                        }
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

                    // Height (imperial)
                    if viewModel.hkHasHeight && !editing.contains("height") {
                        TappableHKRow(label: "Height", value: formatHeightImperial(cm: viewModel.userHeightCm ?? 0)) {
                            initHeightFromCm()
                            editing.insert("height")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Height")
                                .font(.subheadline.weight(.medium))
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    TextField("5", text: $heightFeet)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)
                                        .frame(width: 60)
                                    Text("ft")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 4) {
                                    TextField("10", text: $heightInches)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)
                                        .frame(width: 60)
                                    Text("in")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onChange(of: heightFeet) { _, _ in updateHeightCm() }
                        .onChange(of: heightInches) { _, _ in updateHeightCm() }
                        .onAppear { initHeightFromCm() }
                    }

                    // Weight (imperial)
                    if viewModel.hkHasWeight && !editing.contains("weight") {
                        TappableHKRow(label: "Weight", value: String(format: "%.0f lbs", (viewModel.userWeightKg ?? 0) * 2.20462)) {
                            initWeightFromKg()
                            editing.insert("weight")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Weight")
                                .font(.subheadline.weight(.medium))
                            HStack(spacing: 4) {
                                TextField("170", text: $weightLbs)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.decimalPad)
                                Text("lbs")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: weightLbs) { _, newVal in
                            if let lbs = Double(newVal) {
                                viewModel.userWeightKg = lbs / 2.20462
                            } else {
                                viewModel.userWeightKg = nil
                            }
                        }
                        .onAppear { initWeightFromKg() }
                    }

                    // Resting HR
                    if viewModel.hkHasRestingHR && !editing.contains("rhr") {
                        TappableHKRow(label: "Resting HR", value: "\(viewModel.userRestingHR ?? 0) bpm") {
                            editing.insert("rhr")
                        }
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

    private func updateHeightCm() {
        let feet = Int(heightFeet) ?? 0
        let inches = Int(heightInches) ?? 0
        let totalInches = feet * 12 + inches
        if totalInches > 0 {
            viewModel.userHeightCm = Double(totalInches) * 2.54
        } else {
            viewModel.userHeightCm = nil
        }
    }

    private func initHeightFromCm() {
        guard heightFeet.isEmpty, let cm = viewModel.userHeightCm, cm > 0 else { return }
        let totalInches = Int(round(cm / 2.54))
        heightFeet = "\(totalInches / 12)"
        heightInches = "\(totalInches % 12)"
    }

    private func initWeightFromKg() {
        guard weightLbs.isEmpty, let kg = viewModel.userWeightKg, kg > 0 else { return }
        weightLbs = String(format: "%.0f", kg * 2.20462)
    }

    private func formatHeightImperial(cm: Double) -> String {
        let totalInches = Int(round(cm / 2.54))
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet)'\(inches)\""
    }
}

/// HK-provided row that looks like the old design but is tappable to edit.
struct TappableHKRow: View {
    let label: String
    let value: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
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
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
    @FocusState private var searchFocused: Bool

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

                // Search field + button
                VStack(spacing: 12) {
                    TextField("e.g. Ironman 70.3 Oregon 2026", text: $viewModel.raceSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused)
                        .disabled(viewModel.isSearchingRace)
                        .onSubmit {
                            if !viewModel.raceSearchQuery.isEmpty {
                                Task { await viewModel.searchRace() }
                            }
                        }

                    Button {
                        Task { await viewModel.searchRace() }
                    } label: {
                        if viewModel.isSearchingRace {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Text("Search")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(viewModel.raceSearchQuery.isEmpty ? Color(.systemGray4) : Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                searchFocused = true
            }
        }
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
                    // Just Complete card (default, first)
                    GoalCard(
                        icon: "flag.fill",
                        title: "Just Complete It",
                        subtitle: "I want to finish strong and have fun",
                        isSelected: viewModel.goalType == .justComplete
                    ) {
                        withAnimation { viewModel.goalType = .justComplete }
                    }

                    // Time Target card
                    GoalCard(
                        icon: "stopwatch.fill",
                        title: "Finish Time Goal",
                        subtitle: "I have a specific time I want to hit",
                        isSelected: viewModel.goalType == .timeTarget
                    ) {
                        withAnimation {
                            let defaults = viewModel.defaultFinishTime
                            viewModel.targetHours = defaults.hours
                            viewModel.targetMinutes = defaults.minutes
                            viewModel.goalType = .timeTarget
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Time picker (only if time target selected)
                if viewModel.goalType == .timeTarget {
                    VStack(spacing: 8) {
                        Text("Target Finish Time")
                            .font(.subheadline.weight(.medium))

                        let hourRange = viewModel.finishTimeHourRange
                        HStack(spacing: 4) {
                            Picker("Hours", selection: $viewModel.targetHours) {
                                ForEach(Array(hourRange), id: \.self) { h in
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

                // Per-sport skill levels (only relevant sports)
                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.vertical, 4)

                    Text("Skill Level by Sport")
                        .font(.headline)

                    Text("This helps tailor workout difficulty and progression for each discipline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let sports = viewModel.relevantSports
                    if sports.contains("swim") {
                        SkillLevelPicker(icon: "figure.pool.swim", sport: "Swim", level: $viewModel.swimLevel)
                    }
                    if sports.contains("bike") {
                        SkillLevelPicker(icon: "figure.outdoor.cycle", sport: "Bike", level: $viewModel.bikeLevel)
                    }
                    if sports.contains("run") {
                        SkillLevelPicker(icon: "figure.run", sport: "Run", level: $viewModel.runLevel)
                    }
                }
                .padding(.horizontal, 16)

                // Prep races section (optional)
                PrepRacesOnboardingSection()

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

// MARK: - Prep Races Onboarding Section

struct PrepRacesOnboardingSection: View {
    @ObservedObject private var prepRaces = PrepRacesManager.shared
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.vertical, 4)

            HStack {
                Image(systemName: "flag.2.crossed.fill")
                    .foregroundStyle(.orange)
                Text("Tune-up Races")
                    .font(.headline)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }

            Text("Add any prep races along the way. These help structure your training peaks and tapers.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if prepRaces.races.isEmpty {
                Text("No prep races added yet")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(prepRaces.races) { race in
                    PrepRaceRow(race: race) {
                        prepRaces.removeByID(race.id)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPrepRaceSheet { race in
                prepRaces.add(race)
            }
        }
    }
}

struct PrepRaceRow: View {
    let race: PrepRace
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(race.name)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(race.distance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Formatters.fullDate.string(from: race.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AddPrepRaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var date = Date()
    @State private var distance = "5K"
    @State private var notes = ""
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    let onAdd: (PrepRace) -> Void

    private let distanceOptions = ["5K", "10K", "Half Marathon", "Marathon", "Sprint Tri", "Olympic Tri", "Century Ride", "Other"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Search for Race"), footer: Text("Or enter details manually below.")) {
                    HStack {
                        TextField("e.g. Cherry Creek Sneak 5K 2026", text: $searchQuery)
                            .disabled(isSearching)
                        if isSearching {
                            Button {
                                cancelSearch()
                            } label: {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                        } else {
                            Button {
                                searchTask = Task { await searchRace() }
                            } label: {
                                Text("Search")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    if let error = searchError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section(header: Text("Race Details")) {
                    TextField("Race Name", text: $name)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Distance", selection: $distance) {
                        ForEach(distanceOptions, id: \.self) { Text($0) }
                    }
                }
                Section(header: Text("Notes (optional)")) {
                    TextField("e.g. Goal pace, strategy", text: $notes)
                }
            }
            .navigationTitle("Add Prep Race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let race = PrepRace(
                            name: name,
                            date: date,
                            distance: distance,
                            notes: notes.isEmpty ? nil : notes
                        )
                        onAdd(race)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        searchError = nil
    }

    private func searchRace() async {
        isSearching = true
        searchError = nil
        do {
            let result = try await LLMProxyService.shared.searchPrepRace(query: searchQuery)
            guard !Task.isCancelled else { return }
            name = result.name
            date = result.date
            // Map race type to distance option
            if let matchedDist = distanceOptions.first(where: { result.distance.localizedCaseInsensitiveContains($0) }) {
                distance = matchedDist
            } else {
                distance = "Other"
                if notes.isEmpty { notes = result.distance }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searchError = "Could not find race. Try entering details manually."
        }
        isSearching = false
    }
}

struct SkillLevelPicker: View {
    let icon: String
    let sport: String
    @Binding var level: SkillLevel?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                Text(sport)
                    .font(.subheadline.weight(.medium))
            }
            HStack(spacing: 0) {
                ForEach(SkillLevel.allCases, id: \.self) { lvl in
                    Button {
                        level = lvl
                    } label: {
                        Text(lvl.rawValue)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(level == lvl ? Color.blue : Color(.systemGray5))
                            .foregroundStyle(level == lvl ? .white : .primary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            // Intro header with back button
            ZStack {
                // Back button on leading edge
                HStack {
                    Button {
                        viewModel.goBack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.body.weight(.medium))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                // Centered title
                VStack(spacing: 8) {
                    Text("Fitness Assessment")
                        .font(.headline)
                    Text("Chat with your AI coach to assess your fitness and build your plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 56) // Leave room for back button
            }
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
                        viewModel.advance(chatMessages: chatViewModel.messages)
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
                    goal: goalTypeFromSelection(),
                    skillLevels: (swim: viewModel.swimLevel ?? .beginner, bike: viewModel.bikeLevel ?? .beginner, run: viewModel.runLevel ?? .beginner)
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
        case 2: viewModel.fitnessSchedule = reply.value
        case 3:
            viewModel.fitnessInjuries = reply.value
            // Start plan generation early — we have hours, schedule, and injuries
            viewModel.startEarlyPlanGeneration(chatMessages: chatViewModel.messages)
        case 4: viewModel.fitnessEquipment = reply.value
        default: break
        }

        // Determine next question based on conversation state
        let messageCount = chatViewModel.messages.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if messageCount <= 3 {
                // After hours answer → ask schedule preferences
                let msg = ChatMessage(
                    isUser: false,
                    text: "Got it — \(reply.value). That's a great foundation.\n\nWhat does your weekly schedule look like? When do you prefer to train?",
                    timestamp: Date()
                )
                chatViewModel.messages.append(msg)
                withAnimation { quickReplies = Self.scheduleReplies }
            } else if messageCount <= 5 {
                // After schedule → ask injury history
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
                withAnimation { quickReplies = self.equipmentRepliesForRaceType() }
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

    static let scheduleReplies = [
        QuickReply(label: "Mornings before work", value: "Mornings before work — early riser"),
        QuickReply(label: "Lunch breaks", value: "Lunch breaks and midday sessions"),
        QuickReply(label: "Evenings after work", value: "Evenings after work"),
        QuickReply(label: "Weekends mostly", value: "Mostly weekends — weekdays are tight"),
        QuickReply(label: "Flexible", value: "Flexible schedule — can train anytime"),
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

    static let runningEquipmentReplies = [
        QuickReply(label: "Full setup", value: "Full setup — running shoes, GPS watch, gym access, outdoor trails"),
        QuickReply(label: "Basics", value: "Basics — running shoes and outdoor routes"),
        QuickReply(label: "Gym access", value: "Gym access — treadmill, strength equipment"),
        QuickReply(label: "Home only", value: "Home only — treadmill, basic gear"),
    ]

    static let cyclingEquipmentReplies = [
        QuickReply(label: "Full setup", value: "Full setup — road bike, trainer, power meter, outdoor routes"),
        QuickReply(label: "Basics", value: "Basics — bike, helmet, outdoor routes"),
        QuickReply(label: "Indoor", value: "Indoor — bike trainer or spin bike"),
        QuickReply(label: "Minimal", value: "Minimal — bike and helmet only"),
    ]

    static let swimmingEquipmentReplies = [
        QuickReply(label: "Full setup", value: "Full setup — pool access, wetsuit, paddles, pull buoy"),
        QuickReply(label: "Basics", value: "Basics — pool access, goggles, swim cap"),
        QuickReply(label: "Open water", value: "Open water access — lake or ocean, wetsuit"),
        QuickReply(label: "Pool only", value: "Pool only — lap pool access"),
    ]

    func equipmentRepliesForRaceType() -> [QuickReply] {
        let sports = viewModel.relevantSports
        if sports == ["run"] {
            return Self.runningEquipmentReplies
        } else if sports == ["bike"] {
            return Self.cyclingEquipmentReplies
        } else if sports == ["swim"] {
            return Self.swimmingEquipmentReplies
        }
        return Self.equipmentReplies
    }
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

// MARK: - Step 6: Tutorial

struct TutorialStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var tutorialPage = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tutorialPage) {
                // Page 1: Your Week at a Glance
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer().frame(height: 40)

                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 56))
                            .foregroundStyle(.blue)

                        Text("Your Week at a Glance")
                            .font(.title2.weight(.bold))

                        Text("Each day shows your planned workout type at a glance")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        // Example week blocks
                        HStack(spacing: 0) {
                            WeekDayBlock(day: "M", activity: "Swim", color: .cyan)
                            WeekDayBlock(day: "T", activity: "Run", color: .orange)
                            WeekDayBlock(day: "W", activity: "Bike", color: .green)
                            WeekDayBlock(day: "T", activity: "Run", color: .orange)
                            WeekDayBlock(day: "F", activity: "Swim", color: .cyan)
                            WeekDayBlock(day: "S", activity: "Bike", color: .green)
                            WeekDayBlock(day: "S", activity: "Rest", color: .gray.opacity(0.3))
                        }
                        .padding(.horizontal, 24)

                        // Legend
                        VStack(spacing: 8) {
                            HStack(spacing: 16) {
                                TutorialLegendItem(color: .cyan, label: "Swim")
                                TutorialLegendItem(color: .green, label: "Bike")
                                TutorialLegendItem(color: .orange, label: "Run")
                            }
                            HStack(spacing: 16) {
                                TutorialLegendItem(color: .purple, label: "Brick")
                                TutorialLegendItem(color: .yellow, label: "Strength")
                                TutorialLegendItem(color: .gray.opacity(0.3), label: "Rest")
                            }
                        }
                        .padding(.top, 8)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                .tag(0)

                // Page 2: Track Your Progress
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer().frame(height: 40)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)

                        Text("Track Your Progress")
                            .font(.title2.weight(.bold))

                        Text("Your workouts sync automatically from Apple Health. Completed workouts show a green checkmark.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        // Mock workout row with checkmark
                        VStack(spacing: 0) {
                            TutorialMockWorkoutRow(type: "Run", duration: "45 min", zone: "Z2", completed: true)
                            Divider()
                            TutorialMockWorkoutRow(type: "Swim", duration: "30 min", zone: "Z1-Z2", completed: true)
                            Divider()
                            TutorialMockWorkoutRow(type: "Bike", duration: "60 min", zone: "Z2-Z3", completed: false)
                        }
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)

                        HStack(spacing: 8) {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(.red)
                            Text("Powered by Apple Health")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                .tag(1)

                // Page 3: Your AI Coach
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer().frame(height: 40)

                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.blue)

                        Text("Your AI Coach")
                            .font(.title2.weight(.bold))

                        Text("Ask your coach about today's workout, get pacing advice, or reschedule training days.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        // Mock chat bubbles
                        VStack(alignment: .leading, spacing: 8) {
                            TutorialChatBubble(text: "What should I focus on in today's swim?", isUser: true)
                            TutorialChatBubble(text: "Focus on your catch and pull technique. Aim for 1:50/100yd pace in the main set.", isUser: false)
                        }
                        .padding(.horizontal, 24)

                        Spacer().frame(height: 16)

                        // Plan generation progress
                        if viewModel.isGeneratingPlan {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Building your plan... (\(viewModel.planBatchesCompleted)/\(viewModel.planTotalBatches))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 24)
                        } else if viewModel.minimumWeeksLoaded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            Text("Your plan is ready!")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                        } else if viewModel.planGenerationError != nil {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                Text("Plan generation failed. Please try again.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button {
                                    viewModel.retryPlanGeneration()
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Retry")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 24)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(tutorialPage == index ? Color.blue : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: tutorialPage)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

struct TutorialLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct TutorialMockWorkoutRow: View {
    let type: String
    let duration: String
    let zone: String
    let completed: Bool

    private var typeColor: Color {
        switch type.lowercased() {
        case "swim": return .cyan
        case "bike": return .green
        case "run": return .orange
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(typeColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(type)
                    .font(.subheadline.weight(.medium))
                Text("\(duration) \u{2022} \(zone)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct TutorialChatBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer() }
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer() }
        }
    }
}

// MARK: - Step 7: Plan Review

struct PlanReviewStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var onComplete: ([TrainingWeek]) -> Void

    private var weeksUntilRace: Int {
        guard let race = viewModel.raceSearchResult else { return 0 }
        return max(0, Calendar.current.dateComponents([.weekOfYear], from: Date(), to: race.date).weekOfYear ?? 0)
    }

    private var chatAnswers: [String: String] {
        var answers: [String: String] = [:]
        if !viewModel.fitnessHours.isEmpty { answers["hours"] = viewModel.fitnessHours }
        if !viewModel.fitnessSchedule.isEmpty { answers["schedule"] = viewModel.fitnessSchedule }
        if !viewModel.fitnessInjuries.isEmpty { answers["injuries"] = viewModel.fitnessInjuries }
        if !viewModel.fitnessEquipment.isEmpty { answers["equipment"] = viewModel.fitnessEquipment }
        return answers
    }

    private var planPhases: [(name: String, weeks: String, description: String, color: Color)] {
        // If we have a generated plan, derive phases from it
        if let plan = viewModel.generatedPlan {
            var phaseGroups: [(name: String, startWeek: Int, endWeek: Int)] = []
            for week in plan {
                if let last = phaseGroups.last, last.name == week.phase {
                    phaseGroups[phaseGroups.count - 1] = (last.name, last.startWeek, week.weekNumber)
                } else {
                    phaseGroups.append((week.phase, week.weekNumber, week.weekNumber))
                }
            }
            let phaseColors: [String: Color] = [
                "Base": .blue, "Build": .orange, "Peak": .red,
                "Taper": .green, "Race Week": .purple, "Race Prep": .purple,
                "Recovery": .mint
            ]
            return phaseGroups.map { group in
                let color = phaseColors.first { group.name.contains($0.key) }?.value ?? .gray
                let weekStr = group.startWeek == group.endWeek
                    ? "Week \(group.startWeek)"
                    : "Weeks \(group.startWeek)–\(group.endWeek)"
                return (group.name, weekStr, "", color)
            }
        }

        // Fallback: estimate from weeks until race
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

                        if let plan = viewModel.generatedPlan {
                            Text("\(plan.count) weeks of training")
                                .font(.headline)
                                .foregroundStyle(.blue)
                                .padding(.top, 2)
                        } else if weeksUntilRace > 0 {
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

                // Loading state
                if viewModel.isGeneratingPlan {
                    PlanSummaryCard {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Building your plan... (\(viewModel.planBatchesCompleted)/\(viewModel.planTotalBatches))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let plan = viewModel.generatedPlan, !plan.isEmpty {
                                Text("\(plan.count) weeks loaded so far")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("This may take a minute")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }

                // Error state
                if let error = viewModel.planGenerationError {
                    PlanSummaryCard {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            Text("Plan generation failed")
                                .font(.subheadline.weight(.semibold))
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                viewModel.startPlanGeneration()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
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
                            if let sched = chatAnswers["schedule"] {
                                PlanDetailRow(icon: "calendar.badge.clock", label: "Schedule", value: sched)
                            }
                            if let injury = chatAnswers["injuries"] {
                                PlanDetailRow(icon: "cross.circle.fill", label: "Injuries", value: injury)
                            }
                            if let equip = chatAnswers["equipment"] {
                                let equipIcon: String = {
                                    let sports = viewModel.relevantSports
                                    if sports == ["run"] { return "figure.run" }
                                    if sports == ["swim"] { return "figure.pool.swim" }
                                    if sports == ["bike"] { return "bicycle" }
                                    return "bicycle"
                                }()
                                PlanDetailRow(icon: equipIcon, label: "Equipment", value: equip)
                            }
                        }
                    }
                }

                // Plan phases
                if !planPhases.isEmpty {
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
                                        if !phase.description.isEmpty {
                                            Text(phase.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Weekly structure preview (from generated plan week 1, or fallback)
                PlanSummaryCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Typical Week")
                            .font(.subheadline.weight(.semibold))

                        if let week1 = viewModel.generatedPlan?.first {
                            HStack(spacing: 0) {
                                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { dayName in
                                    let workout = week1.workouts.first { $0.day == dayName }
                                    let (shortDay, activity, color) = weekDayInfo(dayName: dayName, workout: workout)
                                    WeekDayBlock(day: shortDay, activity: activity, color: color)
                                }
                            }
                        } else {
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
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        if let plan = viewModel.generatedPlan {
                            viewModel.planApproved = true
                            onComplete(plan)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Start Training")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(viewModel.generatedPlan != nil ? Color.blue : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(viewModel.generatedPlan == nil)

                    Button {
                        viewModel.goBackToGoalSetting()
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

    private func weekDayInfo(dayName: String, workout: DayWorkout?) -> (String, String, Color) {
        let shortDays: [String: String] = ["Mon": "M", "Tue": "T", "Wed": "W", "Thu": "T", "Fri": "F", "Sat": "S", "Sun": "S"]
        let short = shortDays[dayName] ?? String(dayName.prefix(1))
        guard let w = workout else { return (short, "Rest", .gray.opacity(0.3)) }
        let type = w.type.lowercased()
        if type.contains("swim") { return (short, "Swim", .cyan) }
        if type.contains("bike") && type.contains("run") || type.contains("brick") { return (short, "Brick", .purple) }
        if type.contains("bike") { return (short, "Bike", .green) }
        if type.contains("run") { return (short, "Run", .orange) }
        if type.contains("strength") { return (short, "Strength", .pink) }
        if type.contains("rest") { return (short, "Rest", .gray.opacity(0.3)) }
        return (short, String(w.type.prefix(5)), .gray)
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
