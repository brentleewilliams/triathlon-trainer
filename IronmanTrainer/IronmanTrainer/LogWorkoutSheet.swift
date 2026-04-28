import SwiftUI
import HealthKit

// MARK: - Workout Type Option

private struct WorkoutTypeOption: Identifiable {
    let id: HKWorkoutActivityType
    let label: String
    let color: Color

    static let all: [WorkoutTypeOption] = [
        WorkoutTypeOption(id: .swimming,                    label: "Swim",     color: AppTheme.swim),
        WorkoutTypeOption(id: .cycling,                     label: "Bike",     color: AppTheme.bike),
        WorkoutTypeOption(id: .running,                     label: "Run",      color: AppTheme.run),
        WorkoutTypeOption(id: .cycling,                     label: "Brick",    color: AppTheme.brick),
        WorkoutTypeOption(id: .traditionalStrengthTraining, label: "Strength", color: AppTheme.strength),
        WorkoutTypeOption(id: .other,                       label: "Other",    color: AppTheme.strength),
    ]
}

// HKWorkoutActivityType does not conform to Equatable by default in all SDK versions,
// so use rawValue comparisons inside the view.

// MARK: - LogWorkoutSheet

struct LogWorkoutSheet: View {
    let prefilledType: HKWorkoutActivityType
    let onSave: (HKWorkoutActivityType, Int) -> Void // type, totalMinutes

    @Environment(\.dismiss) private var dismiss

    // Picker index into WorkoutTypeOption.all
    @State private var selectedOptionIndex: Int = 0

    @State private var selectedHours: Int = 0
    @State private var selectedMinutes: Int = 0 // index into minuteSteps

    @State private var isSaving = false
    @State private var showDurationError = false

    private let minuteSteps: [Int] = Array(stride(from: 0, through: 55, by: 5))

    // MARK: - Computed helpers

    private var selectedOption: WorkoutTypeOption {
        WorkoutTypeOption.all[selectedOptionIndex]
    }

    private var totalMinutes: Int {
        selectedHours * 60 + minuteSteps[selectedMinutes]
    }

    private var durationIsZero: Bool {
        totalMinutes == 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sport type picker
                typePicker
                    .padding(.top, 24)
                    .padding(.horizontal, 20)

                Divider()
                    .padding(.top, 20)

                // Duration pickers
                durationPickers
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                if showDurationError {
                    Text("Please add a duration before logging.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                // Log button
                logButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.72)])
        .onAppear { applyPrefilledType() }
    }

    // MARK: - Subviews

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Type")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            // Segmented-style grid of sport chips
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 80), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Array(WorkoutTypeOption.all.enumerated()), id: \.offset) { index, option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedOptionIndex = index
                            showDurationError = false
                        }
                    } label: {
                        Text(option.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                selectedOptionIndex == index
                                    ? option.color
                                    : Color(.systemGray5)
                            )
                            .foregroundStyle(
                                selectedOptionIndex == index
                                    ? Color.white
                                    : Color.primary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var durationPickers: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duration")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            HStack(spacing: 0) {
                // Hours picker
                VStack(spacing: 2) {
                    Picker("Hours", selection: $selectedHours) {
                        ForEach(0...5, id: \.self) { h in
                            Text("\(h) hr").tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedHours) { _, _ in showDurationError = false }
                }

                // Minutes picker
                VStack(spacing: 2) {
                    Picker("Minutes", selection: $selectedMinutes) {
                        ForEach(Array(minuteSteps.enumerated()), id: \.offset) { index, m in
                            Text("\(m) min").tag(index)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedMinutes) { _, _ in showDurationError = false }
                }
            }
            .frame(height: 140)
        }
    }

    private var logButton: some View {
        Button {
            handleLogTap()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(durationIsZero ? Color(.systemGray4) : selectedOption.color)
                    .frame(height: 52)

                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Log Workout")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isSaving)
        .animation(.easeInOut(duration: 0.2), value: isSaving)
        .animation(.easeInOut(duration: 0.15), value: selectedOptionIndex)
    }

    // MARK: - Actions

    private func applyPrefilledType() {
        // Match on rawValue; prefer first matching index
        if let index = WorkoutTypeOption.all.firstIndex(where: { $0.id.rawValue == prefilledType.rawValue }) {
            selectedOptionIndex = index
        }
    }

    private func handleLogTap() {
        guard !durationIsZero else {
            withAnimation { showDurationError = true }
            return
        }

        isSaving = true
        onSave(selectedOption.id, totalMinutes)
        // Give the caller a brief moment to kick off its async work, then dismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            LogWorkoutSheet(prefilledType: .cycling) { type, minutes in
                print("Saved: \(type) for \(minutes) minutes")
            }
        }
}
