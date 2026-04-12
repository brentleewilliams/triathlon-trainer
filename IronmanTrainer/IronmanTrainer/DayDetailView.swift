import SwiftUI
import HealthKit

// MARK: - Day Detail View
struct DayDetailView: View {
    let day: DayWorkout
    let week: TrainingWeek
    @ObservedObject var healthKit: HealthKitManager
    @State private var note: String = ""
    @Environment(\.dismiss) var dismiss

    private var noteKey: String {
        "workout_note_w\(week.weekNumber)_\(day.day)_\(day.type)"
    }

    var dayName: String {
        let dayMap = ["Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday",
                      "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"]
        return dayMap[day.day] ?? day.day
    }

    var navTitle: String {
        return "\(dayName), \(Formatters.shortDate.string(from: getDateForDay()))"
    }

    var matchingHealthKitWorkouts: [HKWorkout] {
        let workoutType = extractWorkoutTypeFromString(day.type)
        let targetDate = getDateForDay()

        return healthKit.workouts.filter { hkWorkout in
            let calendar = Calendar.current
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let targetStartOfDay = calendar.startOfDay(for: targetDate)

            return workoutDate == targetStartOfDay &&
                   workoutTypeMatchesActivityType(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType)
        }
    }

    var matchingBikeWorkouts: [HKWorkout] {
        let targetDate = getDateForDay()
        return healthKit.workouts.filter { hkWorkout in
            let calendar = Calendar.current
            return calendar.startOfDay(for: hkWorkout.startDate) == calendar.startOfDay(for: targetDate) &&
                   hkWorkout.workoutActivityType == .cycling
        }
    }

    var matchingRunWorkouts: [HKWorkout] {
        let targetDate = getDateForDay()
        return healthKit.workouts.filter { hkWorkout in
            let calendar = Calendar.current
            return calendar.startOfDay(for: hkWorkout.startDate) == calendar.startOfDay(for: targetDate) &&
                   hkWorkout.workoutActivityType == .running
        }
    }

