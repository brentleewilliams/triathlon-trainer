import SwiftUI
import HealthKit

// MARK: - mondayOfWeek (used by DayRowComponents & WorkoutDayRows)

/// Returns the Monday of the ISO week containing the given date.
func mondayOfWeek(_ date: Date) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return cal.date(from: comps) ?? date
}

// MARK: - Sport color helpers

// Sport color/emoji helpers: thin shims that route to AppTheme so a single
// edit in Theme.swift propagates everywhere. Don't reintroduce local hex
// constants here — every sport color must come from AppTheme.
private func sportColor(for type: String) -> Color { AppTheme.sportColor(for: type) }
private func sportEmoji(for type: String) -> String { AppTheme.sportEmoji(for: type) }

// MARK: - Phase color helper

private func phaseColor(for phase: String) -> Color {
    switch phase.lowercased() {
    case let p where p.contains("base"):   return Color(hex: "007AFF")
    case let p where p.contains("build"):  return Color(hex: "FF9500")
    case let p where p.contains("peak"):   return Color(hex: "FF3B30")
    case let p where p.contains("taper"):  return Color(hex: "34C759")
    default: return Color(hex: "007AFF")
    }
}

// MARK: - Race readiness model

struct SportReadiness {
    let sport: String
    let score: Int
    let status: Status
    let gapText: String
    let actionText: String?

    enum Status { case green, amber, red, loading }

    var statusColor: Color {
        switch status {
        case .green:   return Color(hex: "34C759")
        case .amber:   return Color(hex: "FFCC00")
        case .red:     return Color(hex: "FF3B30")
        case .loading: return Color.gray.opacity(0.3)
        }
    }

    var statusLabel: String {
        switch status {
        case .green:   return "On track"
        case .amber:   return "Slipping"
        case .red:     return "Behind"
        case .loading: return ""
        }
    }
}

/// Derive per-sport readiness from the volume-based status (actual vs planned
/// minutes over a rolling 6-week window, taper weeks excluded). Falls back to
/// the onboarding weekly-volume baseline for weeks with no plan data.
/// Returns the disciplines that actually appear in the user's plan. Used to
/// hide swim/bike entries on a road-race plan and similar single-sport setups.
/// Falls back to all three when nothing parses (e.g. an empty plan during
/// onboarding).
func activeDisciplines(in weeks: [TrainingWeek]) -> Set<TrainingDiscipline> {
    // Primary: race_sports saved during onboarding from the chosen race type.
    if let sports = UserDefaults.standard.array(forKey: "race_sports") as? [String], !sports.isEmpty {
        var result: Set<TrainingDiscipline> = []
        if sports.contains("swim") { result.insert(.swim) }
        if sports.contains("bike") { result.insert(.bike) }
        if sports.contains("run")  { result.insert(.run) }
        if !result.isEmpty { return result }
    }
    // Fallback: scan the plan.
    var found: Set<TrainingDiscipline> = []
    for w in weeks {
        for wo in w.workouts {
            let t = wo.type.lowercased()
            if t.contains("swim") { found.insert(.swim) }
            if t.contains("bike") || t.contains("cycl") { found.insert(.bike) }
            if t.contains("run") { found.insert(.run) }
            if t.contains("brick") { found.insert(.bike); found.insert(.run) }
        }
    }
    return found.isEmpty ? [.swim, .bike, .run] : found
}

func deriveRaceReadiness(from status: TrainingStatus?, today sport: String, only filter: Set<TrainingDiscipline>? = nil) -> [SportReadiness] {
    let allDisciplines: [(String, TrainingDiscipline)] = [
        ("Swim", .swim), ("Bike", .bike), ("Run", .run)
    ]
    let disciplines = filter.map { f in allDisciplines.filter { f.contains($0.1) } } ?? allDisciplines
    return disciplines.map { (name, disc) in
        guard status != nil else {
            return SportReadiness(sport: name, score: 0, status: .loading, gapText: "Loading…", actionText: nil)
        }
        let v = status?.disciplineVolumeStatuses.first { $0.discipline == disc }
        let score = max(0, min(100, v?.percent ?? 0))

        let sportStatus: SportReadiness.Status
        switch v?.severity {
        case .onTrack:        sportStatus = .green
        case .slipping:       sportStatus = .amber
        case .behind, .none:  sportStatus = .red
        }

        let gapText: String
        if let v = v {
            if v.plannedMinutes == 0 {
                gapText = "No sessions planned"
            } else {
                let suffix = v.usedBaselineFallback ? " · 6w (vs baseline)" : " · 6w"
                gapText = "\(v.actualMinutes) / \(v.plannedMinutes) min\(suffix)"
            }
        } else {
            gapText = "Loading…"
        }

        let action: String? = sportStatus != .green && name.lowercased() != sport.lowercased()
            ? "Add a \(name.lowercased()) session this week" : nil

        return SportReadiness(sport: name, score: score, status: sportStatus,
                              gapText: gapText, actionText: action)
    }
}

// MARK: - Course backdrop (Canvas)

struct CourseBackdropView: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height

            // Sky gradient
            ctx.fill(
                Path { p in p.addRect(CGRect(origin: .zero, size: size)) },
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: "1B2540"), location: 0),
                        .init(color: Color(hex: "28456A"), location: 0.55),
                        .init(color: Color(hex: "2E6480"), location: 1),
                    ]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: h)
                )
            )

            let scaleX = w / 390, scaleY = h / 280

            // Sun glow
            let sunX = 305 * scaleX, sunY = 76 * scaleY
            ctx.fill(Path { p in p.addEllipse(in: CGRect(x: sunX-48*scaleX, y: sunY-48*scaleY, width: 96*scaleX, height: 96*scaleY)) },
                     with: .color(.white.opacity(0.10)))
            ctx.fill(Path { p in p.addEllipse(in: CGRect(x: sunX-24*scaleX, y: sunY-24*scaleY, width: 48*scaleX, height: 48*scaleY)) },
                     with: .color(.white.opacity(0.18)))
            ctx.fill(Path { p in p.addEllipse(in: CGRect(x: sunX-10*scaleX, y: sunY-10*scaleY, width: 20*scaleX, height: 20*scaleY)) },
                     with: .color(.white.opacity(0.32)))

            // Far ridge
            ctx.fill(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 168*scaleY))
                    for pt in [(40,138),(75,156),(115,118),(160,148),(210,108),(250,142),(295,118),(340,146),(390,130),(390,280),(0,280)] {
                        p.addLine(to: CGPoint(x: CGFloat(pt.0)*scaleX, y: CGFloat(pt.1)*scaleY))
                    }
                    p.closeSubpath()
                },
                with: .color(Color(hex: "15263A").opacity(0.70))
            )

            // Near ridge
            ctx.fill(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 202*scaleY))
                    for pt in [(35,175),(80,198),(130,158),(185,195),(235,165),(290,200),(335,182),(390,206),(390,280),(0,280)] {
                        p.addLine(to: CGPoint(x: CGFloat(pt.0)*scaleX, y: CGFloat(pt.1)*scaleY))
                    }
                    p.closeSubpath()
                },
                with: .color(Color(hex: "0C1B2C").opacity(0.90))
            )

            // Water
            let waterY = 218 * scaleY
            ctx.fill(
                Path { p in p.addRect(CGRect(x: 0, y: waterY, width: w, height: h - waterY)) },
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: "1A3B52"), location: 0),
                        .init(color: Color(hex: "0E2435"), location: 1),
                    ]),
                    startPoint: CGPoint(x: 0, y: waterY),
                    endPoint: CGPoint(x: 0, y: h)
                )
            )

            // Stars
            let stars: [(Double, Double)] = [(40,35),(120,22),(220,45),(60,80),(180,62),(350,32),(90,50),(250,28)]
            for star in stars {
                ctx.fill(
                    Path { p in p.addEllipse(in: CGRect(x: star.0*scaleX-1.5, y: star.1*scaleY-1.5, width: 3*scaleX, height: 3*scaleY)) },
                    with: .color(.white.opacity(0.30))
                )
            }
        }
    }
}

// MARK: - Readiness ring pill

struct ReadinessPillView: View {
    let score: Int
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
            .frame(width: 32, height: 32)

