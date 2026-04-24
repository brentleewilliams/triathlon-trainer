# TrainingStatusService — Build Spec
*Created 2026-04-24. Pick up this build in a fresh session.*

## Context
This spec was produced after a deep research session on 2025-era triathlon training science (CTL/ATL/TSB, HRV, aerobic decoupling, discipline balance). The goal is to add a `TrainingStatusService` that computes training load metrics from HealthKit and surfaces them in Claude's coaching context, Analytics, Home, and the morning check-in.

**Start a new session by saying:** "Read `docs/prd-training-status-service.md` and implement the TrainingStatusService feature. Use multiple parallel agents."

---

## What to Build

### New file: `IronmanTrainer/TrainingStatusService.swift`

#### Models

```swift
import Foundation
import HealthKit

enum TrainingDiscipline: String, CaseIterable, Codable {
    case swim, bike, run, combined
}

struct FitnessMetrics: Codable, Equatable {
    let discipline: TrainingDiscipline
    let ctl: Double            // chronic training load (42-day EWA)
    let atl: Double            // acute training load (7-day EWA)
    var tsb: Double { ctl - atl }
    let lastSessionDaysAgo: Int?
    let weeklySessionCount: Int
}

struct DisciplineGap: Codable, Equatable {
    let discipline: TrainingDiscipline
    let daysSinceLastSession: Int
    let weeklySessionCount: Int
    let ctlVsHighest: Double        // this discipline's CTL / highest CTL (0–1)

    var isMissing: Bool { daysSinceLastSession > 14 }
    var isUndertrained: Bool { ctlVsHighest < 0.30 && !isMissing }

    enum GapSeverity: String, Codable { case critical, warning, caution, none }
    var severity: GapSeverity {
        if isMissing { return .critical }
        if isUndertrained { return .warning }
        if daysSinceLastSession > 7 { return .caution }
        return .none
    }
}

struct HRVTrend: Codable, Equatable {
    let todaySDNN: Double?
    let sevenDayAvg: Double?
    let sixtyDayBaseline: Double?
    var percentFromBaseline: Double? {
        guard let t = todaySDNN, let b = sixtyDayBaseline, b > 0 else { return nil }
        return ((t - b) / b) * 100.0
    }
    enum Direction: String, Codable { case improving, stable, declining, insufficient }
    var direction: Direction {
        guard let pct = percentFromBaseline else { return .insufficient }
        if pct > 3 { return .improving }
        if pct < -5 { return .declining }
        return .stable
    }
}

struct DecouplingResult: Codable, Equatable {
    let workoutDate: Date
    let discipline: TrainingDiscipline
    let decouplingPercent: Double   // (EF_first - EF_second) / EF_first × 100
    let durationMinutes: Double
    var isRaceReady: Bool { decouplingPercent < 5.0 }
}

enum IntensityPattern: String, Codable {
    case polarized        // Z1+Z2 ≥78%, Z3 <10%
    case pyramidal        // Z1+Z2 60-78%, Z3 10-20%
    case thresholdHeavy   // Z3+Z4 >30%
    case mixed
    case insufficientData
}

struct LoadSpike: Codable, Equatable {
    let currentWeekHRSS: Double
    let priorWeekHRSS: Double
    var increasePercent: Double {
        guard priorWeekHRSS > 0 else { return 0 }
        return ((currentWeekHRSS - priorWeekHRSS) / priorWeekHRSS) * 100.0
    }
    var isSpiked: Bool { increasePercent > 15 }
    var isCritical: Bool { increasePercent > 25 }
}

struct CompositeReadiness: Codable, Equatable {
    let score: Int        // 0–100
    let tsbScore: Int     // 0–40
    let hrvScore: Int     // 0–30
    let loadSpikeScore: Int  // 0–30

    enum Level: String, Codable {
        case race, fresh, training, tired, overreached
    }
    var level: Level {
        switch score {
        case 80...: return .race
        case 60..<80: return .fresh
        case 40..<60: return .training
        case 20..<40: return .tired
        default: return .overreached
        }
    }
}

struct TrainingStatus: Codable, Equatable {
    let computedAt: Date
    let fitnessPerDiscipline: [FitnessMetrics]   // .swim, .bike, .run, .combined
    let disciplineGaps: [DisciplineGap]           // triathlon disciplines only
    let hrvTrend: HRVTrend
    let recentDecoupling: [DecouplingResult]      // last 5 runs/bikes ≥60 min
    let intensityPattern: IntensityPattern
    let loadSpike: LoadSpike
    let readiness: CompositeReadiness

    var combinedFitness: FitnessMetrics? { fitnessPerDiscipline.first { $0.discipline == .combined } }
    var combinedTSB: Double? { combinedFitness?.tsb }
    var criticalGaps: [DisciplineGap] { disciplineGaps.filter { $0.severity == .critical } }
    var warningGaps: [DisciplineGap] { disciplineGaps.filter { $0.severity == .warning } }
}
```