    func parseBrickDetail(from notes: String) -> WorkoutDayRows.BrickSplit? {
        let pattern = #"[Bb]ike\s+([\d:]+\s*(?:min)?)\s*(?:\([^)]*\))?\s*(?:[@Z][\w\s\-]*)?\s*\+\s*(?:[Bb]rick\s+)?(?:mini-brick\s+)?[Rr]un\s+([\d:]+\s*(?:min)?)\s*(?:[@(]\s*([\d:]+(?:-[\d:]+)?\s*pace))?"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)) {
            let bikeTime = String(notes[Range(match.range(at: 1), in: notes)!]).trimmingCharacters(in: .whitespaces)
            let runTime = String(notes[Range(match.range(at: 2), in: notes)!]).trimmingCharacters(in: .whitespaces)
            var runPace: String? = nil
            if match.range(at: 3).location != NSNotFound,
               let paceRange = Range(match.range(at: 3), in: notes) {
                runPace = String(notes[paceRange]).trimmingCharacters(in: .whitespaces)
            }
            return WorkoutDayRows.BrickSplit(bikeDuration: bikeTime, runDuration: runTime, runPace: runPace)
        }
        return nil
    }

    func getDateForDay() -> Date {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayIndex = dayOrder.firstIndex(of: day.day) ?? 0

        let calendar = Calendar.current
        let weekStart = week.startDate
        let daysToAdd = dayIndex

        return calendar.date(byAdding: .day, value: daysToAdd, to: weekStart) ?? weekStart
    }

    func getWorkoutTypeName(_ workoutType: HKWorkoutActivityType) -> String {
        switch workoutType {
        case .cycling:
            return "Cycling"
        case .swimming:
            return "Swimming"
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return "Strength"
        case .hiking:
            return "Hiking"
        default:
            return "Workout"
        }
    }

    struct DrillInfo {
        let title: String
        let items: [(name: String, tip: String)]
    }

    func drillsReferenced(in notes: String) -> DrillInfo? {
        if notes.contains("Drill Set A") {
            return DrillInfo(title: "Drill Set A — Catch Focus", items: [
                (name: "Catch-Up (4x50)", tip: "One hand stays extended until the other catches up. Focus on hand entry timing and front-quadrant catch."),
                (name: "Fingertip Drag (4x50)", tip: "Drag fingertips along the water during recovery. Builds high elbow recovery and shoulder mobility.")
            ])
        } else if notes.contains("Drill Set B") {
            return DrillInfo(title: "Drill Set B — Kick & Bilateral", items: [
                (name: "6-Kick Switch (4x50)", tip: "Six kicks on your side, then switch with one stroke. Builds kick-to-stroke coordination and rotation."),
                (name: "Side Kick (4x50)", tip: "Kick on your side, bottom arm extended, top arm at hip. Develops balance and bilateral breathing.")
            ])
        } else if notes.contains("Drill Set C") {
            return DrillInfo(title: "Drill Set C — Advanced Stroke", items: [
                (name: "Single-Arm (4x50 alternating)", tip: "Swim with one arm, other at your side. Isolates each arm's pull pattern to find imbalances."),
                (name: "3-Stroke Glide (4x50)", tip: "Three strokes then glide in streamline. Emphasizes distance per stroke and catch power.")
            ])
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Planned Workout
                    let isBrickDetail = day.type.lowercased().contains("brick") || day.type.lowercased().contains("race sim")
                    let brickSplit = isBrickDetail ? (day.notes.flatMap { parseBrickDetail(from: $0) }) : nil

                    if isBrickDetail, let split = brickSplit {
                        // Brick: two exercise sections
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(day.type.lowercased().contains("race sim") ? "Race Sim" : "Brick")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.orange)
                                    .cornerRadius(6)
                                Text("Total: \(day.duration)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                let bikeOk = matchingBikeWorkouts.count > 0
                                let runOk = matchingRunWorkouts.count > 0
                                if bikeOk && runOk {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }

                            // Bike leg
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\u{1F6B4} Bike")
                                    .font(.headline)
                                HStack {
                                    Text("Duration:")
                                    Spacer()
                                    Text(split.bikeDuration)
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Zone:")
                                    Spacer()
                                    Text(day.zone)
                                        .fontWeight(.semibold)
                                }
                                if matchingBikeWorkouts.count > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("Completed: \(Int(matchingBikeWorkouts[0].duration / 60))min")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray5))
                            .cornerRadius(8)

                            // Run leg
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\u{1F3C3} Run")
                                    .font(.headline)
                                HStack {
                                    Text("Duration:")
                                    Spacer()
                                    Text(split.runDuration)
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Target:")
                                    Spacer()
                                    Text(split.runPace ?? day.zone)
                                        .fontWeight(.semibold)
                                }
                                if matchingRunWorkouts.count > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("Completed: \(Int(matchingRunWorkouts[0].duration / 60))min")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    } else {
                        // Standard single workout
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Planned Workout")
                                    .font(.headline)
                                Spacer()
                                if matchingHealthKitWorkouts.count > 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }

                            if day.type.contains("Rest") {
                                Text("Rest Day")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Type:")
                                        Spacer()
                                        Text(day.type)
                                            .fontWeight(.semibold)
                                    }
                                    HStack {
                                        Text("Duration:")
                                        Spacer()
                                        Text(day.duration)
                                            .fontWeight(.semibold)
                                    }
                                    HStack {
                                        Text("Zone:")
                                        Spacer()
                                        Text(day.zone)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    // Workout Notes
                    if let notes = day.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Workout Details", systemImage: "doc.text")
                                .font(.headline)
                            Text(notes)
                                .font(.body)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)

                        // Drill Set Info
                        if let drills = drillsReferenced(in: notes) {
                            NavigationLink {
                                DrillsDetailView()
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label(drills.title, systemImage: "figure.pool.swim")
                                            .font(.headline)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    ForEach(drills.items, id: \.name) { drill in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(drill.name)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Text(drill.tip)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.cyan.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Nutrition Target
                    if let nutrition = day.nutritionTarget {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Nutrition Target", systemImage: "fork.knife")
                                .font(.headline)
                            Text(nutrition)
                                .font(.body)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Weather - show for past days and up to 7 days ahead
                    let dayDate = getDateForDay()
                    let calendar = Calendar.current
                    let today = Date()
                    let daysUntil = calendar.dateComponents([.day], from: today, to: dayDate).day ?? 0
                    let isPastDay = daysUntil < 0

                    if isPastDay || daysUntil <= 7 {
                        let weather = WeatherForecast.forecast(for: dayDate)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(isPastDay ? "Weather" : "Expected Weather")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Conditions:")
                                    Spacer()
                                    Text(weather.condition)
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Temperature:")
                                    Spacer()
                                    Text("\(weather.lowTemp)\u{00B0}F - \(weather.highTemp)\u{00B0}F")
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Wind:")
                                    Spacer()
                                    Text("\(weather.windMph) mph")
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Humidity:")
                                    Spacer()
                                    Text("\(weather.humidity)%")
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBlue).opacity(0.1))
                        .cornerRadius(12)
                    }

                    // HealthKit Workouts
                    if !matchingHealthKitWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Completed Workouts")
                                .font(.headline)

                            ForEach(matchingHealthKitWorkouts, id: \.uuid) { workout in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(getWorkoutTypeName(workout.workoutActivityType))
                                        .fontWeight(.semibold)
                                    HStack {
                                        Text("Duration:")
                                        Spacer()
                                        Text(String(format: "%.0f", workout.duration / 60) + " min")
                                    }
                                    .font(.caption)
                                    if let energy = workout.totalEnergyBurned {
                                        HStack {
                                            Text("Calories:")
                                            Spacer()
                                            Text(String(format: "%.0f", energy.doubleValue(for: .kilocalorie())) + " kcal")
                                        }
                                        .font(.caption)
                                    }
                                }
                                .padding(10)
                                .background(Color(.systemGreen).opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    } else if !day.type.contains("Rest") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.orange)
                                Text("No completed workouts")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    // Notes Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: $note)
                            .frame(height: 120)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                note = UserDefaults.standard.string(forKey: noteKey) ?? ""
            }
            .onChange(of: note) { _, newValue in
                if newValue.isEmpty {
                    UserDefaults.standard.removeObject(forKey: noteKey)
                } else {
                    UserDefaults.standard.set(newValue, forKey: noteKey)
                }
            }
        }
    }
}
