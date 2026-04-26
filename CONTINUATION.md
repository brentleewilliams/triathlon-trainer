# Home Screen Redesign — Continuation Doc

**Branch:** `claude/implement-home-redesign-kimaH`
**Status:** ~70% done — `HomeView.swift` rewrite is the remaining blocker.
**Picked variant:** "Bold" (the right-hand mock from the design fetch).

## To resume in terminal

```bash
git fetch origin claude/implement-home-redesign-kimaH
git checkout claude/implement-home-redesign-kimaH
claude
# Paste this file's "What's left" section as the first prompt.
```

## What's done (committed)

| Commit | File | Change |
|---|---|---|
| `2cae6f1` | `AppConstants.swift` | Added `Notification.Name.navigateToChat` |
| `2cae6f1` | `ContentView.swift` | TabView now uses `selectedTab: Int` state with `.tag(0..3)`; subscribes to `.navigateToChat` and switches to tab 2 (Coach) |
| `2cae6f1` | `HealthKitManager.swift` | Added `saveWorkout(activityType:start:end:)` async, plus `HKObjectType.workoutType()` to write permissions |
| `eb65303` | `LogWorkoutSheet.swift` | New file (243 lines) — modal sheet with sport-type chip grid (Swim/Bike/Run/Brick/Strength/Other) + hours×minutes wheel pickers + "Log Workout" button. Signature: `init(prefilledType: HKWorkoutActivityType, onSave: (HKWorkoutActivityType, Int) -> Void)` |

## What's left

### 1. Rewrite `IronmanTrainer/IronmanTrainer/HomeView.swift` (the big one)

Current file is the **old 519-line** version. Needs full rewrite to bold design.

**Must preserve** (DayRowComponents.swift and WorkoutDayRows.swift call into HomeView):
- Top-level `func mondayOfWeek(_:) -> Date`
- `struct WidgetTipCard` and `struct WidgetInstructionsSheet`
- On `HomeView`: `@EnvironmentObject healthKit`, `@EnvironmentObject trainingPlan`, `@State selectedWeek: Int`, `@State draggedFromDay`, `@State draggedWorkout`
- Methods: `isWorkoutCompleted(_:)`, `isRestDayCompleted(for:)`, `getDateForDay(_:)` — keep exact signatures (called as `parent.isWorkoutCompleted(...)` from DayRowComponents.swift:34, parent.isRestDayCompleted from line 335, parent.healthKit.workouts from line 85)

**Must remove:** `struct ReadinessHomeBadge` (replaced by hero readiness pills).

**New body composition** (top → bottom):
1. **Full-bleed hero** (~280pt + safe area top) — bleeds under status bar
   - `HomeCourseBackdrop` — Canvas-based: navy→teal sky gradient, sun glow circles at (305, 76), two mountain ridge `Path`s, water rect with specular lines (see `HomeBold.jsx:31-73` for SVG paths in 390×280 viewBox — scale to actual size)
   - Race name eyebrow + venue (top-left), Week N · Phase pill (top-right)
   - Massive animated countdown number (96pt, weight 800, tabular nums) — eases from `target + min(40, target*0.5)` down to `target` over ~900ms with easeOutCubic. Use a `Task` with `Task.sleep(30ms)` × 30 steps.
   - "DAYS TO RACE" caption next to it; race date on next line
   - Streak chip pinned right (🔥 emoji + "N-day streak" + sub)
   - Row of 3 pills below: Readiness (with progress ring), Sleep, HRV — translucent white, blur background
   - Race-ready traffic light row (skip if single-sport): "RACE-READY" eyebrow + Swim/Bike/Run with colored dots
2. **TodayTomorrowCard** — overlaps hero by 18pt (negative top padding)
   - Two tabs: Today / Tomorrow with sport-colored top bar
   - Eyebrow + sport chip + (✓ Done if completed)
   - Big title (24pt 700)
   - Duration · distance · zone meta line
   - "Why" tinted box explaining the session purpose
   - **TimelineStrip**: horizontal bar broken into intervals (warm-up 35% opacity, main 100%, cool-down 30% opacity). Width proportional to minutes. Synthesize 3 intervals from workout type+duration since `DayWorkout` has no interval data: 15-20% warm-up, 60-70% main, 15-20% cool-down.
   - 2×2 meta grid: Weather, Route, Fueling, Effort
   - Today CTAs: `[Start workout]` (sport-colored, full width) `[Swap]` (gray, posts `.navigateToChat`)
   - Tomorrow CTAs: `[View full plan]` `[Move]`
   - **Wire `[Start workout]` → `showLogWorkout = true` → `LogWorkoutSheet`** with `onSave` calling `healthKit.saveWorkout(...)` then `healthKit.syncWorkouts()`
