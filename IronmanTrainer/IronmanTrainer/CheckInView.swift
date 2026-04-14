import SwiftUI

// MARK: - Check-In View (fullScreenCover)

/// Full-screen morning check-in presented after the user taps the notification
/// (or manually from Home). Shows readiness signals, today's workout, the
/// pre-generated coach greeting, and offers a "Talk to Coach" shortcut.
struct CheckInView: View {
    let checkIn: DailyCheckIn
    let onDismiss: () -> Void
    let onTalkToCoach: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    readinessHeader
                    metricsGrid
                    if !checkIn.flags.isEmpty {
                        flagsSection
                    }
                    if let workout = checkIn.workoutSummary {
                        workoutSection(workout)
                    }
                    if let msg = checkIn.coachMessage, !msg.isEmpty {
                        coachSection(msg)
                    }
                    Spacer(minLength: 12)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .navigationTitle("Morning Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var readinessHeader: some View {
        HStack(spacing: 16) {
            Text(checkIn.readinessLevel.emoji)
                .font(.system(size: 52))
            VStack(alignment: .leading, spacing: 4) {
                Text(checkIn.readinessLevel.label)
                    .font(.title.weight(.bold))
                    .foregroundColor(readinessColor)
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(readinessColor.opacity(0.12))
        )
    }

    private var metricsGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 12) {
            MetricTile(
                title: "Sleep",
                value: checkIn.snapshot.sleepHours.map { String(format: "%.1fh", $0) } ?? "—",
                systemImage: "bed.double.fill"
            )
            MetricTile(
                title: "HRV",
                value: checkIn.snapshot.hrvMs.map { "\(Int(round($0)))ms" } ?? "—",
                systemImage: "waveform.path.ecg"
            )
            MetricTile(
                title: "Resting HR",
                value: checkIn.snapshot.restingHR.map { "\($0) bpm" } ?? "—",
                systemImage: "heart.fill"
            )
        }
    }

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Signals to watch", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
            ForEach(checkIn.flags, id: \.self) { flag in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundColor(.orange)
                    Text(flag).font(.subheadline)
                    Spacer()
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private func workoutSection(_ workout: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's Workout")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            Text(workout)
                .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private func coachSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.blue)
                Text("From your coach")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Text(message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.08)))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                onTalkToCoach()
            } label: {
                Label("Talk to Coach", systemImage: "message.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Button {
                onDismiss()
            } label: {
                Text("Got it")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Helpers

    private var readinessColor: Color {
        switch checkIn.readinessLevel {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        case .unknown: return .gray
        }
    }

    private var subtitleText: String {
        switch checkIn.readinessLevel {
        case .green: return "Clear to train as planned."
        case .yellow: return "Proceed with awareness."
        case .red: return "Consider easing off or resting today."
        case .unknown: return "Not enough data — wear your watch overnight for insight."
        }
    }
}

// MARK: - Metric Tile

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(.blue)
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
    }
}
