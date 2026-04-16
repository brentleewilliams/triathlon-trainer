import SwiftUI

// MARK: - Course Detail View (§4.6.2)
//
// Tap-through from HomeView's race countdown banner. Shows:
//  - Course overview (venue, distance, terrain, elevation)
//  - Altitude comparison (training vs race)
//  - Phase-appropriate preparation checklist
//  - Race-week weather (only when within 7-day window)

struct CourseDetailView: View {
    @ObservedObject private var service = RaceCourseService.shared
    @Environment(\.dismiss) private var dismiss

    /// Days from today to race day. Falls back to 0 when no profile is loaded.
    var daysToRace: Int {
        guard let profile = service.currentProfile else { return 0 }
        return Calendar.current.dateComponents([.day], from: Date(), to: profile.raceDate).day ?? 0
    }

    /// Weeks from today to race day, rounded to nearest even (no negatives).
    var weeksToRace: Int {
        max(0, Int((Double(daysToRace) / 7.0).rounded(.toNearestOrEven)))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let profile = service.currentProfile {
                    content(profile: profile)
                } else {
                    ContentUnavailableView(
                        "No course data",
                        systemImage: "mappin.slash",
                        description: Text("Course profile not yet loaded.")
                    )
                }
            }
            .navigationTitle("Race Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if service.currentProfile == nil {
                _ = service.loadDefaultProfile()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(profile: RaceCourseProfile) -> some View {
        List {
            overviewSection(profile)
            altitudeSection(profile)
            prepChecklistSection(profile)
            if daysToRace >= 0 && daysToRace <= 7 {
                weatherSection(profile)
            }
        }
    }

    // MARK: - Overview

    private func overviewSection(_ profile: RaceCourseProfile) -> some View {
        Section("Course Overview") {
            row("Race", profile.raceName)
            row("Venue", profile.venue)
            row("Date", Formatters.fullDate.string(from: profile.raceDate))
            row("Distance", profile.totalDistanceDescription)
            row("Terrain", profile.terrain.rawValue.capitalized)
            row("Elevation gain", "\(profile.totalElevationGainFeet) ft")
        }
    }

    // MARK: - Altitude

    private func altitudeSection(_ profile: RaceCourseProfile) -> some View {
        let ctx = service.getAltitudeAdjustment(
            trainingElevation: service.athleteEnvironment.trainingElevationFeet,
            raceElevation: profile.venueElevationFeet
        )
        return Section("Altitude Comparison") {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Training")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(service.athleteEnvironment.trainingElevationFeet) ft")
                        .font(.title3.monospacedDigit())
                        .fontWeight(.semibold)
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text("Race")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(profile.venueElevationFeet) ft")
                        .font(.title3.monospacedDigit())
                        .fontWeight(.semibold)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            Text(ctx.summary)
                .font(.subheadline)
            Text(ctx.acclimationRecommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Prep Checklist (phase-aware)

    private func prepChecklistSection(_ profile: RaceCourseProfile) -> some View {
        Section("Preparation") {
            if weeksToRace > 5 {
                bullet("Build base fitness — course-aware emphasis on \(profile.terrain.rawValue) terrain.")
                bullet("Gather gear list; no race-day-specific prep needed yet.")
                bullet("No race anxiety — course is background context right now.")
            } else if weeksToRace > 2 {
                bullet("Heat acclimation: 20-30 min sauna or hot-bath post-workout, 3-5x/week.")
                bullet("Race-pace sessions calibrated to altitude-adjusted HR zones.")
                bullet("Open-water simulation if access available (sighting drills).")
                bullet("Nutrition rehearsal: practice race-day fueling on long sessions.")
            } else {
                bullet("Travel: arrive 2 days early to adjust to race elevation.")
                bullet("Taper is underway — keep intensity brief, volume low.")
                bullet("Monitor race-day forecast and adjust hydration plan.")
                bullet("Final gear check + nutrition pack.")
            }
        }
    }

    // MARK: - Weather (within 7 days)

    private func weatherSection(_ profile: RaceCourseProfile) -> some View {
        Section("Race-Week Weather") {
            HStack {
                Image(systemName: "thermometer.sun")
                    .foregroundStyle(.orange)
                Text("High \(profile.expectedWeather.tempHighF)°F")
                Spacer()
                Image(systemName: "thermometer.snowflake")
                    .foregroundStyle(.blue)
                Text("Low \(profile.expectedWeather.tempLowF)°F")
            }
            .font(.subheadline)
            Text(profile.expectedWeather.conditionsSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Based on historical averages. v2 will pull actual forecast.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.blue)
            Text(text)
                .font(.subheadline)
        }
    }
}
