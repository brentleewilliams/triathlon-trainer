import SwiftUI
import HealthKit
import MapKit

// MARK: - CompletedWorkoutDetailView

struct CompletedWorkoutDetailView: View {
    let workout: HKWorkout
    @EnvironmentObject var healthKit: HealthKitManager

    @Environment(\.dismiss) private var dismiss

    // Persisted notes keyed by workout UUID
    @State private var notes: String = ""
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    private var notesKey: String { "workout_notes_\(workout.uuid.uuidString)" }

    // MARK: - Computed display values

    private var label: String { activityTypeLabel(workout.workoutActivityType) }

    private var sportColor: Color { AppTheme.sportColor(for: label) }

    private var routeIcon: String {
        switch workout.workoutActivityType {
        case .swimming:  return "figure.pool.swim"
        case .cycling:   return "figure.outdoor.cycle"
        case .running:   return "figure.run"
        default:         return "figure.strengthtraining.traditional"
        }
    }

    private var distanceMiles: Double {
        workout.totalDistance?.doubleValue(for: .mile()) ?? 0
    }

    private var calories: Double {
        workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
    }

    private var paceLabel: String {
        switch workout.workoutActivityType {
        case .running:  return "Avg Pace"
        case .cycling:  return "Avg Speed"
        case .swimming: return "Pace"
        default:        return "Pace"
        }
    }

    private var paceValue: String {
        switch workout.workoutActivityType {
        case .running:
            guard distanceMiles > 0 else { return "—" }
            let secPerMile = workout.duration / distanceMiles
            let m = Int(secPerMile) / 60
            let s = Int(secPerMile) % 60
            return String(format: "%d:%02d/MI", m, s)
        case .cycling:
            guard workout.duration > 0, distanceMiles > 0 else { return "—" }
            let mph = distanceMiles / (workout.duration / 3600)
            return String(format: "%.1f MPH", mph)
        case .swimming:
            let yards = distanceMiles * 1760
            guard yards > 0 else { return "—" }
            let secPer100yd = workout.duration / (yards / 100)
            let m = Int(secPer100yd) / 60
            let s = Int(secPer100yd) % 60
            return String(format: "%d:%02d/100YD", m, s)
        default:
            return "—"
        }
    }

    private var distanceValue: String {
        distanceMiles > 0.01 ? String(format: "%.2f MI", distanceMiles) : "—"
    }