            Text("DAILY READINESS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.70))
                .kerning(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(Color.white.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatPillView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.70))
                .kerning(0.6)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(Color.white.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Streak chip

struct StreakChipView: View {
    let count: Int
    let isBroken: Bool

    private var label: String {
        isBroken ? "Streak paused" : "\(count)-day streak"
    }
    private var sub: String {
        isBroken ? "Recovery counts — reset today" : count > 7 ? "Hit every session this block" : "Don't skip tomorrow"
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isBroken ? Color.white.opacity(0.18) : Color(hex: "FF9500"))
                Text(isBroken ? "·" : "🔥")
                    .font(.system(size: 10))
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(Color.white.opacity(isBroken ? 0.14 : 0.20))
        .clipShape(Capsule())
    }
}

// MARK: - Home Hero

struct HomeHeroView: View {
    let days: Int
    let raceDate: Date
    let raceName: String
    let raceVenue: String
    let readinessScore: Int
    let readinessLabel: String
    let sleepLabel: String
    let hrvLabel: String
    let streakCount: Int
    let streakBroken: Bool
    let raceReadiness: [SportReadiness]
    let isSingleSport: Bool
    let isRaceWeek: Bool

    @State private var animatedDays: Int = 0

    /// Process-scoped flag — the count-down "ramp" animation should only run on
    /// a true cold boot. Tab switches and foreground returns will see this set
    /// to true and skip the ramp; killing the app resets it.
    private static var didRunIntroAnimation = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Backdrop
            CourseBackdropView()

            // Bottom dark vignette
            LinearGradient(
                colors: [.clear, .black.opacity(0.30)],
                startPoint: .init(x: 0.5, y: 0.3),
                endPoint: .bottom
            )

            // Radial highlight top-right
            RadialGradient(
                colors: [Color.white.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 200
            )

            VStack(alignment: .leading, spacing: 0) {
                // Top row: race name + venue (left), week/phase pill (right)
                // Starts at 60pt to clear the 52pt transparent nav bar overlay.
                HStack(alignment: .top) {
                    if !raceName.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(raceName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                                .kerning(0.8)
                            Text(raceVenue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.72))
                        }
                    }

                    Spacer()
                }
                .padding(.top, 60)

                // Countdown row
                HStack(alignment: .bottom, spacing: 14) {
                    // Number + label
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(animatedDays)")
                            .font(.system(size: 72, weight: .black))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isRaceWeek ? "DAYS · RACE WEEK" : "DAYS TO RACE")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .kerning(0.8)
                                .lineLimit(1)
                            Text(raceDate, format: .dateTime.month(.abbreviated).day().year())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        .padding(.bottom, 10)
                    }

                    Spacer()
                }
                .padding(.top, 14)

                // Readiness pills row. In single-sport (road-race) mode the
                // race-ready dot is appended inline so the layout stays one
                // row instead of dropping a near-empty band underneath.
                HStack(spacing: 8) {
                    ReadinessPillView(score: readinessScore, label: readinessLabel)
                    StatPillView(label: "Sleep", value: sleepLabel)
                    StatPillView(label: "HRV", value: hrvLabel)
                    if isSingleSport, let s = raceReadiness.first {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(s.statusColor)
                                .frame(width: 9, height: 9)
                                .shadow(color: s.statusColor.opacity(0.5), radius: 3)
                            Text(s.sport)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                    }
                }
                .padding(.top, 16)

                // Race-ready traffic lights — multi-discipline only. Single-sport
                // case is folded into the readiness pills row above.
                if !isSingleSport && !raceReadiness.isEmpty {
                    HStack(spacing: 10) {
                        Text("PLAN TARGET")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .kerning(0.6)

                        ForEach(raceReadiness, id: \.sport) { s in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(s.statusColor)
                                    .frame(width: 9, height: 9)
                                    .shadow(color: s.statusColor.opacity(0.5), radius: 3)
                                Text(s.sport)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial.opacity(0.8))
                    .background(Color.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 12)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 22)
        }
        .frame(minHeight: 270)
        .onAppear {
            let target = days
            // Skip the ramp on tab switches / foreground returns — only the
            // first time the hero appears in this process should animate.
            guard !Self.didRunIntroAnimation else {
                animatedDays = target
                return
            }
            Self.didRunIntroAnimation = true

            let start = target + min(40, Int(Double(target) * 0.5))
            animatedDays = start
            let steps = 30
            let stepDuration: UInt64 = 30_000_000 // 30ms
            Task {
                for i in 1...steps {
                    try? await Task.sleep(nanoseconds: stepDuration)
                    let p = Double(i) / Double(steps)
                    let eased = 1 - pow(1 - p, 3) // easeOutCubic
                    let val = Double(start) + (Double(target) - Double(start)) * eased
                    await MainActor.run { animatedDays = Int(val.rounded()) }
                }
            }
        }
        .onChange(of: days) { newDays in
            animatedDays = newDays
        }
    }
}

// MARK: - Timeline strip

struct TimelineStripView: View {
    struct Interval {
        let label: String
        let minutes: Int
    }
    let intervals: [Interval]
    let color: Color

    private var total: Int { max(1, intervals.map(\.minutes).reduce(0, +)) }

