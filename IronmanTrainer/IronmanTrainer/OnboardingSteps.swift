import SwiftUI
import HealthKit

// MARK: - Step 1: HealthKit Permission

struct HealthKitPermissionStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                OnboardingIllustrationHeader(step: .healthKit)

                if viewModel.isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                        Text("Analyzing your fitness data...")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.top, 8)
                } else if viewModel.hkDataLoaded {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)

                        if let profile = viewModel.hkProfile {
                            let totalWorkouts = profile.recentWorkoutDetails.count + profile.monthlyTrends.reduce(0) { $0 + $1.swimSessions + $1.bikeSessions + $1.runSessions }
                            Text("Found \(totalWorkouts) workouts")
                                .font(.headline)
                                .foregroundStyle(.white)

                            if !profile.monthlyTrends.isEmpty {
                                Text("\(profile.monthlyTrends.count) months of training data")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        } else {
                            Text("Health data connected")
                                .font(.headline)
                                .foregroundStyle(.white)
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
                        .foregroundStyle(Color(hex: "FF6B6B"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                }

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal)
                        .padding(10)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Step 2: Profile

struct ProfileStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject var authService: AuthService
    @Binding var showingForm: Bool

    private let sexOptions = ["Male", "Female", "Other"]

    // Imperial input state for height (feet + inches)
    @State private var heightFeet: String = ""
    @State private var heightInches: String = ""
    // Imperial input state for weight (lbs)
    @State private var weightLbs: String = ""
    // Track which HK fields user has tapped to edit
    @State private var editing: Set<String> = []
    // Local state for text fields — avoids publishing to viewModel on every keystroke
    @State private var localHomeZip: String = ""

    var body: some View {
        if !showingForm {
            // Illustration intro screen
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 20)
                    OnboardingIllustrationHeader(step: .profile)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        } else {
            profileFormView
        }
    }

    private var profileFormView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

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
                        OnboardingTextField(label: "Home Training Area (zip code)", text: $localHomeZip, placeholder: "e.g. 80202")
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
        .onAppear { localHomeZip = viewModel.homeZip }
        .onDisappear { viewModel.homeZip = localHomeZip }
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

// MARK: - Step 3: Race Search

struct RaceSearchStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var searchFocused: Bool
    @State private var localQuery: String = ""

    private func performSearch() {
        guard !localQuery.isEmpty else { return }
        viewModel.raceSearchQuery = localQuery
        Task { await viewModel.searchRace() }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                if !searchFocused {
                    OnboardingIllustrationHeader(step: .raceSearch)
                }

                // Search field + button
                VStack(spacing: 12) {
                    TextField("e.g. Boston Marathon 2026, Ironman 70.3 Oregon...", text: $localQuery)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .keyboardType(.default)
                        .focused($searchFocused)
                        .disabled(viewModel.isSearchingRace)
                        .onSubmit { performSearch() }

                    Button {
                        performSearch()
                    } label: {
                        if viewModel.isSearchingRace {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Text("Search")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color(hex: "FF9500"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(localQuery.isEmpty ? Color.white.opacity(0.3) : Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .disabled(localQuery.isEmpty || viewModel.isSearchingRace)
                }
                .padding(.horizontal, 16)

                // Results
                if let result = viewModel.raceSearchResult {
                    RaceResultCard(result: result) { newDate in
                        viewModel.raceSearchResult = result.withDate(newDate)
                    }
                    .padding(.horizontal, 16)

                    Button {
                        viewModel.raceSearchResult = nil
                        viewModel.raceSearchQuery = ""
                        localQuery = ""
                    } label: {
                        Text("Search again")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                if let error = viewModel.error {
                    VStack(spacing: 8) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.white)

                        Text("You can try a different search or enter details manually later.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
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

// MARK: - Step 4: Goal Setting

struct GoalSettingStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Binding var showingForm: Bool
    @State private var localCustomGoal: String = ""

    var body: some View {
        if !showingForm {
            goalIntroView
        } else {
            goalFormView
        }
    }

    // MARK: - Intro screen (gradient background)

    private var goalIntroView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                OnboardingIllustrationHeader(step: .goalSetting)

                VStack(spacing: 16) {
                    // Just Complete card (gradient-styled)
                    GoalCardOnGradient(
                        icon: "flag.fill",
                        title: "Just Complete It",
                        subtitle: "I want to finish strong and have fun",
                        isSelected: viewModel.goalType == .justComplete
                    ) {
                        withAnimation { viewModel.goalType = .justComplete }
                    }

                    // Time Target card
                    GoalCardOnGradient(
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

                    // Custom Goal card
                    GoalCardOnGradient(
                        icon: "text.bubble.fill",
                        title: "Custom Goal",
                        subtitle: "Describe your goal in your own words",
                        isSelected: viewModel.goalType == .custom
                    ) {
                        withAnimation { viewModel.goalType = .custom }
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Form screen (white background)

    private var goalFormView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Text("Configure Your Goal")
                    .font(.title2.weight(.bold))

                // Custom goal text field
                if viewModel.goalType == .custom {
                    TextField("e.g., Qualify for Boston, run/walk strategy...", text: $localCustomGoal)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

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

                // Goal validation warning
                if let warning = viewModel.goalValidationWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
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

                // Training Schedule pattern
                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.vertical, 4)

                    Text("Training Schedule")
                        .font(.headline)

                    HStack(spacing: 10) {
                        ForEach(SchedulePattern.allCases, id: \.self) { pattern in
                            Button {
                                withAnimation { viewModel.schedulePattern = pattern }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: pattern.icon)
                                        .font(.title3)
                                    Text(pattern.label)
                                        .font(.caption.weight(.medium))
                                    Text(pattern.description)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 4)
                                .background(viewModel.schedulePattern == pattern ? Color.blue.opacity(0.1) : Color(.systemGray6))
                                .foregroundStyle(viewModel.schedulePattern == pattern ? .blue : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(viewModel.schedulePattern == pattern ? Color.blue : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Strength training toggle
                    Toggle("Include Strength Training", isOn: $viewModel.includeStrength)
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 4)

                    Text(viewModel.strengthRecommended
                         ? "Recommended for your race distance"
                         : "Optional for shorter races")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                // Injuries & Equipment
                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.vertical, 4)

                    Text("Injuries & Equipment")
                        .font(.headline)

                    // Injuries picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Any current injuries or limitations?")
                            .font(.subheadline)

                        Picker("Injuries", selection: $viewModel.fitnessInjuries) {
                            Text("No injuries").tag("No current injuries or limitations")
                            Text("Minor niggles").tag("Minor niggles but can train through them")
                            Text("Recovering from injury").tag("Recovering from an injury — need modifications")
                            Text("Chronic issue").tag("Chronic issue that limits some activities")
                        }
                        .pickerStyle(.menu)
                    }

                    // Equipment picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What equipment do you have access to?")
                            .font(.subheadline)

                        let equipmentOpts = equipmentOptionsForRaceType()
                        let validatedEquipment = Binding<String>(
                            get: {
                                equipmentOpts.contains(where: { $0.value == viewModel.fitnessEquipment })
                                    ? viewModel.fitnessEquipment
                                    : (equipmentOpts.first?.value ?? viewModel.fitnessEquipment)
                            },
                            set: { viewModel.fitnessEquipment = $0 }
                        )
                        Picker("Equipment", selection: validatedEquipment) {
                            ForEach(equipmentOpts, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.menu)
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
        .onAppear {
            localCustomGoal = viewModel.customGoalText
            // Reset equipment if current value isn't valid for this race type
            let opts = equipmentOptionsForRaceType()
            if !opts.contains(where: { $0.value == viewModel.fitnessEquipment }) {
                viewModel.fitnessEquipment = opts.first?.value ?? viewModel.fitnessEquipment
            }
        }
        .onChange(of: localCustomGoal) { _, newVal in viewModel.customGoalText = newVal }
        .onDisappear { viewModel.customGoalText = localCustomGoal }
        .onChange(of: viewModel.targetHours) { _, _ in viewModel.validateGoal() }
        .onChange(of: viewModel.targetMinutes) { _, _ in viewModel.validateGoal() }
        .onChange(of: viewModel.goalType) { _, _ in viewModel.validateGoal() }
    }

    // MARK: - Equipment Options

    struct EquipmentOption {
        let label: String
        let value: String
    }

    func equipmentOptionsForRaceType() -> [EquipmentOption] {
        let sports = viewModel.relevantSports
        if sports == ["run"] {
            return [
                EquipmentOption(label: "Full setup", value: "Full setup — running shoes, GPS watch, gym access, outdoor trails"),
                EquipmentOption(label: "Basics", value: "Basics — running shoes and outdoor routes"),
                EquipmentOption(label: "Gym access", value: "Gym access — treadmill, strength equipment"),
                EquipmentOption(label: "Home only", value: "Home only — treadmill, basic gear"),
            ]
        } else if sports == ["bike"] {
            return [
                EquipmentOption(label: "Full setup", value: "Full setup — road bike, trainer, power meter, outdoor routes"),
                EquipmentOption(label: "Basics", value: "Basics — bike, helmet, outdoor routes"),
                EquipmentOption(label: "Indoor", value: "Indoor — bike trainer or spin bike"),
                EquipmentOption(label: "Minimal", value: "Minimal — bike and helmet only"),
            ]
        } else if sports == ["swim"] {
            return [
                EquipmentOption(label: "Full setup", value: "Full setup — pool access, wetsuit, paddles, pull buoy"),
                EquipmentOption(label: "Basics", value: "Basics — pool access, goggles, swim cap"),
                EquipmentOption(label: "Open water", value: "Open water access — lake or ocean, wetsuit"),
                EquipmentOption(label: "Pool only", value: "Pool only — lap pool access"),
            ]
        }
        return [
            EquipmentOption(label: "Full setup", value: "Full setup — bike trainer, pool access, gym, outdoor routes"),
            EquipmentOption(label: "Basics", value: "Basics — bike, running shoes, pool access"),
            EquipmentOption(label: "Minimal", value: "Minimal — running shoes and a gym membership"),
            EquipmentOption(label: "Home only", value: "Home only — treadmill/trainer, no pool"),
        ]
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
                Text("Secondary Races")
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

            Text("Add any secondary races along the way. These help structure your training peaks and tapers.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if prepRaces.races.isEmpty {
                Text("No secondary races added yet")
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
            // During onboarding the plan hasn't been generated yet — just add the race.
            AddPrepRaceSheet { race, _ in
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
    @State private var showAdjustAlert = false
    @State private var pendingRace: PrepRace?

    /// Called with the race and a Bool indicating whether the user wants surrounding plan adjustment.
    let onAdd: (PrepRace, Bool) -> Void

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
            .navigationTitle("Add Secondary Race")
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
                        if race.isBigRace {
                            pendingRace = race
                            showAdjustAlert = true
                        } else {
                            onAdd(race, false)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Adjust Surrounding Plan?", isPresented: $showAdjustAlert, presenting: pendingRace) { race in
                Button("Adjust Plan") {
                    onAdd(race, true)
                    dismiss()
                }
                Button("Just Add Race") {
                    onAdd(race, false)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { pendingRace = nil }
            } message: { race in
                Text("This is a \(race.distance). Would you like to rebuild the 3 surrounding training weeks to taper before and recover after?")
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

// MARK: - Step 5: Tutorial

struct TutorialStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 20)

                    OnboardingIllustrationHeader(step: .tutorial)

                    // AI coach identity card
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 40, height: 40)
                            Image(systemName: "sparkles")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("AI Coach")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                Text("• Powered by Claude")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Text("Hi! I'm your AI race coach. I'll ask a few quick questions about your schedule, injuries, and gear — then build your personalized plan.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    // Plan generation status
                    if viewModel.isGeneratingPlan {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.white)
                            Text("Building your plan...")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    } else if viewModel.planGenerationError != nil {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                            Text("Plan generation failed.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                            Button {
                                viewModel.retryPlanGeneration()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(hex: "00C7BE"))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            // Build My Plan button
            VStack(spacing: 0) {
                Button {
                    viewModel.advance()
                } label: {
                    Text(viewModel.minimumWeeksLoaded ? "Build My Plan" : "Please wait...")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(viewModel.minimumWeeksLoaded ? Color(hex: "00C7BE") : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(viewModel.minimumWeeksLoaded ? Color.white : Color.white.opacity(0.3))
                        .clipShape(Capsule())
                }
                .disabled(!viewModel.minimumWeeksLoaded)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }
}

// MARK: - Step 6: Plan Review

struct PlanReviewStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var onComplete: ([TrainingWeek]) -> Void

    @State private var minimumSpinnerElapsed = false

    private var isLoading: Bool {
        viewModel.isGeneratingPlan || !minimumSpinnerElapsed
    }

    private var weeksUntilRace: Int {
        guard let race = viewModel.raceSearchResult else { return 0 }
        return max(0, Calendar.current.dateComponents([.weekOfYear], from: Date(), to: race.date).weekOfYear ?? 0)
    }

    private var chatAnswers: [String: String] {
        var answers: [String: String] = [:]
        answers["schedule"] = viewModel.schedulePattern.label
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

    private var illustrationSubtitle: String {
        let weeks: Int = {
            if let plan = viewModel.generatedPlan { return plan.count }
            return weeksUntilRace
        }()
        let raceName = viewModel.raceSearchResult?.name ?? "your race"
        if weeks > 0 {
            return "\(weeks) weeks of personalized training, built for \(raceName)"
        }
        return "Your personalized training plan"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 12)

                // Illustration header
                OnboardingIllustrationHeader(
                    step: .planReview,
                    subtitleOverride: illustrationSubtitle
                )

                // Loading state
                if isLoading {
                    VStack(spacing: 20) {
                        Spacer().frame(height: 40)
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.6)
                        VStack(spacing: 8) {
                            Text("Building your AI plan...")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                            if !viewModel.isGeneratingPlan {
                                Text("Almost ready")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.85))
                            } else if viewModel.planMethod != "template" && viewModel.planBatchesCompleted > 0 {
                                Text("(\(viewModel.planBatchesCompleted)/\(viewModel.planTotalBatches) sections complete)")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.85))
                            } else {
                                Text("Personalizing based on your profile")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                }

                // Error state
                if !isLoading, let error = viewModel.planGenerationError {
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

                // Plan details (hidden while loading)
                if !isLoading { Group {

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
                        case .custom:
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom Goal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(viewModel.customGoalText.isEmpty ? "Custom goal" : viewModel.customGoalText)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(2)
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

                // Plan warnings
                if !viewModel.planWarnings.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(viewModel.planWarnings, id: \.self) { warning in
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.yellow.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 16)
                }

                }} // end if !isLoading / Group

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        if let plan = viewModel.generatedPlan {
                            viewModel.planApproved = true
                            // Persist race date for countdown banner and widget
                            if let raceDate = viewModel.raceSearchResult?.date {
                                UserDefaults.standard.set(raceDate.timeIntervalSince1970, forKey: "race_date")
                                AppGroupConstants.syncRaceDateToWidget(raceDate)
                            }
                            onComplete(plan)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Start Training")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(!isLoading && viewModel.generatedPlan != nil ? Color(hex: "5856D6") : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(!isLoading && viewModel.generatedPlan != nil ? Color.white : Color.white.opacity(0.3))
                        .clipShape(Capsule())
                    }
                    .disabled(isLoading || viewModel.generatedPlan == nil)

                    if !isLoading {
                        Button {
                            viewModel.goBackToGoalSetting()
                        } label: {
                            Text("Go Back & Adjust")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        Text("You can adjust your plan anytime by chatting with your AI coach.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            minimumSpinnerElapsed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                minimumSpinnerElapsed = true
            }
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
