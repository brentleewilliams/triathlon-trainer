import SwiftUI

// MARK: - Plan Diff Card

struct PlanDiffCard: View {
    @ObservedObject var viewModel: ChatViewModel
    let enriched: EnrichedProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text(enriched.proposal.summary)
                .font(.body.bold())

            // Per-week sections
            ForEach(enriched.weekDiffs) { weekDiff in
                WeekDiffSection(weekDiff: weekDiff)
            }

            // Volume summary bar
            VolumeSummaryBar(enriched: enriched)

            // Action buttons
            NegotiationButtons(viewModel: viewModel, proposal: enriched.proposal)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Week Diff Section

private struct WeekDiffSection: View {
    let weekDiff: WeekDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Week header
            HStack {
                Text("Week \(weekDiff.weekNumber)")
                    .font(.subheadline.bold())
                Text("·")
                    .foregroundStyle(.secondary)
                Text(weekDiff.phase)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Day rows
            ForEach(weekDiff.dayDiffs) { dayDiff in
                if dayDiff.status == .unchanged {
                    UnchangedDayRow(dayDiff: dayDiff)
                } else {
                    ChangedDayCard(dayDiff: dayDiff)
                }
            }

            // Per-week volume if multiple weeks
            if weekDiff.volumeChangeMinutes != 0 {
                HStack(spacing: 4) {
                    Text("Week volume:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(PlanDiffEngine.formatVolumeChange(weekDiff.volumeChangeMinutes))
                        .font(.caption.bold())
                        .foregroundColor(weekDiff.volumeChangeMinutes > 0 ? .blue : .orange)
                }
            }
        }
    }
}

// MARK: - Unchanged Day Row (collapsed)

private struct UnchangedDayRow: View {
    let dayDiff: DayDiff

    var body: some View {
        let workoutSummary = dayDiff.currentWorkouts.isEmpty
            ? "Rest"
            : dayDiff.currentWorkouts.map { $0.type }.joined(separator: " + ")

        HStack(spacing: 8) {
            Text(dayDiff.day)
                .font(.caption.bold())
                .frame(width: 30, alignment: .leading)
            Text(workoutSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }
}

// MARK: - Changed Day Card (full detail)

private struct ChangedDayCard: View {
    let dayDiff: DayDiff

    private var statusColor: Color {
        switch dayDiff.status {
        case .unchanged: return .clear
        case .modified: return .yellow
        case .dropped: return .red
        case .added: return .blue
        case .swapped: return .orange
        }
    }

    private var statusLabel: String {
        switch dayDiff.status {
        case .unchanged: return ""
        case .modified: return "MODIFIED"
        case .dropped: return "DROPPED"
        case .added: return "ADDED"
        case .swapped: return "SWAPPED"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Day header with status badge
            HStack(spacing: 8) {
                Text(dayDiff.day)
                    .font(.subheadline.bold())

                Text(statusLabel)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor == .yellow ? .orange : statusColor)
                    .clipShape(Capsule())

                if dayDiff.isKeySession {
                    Text("KEY SESSION")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                }

                Spacer()
            }

            // Current → Proposed columns
            if !dayDiff.currentWorkouts.isEmpty || !dayDiff.proposedWorkouts.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    // Current
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if dayDiff.currentWorkouts.isEmpty {
                            Text("Rest")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(dayDiff.currentWorkouts, id: \.day) { w in
                                WorkoutMiniRow(workout: w)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 14)

                    // Proposed
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Proposed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if dayDiff.proposedWorkouts.isEmpty {
                            Text("Rest")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(dayDiff.proposedWorkouts, id: \.day) { w in
                                WorkoutMiniRow(workout: w)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Rationale
            if let rationale = dayDiff.rationale {
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(statusColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Workout Mini Row

private struct WorkoutMiniRow: View {
    let workout: DayWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(workout.type)
                .font(.caption)
                .fontWeight(.medium)
            if workout.duration != "-" || workout.zone != "-" {
                Text("\(workout.duration) · \(workout.zone)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Volume Summary Bar

private struct VolumeSummaryBar: View {
    let enriched: EnrichedProposal

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Volume:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(PlanDiffEngine.formatMinutes(enriched.originalTotalMinutes))
                .font(.caption)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(PlanDiffEngine.formatMinutes(enriched.proposedTotalMinutes))
                .font(.caption)

            Text("(\(PlanDiffEngine.formatVolumeChange(enriched.volumeChangeMinutes)))")
                .font(.caption.bold())
                .foregroundColor(volumeColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray5).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var volumeColor: Color {
        if enriched.volumeChangeMinutes > 0 { return .blue }
        if enriched.volumeChangeMinutes < 0 { return .orange }
        return .secondary
    }
}

// MARK: - Negotiation Buttons

private struct NegotiationButtons: View {
    @ObservedObject var viewModel: ChatViewModel
    let proposal: PlanChangeProposal

    var body: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.acceptAllChanges(proposal)
            } label: {
                Text("Accept All")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                viewModel.startModification()
            } label: {
                Text("Modify")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray4))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                viewModel.rejectProposal()
            } label: {
                Text("Reject")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .foregroundColor(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