    private func opacity(for label: String) -> Double {
        let l = label.lowercased()
        if l.contains("warm") { return 0.35 }
        if l.contains("cool") { return 0.30 }
        if l.contains("aerobic") || l.contains("easy") { return 0.55 }
        return 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SESSION TIMELINE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(.systemGray))
                    .kerning(0.6)
                Spacer()
                Text("\(total) min total")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.systemGray))
                    .monospacedDigit()
            }

            // Bar
            HStack(spacing: 0) {
                ForEach(Array(intervals.enumerated()), id: \.offset) { i, iv in
                    let fraction = CGFloat(iv.minutes) / CGFloat(total)
                    RoundedRectangle(cornerRadius: 0)
                        .fill(color.opacity(opacity(for: iv.label)))
                        .overlay(
                            iv.minutes * 100 / total > 18 ?
                            Text(iv.label.prefix(10).uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .kerning(0.6)
                                .shadow(color: .black.opacity(0.18), radius: 1)
                            : nil
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .aspectRatio(fraction * CGFloat(total), contentMode: .fit)
                    if i < intervals.count - 1 {
                        Divider().frame(width: 1).background(Color.white.opacity(0.7))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .background(Color(.systemGray6).clipShape(RoundedRectangle(cornerRadius: 6)))

            // Tick labels
            HStack(spacing: 0) {
                ForEach(Array(intervals.enumerated()), id: \.offset) { _, iv in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(iv.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text("\(iv.minutes) min")
                            .font(.system(size: 10))
                            .foregroundColor(Color(.systemGray))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

/// Synthesize warm/main/cool intervals from a DayWorkout (no interval data in model).
private func syntheticIntervals(for workout: DayWorkout, color: Color) -> [TimelineStripView.Interval] {
    guard let totalMin = parseWorkoutDuration(workout.duration), totalMin > 0 else {
        return [TimelineStripView.Interval(label: workout.type, minutes: 30)]
    }
    let warmup = max(5, Int(Double(totalMin) * 0.15))
    let cooldown = max(5, Int(Double(totalMin) * 0.15))
    let main = max(5, totalMin - warmup - cooldown)
    return [
        TimelineStripView.Interval(label: "Warm-up", minutes: warmup),
        TimelineStripView.Interval(label: "Main set", minutes: main),
        TimelineStripView.Interval(label: "Cool-down", minutes: cooldown),
    ]
}

// MARK: - Meta cell

struct MetaCellView: View {
    let label: String
    let value: String
    let sub: String?
    var borderLeft = false
    var borderTop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(.systemGray))
                .kerning(0.6)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            if let sub = sub {
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundColor(Color(.systemGray))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(
            HStack(spacing: 0) {
                if borderLeft {
                    Rectangle().fill(Color(.systemGray5)).frame(width: 0.5)
                }
                Spacer()
            }
        )
        .overlay(
            VStack(spacing: 0) {
                if borderTop {
                    Rectangle().fill(Color(.systemGray5)).frame(height: 0.5)
                }
                Spacer()
            }
        )
    }
}

// MARK: - Workout tab card

struct WorkoutTabCardView: View {
    let todayWorkout: DayWorkout?
    let tomorrowWorkout: DayWorkout?
    let afterWorkout: Bool
    let todayHKWorkouts: [HKWorkout]
    let onSwap: () -> Void
    let onViewPlan: () -> Void
    let onLogWorkout: () -> Void

    @State private var selectedTab: Tab = .today

    enum Tab { case today, tomorrow }

    private var displayWorkout: DayWorkout? {
        selectedTab == .today ? todayWorkout : tomorrowWorkout
    }

    var body: some View {
        VStack(spacing: 0) {
            if let workout = displayWorkout {
                tabStrip(workout)
                workoutBody(workout)
                ctaRow(workout)
            } else {
                noWorkoutFallback
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 0, x: 0, y: 1)
        .padding(.top, -18)
    }

    @ViewBuilder
    private func tabStrip(_ current: DayWorkout) -> some View {
        HStack(spacing: 0) {
            tabButton(
                tab: .today,
                eyebrow: afterWorkout ? "Today · Done" : "Today",
                sport: todayWorkout?.type ?? "",
                title: todayWorkout?.type ?? "Rest",
                meta: todayWorkout?.duration ?? "—",
                done: afterWorkout
            )
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(width: 0.5)
            tabButton(
                tab: .tomorrow,
                eyebrow: "Tomorrow",
                sport: tomorrowWorkout?.type ?? "",
                title: tomorrowWorkout?.type ?? "Rest",
                meta: tomorrowWorkout?.duration ?? "—",
                done: false
            )
        }
        .frame(height: 72)
        .overlay(Rectangle().fill(Color(.systemGray5)).frame(height: 0.5), alignment: .bottom)
    }

    @ViewBuilder
    private func tabButton(tab: Tab, eyebrow: String, sport: String, title: String, meta: String, done: Bool) -> some View {
        let isActive = selectedTab == tab
        let color = sportColor(for: sport)

        Button { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab } } label: {
            ZStack(alignment: .top) {
                // Active color bar
                Rectangle()
                    .fill(isActive ? color : Color.clear)
                    .frame(height: 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                            .opacity(isActive ? 1 : 0.55)
                        Text(eyebrow.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isActive ? Color(.label).opacity(0.85) : Color(.systemGray))
                            .kerning(0.6)
                        if done {
                            Text("✓")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "34C759"))
                        }
                    }

                    Text(title.count > 22 ? String(title.prefix(20)) + "…" : title)
                        .font(.system(size: isActive ? 14 : 13, weight: isActive ? .bold : .semibold))
                        .foregroundColor(isActive ? .primary : Color(.systemGray))
                        .lineLimit(1)

                    Text("\(sport.isEmpty ? "Rest" : sport) · \(meta)")
                        .font(.system(size: 11))
                        .foregroundColor(isActive ? Color(.systemGray) : Color(.systemGray2))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .background(isActive ? Color(.systemBackground) : Color(hex: "FAFAFC"))
    }

    @ViewBuilder
    private func workoutBody(_ workout: DayWorkout) -> some View {
        let color = sportColor(for: workout.type)
        let isToday = selectedTab == .today

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text(isToday ? (afterWorkout ? "Today · Completed" : "Today · Up next") : "Tomorrow · Planned")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .kerning(0.6)
                sportChip(workout.type, color: color)
                if isToday && afterWorkout {
                    Spacer()
                    Label("Done", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "34C759"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "34C759").opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Title
            Text(strippedType(workout.type))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .padding(.horizontal, 16)

            // Meta line
            Text(workout.duration + (workout.zone.isEmpty ? "" : " · \(workout.zone)"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(.systemGray))
                .monospacedDigit()
                .padding(.horizontal, 16)
                .padding(.top, 4)

            // Brick leg breakdown (tab card path — same fallback logic as SelectedDayWorkoutCard)
            if workout.type.lowercased().contains("brick") || workout.type.lowercased().contains("race sim") {
                let split = workout.notes.flatMap { WorkoutDetailParser.parseBrickDetail(from: $0) }
                VStack(spacing: 0) {
                    BrickLegRow(emoji: "🚴", label: "Bike", duration: split?.bikeDuration ?? "—", accent: AppTheme.bike)
                    Divider().padding(.leading, 12)
                    BrickLegRow(emoji: "🏃", label: "Run",  duration: split?.runDuration ?? "—",  accent: AppTheme.run, paceSuffix: split?.runPace)
                }
                .background(Color(.systemGray6).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            // Why box
            if let notes = workout.notes, !notes.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    Text("Why · ")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(color)
                    + Text(notes)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(.label).opacity(0.85))
                }
                .lineLimit(3)
                .padding(10)
                .background(color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 2)
            }

            // Timeline strip
            TimelineStripView(
                intervals: syntheticIntervals(for: workout, color: color),
                color: color
            )
            .padding(.top, 10)

            // 2×2 meta grid
            let weather = WeatherForecast.forecast(for: Date())
            Divider().padding(.horizontal, 0)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                MetaCellView(label: "Weather",
                             value: "\(weather.highTemp)° · \(weather.icon)",
                             sub: "High today")
                MetaCellView(label: "Zone",
                             value: workout.zone.components(separatedBy: " · ").first ?? workout.zone,
                             sub: workout.zone.components(separatedBy: " · ").dropFirst().first,
                             borderLeft: true)
                if let nutrition = workout.nutritionTarget {
                    MetaCellView(label: "Fueling",
                                 value: nutrition.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) ?? nutrition,
                                 sub: nutrition.components(separatedBy: "·").dropFirst().first?.trimmingCharacters(in: .whitespaces),
                                 borderTop: true)
                    MetaCellView(label: "Duration",
                                 value: workout.duration,
                                 sub: nil,
                                 borderLeft: true, borderTop: true)
                } else {
                    MetaCellView(label: "Duration",
                                 value: workout.duration,
                                 sub: nil,
                                 borderTop: true)
                    MetaCellView(label: "Type",
                                 value: strippedType(workout.type),
                                 sub: nil,
                                 borderLeft: true, borderTop: true)
                }
            }
            .background(Color(.secondarySystemBackground))

            // Actual workouts recorded today (all HK workouts, matched or not)
            if isToday && !todayHKWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RECORDED TODAY")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(.systemGray))
                            .kerning(0.6)
                            .padding(.bottom, 2)
                        ForEach(todayHKWorkouts, id: \.uuid) { hkWorkout in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(hkWorkoutColor(hkWorkout.workoutActivityType))
                                    .frame(width: 8, height: 8)
                                Text(hkWorkoutTypeName(hkWorkout.workoutActivityType))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(hkDurationString(hkWorkout.duration))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(.systemGray))
                                    .monospacedDigit()
                                if let dist = hkDistanceString(hkWorkout) {
                                    Text("· \(dist)")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(.systemGray2))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func hkWorkoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .running: return "Running"
        case .walking: return "Walking"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .hiking: return "Hiking"
        default: return "Workout"
        }
    }

    private func hkWorkoutColor(_ type: HKWorkoutActivityType) -> Color {
        AppTheme.sportColor(for: type)
    }

    private func hkDurationString(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins >= 60 { return "\(mins / 60)h \(mins % 60)m" }
        return "\(mins) min"
    }

    private func hkDistanceString(_ workout: HKWorkout) -> String? {
        guard let dist = workout.totalDistance else { return nil }
        let meters = dist.doubleValue(for: .meter())
        if workout.workoutActivityType == .swimming {
            return String(format: "%.0f yd", meters * 1.09361)
        }
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    }

    @ViewBuilder
    private func ctaRow(_ workout: DayWorkout) -> some View {
        let isToday = selectedTab == .today

        if isToday {
            if !afterWorkout {
                HStack(spacing: 8) {
                    Button(action: onLogWorkout) {
                        Text("Log workout")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(sportColor(for: workout.type))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button(action: onSwap) {
                        Text("Swap")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "007AFF"))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(14)
            }
        } else {
            HStack(spacing: 8) {
                Button(action: onViewPlan) {
                    Text("View full plan")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button(action: onSwap) {
                    Text("Move")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "007AFF"))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(14)
        }
    }

    private var noWorkoutFallback: some View {
        VStack(spacing: 12) {
            Text("😴")
                .font(.system(size: 40))
            Text("Rest day")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private func sportChip(_ type: String, color: Color) -> some View {
        Text(strippedType(type))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func strippedType(_ type: String) -> String {
        if let idx = type.firstIndex(where: { $0.isLetter }) {
            return String(type[idx...])
        }
        return type
    }
}

// MARK: - Section header (selected-day title + weather)

struct SectionHeaderWithWeather: View {
    let dayLabel: String        // e.g. "Today", "Mon", "Tue"
    let date: Date              // used to fetch the right day's forecast

    private var forecast: WeatherForecast { WeatherForecast.forecast(for: date) }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(dayLabel)'s workout")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
            Spacer()
            HStack(spacing: 4) {
                Text(forecast.icon)
                    .font(.system(size: 16))
                Text("\(forecast.highTemp)°")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Selected Day Workout Card

struct SelectedDayWorkoutCard: View {
    let workout: DayWorkout?
    let dayLabel: String         // e.g. "Mon", "Tue"
    let hkWorkouts: [HKWorkout]
    let isCompleted: Bool
    let onSwap: () -> Void
    let onLogWorkout: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if let workout = workout {
                workoutBody(workout)
                if isExpanded {
                    ctaRow(workout)
                }
            } else {
                restDayFallback
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .shadow(color: .black.opacity(AppTheme.cardShadowOpacity), radius: AppTheme.cardShadowRadius, y: 2)
    }

    // MARK: Workout content

    @ViewBuilder
    private func workoutBody(_ workout: DayWorkout) -> some View {
        let color = sportColor(for: workout.type)

        HStack(spacing: 0) {
            // Colored left border
            Rectangle()
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                // Header row — always visible, tapping expands/collapses detail
                HStack(spacing: 8) {
                    Text(isCompleted ? "\(dayLabel) · Completed" : "\(dayLabel) · Up next")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color)
                        .kerning(0.6)
                    sportChip(workout.type, color: color)
                    if isCompleted {
                        Spacer()
                        Label("Done", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.statusGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.statusGreen.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.trailing, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }

                // Title
                Text(strippedType(workout.type))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .padding(.horizontal, 16)

                // Meta line
                Text(workout.duration + (workout.zone.isEmpty ? "" : " · \(workout.zone)"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(.systemGray))
                    .monospacedDigit()
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 14)

                if isExpanded {
                    // Brick leg breakdown — two-row card showing bike + run components.
                    // Always rendered for bricks; falls back to "—" when notes don't contain
                    // a parseable split (e.g. AI plan described split in prose, not in
                    // "Bike X:XX + Run Xmin" format).
                    if workout.type.lowercased().contains("brick") || workout.type.lowercased().contains("race sim") {
                        let split = workout.notes.flatMap { WorkoutDetailParser.parseBrickDetail(from: $0) }
                        VStack(spacing: 0) {
                            BrickLegRow(emoji: "🚴", label: "Bike", duration: split?.bikeDuration ?? "—", accent: AppTheme.bike)
                            Divider().padding(.leading, 12)
                            BrickLegRow(emoji: "🏃", label: "Run",  duration: split?.runDuration ?? "—",  accent: AppTheme.run, paceSuffix: split?.runPace)
                        }
                        .background(Color(.systemGray6).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    // What box
                    if let notes = workout.notes, !notes.isEmpty {
                        HStack(alignment: .top, spacing: 0) {
                            Text("What · ")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(color)
                            + Text(notes)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(.label).opacity(0.85))
                        }
                        .lineLimit(3)
                        .padding(10)
                        .background(color.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                    }

                    // Timeline strip
                    TimelineStripView(
                        intervals: syntheticIntervals(for: workout, color: color),
                        color: color
                    )
                    .padding(.top, 10)

                    // 2×2 meta grid (weather moved up to the section header on home)
                    Divider().padding(.horizontal, 0)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                        MetaCellView(label: "Zone",
                                     value: workout.zone.components(separatedBy: " · ").first ?? workout.zone,
                                     sub: workout.zone.components(separatedBy: " · ").dropFirst().first)
                        MetaCellView(label: "Duration",
                                     value: workout.duration,
                                     sub: nil,
                                     borderLeft: true)
                        if let nutrition = workout.nutritionTarget {
                            MetaCellView(label: "Fueling",
                                         value: nutrition.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) ?? nutrition,
                                         sub: nutrition.components(separatedBy: "·").dropFirst().first?.trimmingCharacters(in: .whitespaces),
                                         borderTop: true)
                            MetaCellView(label: "Type",
                                         value: strippedType(workout.type),
                                         sub: nil,
                                         borderLeft: true, borderTop: true)
                        } else {
                            MetaCellView(label: "Type",
                                         value: strippedType(workout.type),
                                         sub: nil,
                                         borderTop: true)
                            Color.clear.frame(height: 1)
                                .overlay(Rectangle().fill(Color(.systemGray5)).frame(width: 0.5), alignment: .leading)
                                .overlay(Rectangle().fill(Color(.systemGray5)).frame(height: 0.5), alignment: .top)
                        }
                    }
                    .background(Color(.secondarySystemBackground))

                    // Recorded workouts for this day
                    if !hkWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("RECORDED TODAY")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color(.systemGray))
                                    .kerning(0.6)
                                    .padding(.bottom, 2)
                                ForEach(hkWorkouts, id: \.uuid) { hkWorkout in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(hkWorkoutColor(hkWorkout.workoutActivityType))
                                            .frame(width: 8, height: 8)
                                        Text(hkWorkoutTypeName(hkWorkout.workoutActivityType))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text(hkDurationString(hkWorkout.duration))
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Color(.systemGray))
                                            .monospacedDigit()
                                        if let dist = hkDistanceString(hkWorkout) {
                                            Text("· \(dist)")
                                                .font(.system(size: 13))
                                                .foregroundColor(Color(.systemGray2))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: CTA row

    @ViewBuilder
    private func ctaRow(_ workout: DayWorkout) -> some View {
        if !isCompleted {
            HStack(spacing: 8) {
                Button(action: onLogWorkout) {
                    Text("Log workout")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(sportColor(for: workout.type))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button(action: onSwap) {
                    Text("Swap")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "007AFF"))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(14)
        }
    }

    // MARK: Rest day (also shows any HK workouts recorded on this day)

    private var restDayFallback: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("😴")
                    .font(.system(size: 32))
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .kerning(0.4)
                    Text("Rest Day")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                Spacer()
            }
            .padding(20)

            if !hkWorkouts.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECORDED")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(.systemGray))
                        .kerning(0.6)
                        .padding(.bottom, 2)
                    ForEach(hkWorkouts, id: \.uuid) { hkWorkout in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(hkWorkoutColor(hkWorkout.workoutActivityType))
                                .frame(width: 8, height: 8)
                            Text(hkWorkoutTypeName(hkWorkout.workoutActivityType))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(hkDurationString(hkWorkout.duration))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(.systemGray))
                                .monospacedDigit()
                            if let dist = hkDistanceString(hkWorkout) {
                                Text("· \(dist)")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(.systemGray2))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Always offer a way to log a workout, even on rest days. Lets the
            // user record a strength session or unscheduled cardio without
            // needing today to be a planned-workout day.
            Divider()
            Button(action: onLogWorkout) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Log Workout")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(Color(hex: "007AFF"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    // MARK: Private helpers

    private func sportChip(_ type: String, color: Color) -> some View {
        Text(strippedType(type))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func strippedType(_ type: String) -> String {
        if let idx = type.firstIndex(where: { $0.isLetter }) {
            return String(type[idx...])
        }
        return type
    }

    private func hkWorkoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .running: return "Running"
        case .walking: return "Walking"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .hiking: return "Hiking"
        default: return "Workout"
        }
    }

    private func hkWorkoutColor(_ type: HKWorkoutActivityType) -> Color {
        AppTheme.sportColor(for: type)
    }

    private func hkDurationString(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins >= 60 { return "\(mins / 60)h \(mins % 60)m" }
        return "\(mins) min"
    }

    private func hkDistanceString(_ workout: HKWorkout) -> String? {
        guard let dist = workout.totalDistance else { return nil }
        let meters = dist.doubleValue(for: .meter())
        if workout.workoutActivityType == .swimming {
            return String(format: "%.0f yd", meters * 1.09361)
        }
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    }
}

// MARK: - Week Overview Card

struct WeekOverviewCard: View {
    let workoutsByDay: [(day: String, workouts: [DayWorkout])]
    @Binding var selectedDayIndex: Int
    let isWorkoutCompleted: (DayWorkout) -> Bool
    /// Invoked when the user drags a workout from one day onto another. Both
    /// arguments are short day names ("Mon", "Tue", …). The drop site supplies
    /// destDay; the dragged payload supplies sourceDay + workout.
    var onSwap: ((DayWorkout, String, String) -> Void)? = nil

    @State private var isExpanded = true
    @State private var dropTargetDay: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "Week Overview" + expand/collapse chevron + workouts completed count
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text("Week Overview")
                        .font(.headline)
                    Spacer()
                    let completed = workoutsByDay.flatMap(\.workouts).filter { !$0.type.contains("Rest") && isWorkoutCompleted($0) }.count
                    let total = workoutsByDay.flatMap(\.workouts).filter { !$0.type.contains("Rest") && !$0.type.contains("pre_onboarding") }.count
                    Text("\(completed)/\(total)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(AppTheme.cardPadding)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                // One row per workout — multi-session days get individual rows
                ForEach(Array(workoutsByDay.enumerated()), id: \.offset) { index, dayEntry in
                    let nonRestWorkouts = dayEntry.workouts.filter {
                        !$0.type.lowercased().contains("rest") && !$0.type.contains("pre_onboarding")
                    }
                    // If all workouts are rest/placeholder, show one rest row; otherwise show each non-rest workout
                    let displayWorkouts: [DayWorkout] = nonRestWorkouts.isEmpty
                        ? dayEntry.workouts.filter { !$0.type.contains("pre_onboarding") }.prefix(1).map { $0 }
                        : nonRestWorkouts
                    let isDropTarget = dropTargetDay == dayEntry.day

                    VStack(spacing: 0) {
                        ForEach(Array(displayWorkouts.enumerated()), id: \.offset) { wIndex, workout in
                            let isRest = workout.type.lowercased().contains("rest")
                            let dotColor: Color = isRest ? Color(.systemGray4) : sportColor(for: workout.type)
                            let isBrick = !isRest && (workout.type.lowercased().contains("brick") || workout.type.lowercased().contains("race sim"))
                            let label: String = {
                                if let i = workout.type.firstIndex(where: { $0.isLetter }) { return String(workout.type[i...]) }
                                return workout.type
                            }()

                            let rowContent = Button(action: { withAnimation { selectedDayIndex = index } }) {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(dotColor)
                                        .frame(width: 7, height: 7)
                                        .frame(width: 18, alignment: .leading)

                                    Text(dayEntry.day)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 28, alignment: .leading)

                                    Text(label)
                                        .font(.system(size: 13))
                                        .foregroundColor(isRest ? .secondary : .primary)
                                        .lineLimit(1)

                                    if isBrick {
                                        Text("Bike & Run")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if !isRest {
                                        Image(systemName: isWorkoutCompleted(workout) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isWorkoutCompleted(workout) ? AppTheme.statusGreen : Color(.systemGray4))
                                            .font(.system(size: 16))
                                    }
                                }
                                .padding(.horizontal, AppTheme.cardPadding)
                                .padding(.vertical, 10)
                                .background(
                                    isDropTarget
                                        ? Color.accentColor.opacity(0.18)
                                        : (index == selectedDayIndex ? AppTheme.bike.opacity(0.06) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)

                            Group {
                                if !isRest, onSwap != nil {
                                    rowContent
                                        .draggable(DraggedWorkoutRef(
                                            weekNumber: 0,
                                            sourceDay: dayEntry.day,
                                            workout: workout
                                        ))
                                } else {
                                    rowContent
                                }
                            }

                            if wIndex < displayWorkouts.count - 1 {
                                Divider().padding(.leading, AppTheme.cardPadding + 20)
                            }
                        }
                    }
                    .dropDestination(for: DraggedWorkoutRef.self) { items, _ in
                        guard let ref = items.first, let onSwap else { return false }
                        onSwap(ref.workout, ref.sourceDay, dayEntry.day)
                        return true
                    } isTargeted: { targeted in
                        dropTargetDay = targeted ? dayEntry.day : (dropTargetDay == dayEntry.day ? nil : dropTargetDay)
                    }

                    if index < workoutsByDay.count - 1 {
                        Divider().padding(.leading, AppTheme.cardPadding + 20)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .shadow(color: .black.opacity(AppTheme.cardShadowOpacity), radius: AppTheme.cardShadowRadius, y: 2)
    }
}

// MARK: - Race readiness card

struct RaceReadinessCardView: View {
    let readiness: [SportReadiness]
    let overall: Int
    let onSwap: () -> Void

    private var overallColor: Color {
        overall >= 75 ? Color(hex: "34C759") : overall >= 50 ? Color(hex: "FFCC00") : Color(hex: "FF3B30")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Race readiness")
                    .font(.system(size: 15, weight: .bold))
                Text("per discipline")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.systemGray))
                Spacer()
                Text("\(overall)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(overallColor)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 16)

            // Per-sport rows
            ForEach(Array(readiness.enumerated()), id: \.element.sport) { i, s in
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(s.statusColor)
                            .frame(width: 10, height: 10)
                            .shadow(color: s.statusColor.opacity(0.4), radius: 3)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(s.sport)
                                    .font(.system(size: 14, weight: .bold))
                                Text(s.statusLabel)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(s.statusColor)
                            }
                            Text(s.gapText)
                                .font(.system(size: 12))
                                .foregroundColor(Color(.systemGray))
                        }

                        Spacer()

                        Text("\(s.score)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(s.statusColor)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // Inline swap CTA under slipping sport
                    if let action = s.actionText {
                        HStack(spacing: 10) {
                            Text(action)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(.label).opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button(action: onSwap) {
                                Text("Swap today")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(s.statusColor)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(s.statusColor.opacity(0.08))
                        .overlay(Rectangle().fill(s.statusColor).frame(width: 2), alignment: .leading)
                        .padding(.leading, 22)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }

                    if i < readiness.count - 1 {
                        Divider().padding(.leading, 38)
                    }
                }
            }

            Spacer(minLength: 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5), lineWidth: 0.5))
    }
}

// MARK: - Coach nudge card

struct CoachNudgeCardView: View {
    let nudge: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "AF52DE").opacity(0.18))
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "AF52DE"))
                }
                .frame(width: 30, height: 30)
                .flexibleFrame(minWidth: 30)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("COACH")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(.systemGray))
                            .kerning(0.6)
                        if onTap != nil {
                            Text("· tap to discuss")
                                .font(.system(size: 11))
                                .foregroundColor(Color(.systemGray2))
                        }
                    }
                    Text(nudge)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(.systemGray3))
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

// MARK: - Race forecast card (race week only)

struct RaceForecastCardView: View {
    let raceDate: Date

    private var forecast: WeatherForecast { WeatherForecast.forecast(for: raceDate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Race-day forecast")
                    .font(.system(size: 15, weight: .bold))
                Text("updated today")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.systemGray))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(forecast.icon)
                            .font(.system(size: 28))
                        Text("\(forecast.highTemp)°")
                            .font(.system(size: 32, weight: .black))
                            .monospacedDigit()
                        Text("/ \(forecast.lowTemp)°")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(.systemGray))
                    }
                    Text(forecast.condition + " · Wind —")
                        .font(.system(size: 12))
                        .foregroundColor(Color(.systemGray))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan for race morning conditions.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(.label).opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(hex: "007AFF").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5), lineWidth: 0.5))
    }
}

// MARK: - Packing list card (race week only)

struct PackingListCardView: View {
    @State private var checked: Set<Int> = [0, 1] // first two pre-checked

    private let items = [
        "Race kit + spare goggles",
        "Bike tune + race wheels",
        "Nutrition (8 gels, 4 bottles)",
        "Wetsuit + body glide",
        "Photo ID + race card",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Packing list")
                    .font(.system(size: 15, weight: .bold))
                Text("\(items.count - checked.count) of \(items.count) left")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.systemGray))
                Spacer()
                Text("See all")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "007AFF"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(spacing: 10) {
                    Button {
                        if checked.contains(i) { checked.remove(i) } else { checked.insert(i) }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(checked.contains(i) ? Color(hex: "34C759") : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(checked.contains(i) ? Color.clear : Color(.systemGray3), lineWidth: 1.5)
                                )
                                .frame(width: 18, height: 18)
                            if checked.contains(i) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Text(item)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(checked.contains(i) ? Color(.systemGray) : .primary)
                        .strikethrough(checked.contains(i))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)

                if i < items.count - 1 {
                    Divider().padding(.horizontal, 16)
                }
            }

            Spacer(minLength: 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5), lineWidth: 0.5))
    }
}

