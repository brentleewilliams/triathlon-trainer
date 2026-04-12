import SwiftUI
import HealthKit

// MARK: - Workout Day Rows
struct WorkoutDayRows: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView
    let week: TrainingWeek?
    @Binding var draggedWorkout: DayWorkout?
    @Binding var draggedFromDay: String?
    var hideHeader: Bool = false
    let selectedWeek: Int

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var dayDate: String {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: mondayOfWeek(weekStartDate)) ?? weekStartDate
        return Formatters.monthDay.string(from: date)
    }

    var isDayInPast: Bool {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: mondayOfWeek(weekStartDate)) ?? weekStartDate
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }

    var trainingPlan: TrainingPlanManager {
        parent.trainingPlan
    }

    func isWorkoutCompleted(_ workout: DayWorkout) -> Bool {
        parent.isWorkoutCompleted(workout)
    }

    func workoutEmoji(_ type: String) -> String {
        // Extract any emojis already embedded at the start of the type string
        var emojis = ""
        for char in type {
            if char.isLetter { break }
            if char.unicodeScalars.allSatisfy({ $0.properties.isEmoji }) {
                emojis.append(char)
            }
        }
        if !emojis.isEmpty { return emojis }

        // Fallback for type strings without embedded emojis
        let t = type.lowercased()
        if t.contains("swim") { return "🏊" }
        if t.contains("brick") { return "🚴🏃" }
        if t.contains("bike") || t.contains("cycl") { return "🚴" }
        if t.contains("run") { return "🏃" }
        if t.contains("strength") || t.contains("gym") { return "💪" }
        if t.contains("rest") || t.contains("recover") { return "😴" }
        return "🏋️"
    }

    /// Strip any leading emoji/symbol characters so the hardcoded plan's
    /// embedded emojis don't double up with workoutEmoji().
    func strippedType(_ type: String) -> String {
        if let idx = type.firstIndex(where: { $0.isLetter }) {
            return String(type[idx...])
        }
        return type
    }

    var body: some View {
        let date = Calendar.current.date(byAdding: .day, value: Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0, to: mondayOfWeek(weekStartDate)) ?? weekStartDate

        // Show weather for past days and up to 7 days ahead
        let calendar = Calendar.current
        let today = Date()
        let daysUntil = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        let showWeather = daysUntil < 0 || daysUntil <= 7

        return VStack(alignment: .leading, spacing: 8) {
            // Day header - separate from cards
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(dayGroup.day)
                        .fontWeight(.bold)
                    Text(dayDate)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(width: 50)

                if showWeather {
                    let weather = WeatherForecast.forecast(for: date)
                    HStack(spacing: 4) {
                        Text(weather.icon)
                            .font(.title3)
                        Text("\(weather.highTemp)\u{00B0}")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Workout cards - draggable as a group
            VStack(spacing: 8) {
                let isMultiWorkoutDay = dayGroup.workouts.filter { !$0.type.contains("Rest") }.count > 1
                ForEach(Array(dayGroup.workouts.enumerated()), id: \.element.duration) { index, workout in
                    let isBrick = workout.type.lowercased().contains("brick") || workout.type.lowercased().contains("race sim")
                    NavigationLink(destination: DayDetailView(day: workout, week: week ?? TrainingWeek(weekNumber: 1, phase: "", startDate: Date(), endDate: Date(), workouts: []), healthKit: parent.healthKit)) {
                        VStack(alignment: .leading, spacing: 0) {
                            if isBrick, let notes = workout.notes, let split = parseBrickComponents(from: notes) {
                                // Brick label header
                                HStack {
                                    Text(workout.type.lowercased().contains("race sim") ? "Race Sim" : "Brick")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .cornerRadius(4)
                                    Text(workout.duration)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    let brickCompliance = brickComplianceLevel(for: workout, on: date)
                                    Image(systemName: brickCompliance.iconName)
                                        .foregroundColor(brickCompliance.color)
                                        .font(.title3)
                                }
                                .padding(.bottom, 6)
                                // Bike leg
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\u{1F6B4} Bike")
                                            .fontWeight(.semibold)
                                        Text("\(split.bikeDuration) \u{2022} \(workout.zone)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    let bikeMatch = findMatchingWorkout(type: "Bike", on: date)
                                    if let bikeWorkout = bikeMatch {
                                        Text("\u{2192} \(Int(bikeWorkout.duration / 60))min")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }
                                .padding(.bottom, 6)
                                Divider()
                                // Run leg
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\u{1F3C3} Run")
                                            .fontWeight(.semibold)
                                        Text("\(split.runDuration) \u{2022} \(split.runPace ?? workout.zone)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    let runMatch = findMatchingWorkout(type: "Run", on: date)
                                    if let runWorkout = runMatch {
                                        Text("\u{2192} \(Int(runWorkout.duration / 60))min")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }
                                .padding(.top, 6)
                            } else {
                                // Standard workout card
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            if isMultiWorkoutDay && !workout.type.contains("Rest") {
                                                Text(index == 0 ? "AM" : "PM")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color(.systemGray2))
                                                    .cornerRadius(4)
                                            }
                                            Text(workoutEmoji(workout.type) + " " + strippedType(workout.type))
                                                .fontWeight(.semibold)
                                        }
                                        Text("\(workout.duration) \u{2022} \(workout.zone)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    let compliance = calculateCompliance(for: workout, on: date, from: parent.healthKit.workouts)
                                    if let actualMin = compliance.actualDurationMinutes {
                                        Text("\u{2192} \(Int(actualMin))min")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Image(systemName: compliance.level.iconName)
                                        .foregroundColor(compliance.level.color)
                                        .font(.title3)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)

            // Threshold warning for missed workouts
            let hasMissedWorkout = dayGroup.workouts.contains { workout in
                workout.type.lowercased() != "rest" &&
                calculateCompliance(for: workout, on: date, from: parent.healthKit.workouts).level == .missed
            }
            if hasMissedWorkout {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Missed workout")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
            }
        }
        // Opacity feedback when dragging this entire day
        .opacity(draggedFromDay == dayGroup.day ? 0.5 : 1.0)
        // Drag the entire day as one unit (disabled for past days)
        .onDrag {
            let pastDay = self.isDayInPast
            guard !pastDay else {
                print("[DRAG] Blocked: \(dayGroup.day) is in the past")
                return NSItemProvider()
            }
            draggedFromDay = dayGroup.day
            draggedWorkout = nil
            print("[DRAG] Started dragging day=\(dayGroup.day), draggedFromDay is now=\(draggedFromDay ?? "nil")")
            // Auto-clear after 2 seconds if drop never completes (cancelled drag)
            let dragDay = dayGroup.day
            let binding = $draggedFromDay
            let workoutBinding = $draggedWorkout
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if binding.wrappedValue == dragDay {
                    binding.wrappedValue = nil
                    workoutBinding.wrappedValue = nil
                    print("[DRAG] Auto-cleared stale drag state for \(dragDay)")
                }
            }
            return NSItemProvider(object: dayGroup.day as NSString)
        }
        .onDrop(of: [.plainText], delegate: WorkoutDropDelegate(
            targetDay: dayGroup.day,
            selectedWeek: selectedWeek,
            trainingPlan: trainingPlan,
            getDraggedFromDay: {
                draggedFromDay
            },
            isCompleted: { dayToCheck in
                guard let week = parent.trainingPlan.getWeek(selectedWeek) else { return false }
                let workoutsForDay = week.workouts.filter { $0.day == dayToCheck }
                return workoutsForDay.allSatisfy { parent.isWorkoutCompleted($0) }
            },
            clearDragState: {
                draggedFromDay = nil
                draggedWorkout = nil
                print("[DROP] Drag state cleared")
            }
        ))
    }

    struct BrickSplit {
        let bikeDuration: String
        let runDuration: String
        let runPace: String?
    }

    func parseBrickComponents(from notes: String) -> BrickSplit? {
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
            return BrickSplit(bikeDuration: bikeTime, runDuration: runTime, runPace: runPace)
        }
        return nil
    }

    func extractBrickSplit(from notes: String) -> String? {
        guard let split = parseBrickComponents(from: notes) else { return nil }
        return "Bike \(split.bikeDuration) + Run \(split.runDuration)"
    }

    func findMatchingWorkout(type: String, on date: Date) -> HKWorkout? {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        let hkType: HKWorkoutActivityType = type == "Bike" ? .cycling : .running
        return parent.healthKit.workouts.first { hkWorkout in
            calendar.startOfDay(for: hkWorkout.startDate) == targetDay &&
            hkWorkout.workoutActivityType == hkType
        }
    }

    func brickComplianceLevel(for workout: DayWorkout, on date: Date) -> ComplianceLevel {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.startOfDay(for: date)
        if targetDay > today { return .future }

        let hasBike = findMatchingWorkout(type: "Bike", on: date) != nil
        let hasRun = findMatchingWorkout(type: "Run", on: date) != nil

        if hasBike && hasRun { return .green }
        if targetDay == today { return .future }
        if hasBike || hasRun { return .under }  // Did one leg but not both
        return .missed
    }
}