    private var elevationValue: String {
        if let elevQuantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
            let feet = elevQuantity.doubleValue(for: HKUnit.foot())
            return String(format: "%,d ft", Int(feet))
        }
        return "—"
    }

    // Average HR from zone data: weighted average of zone midpoints
    private var avgHRValue: String {
        guard let zones = healthKit.workoutZones[workout.uuid],
              zones.values.reduce(0, +) > 0 else { return "—" }

        let bounds = healthKit.zoneBoundaries
        let maxHR  = Double(healthKit.maxHeartRate)

        // Zone midpoints (bpm)
        let midpoints: [String: Double] = [
            "Z1": Double(bounds.z2) / 2,
            "Z2": Double(bounds.z2 + bounds.z3) / 2,
            "Z3": Double(bounds.z3 + bounds.z4) / 2,
            "Z4": Double(bounds.z4 + bounds.z5) / 2,
            "Z5": (Double(bounds.z5) + maxHR) / 2
        ]

        // Zones dict holds percentages (0-100); weight each midpoint
        var weightedSum = 0.0
        var totalWeight = 0.0
        for (zone, pct) in zones {
            if let mid = midpoints[zone], pct > 0 {
                weightedSum += mid * pct
                totalWeight += pct
            }
        }
        guard totalWeight > 0 else { return "—" }
        return String(format: "%.0f bpm", weightedSum / totalWeight)
    }

    private var caloriesValue: String {
        calories > 0 ? "\(Int(calories))" : "—"
    }

    // MARK: - Source

    private var isAppCreated: Bool {
        workout.sourceRevision.source.bundleIdentifier == "com.brent.race1"
    }

    private var sourceName: String {
        isAppCreated ? "Race1 Trainer (manual)" : workout.sourceRevision.source.name
    }

    private var sourceIcon: String {
        if isAppCreated { return "square.and.pencil" }
        let name = workout.sourceRevision.source.name.lowercased()
        if name.contains("watch") { return "applewatch" }
        if name.contains("iphone") || name.contains("phone") { return "iphone" }
        return "app.connected.to.app.below.fill"
    }

    // Zone colors matching the 5-zone system
    private let zoneColors: [String: Color] = [
        "Z1": Color(hex: "92CBFD"),
        "Z2": Color(hex: "4CAF50"),
        "Z3": Color(hex: "FFC107"),
        "Z4": Color(hex: "FF9800"),
        "Z5": Color(hex: "F44336")
    ]

    private var hasZoneData: Bool {
        guard let zones = healthKit.workoutZones[workout.uuid] else { return false }
        return zones.values.reduce(0, +) > 0
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapPlaceholder
                statsGrid
                if hasZoneData {
                    zoneBreakdown
                }
                sourceSection
                notesSection
                if isAppCreated {
                    deleteButton
                }
            }
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            notes = UserDefaults.standard.string(forKey: notesKey) ?? ""
        }
        .alert("Delete Workout?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    try? await healthKit.deleteWorkout(workout)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the workout from Health. This cannot be undone.")
        }
    }

    // MARK: - Map

    private var mapPlaceholder: some View {
        WorkoutMapView(workout: workout, healthKit: healthKit)
            .frame(height: 200)
            .ignoresSafeArea(edges: .horizontal)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statCell(label: "Distance",  value: distanceValue)
                Divider().frame(height: 56)
                statCell(label: "Time",      value: formatDuration(workout.duration))
                Divider().frame(height: 56)
                statCell(label: paceLabel,   value: paceValue)
            }

            Divider()

            HStack(spacing: 0) {
                statCell(label: "Elev Gain", value: elevationValue)
                Divider().frame(height: 56)
                statCell(label: "Avg HR",    value: avgHRValue)
                Divider().frame(height: 56)
                statCell(label: "Calories",  value: caloriesValue)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cardCornerRadius)
        .shadow(color: .black.opacity(AppTheme.cardShadowOpacity),
                radius: AppTheme.cardShadowRadius, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    // MARK: - HR Zone Breakdown

    private var zoneBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate Zones")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)

            // Stacked bar
            if let zones = healthKit.workoutZones[workout.uuid] {
                let orderedZones: [(String, Double)] = ["Z1", "Z2", "Z3", "Z4", "Z5"]
                    .compactMap { key in
                        guard let val = zones[key], val > 0 else { return nil }
                        return (key, val)
                    }
                let total = orderedZones.reduce(0) { $0 + $1.1 }

                if total > 0 {
                    // Horizontal stacked bar
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(orderedZones, id: \.0) { (zone, pct) in
                                Rectangle()
                                    .fill(zoneColors[zone] ?? Color.gray)
                                    .frame(width: geo.size.width * CGFloat(pct / total))
                                    .cornerRadius(2)
                            }
                        }
                    }
                    .frame(height: 14)
                    .padding(.horizontal, 16)

                    // Zone legend rows
                    VStack(spacing: 6) {
                        ForEach(orderedZones, id: \.0) { (zone, pct) in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(zoneColors[zone] ?? Color.gray)
                                    .frame(width: 10, height: 10)
                                Text(zone)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(String(format: "%.0f%%", pct))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cardCornerRadius)
        .shadow(color: .black.opacity(AppTheme.cardShadowOpacity),
                radius: AppTheme.cardShadowRadius, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Private Notes")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)

            TextEditor(text: $notes)
                .font(.system(size: 15))
                .frame(minHeight: 90)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .onChange(of: notes) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: notesKey)
                }
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cardCornerRadius)
        .shadow(color: .black.opacity(AppTheme.cardShadowOpacity),
                radius: AppTheme.cardShadowRadius, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        HStack(spacing: 12) {
            Image(systemName: sourceIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Source")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(sourceName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cardCornerRadius)
        .shadow(color: .black.opacity(AppTheme.cardShadowOpacity),
                radius: AppTheme.cardShadowRadius, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemRed))
                    .frame(height: 52)
                if isDeleting {
                    ProgressView().tint(.white)
                } else {
                    Text("Delete Workout")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isDeleting)
        .padding(.horizontal, 16)
    }

    // MARK: - Share text

    private var shareText: String {
        var parts = ["\(label) — \(Formatters.fullDate.string(from: workout.startDate))"]
        if distanceMiles > 0.01 { parts.append(String(format: "Distance: %.2f mi", distanceMiles)) }
        parts.append("Time: \(formatDuration(workout.duration))")
        if paceValue != "—" { parts.append("\(paceLabel): \(paceValue)") }
        if caloriesValue != "—" { parts.append("Calories: \(caloriesValue)") }
        return parts.joined(separator: "\n")
    }
}