// MARK: - Widget tip card

struct WidgetTipCard: View {
    @Binding var isVisible: Bool
    @State private var showInstructions = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add the Race1 widget")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("See today's workout on your home screen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showInstructions = true
            } label: {
                Text("How")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Button {
                withAnimation { isVisible = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5), lineWidth: 0.5))
        .sheet(isPresented: $showInstructions) {
            WidgetInstructionsSheet()
                .presentationDetents([.medium])
        }
    }
}

struct WidgetInstructionsSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Add the Race1 Widget")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array([
                    ("1", "Long-press your home screen until icons wiggle"),
                    ("2", "Tap the \"+\" button in the top-left corner"),
                    ("3", "Search for \"Race1\""),
                    ("4", "Select the widget and tap \"Add Widget\""),
                ].enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(step.0)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.blue)
                            .clipShape(Circle())
                        Text(step.1)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 32)
    }
}

// MARK: - Helper: View extension for optional frame

private extension View {
    @ViewBuilder
    func flexibleFrame(minWidth: CGFloat) -> some View {
        self.frame(minWidth: minWidth)
    }
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @EnvironmentObject var trainingStatusService: TrainingStatusService

    // Keep for DayRowComponents / WorkoutDayRows parent references
    @State var selectedWeek: Int = 1
    @State var draggedFromDay: String?
    @State var draggedWorkout: DayWorkout?

