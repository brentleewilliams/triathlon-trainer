import SwiftUI
import HealthKit

// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @State private var selectedWeek: Int = 1
    @State private var hasAppearedOnce = false
    @State private var draggedFromDay: String?
    @State private var draggedWorkout: DayWorkout?

    var currentWeek: TrainingWeek? {
        trainingPlan.getWeek(selectedWeek)
    }

    var formattedDateRange: String {
        guard let week = currentWeek else { return "" }
        let startStr = Formatters.shortDate.string(from: week.startDate)
        let endStr = Formatters.shortDate.string(from: week.endDate)
        return "\(startStr) - \(endStr), 2026"
    }

    var daysUntilRace: Int {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 19
        guard let raceDate = calendar.date(from: comps) else { return 0 }
        let today = calendar.startOfDay(for: Date())
        let race = calendar.startOfDay(for: raceDate)
        return calendar.dateComponents([.day], from: today, to: race).day ?? 0
    }

    var currentPhase: String {
        switch selectedWeek {
        case 1...4: return "Base Building"
        case 5...8: return "Build Phase"
        case 9...12: return "Peak Training"
        case 13...15: return "Race Specific"
        case 16...17: return "Taper"
        default: return "Training"
        }
    }

    var completionCounts: (total: Int, completed: Int) {
        guard let week = currentWeek else { return (0, 0) }

        let calendar = Calendar.current
        let todayStartOfDay = calendar.startOfDay(for: Date())
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let grouped = Dictionary(grouping: week.workouts, by: { $0.day })

        var total = 0
        var completed = 0

        for day in dayOrder {
            guard let dayWorkouts = grouped[day] else { continue }
            let sampleWorkout = dayWorkouts[0]
            let dayDate = getDateForDay(sampleWorkout)
            let dayStartOfDay = calendar.startOfDay(for: dayDate)
            guard dayStartOfDay <= todayStartOfDay else { continue }

            if let restWorkout = dayWorkouts.first(where: { $0.type.contains("Rest") }) {
                if isRestDayCompleted(for: restWorkout) {
                    total += 1
                    completed += 1
                }
            } else {
                for workout in dayWorkouts {
                    total += 1
                    if isWorkoutCompleted(workout) {
                        completed += 1
                    }
                }
            }
        }

        return (total, completed)
    }

    var todaysTotalWorkouts: Int { completionCounts.total }
    var todaysCompletedWorkouts: Int { completionCounts.completed }

    var weeklyComplianceText: String? {
        guard let week = currentWeek else { return nil }
        if let pct = calculateWeekCompliance(week: week, hkWorkouts: healthKit.workouts) {
            return "\(Int(pct))%"
        }
        return nil
    }

    var workoutsByDay: [(day: String, workouts: [DayWorkout])] {
        guard let week = currentWeek else { return [] }

        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let grouped = Dictionary(grouping: week.workouts, by: { $0.day })

        return dayOrder.compactMap { day in
            guard let workouts = grouped[day] else { return nil }
            return (day: day, workouts: workouts)
        }
    }

    func isWorkoutCompleted(_ workout: DayWorkout) -> Bool {
        let isBrick = workout.type.lowercased().contains("brick") || workout.type.lowercased().contains("race sim")
        let targetDate = getDateForDay(workout)

        if isBrick {
            // Brick requires both bike AND run on the same day
            let calendar = Calendar.current
            let targetDay = calendar.startOfDay(for: targetDate)
            let hasBike = healthKit.workouts.contains { hkWorkout in
                calendar.startOfDay(for: hkWorkout.startDate) == targetDay &&
                hkWorkout.workoutActivityType == .cycling
            }
            let hasRun = healthKit.workouts.contains { hkWorkout in
                calendar.startOfDay(for: hkWorkout.startDate) == targetDay &&
                hkWorkout.workoutActivityType == .running
            }
            return hasBike && hasRun
        }

        // Standard workout: check type + duration tolerance
        let workoutType = extractWorkoutType(from: workout.type)
        let plannedDurationMinutes = parseDuration(workout.duration)
        let toleranceMinutes = 15

        return healthKit.workouts.contains { hkWorkout in
            let calendar = Calendar.current
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let targetStartOfDay = calendar.startOfDay(for: targetDate)

            guard workoutDate == targetStartOfDay &&
                   workoutTypeMatches(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType) else {
                return false
            }

            if let plannedMin = plannedDurationMinutes {
                let hkDurationMinutes = Int(hkWorkout.duration / 60)
                let durationDiff = abs(hkDurationMinutes - plannedMin)
                return durationDiff <= toleranceMinutes
            }

            return true
        }
    }

    func isRestDayCompleted(for workout: DayWorkout) -> Bool {
        // Rest day is "completed" if no non-yoga/walking workouts were done
        let targetDate = getDateForDay(workout)
        let calendar = Calendar.current
        let targetStartOfDay = calendar.startOfDay(for: targetDate)

        return !healthKit.workouts.contains { hkWorkout in
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let isTargetDay = workoutDate == targetStartOfDay

            // Exclude yoga and walking
            let isYogaOrWalking = hkWorkout.workoutActivityType == .yoga ||
                                   hkWorkout.workoutActivityType == .walking

            return isTargetDay && !isYogaOrWalking
        }
    }

    func getDateForDay(_ workout: DayWorkout) -> Date {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayIndex = dayOrder.firstIndex(of: workout.day) ?? 0

        let calendar = Calendar.current
        let weekStart = currentWeek?.startDate ?? Date()
        let daysToAdd = dayIndex

        return calendar.date(byAdding: .day, value: daysToAdd, to: weekStart) ?? weekStart
    }

    func workoutTypeMatches(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool {
        let planned = plannedType.lowercased()
        switch healthKitType {
        case .cycling:
            return planned == "bike"
        case .swimming:
            return planned == "swim"
        case .running:
            return planned == "run"
        case .walking:
            return planned == "walk"
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return planned == "strength"
        case .hiking:
            return planned == "hike"
        default:
            return false
        }
    }

    func extractWorkoutType(from typeString: String) -> String {
        if typeString.contains("\u{1F6B4}") { return "Bike" }
        if typeString.contains("\u{1F3CA}") { return "Swim" }
        if typeString.contains("\u{1F3C3}") { return "Run" }
        if typeString.contains("\u{1F3C1}") { return "Run" }
        let lower = typeString.lowercased()
        if lower.contains("strength") { return "Strength" }
        if lower.contains("hike") || lower.contains("hiking") { return "Hike" }
        return typeString
    }

    func parseDuration(_ durationStr: String) -> Int? {
        // Parse "60 min" -> 60, "1.5 hrs" -> 90, "1:00" -> 60, "1,800yd" -> nil, "Rest" -> nil
        let lowercased = durationStr.lowercased()

        // Skip distance-based or rest days
        if lowercased.contains("yd") || lowercased.contains("rest") {
            return nil
        }

        // Handle H:MM format first (e.g., "1:00" -> 60 minutes, "1:45" -> 105 minutes)
        if let regex = try? NSRegularExpression(pattern: "^(\\d+):(\\d{2})", options: []) {
            if let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased)) {
                if let hoursRange = Range(match.range(at: 1), in: lowercased),
                   let minutesRange = Range(match.range(at: 2), in: lowercased),
                   let hours = Int(lowercased[hoursRange]),
                   let minutes = Int(lowercased[minutesRange]) {
                    return hours * 60 + minutes
                }
            }
        }

        // Handle "number min/hr" format (with or without space)
        if let regex = try? NSRegularExpression(pattern: "([\\d.]+)\\s*(min|hr)", options: []) {
            if let match = regex.firstMatch(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased)) {
                if let numberRange = Range(match.range(at: 1), in: lowercased),
                   let unitRange = Range(match.range(at: 2), in: lowercased),
                   let value = Double(lowercased[numberRange]) {
                    let unit = String(lowercased[unitRange])
                    if unit == "hr" {
                        return Int(value * 60)
                    } else if unit == "min" {
                        return Int(value)
                    }
                }
            }
        }

        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Race Countdown Banner
                HStack {
                    if daysUntilRace > 0 {
                        HStack(spacing: 4) {
                            Text("\(daysUntilRace)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("DAYS TO RACE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                    } else if daysUntilRace == 0 {
                        Text("RACE DAY!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    } else {
                        Text("RACE COMPLETE")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Text("Week \(selectedWeek) \u{00B7} \(currentPhase)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        Task { await healthKit.syncWorkouts() }
                    } label: {
                        if healthKit.isSyncing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .disabled(healthKit.isSyncing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(10)

                // Week Navigation Header with Completion Count and Undo
                HStack {
                    WeekNavigationHeader(selectedWeek: $selectedWeek, completionText: "\(todaysCompletedWorkouts)/\(todaysTotalWorkouts)", complianceText: weeklyComplianceText)

                    if trainingPlan.previousPlanVersion != nil {
                        Button(action: {
                            _ = trainingPlan.rollbackToPreviousVersion()
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    }
                }

                // Sync Error Display
                if let error = healthKit.syncError {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Sync Error")
                                .font(.headline)
                        }
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                ScrollView {
                    DayGroupsView(
                        dayGroups: workoutsByDay,
                        week: currentWeek,
                        healthKit: healthKit,
                        parent: self,
                        draggedWorkout: $draggedWorkout,
                        draggedFromDay: $draggedFromDay,
                        selectedWeek: selectedWeek
                    )
                }
                .onDrop(of: [.plainText], isTargeted: nil) { _ in
                    print("[DROP] ScrollView catch-all onDrop fired, clearing drag state")
                    draggedFromDay = nil
                    draggedWorkout = nil
                    return false
                }
                .onTapGesture {
                    if draggedFromDay != nil {
                        print("[DRAG] Tap detected, clearing draggedFromDay=\(draggedFromDay ?? "nil")")
                        draggedFromDay = nil
                        draggedWorkout = nil
                    }
                }
                .onChange(of: selectedWeek) { _, _ in
                    draggedFromDay = nil
                    draggedWorkout = nil
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < -50 && selectedWeek < 17 {
                            withAnimation { selectedWeek += 1 }
                        } else if value.translation.width > 50 && selectedWeek > 1 {
                            withAnimation { selectedWeek -= 1 }
                        }
                    }
            )
            .onAppear {
                if !hasAppearedOnce {
                    selectedWeek = trainingPlan.currentWeekNumber
                    hasAppearedOnce = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToWeek)) { notification in
                if let week = notification.userInfo?["week"] as? Int {
                    withAnimation { selectedWeek = week }
                }
            }
        }
    }
}

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
        let workoutType = extractWorkoutType(from: day.type)
        let targetDate = getDateForDay()

        return healthKit.workouts.filter { hkWorkout in
            let calendar = Calendar.current
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let targetStartOfDay = calendar.startOfDay(for: targetDate)

            return workoutDate == targetStartOfDay &&
                   workoutTypeMatches(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType)
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

    func workoutTypeMatches(plannedType: String, healthKitType: HKWorkoutActivityType) -> Bool {
        let planned = plannedType.lowercased()
        switch healthKitType {
        case .cycling:
            return planned == "bike"
        case .swimming:
            return planned == "swim"
        case .running:
            return planned == "run"
        case .walking:
            return planned == "walk"
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return planned == "strength"
        case .hiking:
            return planned == "hike"
        default:
            return false
        }
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

    func extractWorkoutType(from typeString: String) -> String {
        if typeString.contains("\u{1F6B4}") { return "Bike" }
        if typeString.contains("\u{1F3CA}") { return "Swim" }
        if typeString.contains("\u{1F3C3}") { return "Run" }
        if typeString.contains("\u{1F3C1}") { return "Run" }
        let lower = typeString.lowercased()
        if lower.contains("strength") { return "Strength" }
        if lower.contains("hike") || lower.contains("hiking") { return "Hike" }
        return typeString
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

struct WeekdayWorkoutRow: View {
    let day: String
    let type: String
    let duration: String
    let zone: String
    var isCompleted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(day)
                .fontWeight(.bold)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(type)
                    .fontWeight(.semibold)
                Text("\(duration) \u{2022} \(zone)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Day Groups View
struct DayGroupsView: View {
    let dayGroups: [(day: String, workouts: [DayWorkout])]
    let week: TrainingWeek?
    @ObservedObject var healthKit: HealthKitManager
    let parent: HomeView
    @Binding var draggedWorkout: DayWorkout?
    @Binding var draggedFromDay: String?
    let selectedWeek: Int

    var body: some View {
        if let week = week, !dayGroups.isEmpty {
            VStack(spacing: 12) {
                ForEach(dayGroups, id: \.day) { dayGroup in
                    DayRowView(
                        dayGroup: dayGroup,
                        weekStartDate: week.startDate,
                        parent: parent,
                        draggedWorkout: $draggedWorkout,
                        draggedFromDay: $draggedFromDay,
                        week: week,
                        healthKit: healthKit,
                        selectedWeek: selectedWeek
                    )
                }
            }
            .padding()
        } else {
            VStack(spacing: 12) {
                Text("No workouts planned for this week")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
    }
}

// MARK: - Day Row View
struct DayRowView: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView
    @Binding var draggedWorkout: DayWorkout?
    @Binding var draggedFromDay: String?
    let week: TrainingWeek?
    @ObservedObject var healthKit: HealthKitManager
    let selectedWeek: Int

    var isRestDay: Bool {
        dayGroup.workouts.allSatisfy { $0.type.contains("Rest") }
    }

    var body: some View {
        if isRestDay {
            RestDayRow(dayGroup: dayGroup, weekStartDate: weekStartDate, parent: parent)
        } else {
            // Workouts without any NavigationLink wrapping - test if drag works
            WorkoutDayRows(
                dayGroup: dayGroup,
                weekStartDate: weekStartDate,
                parent: parent,
                week: week,
                draggedWorkout: $draggedWorkout,
                draggedFromDay: $draggedFromDay,
                hideHeader: false,
                selectedWeek: selectedWeek
            )
        }
    }
}

// MARK: - Rest Day Row
struct RestDayRow: View {
    let dayGroup: (day: String, workouts: [DayWorkout])
    let weekStartDate: Date
    let parent: HomeView

    private static let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var dayDate: String {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate
        return Formatters.monthDay.string(from: date)
    }

    var body: some View {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate

        // Show weather for past days and up to 7 days ahead
        let calendar = Calendar.current
        let today = Date()
        let daysUntil = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        let showWeather = daysUntil < 0 || daysUntil <= 7

        return VStack(alignment: .leading, spacing: 8) {
            // Day header - separate from card
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

            // Rest card
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("\u{1F6CC}")
                        .font(.title3)
                    Text("Rest")
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                Spacer()

                if parent.isRestDayCompleted(for: dayGroup.workouts[0]) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal, 12)
        }
    }
}

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
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate
        return Formatters.monthDay.string(from: date)
    }

    var isDayInPast: Bool {
        let offset = Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }

    var trainingPlan: TrainingPlanManager {
        parent.trainingPlan
    }

    func isWorkoutCompleted(_ workout: DayWorkout) -> Bool {
        parent.isWorkoutCompleted(workout)
    }

    func workoutEmoji(_ type: String) -> String {
        let t = type.lowercased()
        if t.contains("swim") { return "🏊" }
        if t.contains("brick") || (t.contains("bike") && t.contains("run")) { return "🏊🚴🏃" }
        if t.contains("bike") || t.contains("cycl") { return "🚴" }
        if t.contains("run") { return "🏃" }
        if t.contains("strength") || t.contains("gym") { return "💪" }
        if t.contains("rest") || t.contains("recover") { return "😴" }
        return "🏋️"
    }

    var body: some View {
        let date = Calendar.current.date(byAdding: .day, value: Self.dayOrder.firstIndex(of: dayGroup.day) ?? 0, to: weekStartDate) ?? weekStartDate

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
                                                    .background(Color.secondary.opacity(0.6))
                                                    .cornerRadius(4)
                                            }
                                            Text(workoutEmoji(workout.type) + " " + workout.type)
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
