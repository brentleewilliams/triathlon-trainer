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

private let swimColor     = Color(hex: "007AFF")
private let bikeColor     = Color(hex: "00A89E")
private let runColor      = Color(hex: "FF9500")
private let strengthColor = Color(hex: "AF52DE")
private let brickColor    = Color(hex: "FF3B30")
private let restColor     = Color(hex: "8E8E93")

private func sportColor(for type: String) -> Color {
    let t = type.lowercased()
    if t.contains("swim") { return swimColor }
    if t.contains("brick") || t.contains("race sim") { return brickColor }
    if t.contains("bike") || t.contains("cycl") { return bikeColor }
    if t.contains("run") { return runColor }
    if t.contains("strength") || t.contains("gym") { return strengthColor }
    return restColor
}

private func sportEmoji(for type: String) -> String {
    let t = type.lowercased()
    if t.contains("swim") { return "🏊" }
    if t.contains("brick") || t.contains("race sim") { return "🚴🏃" }
    if t.contains("bike") || t.contains("cycl") { return "🚴" }
    if t.contains("run") { return "🏃" }
    if t.contains("strength") || t.contains("gym") { return "💪" }
    return "😴"
}

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

    enum Status { case green, amber, red }

    var statusColor: Color {
        switch status {
        case .green: return Color(hex: "34C759")
        case .amber: return Color(hex: "FF9500")
        case .red:   return Color(hex: "FF3B30")
        }
    }

    var statusLabel: String {
        switch status {
        case .green: return "On track"
        case .amber: return "Slipping"
        case .red:   return "Behind"
        }
    }
}

