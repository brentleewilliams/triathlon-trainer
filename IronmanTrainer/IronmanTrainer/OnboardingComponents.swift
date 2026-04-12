import SwiftUI

// MARK: - Reusable Illustration Header

struct OnboardingIllustrationHeader: View {
    let step: OnboardingStep
    var subtitleOverride: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(step.illustrationName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: UIScreen.main.bounds.height * 0.35)
                .padding(.horizontal, 32)

            VStack(spacing: 8) {
                Text(step.illustrationTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                let subtitle = subtitleOverride ?? step.illustrationSubtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}

// MARK: - HealthKit Data Rows

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

// MARK: - Onboarding Input Fields

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

// MARK: - Race Components

struct RaceResultCard: View {
    let result: RaceSearchResult
    var onDateChange: ((Date) -> Void)?

    @State private var selectedDate: Date

    init(result: RaceSearchResult, onDateChange: ((Date) -> Void)? = nil) {
        self.result = result
        self.onDateChange = onDateChange
        self._selectedDate = State(initialValue: result.date)
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

            if onDateChange != nil {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: selectedDate) { _, newDate in
                            onDateChange?(newDate)
                        }
                }
            } else {
                RaceDetailRow(icon: "calendar", label: "Date", value: {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .long
                    return formatter.string(from: result.date)
                }())
            }
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

// MARK: - Goal Components

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

struct GoalCardOnGradient: View {
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
                    .foregroundStyle(isSelected ? Color(hex: "34C759") : .white)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.white : Color.white.opacity(0.2))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .font(.title3)
                }
            }
            .padding(16)
            .background(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tutorial Components

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

// MARK: - Plan Review Components

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