#### Service class pattern
- `@MainActor final class TrainingStatusService: ObservableObject`
- `@Published var status: TrainingStatus?`
- `@Published var isComputing = false`
- `func compute() async` — main entry point, called on foreground sync
- Persists result to `UserDefaults` key `"trainingStatus_v1"` as JSON (6h cache)
- `func contextString(brief: Bool = false) -> String` — plain-text summary for LLM

#### HRSS formula
```
LTHR = maxHR × 0.89
HRSS = durationHours × (avgHR / LTHR)² × 100
```

#### EWA formulas
```
CTL lambda = 2 / (42 + 1) = 0.04651   // 42-day fitness
ATL lambda = 2 / (7 + 1)  = 0.25      // 7-day fatigue
TSB = CTL − ATL                         // form
```
EWA iterates daily values chronologically. Initialize with first non-zero day, then: `ewa = λ × value + (1 − λ) × ewa`.

#### Aerobic decoupling
Only for runs/bikes ≥60 min with ≥40 HR samples and ≥20 distance samples.
```
Split workout at midpoint by timestamp
EF (efficiency factor) = avg_pace_m_s / avg_HR
Decoupling% = (EF_first − EF_second) / EF_first × 100
Race-ready threshold: < 5%
```

#### Composite readiness scoring
| Signal | Points |
|--------|--------|
| TSB +10 to +20 | 40 |
| TSB +5 to +10 | 32 |
| TSB +20 to +30 | 30 |
| TSB 0 to +5 | 22 |
| TSB +30 to +40 | 20 |
| TSB −10 to 0 | 12 |
| TSB −20 to −10 | 6 |
| TSB < −20 or > +40 | 0 |
| HRV ≥+5% baseline | 30 |
| HRV 0–5% | 22 |
| HRV −5 to 0% | 14 |
| HRV −10 to −5% | 7 |
| HRV < −10% | 0 |
| No HRV data | 15 (neutral) |
| No load spike | 30 |
| Spike >15% | 15 |
| Spike >25% (critical) | 0 |

#### Intensity pattern classification (from zone cache)
```
Polarized:      Z1+Z2 ≥ 78% AND Z3 < 10%
ThresholdHeavy: Z3+Z4 > 30%
Pyramidal:      Z1+Z2 60–78%
Mixed:          everything else
```

#### Discipline gap detection (triathlon users)
- `isMissing`: no sessions in 14+ days → severity `.critical`
- `isUndertrained`: CTL < 30% of the highest-CTL discipline → severity `.warning`
- `daysSinceLastSession > 7` → severity `.caution`

#### LLM context string (brief vs full)
Brief (2 lines, for check-in):
```
READINESS: 72/100 (Fresh) — Form: +8, HRV: +4% above baseline
⚠️ DISCIPLINE GAPS: Swim (18d gap)
```
Full (for Claude coaching context):
```
====== TRAINING STATUS ======
Overall — CTL: 85 | ATL: 92 | Form (TSB): -7
Readiness: 68/100 (Fresh)
HRV: 54 ms today, +4% vs 60-day baseline (improving)
⚠️ DISCIPLINE GAPS: Swim (18d gap) — athlete has not trained these in 14+ days
  Swim — CTL: 12 | ATL: 0 | TSB: +12 | Last: 18d ago | This week: 0x
  Bike — CTL: 95 | ATL: 105 | TSB: -10 | Last: 1d ago | This week: 3x
  Run — CTL: 78 | ATL: 82 | TSB: -4 | Last: 2d ago | This week: 2x
Intensity pattern (14d): pyramidal
Aerobic decoupling (last run ≥60min): 3.2% (✅ race-ready)
```

---

## HealthKitManager.swift Changes

**File:** `IronmanTrainer/HealthKitManager.swift`

### 1. Add HRV to `requiredHKTypes`
Add to the set:
```swift
HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
```

### 2. Extend workout window 30 → 60 days
Find the line creating a date 30 days ago for workout sync and change to 60 days.

### 3. Add 4 new async methods (follow `fetchSleepData` pattern exactly)
```swift
func fetchHRSamples(for workout: HKWorkout) async -> [HKQuantitySample]
func fetchHRSamples(from startDate: Date, to endDate: Date) async -> [HKQuantitySample]
func fetchDistanceSamples(for workout: HKWorkout) async -> [HKQuantitySample]
// distanceCycling for .cycling, distanceWalkingRunning for everything else
func fetchHRVSamples(days: Int = 60) async -> [HKQuantitySample]
// type: HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
```
All use `HKSampleQuery` with `HKObjectQueryNoLimit`, ascending sort, `withCheckedContinuation`.