private func deriveRaceReadiness(from status: TrainingStatus?, today sport: String) -> [SportReadiness] {
    let disciplines: [(String, TrainingDiscipline)] = [
        ("Swim", .swim), ("Bike", .bike), ("Run", .run)
    ]
    return disciplines.map { (name, disc) in
        let gap = status?.disciplineGaps.first { $0.discipline == disc }
        let fitness = status?.fitnessPerDiscipline.first { $0.discipline == disc }
        let combinedCTL = status?.combinedFitness?.ctl ?? 1.0

        // Build a rough score from gap severity + fitness contribution
        var baseScore = 75
        if let g = gap {
            switch g.severity {
            case .critical:  baseScore = 30
            case .warning:   baseScore = 52
            case .caution:   baseScore = 62
            case .none:      baseScore = 80
            }
        }
        // Adjust by fitness vs combined baseline
        if let f = fitness, combinedCTL > 0 {
            let ratio = f.ctl / combinedCTL
            let adj = Int((ratio - 0.33) * 30)
            baseScore = max(10, min(95, baseScore + adj))
        }

        let sportStatus: SportReadiness.Status = baseScore >= 75 ? .green : baseScore >= 50 ? .amber : .red
        let gapText: String = {
            if let g = gap {
                if g.isMissing { return "No sessions in \(g.daysSinceLastSession) days" }
                if g.isUndertrained { return "Undertrained vs. other disciplines" }
                if g.daysSinceLastSession > 7 { return "No session in \(g.daysSinceLastSession) days" }
            }
            return "On plan"
        }()
        let action: String? = sportStatus != .green && name.lowercased() != sport.lowercased()
            ? "Swap today for a \(name.lowercased()) session" : nil

        return SportReadiness(sport: name, score: baseScore, status: sportStatus,
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

            VStack(alignment: .leading, spacing: 2) {
                Text("READINESS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.70))
                    .kerning(0.6)
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
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
    let raceName: String
    let raceVenue: String
    let weekNum: Int
    let phase: String
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(raceName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .kerning(0.8)
                        Text(raceVenue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.72))
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(phaseColor(for: phase))
                            .frame(width: 7, height: 7)
                            .shadow(color: phaseColor(for: phase).opacity(0.6), radius: 3)
                        Text("Wk \(weekNum) · \(phase)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial.opacity(0.9))
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
                }
                .padding(.top, 18)

                // Countdown row
                HStack(alignment: .bottom, spacing: 14) {
                    // Number + label
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(animatedDays)")
                            .font(.system(size: 96, weight: .black))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isRaceWeek ? "DAYS · RACE WEEK" : "DAYS TO RACE")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .kerning(0.8)
                            Text("Jul 19, 2026 · \(phase.prefix(4))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.bottom, 10)
                    }

                    Spacer()

                    StreakChipView(count: streakCount, isBroken: streakBroken)
                        .padding(.bottom, 8)
                }
                .padding(.top, 14)

                // Readiness pills row
                HStack(spacing: 8) {
                    ReadinessPillView(score: readinessScore, label: readinessLabel)
                    StatPillView(label: "Sleep", value: sleepLabel)
                    StatPillView(label: "HRV", value: hrvLabel)
                }
                .padding(.top, 16)

                // Race-ready traffic lights (tri only)
                if !isSingleSport && !raceReadiness.isEmpty {
                    HStack(spacing: 10) {
                        Text("RACE-READY")
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

                Spacer(minLength: 28)
            }
            .padding(.horizontal, 22)
        }
        .frame(minHeight: 280)
        .onAppear {
            let target = days
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
            .background(Color(hex: "FAFAFC"))
        }
    }

    @ViewBuilder
    private func ctaRow(_ workout: DayWorkout) -> some View {
        let isToday = selectedTab == .today

        if isToday {
            if !afterWorkout {
                HStack(spacing: 8) {
                    Button(action: onLogWorkout) {
                        Text("Start workout")
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

// MARK: - Race readiness card

struct RaceReadinessCardView: View {
    let readiness: [SportReadiness]
    let overall: Int
    let onSwap: () -> Void

    private var overallColor: Color {
        overall >= 75 ? Color(hex: "34C759") : overall >= 50 ? Color(hex: "FF9500") : Color(hex: "FF3B30")
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

    var body: some View {
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
                Text("COACH")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(.systemGray))
                    .kerning(0.6)
                Text(nudge)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray5), lineWidth: 0.5))
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
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @EnvironmentObject var trainingStatusService: TrainingStatusService

    // Keep for DayRowComponents / WorkoutDayRows parent references
    @State var selectedWeek: Int = 1
    @State var draggedFromDay: String?
    @State var draggedWorkout: DayWorkout?

    // New state
    @State private var showWidgetTip: Bool = !UserDefaults.standard.bool(forKey: "widget_tip_dismissed")
    @State private var showCourseDetail: Bool = false
    @State private var showLogWorkout: Bool = false
    @State private var sleepLabel: String = "—"
    @State private var hrvLabel: String = "—"
    @State private var hasAppearedOnce = false

    // MARK: Race date
    var raceDate: Date {
        if let ts = UserDefaults.standard.object(forKey: "race_date") as? Double {
            return Date(timeIntervalSince1970: ts)
        }
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 19
        return Calendar.current.date(from: c) ?? Date()
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
    var raceReadiness: [SportReadiness] {
        deriveRaceReadiness(
            from: trainingStatusService.status,
            today: todayWorkout?.type ?? ""
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
    var raceName: String {
        RaceCourseService.shared.currentProfile?.raceName ?? "Race1 — Pacific NW 70.3"
    }
    var raceVenue: String {
        RaceCourseService.shared.currentProfile?.venue ?? "Cascade Lake — Bend, OR"
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
        dateForWorkoutDay(workout.day, weekStartDate: mondayOfWeek(currentWeek?.startDate ?? Date()))
    }

    var workoutsByDay: [(day: String, workouts: [DayWorkout])] {
        guard let week = currentWeek else { return [] }
        let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let grouped = Dictionary(grouping: week.workouts, by: { $0.day })
        let calendar = Calendar.current
        let weekMonday = mondayOfWeek(week.startDate)
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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let safeTop = proxy.safeAreaInsets.top
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero (full-bleed, under status bar)
                        HomeHeroView(
                            days: daysUntilRace,
                            raceName: raceName,
                            raceVenue: raceVenue,
                            weekNum: selectedWeek,
                            phase: currentPhase,
                            readinessScore: readinessScore,
                            readinessLabel: readinessLabel,
                            sleepLabel: sleepLabel,
                            hrvLabel: hrvLabel,
                            streakCount: streakCount,
                            streakBroken: streakBroken,
                            raceReadiness: raceReadiness,
                            isSingleSport: false,
                            isRaceWeek: isRaceWeek
                        )
                        .padding(.top, safeTop)

                        // Cards below hero
                        VStack(spacing: 10) {
                            // Today / Tomorrow workout card
                            WorkoutTabCardView(
                                todayWorkout: todayWorkout,
                                tomorrowWorkout: tomorrowWorkout,
                                afterWorkout: afterWorkout,
                                onSwap: {
                                    NotificationCenter.default.post(name: .navigateToChat, object: nil)
                                },
                                onViewPlan: {
                                    // Plan tab not yet wired — navigate to chat for now
                                    NotificationCenter.default.post(name: .navigateToChat, object: nil)
                                },
                                onLogWorkout: { showLogWorkout = true }
                            )

                            if isRaceWeek {
                                // Race week: forecast + packing list
                                RaceForecastCardView(raceDate: raceDate)
                                PackingListCardView()
                            } else {
                                // Normal: race readiness
                                RaceReadinessCardView(
                                    readiness: raceReadiness,
                                    overall: raceReadinessOverall,
                                    onSwap: {
                                        NotificationCenter.default.post(name: .navigateToChat, object: nil)
                                    }
                                )
                            }

                            CoachNudgeCardView(nudge: coachNudge)

                            if showWidgetTip {
                                WidgetTipCard(isVisible: Binding(
                                    get: { showWidgetTip },
                                    set: { newVal in
                                        showWidgetTip = newVal
                                        if !newVal {
                                            UserDefaults.standard.set(true, forKey: "widget_tip_dismissed")
                                        }
                                    }
                                ))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, -18)
                        .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if !hasAppearedOnce {
                    selectedWeek = trainingPlan.currentWeekNumber
                    hasAppearedOnce = true
                }
                Task { await fetchHealthData() }
            }
            .onChange(of: trainingPlan.currentWeekNumber) { newValue in
                selectedWeek = newValue
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToWeek)) { notification in
                if let week = notification.userInfo?["week"] as? Int {
                    withAnimation { selectedWeek = week }
                }
            }
            .sheet(isPresented: $showCourseDetail) {
                CourseDetailView()
            }
            .sheet(isPresented: $showLogWorkout) {
                if let workout = todayWorkout {
                    LogWorkoutSheet(
                        prefilledType: hkType(for: workout.type),
                        onSave: { activityType, minutes in
                            showLogWorkout = false
                            Task {
                                let now = Date()
                                let start = now.addingTimeInterval(-Double(minutes * 60))
                                try? await healthKit.saveWorkout(activityType: activityType, start: start, end: now)
                                await healthKit.syncWorkouts()
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Private helpers

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