    // New state
    @AppStorage("race_primary_name")  private var storedRaceName:  String = ""
    @AppStorage("race_primary_venue") private var storedRaceVenue: String = ""
    @State private var showWidgetTip: Bool = !UserDefaults.standard.bool(forKey: "widget_tip_dismissed")
    @State private var showCourseDetail: Bool = false
    @State private var showLogWorkout: Bool = false
    @State private var sleepLabel: String = "—"
    @State private var hrvLabel: String = "—"
    @State private var hasAppearedOnce = false
    @State private var selectedDayIndex: Int = HomeView.todayDayIndex()
    @State private var showWeekPicker = false

    // MARK: Static helpers

    static func todayDayIndex() -> Int {
        // Returns 0 for Monday, 6 for Sunday
        let weekday = Calendar.current.component(.weekday, from: Date()) // 1=Sun, 2=Mon, ... 7=Sat
        return (weekday + 5) % 7  // converts to 0=Mon...6=Sun
    }

    // MARK: Selected-day computed properties

    /// All non-Rest workouts for the selected day, in plan order.
    var selectedDayAllWorkouts: [DayWorkout] {
        guard selectedDayIndex < workoutsByDay.count else { return [] }
        return workoutsByDay[selectedDayIndex].workouts.filter {
            !$0.type.lowercased().contains("rest") && !$0.type.contains("pre_onboarding")
        }
    }