3. **HomeRaceReadinessCard** — single composite for single-sport, per-sport rows for tri
   - "Race readiness" header + overall score
   - Per-sport rows: colored dot, sport name, status label, gap text, score number
   - When a discipline is at risk (`status != green` AND not today's sport), show inline indented swap CTA: `[Swap today]` posts `.navigateToChat`
   - Compute per-sport status from `trainingStatusService.status?.disciplineGaps` and `fitnessPerDiscipline[disc].tsb`. Score buckets: green ≥75, amber 50–74, red <50.
4. **HomeCoachNudgeCard** — purple bolt icon + "COACH" eyebrow + nudge text
   - Derive nudge from `trainingStatusService.status?.readiness.score`
5. **WidgetTipCard** if `showWidgetTip`
6. **Race-week mode** (`daysUntilRace ≤ 7`): replace race-readiness card with `HomeRaceForecastCard` + `HomePackingListCard`. Use `WeatherForecast.forecast(for: raceDate)` for forecast.

**Layout pattern** for full-bleed hero in NavigationStack:
```swift
NavigationStack {
    GeometryReader { proxy in
        let safeTop = proxy.safeAreaInsets.top
        ScrollView {
            VStack(spacing: 0) {
                HeroView(safeTop: safeTop, ...)
                    .frame(minHeight: 280 + safeTop)
                VStack(spacing: 10) { /* cards */ }
                    .padding(.horizontal, 16)
                    .padding(.top, -18)  // overlap hero
                    .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
    .toolbar(.hidden, for: .navigationBar)
}
```

### 2. Build verification

```bash
cd /home/user/triathlon-trainer
xcodebuild build -scheme "IronmanTrainer" \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

### 3. Commit + push + draft PR

```bash
git add IronmanTrainer/IronmanTrainer/HomeView.swift
git commit -m "feat: bold home redesign — full-bleed hero, today/tomorrow tabs, race readiness traffic lights"
git push -u origin claude/implement-home-redesign-kimaH
```

Then create a **draft PR** via GitHub MCP (`mcp__github__create_pull_request`, `draft: true`). Repo is `brentleewilliams/triathlon-trainer`. Base is whatever main is — check with `gh repo view` or list_pull_requests.

## Design source (already extracted on this machine)

```
/tmp/design_extract/race1-trainer-design-system/
├── project/home_redesign/
│   ├── HomeBold.jsx       ← THE design (the variant we're building)
│   ├── HomeData.jsx       ← scenarios, scoring formulas
│   ├── Primitives.jsx     ← sport colors, Icon set
│   └── Home redesign.html ← entry point
└── chats/
    ├── chat1.md           ← initial design build
    └── chat2.md           ← refinement (Bold variant chosen)
```

If `/tmp/design_extract` is gone, refetch:
```bash
curl -L -o /tmp/design.tgz "https://api.anthropic.com/v1/design/h/3IFhXv-SpkvLzzedbh6Z7Q"
mkdir -p /tmp/design_extract && tar xzf /tmp/design.tgz -C /tmp/design_extract
```

## Key data references inside the codebase

| Need | Source |
|---|---|
| Today/tomorrow workout | `currentWeek?.workouts.first { $0.day == "Mon"/etc. }` from `TrainingPlanManager.swift:71` (`DayWorkout` struct) |
| Readiness score + level | `trainingStatusService.status?.readiness.score` and `.level` (`.race`/`.fresh`/`.training`/`.tired`/`.overreached`) — `TrainingStatusService.swift:81` |
| TSB (form) | `trainingStatusService.status?.combinedTSB` |
| HRV | `trainingStatusService.status?.hrvTrend.todaySDNN` (Double? in ms) |
| Sleep | `await healthKit.fetchSleepData(for: Date())` returns `SleepSummary?` with `totalSleepMinutes` — `HealthKitManager.swift:9` |
| Discipline gaps | `trainingStatusService.status?.disciplineGaps` — each has `.discipline` (`.swim`/`.bike`/`.run`), `.daysSinceLastSession`, `.severity` (`.critical`/`.warning`) |
| Race date | `UserDefaults.standard.object(forKey: "race_date") as? Double` (timeIntervalSince1970), fallback July 19 2026 |
| Race name/venue | `RaceCourseService.shared.currentProfile?.raceName / .venue` if loaded, else hardcode "Pacific NW 70.3" / "Cascade Lake — Bend, OR" |
| Weather (deterministic) | `WeatherForecast.forecast(for: Date())` — `TrainingPlanManager.swift:206` |
| HKWorkoutActivityType for sport | swim→`.swimming`, bike→`.cycling`, run→`.running`, strength→`.traditionalStrengthTraining`, brick→`.cycling` |

## Sport colors (from Primitives.jsx)

```swift
// Don't redefine Color(hex:) — it's already in OnboardingView.swift
let swimColor     = Color(hex: "007AFF")
let bikeColor     = Color(hex: "00A89E")  // teal
let runColor      = Color(hex: "FF9500")
let strengthColor = Color(hex: "AF52DE")
let brickColor    = Color(hex: "FF3B30")
let restColor     = Color(hex: "8E8E93")
```

## Status bucket labels/colors (race readiness)

```swift
// score >= 75 → green "On track"
// score 50–74 → amber "Slipping"
// score < 50  → red "Behind"
let statusGreen = Color(hex: "34C759")
let statusAmber = Color(hex: "FF9500")
let statusRed   = Color(hex: "FF3B30")
```

## Backdrop SVG paths (scale from 390×280 viewBox to actual size)

```
Far ridge:  M0 168 L40 138 L75 156 L115 118 L160 148 L210 108 L250 142 L295 118 L340 146 L390 130 L390 280 L0 280 Z
            fill #15263A opacity .70
Near ridge: M0 202 L35 175 L80 198 L130 158 L185 195 L235 165 L290 200 L335 182 L390 206 L390 280 L0 280 Z
            fill #0C1B2C opacity .90
Sky:        rect 0,0 → 390,280, gradient 0:#1B2540 → .55:#28456A → 1:#2E6480
Sun glow:   3 concentric circles at (305, 76), radii 48/24/10, fills white .10/.18/.32
Water:      rect y=218 h=62, gradient 0:#1A3B52 → 1:#0E2435
```

## Things that surfaced during research (gotchas)

- `Color(hex:)` is **already defined** in `OnboardingView.swift` — DO NOT redefine, it'll cause "ambiguous use" compile errors.
- `HKWorkoutActivityType` doesn't conform to `Equatable` in some SDK versions — `LogWorkoutSheet.swift` matches on `.rawValue` for `prefilledType` lookup. Mirror that pattern if comparing types in HomeView.
- `DayWorkout` has no interval data — synthesize warm/main/cool from `parseWorkoutDuration(workout.duration)`.
- The `parent: HomeView` pattern in `DayRowComponents.swift` and `WorkoutDayRows.swift` means HomeView **is still passed by value to those structs** — keep methods on `HomeView`, don't move them to a view model.
- Animating `Int` in SwiftUI doesn't work with `withAnimation` directly. Use a `Task` loop with `Task.sleep(nanoseconds: 30_000_000)` for the countdown easeOutCubic over 30 frames.
- Old HomeView swiped between weeks via `DragGesture`. The new design has no week nav at all (week shown only in hero pill, not switchable from Home). Week navigation moved to **Plan tab** — confirm that's the intended product behavior before deleting the gesture.

## TodoWrite list (current state)

1. ✅ Add navigateToChat notification + tab selection to AppConstants + ContentView
2. ✅ Add saveWorkout to HealthKitManager + write permission
3. ✅ Create LogWorkoutSheet (type + duration)
4. ⏳ Write new HomeView.swift (hero, cards, all sub-views) — **THIS IS THE BLOCKER**
5. ⏳ Commit and push, create draft PR