---

## ChatViewModel.swift Changes

**File:** `IronmanTrainer/ChatViewModel.swift`

1. Add property after `var healthKit: HealthKitManager?`:
```swift
var trainingStatus: TrainingStatusService?
```
2. In `getContextForClaude()`, just before `return context`:
```swift
if let ts = trainingStatus?.status {
    context += "\n\n" + ts.contextString(brief: false)
}
```

---

## CheckInManager.swift Changes

**File:** `IronmanTrainer/CheckInManager.swift`

1. Add `trainingStatus: TrainingStatusService? = nil` parameter to `prepareCheckInContext`
2. After the sleep block, before `return out`:
```swift
if let ts = trainingStatus?.status {
    out += "\n\(ts.contextString(brief: true))\n"
}
```

---

## AnalyticsView.swift Changes

**File:** `IronmanTrainer/AnalyticsView.swift`

Add `@EnvironmentObject var trainingStatusService: TrainingStatusService`.

Insert a new **"Training Load & Readiness"** card between the last content section and `Spacer()`:

```
VStack card containing:
  - Title: "Training Load & Readiness"
  - ReadinessBadgeView (large circle, score, level label, colored ring)
  - FitnessMetricsRow: CTL / ATL / TSB (three cells, TSB colored by value)
  - DisciplineBalanceRow: horizontal bar showing swim/bike/run CTL proportions
    → highlight any discipline with a critical/warning gap in red/orange
  - HRVTrendRow: today SDNN, 7d avg, % from baseline, trend arrow
  - IntensityPatternRow: label + color (green=polarized, yellow=pyramidal, red=threshold-heavy)
  - LoadSpikeWarningRow: only shown if isSpiked — orange warning + %
  - DecouplingRow: % + ✅/❌ race-ready indicator
```

**DisciplineBalanceRow** is the key new UI for the "low on one type" requirement. Show three labeled segments (Swim / Bike / Run) as proportional bars based on CTL. If any discipline's `severity == .critical`, show it in red with a "⚠️ No sessions in 14d" label. If `.warning`, show orange with "Undertrained".

---

## HomeView.swift Changes

**File:** `IronmanTrainer/HomeView.swift`

Add `@EnvironmentObject var trainingStatusService: TrainingStatusService`.

Insert `ReadinessHomeBadge` between WeekNavigationHeader and the sync error display:

```swift
if let ts = trainingStatusService.status {
    ReadinessHomeBadge(readiness: ts.readiness, tsb: ts.combinedTSB, gaps: ts.criticalGaps)
}
```

`ReadinessHomeBadge` — compact horizontal card:
- Colored circle with readiness score (green/blue/yellow/orange/red)
- Level label + TSB form value
- If any `criticalGaps`: show a small red pill "⚠️ No [swim/bike/run] in 14d"

---

## ContentView.swift Changes

**File:** `IronmanTrainer/ContentView.swift`

1. Add `@StateObject private var trainingStatus = TrainingStatusService(healthKit: healthKit)` — read the file to see how `healthKit` is currently initialized and match the pattern
2. Pass `.environmentObject(trainingStatus)` to `HomeView`, `AnalyticsView`, and the `CheckInView` sheet
3. In `.onAppear` or scene phase handler, add: `Task { await trainingStatus.compute() }`
4. Pass `trainingStatus` to `chatViewModel`: `chatViewModel.trainingStatus = trainingStatus`

---

## Tests: `IronmanTrainerTests/TrainingStatusServiceTests.swift`

Test only pure static/instance methods — no live HealthKit. Pattern: `@testable import Race1_Trainer`, `@MainActor` where needed.

### HRSS tests
- `testHRSS_typicalRun`: 1h at 155 bpm, maxHR=182 → LTHR=161.98 → result ≈ 91.9
- `testHRSS_zeroDuration`: returns 0
- `testHRSS_hrAboveLTHR`: result > 100 (valid)

### EWA tests
- `testEWA_allZeros`: returns 0
- `testEWA_singleDay_CTL`: one 100-pt day → CTL result < 100 (slow build)
- `testEWA_singleDay_ATL`: same day → ATL result > CTL result (faster response)
- `testEWA_decayWithRest`: 100 pts day 0, zeros for 7 days → ATL decays faster than CTL