    /// The primary workout for the currently selected day in the strip.
    var selectedDayWorkout: DayWorkout? { selectedDayAllWorkouts.first }

    /// Calendar date corresponding to the currently selected day in the strip.
    var selectedDayDate: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: selectedDayIndex, to: currentWeekStartDate) ?? currentWeekStartDate
    }

    /// Builds the prefilled chat seed used when the user taps "Swap" on the
    /// home selected-day card. Format:
    ///   "(from app insight) Swap <Day Mon D>'s <Type> (<duration>) for "
    /// Trailing space invites the user to complete with what they want.
    func swapSeed(for workout: DayWorkout?, on date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        let dateStr = f.string(from: date)
        if let w = workout {
            return "(from app insight) Swap \(dateStr)'s \(w.type) (\(w.duration)) for "
        }
        return "(from app insight) Swap \(dateStr)'s workout for "
    }

    /// Header label that reads "Today", "Tomorrow", or the weekday name.
    var selectedDayHeaderLabel: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: selectedDayDate)
        let delta = cal.dateComponents([.day], from: today, to: target).day ?? 0
        if delta == 0 { return "Today" }
        if delta == 1 { return "Tomorrow" }
        if delta == -1 { return "Yesterday" }
        let df = DateFormatter()
        df.dateFormat = "EEEE"
        return df.string(from: target)
    }

    /// HK workouts for the selected day (works for pre-plan weeks).
    var selectedDayHKWorkouts: [HKWorkout] {
        let cal = Calendar.current
        let dayDate = cal.date(byAdding: .day, value: selectedDayIndex, to: currentWeekStartDate) ?? currentWeekStartDate
        let targetDay = cal.startOfDay(for: dayDate)
        return healthKit.workouts.filter { cal.startOfDay(for: $0.startDate) == targetDay }
    }

    /// Whether selected day's workout is completed.
    var selectedDayAfterWorkout: Bool {
        guard let w = selectedDayWorkout else { return false }
        return isWorkoutCompleted(w)
    }

    // MARK: Race date
    var raceDate: Date {
        if let ts = UserDefaults.standard.object(forKey: "race_date") as? Double, ts > 0 {
            return Date(timeIntervalSince1970: ts)
        }
        // Derive from last week of the loaded plan — works even after a sign-out
        // wipe when the plan is restored from Firestore before race_date is backfilled.
        if let lastWeek = trainingPlan.weeks.sorted(by: { $0.weekNumber < $1.weekNumber }).last {
            return lastWeek.endDate
        }
        return Date().addingTimeInterval(60 * 24 * 3600) // distant future, never hardcode a specific race
    }

    var daysUntilRace: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let race  = Calendar.current.startOfDay(for: raceDate)
        return Calendar.current.dateComponents([.day], from: today, to: race).day ?? 0
    }

    var isRaceWeek: Bool { daysUntilRace >= 0 && daysUntilRace <= 7 }

    // MARK: Current week

    var currentWeek: TrainingWeek? { trainingPlan.getWeek(selectedWeek) }

    var currentPhase: String { currentWeek?.phase ?? "" }

    /// Monday of the displayed week, works for pre-plan weeks (selectedWeek < 1) too.
    var currentWeekStartDate: Date {
        if let week = currentWeek { return mondayOfWeek(week.startDate) }
        guard let week1 = trainingPlan.getWeek(1) else { return mondayOfWeek(Date()) }
        let planMonday = mondayOfWeek(week1.startDate)
        let offset = selectedWeek - 1
        return Calendar.current.date(byAdding: .weekOfYear, value: offset, to: planMonday) ?? planMonday
    }

    /// Week label for the top nav — nil for pre-plan weeks so the nav shows "Today" instead.
    var navWeekLabel: String? {
        guard selectedWeek >= 1 else { return nil }
        return "Week \(selectedWeek)/\(trainingPlan.weeks.count)"
    }

    /// True when the displayed week contains today (used to highlight today's day in the strip).
    var isCurrentDisplayWeek: Bool {
        let cal = Calendar.current
        let monday = currentWeekStartDate
        guard let sunday = cal.date(byAdding: .day, value: 6, to: monday) else { return false }
        let today = Date()
        return today >= monday && today <= sunday
    }

    // MARK: Today / tomorrow workouts
    private var todayDayAbbrev: String {
        let df = DateFormatter(); df.dateFormat = "EEE"
        return String(df.string(from: Date()).prefix(3))
    }
    private var tomorrowDayAbbrev: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let df = DateFormatter(); df.dateFormat = "EEE"
        return String(df.string(from: tomorrow).prefix(3))
    }

    var todayWorkout: DayWorkout? {
        currentWeek?.workouts.first { $0.day == todayDayAbbrev && !$0.type.contains("Rest") }
    }

    var tomorrowWorkout: DayWorkout? {
        currentWeek?.workouts.first { $0.day == tomorrowDayAbbrev && !$0.type.contains("Rest") }
            ?? {
                // Tomorrow might be in next week
                let nextWeek = trainingPlan.getWeek(selectedWeek + 1)
                return nextWeek?.workouts.first { $0.day == tomorrowDayAbbrev && !$0.type.contains("Rest") }
            }()
    }

    var afterWorkout: Bool {
        guard let w = todayWorkout else { return false }
        return isWorkoutCompleted(w)
    }

    var todayHKWorkouts: [HKWorkout] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return healthKit.workouts.filter { cal.startOfDay(for: $0.startDate) == today }
    }

    // MARK: Readiness
    var readinessScore: Int  { trainingStatusService.status?.readiness.score ?? 0 }
    var readinessLabel: String {
        switch trainingStatusService.status?.readiness.level {
        case .race:        return "Race ready"
        case .fresh:       return "Fresh"
        case .training:    return "Training"
        case .tired:       return "Tired"
        case .overreached: return "Overreached"
        case .none:        return "—"
        }
    }

    // MARK: Streak
    var streakCount: Int {
        let status = trainingStatusService.status
        switch status?.readiness.level {
        case .fresh:  return 12
        case .tired:  return 0
        default:      return 8
        }
    }
    var streakBroken: Bool { trainingStatusService.status?.readiness.level == .tired }

    // MARK: Race readiness per sport
    var activeDisciplineSet: Set<TrainingDiscipline> {
        activeDisciplines(in: trainingPlan.weeks)
    }
    var raceReadiness: [SportReadiness] {
        guard trainingStatusService.hasEverComputed else {
            let allDisciplines: [(String, TrainingDiscipline)] = [("Swim", .swim), ("Bike", .bike), ("Run", .run)]
            let disciplines = activeDisciplineSet.isEmpty ? allDisciplines : allDisciplines.filter { activeDisciplineSet.contains($0.1) }
            return disciplines.map { (name, _) in
                SportReadiness(sport: name, score: 0, status: .loading, gapText: "Loading…", actionText: nil)
            }
        }
        return deriveRaceReadiness(
            from: trainingStatusService.status,
            today: todayWorkout?.type ?? "",
            only: activeDisciplineSet
        )
    }
    var raceReadinessOverall: Int {
        guard !raceReadiness.isEmpty else { return 0 }
        return raceReadiness.map(\.score).reduce(0, +) / raceReadiness.count
    }

    // MARK: Coach nudge
    var coachNudge: String {
        switch trainingStatusService.status?.readiness.level {
        case .race:
            return "Body is primed. Today's a good day to race — hit the key session clean."
        case .fresh:
            return "Sleep and HRV are trending up. Good day to push the main set."
        case .training:
            return "You're tracking the block well. Fuel early and execute the plan."
        case .tired:
            return "HRV is down. Consider swapping today's hard effort for a Z2 session without losing the block."
        case .overreached:
            return "Signs of overreaching — a rest or easy day now will pay dividends this week."
        case .none:
            return "Loading your training context…"
        }
    }

    // MARK: Race name / venue
    // @AppStorage vars above (storedRaceName / storedRaceVenue) make these
    // reactive: SwiftUI re-renders automatically when the async Firestore
    // backfill writes the user's actual race into UserDefaults — preventing
    // the bundled Oregon 70.3 profile from leaking through as the header.
    var raceName: String {
        storedRaceName
            .replacingOccurrences(of: "Race1 — ", with: "")
            .replacingOccurrences(of: "Race1 - ", with: "")
    }
    var raceVenue: String {
        storedRaceVenue.isEmpty ? "" : storedRaceVenue
    }

    // MARK: - Completion helpers (called by DayRowComponents / WorkoutDayRows)

    func isWorkoutCompleted(_ workout: DayWorkout) -> Bool {
        let isBrick = workout.type.lowercased().contains("brick") || workout.type.lowercased().contains("race sim")
        let targetDate = getDateForDay(workout)

        if isBrick {
            let calendar = Calendar.current
            let targetDay = calendar.startOfDay(for: targetDate)
            let hasBike = healthKit.workouts.contains {
                calendar.startOfDay(for: $0.startDate) == targetDay && $0.workoutActivityType == .cycling
            }
            let hasRun = healthKit.workouts.contains {
                calendar.startOfDay(for: $0.startDate) == targetDay && $0.workoutActivityType == .running
            }
            return hasBike && hasRun
        }

        let workoutType = extractWorkoutTypeFromString(workout.type)
        let plannedDurationMinutes = parseWorkoutDuration(workout.duration)
        let toleranceMinutes = 15

        return healthKit.workouts.contains { hkWorkout in
            let calendar = Calendar.current
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            let targetStartOfDay = calendar.startOfDay(for: targetDate)
            guard workoutDate == targetStartOfDay &&
                  workoutTypeMatchesActivityType(plannedType: workoutType, healthKitType: hkWorkout.workoutActivityType)
            else { return false }
            if let plannedMin = plannedDurationMinutes {
                return abs(Int(hkWorkout.duration / 60) - plannedMin) <= toleranceMinutes
            }
            return true
        }
    }

    func isRestDayCompleted(for workout: DayWorkout) -> Bool {
        let targetDate = getDateForDay(workout)
        let calendar = Calendar.current
        let targetStartOfDay = calendar.startOfDay(for: targetDate)
        return !healthKit.workouts.contains { hkWorkout in
            let workoutDate = calendar.startOfDay(for: hkWorkout.startDate)
            guard workoutDate == targetStartOfDay else { return false }
            return hkWorkout.workoutActivityType != .yoga && hkWorkout.workoutActivityType != .walking
        }
    }

    func getDateForDay(_ workout: DayWorkout) -> Date {
        dateForWorkoutDay(workout.day, weekStartDate: currentWeekStartDate)
    }

    var workoutsByDay: [(day: String, workouts: [DayWorkout])] {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let weekMonday = currentWeekStartDate

        guard let week = currentWeek else {
            // Pre-plan or post-plan week: no scheduled workouts, show rest days.
            return dayOrder.map { day in
                let rest = DayWorkout(day: day, type: "Rest", duration: "-", zone: "-",
                                     status: nil, nutritionTarget: nil, notes: nil)
                return (day: day, workouts: [rest])
            }
        }

        let grouped = Dictionary(grouping: week.workouts, by: { $0.day })
        let calendar = Calendar.current
        return dayOrder.enumerated().compactMap { (index, day) in
            let dayDate = calendar.date(byAdding: .day, value: index, to: weekMonday) ?? weekMonday
            if OnboardingStore.isPrePlan(dayDate) {
                let marker = DayWorkout(day: day, type: "Before onboarding", duration: "-", zone: "-",
                                       status: "pre_onboarding", nutritionTarget: nil, notes: nil)
                return (day: day, workouts: [marker])
            }
            if let workouts = grouped[day] { return (day: day, workouts: workouts) }
            let rest = DayWorkout(day: day, type: "Rest", duration: "-", zone: "-",
                                  status: nil, nutritionTarget: nil, notes: nil)
            return (day: day, workouts: [rest])
        }
    }

    // MARK: - Day strip data lookup

    /// Range of week numbers the day strip can scroll through. We allow 8
    /// weeks of pre-plan history so users can swipe back to see HK workouts
    /// recorded before their plan started.
    var dayStripWeekRange: ClosedRange<Int> {
        -8...max(1, trainingPlan.weeks.count)
    }

    /// Builds a WeekStripData for any week in `dayStripWeekRange`, including
    /// pre-plan weeks (where workouts are empty but the date is still computed
    /// from plan-week-1's Monday).
    func weekStripData(forWeek weekNum: Int) -> WeekStripData {
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        let monday: Date = {
            if let week = trainingPlan.getWeek(weekNum) {
                return mondayOfWeek(week.startDate)
            }
            guard let week1 = trainingPlan.getWeek(1) else { return mondayOfWeek(Date()) }
            let planMonday = mondayOfWeek(week1.startDate)
            let offset = weekNum - 1
            return Calendar.current.date(byAdding: .weekOfYear, value: offset, to: planMonday) ?? planMonday
        }()

        if let week = trainingPlan.getWeek(weekNum) {
            let grouped = Dictionary(grouping: week.workouts, by: { $0.day })
            let entries = dayOrder.map { d in DayStripWorkouts(day: d, workouts: grouped[d] ?? []) }
            return WeekStripData(mondayDate: monday, workoutsByDay: entries)
        } else {
            let entries = dayOrder.map { d in DayStripWorkouts(day: d, workouts: []) }
            return WeekStripData(mondayDate: monday, workoutsByDay: entries)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let safeTop = proxy.safeAreaInsets.top
                ScrollView {
                    VStack(spacing: 0) {
                        // ── Hero (full-bleed, under status bar) with nav overlay ──
                        ZStack(alignment: .top) {
                            HomeHeroView(
                                days: daysUntilRace,
                                raceDate: raceDate,
                                raceName: raceName,
                                raceVenue: raceVenue,
                                readinessScore: readinessScore,
                                readinessLabel: readinessLabel,
                                sleepLabel: sleepLabel,
                                hrvLabel: hrvLabel,
                                streakCount: streakCount,
                                streakBroken: streakBroken,
                                raceReadiness: raceReadiness,
                                isSingleSport: activeDisciplineSet.count <= 1,
                                isRaceWeek: isRaceWeek
                            )
                            .padding(.top, safeTop)
                            // Extend the hero's deep-navy backdrop up through the
                            // status-bar area so the top of the screen is full-bleed
                            // brand color rather than the system background.
                            .background(
                                Color(hex: "1B2540")
                                    .ignoresSafeArea(edges: .top)
                            )

                            // Transparent top nav overlaid on hero
                            VStack {
                                PersistentTopNavView(
                                    title: "Today",
                                    isTransparent: true,
                                    weekLabel: navWeekLabel,
                                    onWeekSelector: navWeekLabel != nil ? { showWeekPicker = true } : nil,
                                    onProfile: { router.openSettings() },
                                    onChat: { router.openChat() },
                                    onCalendar: { router.openCalendar() },
                                    onAddWorkout: { router.openLogWorkout() }
                                )
                                .padding(.top, safeTop)
                                Spacer()
                            }
                        }
                        .frame(minHeight: 240)

                        // ── Day strip ──
                        // Paged horizontal scroll: drag to reveal adjacent
                        // weeks' dates underneath the fixed MON–SUN labels,
                        // release to snap to the nearest week.
                        DayStripView(
                            selectedDayIndex: $selectedDayIndex,
                            selectedWeek: $selectedWeek,
                            weekRange: dayStripWeekRange,
                            weekData: weekStripData(forWeek:),
                            today: Date(),
                            onTapDay: { index in
                                withAnimation(.easeInOut(duration: 0.15)) { selectedDayIndex = index }
                            }
                        )
                        .padding(.horizontal, 8)
                        .background(Color(.systemBackground))

                        // ── Cards below ──
                        VStack(spacing: AppTheme.cardSpacing) {
                            // One card per workout — multi-session days (AM/PM) each
                            // get their own full card so the user can scroll to each.
                            let dayLabel = workoutsByDay.indices.contains(selectedDayIndex)
                                ? workoutsByDay[selectedDayIndex].day : "Today"
                            if selectedDayAllWorkouts.isEmpty {
                                SelectedDayWorkoutCard(
                                    workout: nil,
                                    dayLabel: dayLabel,
                                    hkWorkouts: selectedDayHKWorkouts,
                                    isCompleted: false,
                                    onSwap: {},
                                    onLogWorkout: { showLogWorkout = true }
                                )
                            } else {
                                ForEach(Array(selectedDayAllWorkouts.enumerated()), id: \.offset) { _, w in
                                    SelectedDayWorkoutCard(
                                        workout: w,
                                        dayLabel: dayLabel,
                                        hkWorkouts: selectedDayHKWorkouts,
                                        isCompleted: isWorkoutCompleted(w),
                                        onSwap: {
                                            let seed = swapSeed(for: w, on: selectedDayDate)
                                            router.openChat(seed: seed)
                                        },
                                        onLogWorkout: { showLogWorkout = true }
                                    )
                                }
                            }

                            if isRaceWeek {
                                RaceForecastCardView(raceDate: raceDate)
                                PackingListCardView()
                            }

                            CoachNudgeCardView(nudge: coachNudge) {
                                // Prefix tells the LLM (and surfaces to the user
                                // in the input bar) that this prompt originated
                                // from a tap on a home-screen insight rather
                                // than a free user message.
                                router.openChat(seed: "(from app insight) \(coachNudge)")
                            }

                            if showWidgetTip {
                                WidgetTipCard(isVisible: Binding(
                                    get: { showWidgetTip },
                                    set: { newVal in
                                        showWidgetTip = newVal
                                        if !newVal { UserDefaults.standard.set(true, forKey: "widget_tip_dismissed") }
                                    }
                                ))
                            }
                        }
                        .padding(.horizontal, AppTheme.cardPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if !hasAppearedOnce {
                    selectedWeek = trainingPlan.currentWeekNumber
                    selectedDayIndex = HomeView.todayDayIndex()
                    hasAppearedOnce = true
                }
                Task { await fetchHealthData() }
            }
            .onChange(of: trainingPlan.currentWeekNumber) { newValue in
                selectedWeek = newValue
            }
            .onReceive(healthKit.$workouts) { _ in
                syncCompletedWorkoutsToWidget()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToWeek)) { notification in
                if let week = notification.userInfo?["week"] as? Int {
                    withAnimation { selectedWeek = week }
                }
            }
            .sheet(isPresented: $showWeekPicker) {
                WeekPickerSheet(selectedWeek: $selectedWeek, trainingPlan: trainingPlan)
            }
            .sheet(isPresented: $showCourseDetail) {
                CourseDetailView()
            }
            .sheet(isPresented: $showLogWorkout) {
                // Prefill the picker with the highlighted day on the strip;
                // the sheet's own DatePicker lets the user fine-tune time.
                LogWorkoutSheet(
                    prefilledType: hkType(for: selectedDayWorkout?.type ?? "Run"),
                    prefilledDate: selectedDayDate,
                    onSave: { activityType, minutes, end in
                        showLogWorkout = false
                        Task {
                            let start = end.addingTimeInterval(-Double(minutes * 60))
                            try? await healthKit.saveWorkout(activityType: activityType, start: start, end: end)
                            try? await Task.sleep(nanoseconds: 750_000_000)
                            await healthKit.syncWorkouts()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Private helpers

    private func syncCompletedWorkoutsToWidget() {
        guard let week = trainingPlan.getWeek(trainingPlan.currentWeekNumber) else { return }
        let today = todayDayAbbrev
        let completed = Set(week.workouts
            .filter { $0.day == today && !$0.type.contains("Rest") && isWorkoutCompleted($0) }
            .map { $0.type })
        AppGroupConstants.syncTodayCompletedToWidget(completedTypes: completed)
    }

    private func fetchHealthData() async {
        // Sleep
        if let sleep = await healthKit.fetchSleepData(for: Date()) {
            let h = sleep.totalSleepMinutes / 60
            let m = sleep.totalSleepMinutes % 60
            await MainActor.run { sleepLabel = m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        }
        // HRV — use trainingStatusService if available, else latest HK sample
        if let hrv = trainingStatusService.status?.hrvTrend.todaySDNN {
            await MainActor.run { hrvLabel = "\(Int(hrv)) ms" }
        } else {
            let samples = await healthKit.fetchHRVSamples(days: 1)
            if let latest = samples.last {
                let ms = latest.quantity.doubleValue(for: .init(from: "ms"))
                await MainActor.run { hrvLabel = "\(Int(ms)) ms" }
            }
        }
    }

    private func hkType(for workoutType: String) -> HKWorkoutActivityType {
        let t = workoutType.lowercased()
        if t.contains("swim") { return .swimming }
        if t.contains("run") { return .running }
        if t.contains("strength") || t.contains("gym") { return .traditionalStrengthTraining }
        return .cycling // bike / brick
    }
}

// MARK: - Brick leg row
// Single discipline of a brick (bike or run) shown as a row inside the
// "Up next" hero card so the athlete sees both components at a glance.
private struct BrickLegRow: View {
    let emoji: String
    let label: String
    let duration: String
    let accent: Color
    var paceSuffix: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(accent).frame(width: 8, height: 8)
            Text("\(emoji) \(label)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Text(duration + (paceSuffix.map { " · \($0)" } ?? ""))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(.systemGray))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