### Intensity pattern tests
- `testPattern_polarized`: Z1=50,Z2=30,Z3=8,Z4=10,Z5=2 → `.polarized`
- `testPattern_pyramidal`: Z1=40,Z2=30,Z3=15,Z4=10,Z5=5 → `.pyramidal`
- `testPattern_thresholdHeavy`: Z1=20,Z2=20,Z3=20,Z4=15,Z5=5 → `.thresholdHeavy`

### Load spike tests
- `testSpike_none`: current=200, prior=190 → `isSpiked == false`
- `testSpike_spiked`: current=240, prior=200 → `isSpiked == true`
- `testSpike_critical`: current=260, prior=200 → `isCritical == true`
- `testSpike_priorZero`: no divide-by-zero, `increasePercent == 0`

### Readiness tests
- `testReadiness_optimal`: TSB=+15, HRV +6%, no spike → score ≥ 80
- `testReadiness_negativeTSB`: TSB=−25 → `tsbScore == 0`
- `testReadiness_lowHRV`: HRV −12% → `hrvScore == 0`
- `testReadiness_criticalSpike`: critical spike → `loadSpikeScore == 0`

### Decoupling tests
- `testDecoupling_raceReady`: ef1=0.110, ef2=0.108 → 1.8%, `isRaceReady == true`
- `testDecoupling_notRaceReady`: ef1=0.110, ef2=0.095 → 13.6%, `isRaceReady == false`

### Discipline gap tests
- `testGap_missing`: 20 days since last session → `isMissing == true`, `severity == .critical`
- `testGap_undertrained`: ctlVsHighest=0.20 → `isUndertrained == true`, `severity == .warning`
- `testGap_healthy`: 3 days ago, ctlVsHighest=0.8 → `severity == .none`

### HRV trend tests
- `testHRV_improving`: today=60, baseline=50 → `.improving`
- `testHRV_declining`: today=40, baseline=50 → `.declining`
- `testHRV_noData`: nils → `.insufficient`

### Context string tests
- `testContextString_brief`: ≤ 3 lines
- `testContextString_full`: contains "CTL", "ATL", "Form" keywords

---

## LangSmith Prompt Update

The Claude coaching system prompt (in LangSmith, project "IronmanTrainer") needs a new section explaining the training status context block. After any existing context description, add:

```
TRAINING STATUS CONTEXT
The user's current training status is provided in a structured block starting with
"====== TRAINING STATUS ======". Use this to:
- Reference their CTL/ATL/Form (TSB) when discussing fatigue or readiness
- Call out DISCIPLINE GAPS proactively — if swim/bike/run hasn't been trained in 14+ days,
  flag it and suggest how to reintegrate it safely
- If intensity pattern is "thresholdHeavy", recommend more easy aerobic work
- If decoupling > 10%, recommend building aerobic base before adding intensity
- If readiness < 40, suggest easy/recovery session rather than hard workout
- Taper phase (TSB rising toward +15): affirm the athlete is on track, don't add load
```

Also add a ❌/✅ LangSmith eval example:
```
❌ BAD: Claude ignores a 21-day swim gap and just talks about the bike workout
✅ GOOD: "I notice you haven't swum in 3 weeks — before we adjust your bike block,
          let's talk about reintegrating swim safely. With Oregon 70.3 12 weeks out,
          you still have time but the gap needs attention."
```

---

## Build Order

Run these in parallel (independent files):
1. **Agent A** — Create `TrainingStatusService.swift` + extend `HealthKitManager.swift`
2. **Agent B** — Write `TrainingStatusServiceTests.swift`
3. **Agent C** — Update LangSmith coaching prompt

Then after A completes, run in parallel:
4. **Agent D** — `ChatViewModel.swift` + `CheckInManager.swift` wiring
5. **Agent E** — `AnalyticsView.swift` Training Status section (with DisciplineBalanceRow)
6. **Agent F** — `HomeView.swift` ReadinessHomeBadge + `ContentView.swift` wiring

Finally:
7. Build + test: `xcodebuild test -scheme "IronmanTrainer" -destination 'platform=iOS Simulator,name=iPhone 16'`
8. Update `CLAUDE.md` to document TrainingStatusService

---

## Coding Patterns to Match

- Service class: `@MainActor final class Foo: ObservableObject` (same as `CheckInManager`)
- HealthKit async: `withCheckedContinuation { continuation in healthStore.execute(query) }` (same as `fetchSleepData`)
- Published state: `@Published var status: TrainingStatus?`
- Dependency injection: `var trainingStatus: TrainingStatusService?` on ChatViewModel (same as `var healthKit`)
- Environment injection in views: `@EnvironmentObject var trainingStatusService: TrainingStatusService`
- No `DispatchQueue.main.async` — use `await MainActor.run { }` where needed
