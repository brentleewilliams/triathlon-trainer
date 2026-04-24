# Race1 Trainer Project Specification

*Updated 2026-04-24.*

## Project Overview

iOS race coaching app (display name "Race1 Trainer", Xcode scheme "IronmanTrainer") with:
- AI coaching via Claude tool-calling (plan changes, workout swaps, injury adjustments)
- HealthKit integration for automatic workout sync + compliance tracking
- AI-generated training plans via Cloud Functions + LangSmith prompt management
- Analytics dashboard with volume and zone tracking
- Race-agnostic architecture (any triathlon, running, or custom race type)
- Firebase Auth + Firestore cloud sync + onboarding flow

**Current use:** Brent's Ironman 70.3 Oregon (July 19, 2026, sub-6:00 goal)
**V2 vision:** Generalize to any triathlon/running race, any athlete

## Completed Features

✅ HealthKit integration (auto-request on app open, auto-sync on foreground)
✅ Training plan display with week-by-week navigation
✅ All 17 weeks with 100% accurate workout data from PDF
✅ Completion tracking (green checkmarks for completed workouts)
✅ Completion counter (X/Y workouts completed per week)
✅ Day detail view (split into DayDetailView.swift, DayRowComponents.swift, WorkoutDayRows.swift)
✅ Analytics page with week navigator and dynamic data (AnalyticsService extracted)
✅ Chat with Claude AI coaching (tool-calling for plan changes, conversation history, image support)
✅ Date filtering (only shows HK workouts from specific day, not past 30 days)
✅ App icon (custom branding, no white borders)
✅ Keyboard handling in chat (auto-dismiss, no obstruction)
✅ Config-based API key management (Config.xcconfig gitignored)
✅ Weather forecast integration (shows high/low/conditions in headers and detail views)
✅ Weather limited to 7-day window (hidden for days >7 days in future)
✅ Undo/rollback button for plan modifications (shows when previous version exists)
✅ Core Data persistence for workout plan versions
✅ Per-workout nutrition targets (60+ min workouts get type-specific fueling guidance)
✅ Real HealthKit workout data in Claude context (side-by-side planned vs actual format)
✅ Per-workout HR zone breakdowns cached from HealthKit (last 14 days)
✅ Race countdown banner on HomeView
✅ Weather data shown for past workout days (not just 7-day forecast window)
✅ Dynamic HR zone boundaries derived from maxHR (consistent across analytics + Claude)
✅ LangSmith integration for Claude API call tracing and evaluation
✅ Settings view with notification management
✅ Firebase Auth (Sign In with Apple) + Firestore cloud sync
✅ 6-step onboarding flow (HealthKit → Profile → Race Search → Goals → Fitness Chat → Plan Review)
✅ Tool-calling for plan changes (replace, swap, add, remove workouts via structured tool calls)
✅ Plan change persistence across app launches
✅ Secondary races (add tune-up races, auto-insert cards into plan)
✅ Race-agnostic prompts, phase labels, week caps, and race display
✅ VerifiedRaceDatabase for race date validation with fuzzy matching
✅ Expanded HealthKit workout matching for non-triathlon sports
✅ Home screen widget with race-agnostic countdown + tip cards
✅ Architecture refactored: weak self patterns, shared date helper, WorkoutDetailParser, AnalyticsViewModel
✅ Silent print() suppression in non-Debug builds
✅ Onboarding profile step gates Continue until all fields (sex, height, weight, resting HR, home zip) are filled
✅ Account deletion (Settings → Delete Account) — wipes Firestore data, UserDefaults caches, and Firebase Auth user
✅ Plan Negotiation UI — PlanDiffEngine enriches proposals with per-day diffs, key session badges, rationale; PlanDiffCard shows color-coded visual diff with Accept/Modify/Reject buttons
✅ Morning Check-In v1 — daily push notification triggers focused 3-message check-in sheet; contextual opening message from HealthKit sleep + yesterday's workout; Accept/Keep-Original buttons apply or discard plan tweaks
✅ Race Course Intelligence v1 — bundled Oregon 70.3 course profile with altitude adjustment, phase-based pacing strategy, and course detail view accessible from race countdown banner
✅ Unplanned workout visibility — off-plan HealthKit workouts (strength on easy-bike day, run on rest day) surface as a "N bonus" badge on HomeView day rows, an "Other Activity" section in DayDetailView, and a per-discipline bonus-hours footer in Analytics. Shared `findUnplannedWorkouts` helper + 10 unit tests on the pure `unplannedActivityIndices` core.
✅ TrainingStatusService — computes CTL/ATL/TSB per discipline (swim/bike/run/combined), discipline gap detection, HRV trend, aerobic decoupling, intensity pattern classification, load spike detection, and composite readiness score (0–100). Surfaces in AnalyticsView (Training Load & Readiness card), HomeView (ReadinessHomeBadge), Claude coaching context, and morning check-in. 29 unit tests. 6h UserDefaults cache.

## Architecture

### App Entry
- **IronmanTrainerApp.swift** (105 lines) — App lifecycle, Firebase init, auth flow, HealthKit manager init, foreground sync, notification center delegate for check-in routing (.openCheckIn)

### Constants & Utilities
- **AppConstants.swift** — Notification.Name extensions, AppGroupConstants, Formatters, Secrets (loads API keys from Config.xcconfig)

### Data Managers
- **TrainingPlanManager.swift** (678 lines) — DayWorkout model, TrainingWeek model, TrainingPlanManager (manages training data, dynamic week calculation from user's race date, plan change execution)
- **HealthKitManager.swift** (~446 lines) — HealthKit permissions, syncs workouts (last 60 days), caches per-workout HR zone breakdowns. Zone boundaries derived from `maxHeartRate` via computed `zoneBoundaries` property. Supports non-triathlon sport types. Includes `fetchSleepData` and `summarizeSleep` helpers for check-in context. New async methods: `fetchHRSamples(for:)`, `fetchHRSamples(from:to:)`, `fetchDistanceSamples(for:)`, `fetchHRVSamples(days:)` — used by TrainingStatusService.
- **HealthKitOnboardingData.swift** (549 lines) — Pre-populate user profile from HealthKit during onboarding
- **ClaudeService.swift** — API integration with Anthropic Claude (claude-sonnet-4-6), loads API key from Secrets
- **ChatViewModel.swift** (580 lines) — Chat message management, builds training context, tool-calling for plan changes (swap/replace/add/remove), conversation history persistence, reschedule context with ±2 week window
- **LangSmithTracer.swift** — Singleton tracer logging Claude API calls to LangSmith REST API
- **LLMProxyService.swift** (542 lines) — Client proxy for Cloud Function plan generation (batched 2-pass LLM with LangSmith prompt management)
- **PlanGenerationService.swift** (464 lines) — Training plan generation orchestration
- **OpenAIService.swift** — OpenAI API client for plan generation calls
- **WorkoutComplianceService.swift** — Green/yellow/red workout deviation tracking (±20%/±50%)
- **WorkoutMatchingHelpers.swift** — Type + date + duration matching for HealthKit → planned workout. Also hosts `findUnplannedWorkouts(on:plannedWorkouts:hkWorkouts:)` and its pure testable core `unplannedActivityIndices(plannedTypes:actualTypes:hasBrick:)` — used by DayDetailView, WorkoutDayRows, and AnalyticsViewModel to surface off-plan activity.
- **VerifiedRaceDatabase.swift** (413 lines) — Local race database for date validation with fuzzy matching
- **AnalyticsService.swift** — Analytics data computation extracted from view layer
- **CheckInManager.swift** (280 lines) — @MainActor singleton for morning check-in orchestration; 6h cache, tier-2/3 fallback, generates contextual opening message from HealthKit sleep + workout data, local UNUserNotification fallback when FCM token unavailable. `prepareCheckInContext` accepts optional `trainingStatus: TrainingStatusService` to append brief readiness summary.
- **TrainingStatusService.swift** (~540 lines) — @MainActor ObservableObject. Computes training load metrics from HealthKit: CTL/ATL/TSB per discipline (42-day/7-day EWA of HRSS), discipline gap detection (isMissing/isUndertrained), HRV trend (today vs 60-day baseline), aerobic decoupling for runs/bikes ≥60min, intensity pattern (polarized/pyramidal/thresholdHeavy/mixed), weekly load spike detection, and composite readiness score (0–100 from TSB+HRV+load). 6h UserDefaults cache. `contextString(brief:)` provides plain-text LLM context (brief for check-in, full for coaching).
- **RaceCourseService.swift** (351 lines) — @MainActor singleton for course-aware coaching; loads bundled or user-entered course profile, provides phase-dependent context at always/+5wk/+2wk tiers, altitude adjustment, pacing strategy, UserDefaults persistence for AthleteEnvironment
- **PlanDiffEngine.swift** (285 lines) — Enriches Claude plan proposals with week-by-week diffs (DayDiff/WeekDiff/EnrichedProposal), detects key sessions, tracks volume deltas, adds per-change rationale

### Auth & Cloud
- **AuthService.swift** — Firebase Auth with Sign In with Apple, onboarding state listener
- **FirestoreService.swift** — Cloud sync for user profiles and training plans
- **UserProfile.swift** (388 lines) — RaceType, GoalType, Race models

### Views
- **ContentView.swift** (~80 lines) — TabView container (Home, Analytics, Chat, Settings); presents CheckInView sheet on .openCheckIn notification. Owns `@StateObject private var trainingStatus = TrainingStatusService(healthKit: HealthKitManager.shared)`; passes it as `.environmentObject` to Home, Analytics, and CheckInView; wires `chatViewModel.trainingStatus` and calls `trainingStatus.compute()` on appear.
- **HomeView.swift** (~520 lines) — Weekly plan display, race countdown, completion status, widget tip card; race countdown banner taps through to CourseDetailView. Includes `ReadinessHomeBadge` (compact horizontal card with readiness score, level, form value, and critical gap pills) shown between week nav header and sync error display.
- **DayDetailView.swift** (454 lines) — Full day workout detail view (extracted from HomeView)
- **DayRowComponents.swift** — Reusable day row UI components (extracted from HomeView)
- **WorkoutDayRows.swift** — Workout-specific day row renderers
- **AnalyticsView.swift** (~800 lines) — Volume summary, zone distribution, weekly compliance trend, and Training Load & Readiness card (ReadinessBadgeView, FitnessMetricsRow, DisciplineBalanceRow, HRVTrendRow, IntensityPatternRow, LoadSpikeWarningRow, DecouplingRow). Receives `TrainingStatusService` via `@EnvironmentObject`.
- **ChatView.swift** (416 lines) — Chat messaging interface with keyboard handling, image support, ChatFilter enum (All/Check-ins filter chips), CheckInManager integration
- **PlanView.swift** — Calendar overview of all training weeks
- **SettingsView.swift** (678 lines) — Notification settings, workout reminders, plan regeneration, Morning Check-In section (toggle + time picker), Training Environment section (elevation, climate), Performance Thresholds disclosure
- **CheckInView.swift** (246 lines) — Focused check-in sheet UI (max 3 message exchanges, Accept/Keep-Original buttons)
- **CourseDetailView.swift** (184 lines) — Race course detail UI (overview, altitude comparison, phase checklist, race-week weather)
- **PlanDiffCard.swift** (324 lines) — Visual diff card UI for plan proposals (color-coded day changes, key session badges, per-change rationale, volume bars, Accept/Modify/Reject buttons)
- **SharedComponents.swift** — WeekNavigationHeader, WeekPickerSheet (shared week navigation)
- **SignInView.swift** — Sign In with Apple UI

### Onboarding
- **OnboardingView.swift** — 6-step onboarding container
- **OnboardingSteps.swift** (1,415 lines) — Individual onboarding step views
- **OnboardingComponents.swift** (580 lines) — Reusable onboarding UI components
- **OnboardingViewModel.swift** (635 lines) — Onboarding state machine, early plan generation trigger
- **OnboardingChatHelper.swift** — AI-assisted fitness assessment during onboarding

### Widget
- **IronmanTrainerWidget.swift** — Home screen widget with race-agnostic countdown + tip cards

### Core Data
- **CompletedWorkoutEntity+CoreDataClass.swift** / **+CoreDataProperties.swift** — Completed workout persistence
- **WorkoutPlanVersion+CoreDataClass.swift** / **+CoreDataProperties.swift** — Workout plan version persistence (supports undo/rollback)

### Race Course Data
- **RaceCourseProfile.swift** (173 lines) — Data models: `RaceCourseProfile`, `AthleteEnvironment`, `PerformanceThresholds`, `AltitudeContext`, `PacingTarget`, `PacingPlan`; enums: `TerrainProfile`, `DataSource`, `ThresholdSource`, `PacingDiscipline`
- **BundledCourseProfiles.swift** (44 lines) — Hardcoded Ironman 70.3 Oregon profile; v2 seam for Cloud Function + Firestore research path

### Supporting Files
- **Config.xcconfig** — API keys (gitignored, only exists locally)
- **ci_scripts/ci_post_clone.sh** — Xcode Cloud post-clone script for CI builds

## Key Technical Details

### HealthKit Integration
- **Permissions:** Requested on app open via onAppear in IronmanTrainerApp
- **Sync Trigger:** onAppear in IronmanTrainerApp detects foreground via scenePhase
- **Filtering:** By exact calendar date (no cross-day bleeding), exact workout type (no cross-matching)
- **Types Tracked:** Swimming, Cycling, Running (from last 30 days max)
- **Date of Birth:** Uses `dateOfBirthComponents()` (not the deprecated `dateOfBirth()`)

### Training Plan Data
- **Source:** AI-generated from onboarding data via Cloud Functions (hardcoded 17-week plan as fallback for Brent's Oregon race)
- **Structure:** Variable weeks x 7 days, each day has 0+ workouts
- **Week Calculation:** Dynamic from user's race date (stored in UserDefaults), not hardcoded start date
- **Plan Changes:** Tool-calling approach — Claude proposes structured changes (swap/replace/add/remove), user confirms, changes persist via Core Data WorkoutPlanVersion
- **Rest Days:** Marked as "Rest" type, count in completion tracking if no actual workouts done
- **Nutrition Targets:** Optional per-workout fueling guidance (nutritionTarget field on DayWorkout). Rules: Bike 60-75min -> 60g carbs/hr; Bike >75min -> 60-80g carbs/hr; Run >=60min -> 30-45g carbs/hr; Brick -> bike-rate then run-rate; Swim/Rest/<60min -> nil
- **Secondary Races:** Users can add tune-up races; cards auto-inserted into plan timeline

### Claude AI Coach
- **API:** Anthropic Claude API (claude-sonnet-4-6 model) via LLMProxyService → Cloud Functions
- **Tool Calling:** Plan changes use structured tool calls (not JSON-in-text). ChatViewModel parses tool_use blocks, PlanDiffEngine enriches proposals with visual diff data, PlanDiffCard presents color-coded day changes with Accept/Modify/Reject. `rationale` field on PlanChange populated by Cloud Function tool.
- **Context Window:** Current week ±2 weeks of plan data + tool-call instructions. Kept small to ensure tool-call rules stay prominent.
- **Context Passed:**
  - Current week ±2 planned workouts (with nutrition targets when present)
  - Side-by-side planned vs actual workout comparison from HealthKit
  - Per-workout HR zone breakdowns for last 14 days
  - Race date (dynamic from user profile), goals, dynamic HR zones from maxHR
  - Current date in local timezone
  - Race course phase context from RaceCourseService (always/+5wk/+2wk tiers: terrain, altitude, pacing targets)
- **HR Zones:** Dynamically computed from maxHeartRate: Z1 <69%, Z2 69-79%, Z3 79-85%, Z4 85-92%, Z5 >92%
- **System Prompt:** Race-agnostic coaching prompt with tool-call instructions, safety boundary (coaching topics only)
- **API Key:** Loaded from Config.xcconfig via Secrets
- **Tracing:** All API calls logged to LangSmith via LangSmithTracer (startRun/endRun wrapping)
- **Prompt Management:** LangSmith MCP server for reading/editing prompts from Claude Code; Cloud Function proxy for runtime prompt delivery

### LangSmith Integration
- **Endpoint:** `POST https://api.smith.langchain.com/runs`
- **Headers:** `x-api-key`, `Content-Type: application/json`
- **Run format:** `{id, name, run_type: "llm", inputs, start_time, session_name, outputs, end_time}`
- **Session:** "IronmanTrainer" groups all coaching conversations
- **Benefits:** View all prompts/responses, evaluate coaching quality, identify improvements

### Timezone Handling
- DateFormatter uses `TimeZone.current` to ensure local date formatting
- Prevents off-by-one errors when Claude sees date in different timezone

## In Progress / TODO

### Test Coverage
Test infrastructure fully configured:
- `IronmanTrainerTests` target with proper build phases
- Scheme "IronmanTrainer" configured for `xcodebuild test` execution
- XCTest framework integrated

18 test files, active:
- **ChatSwapTests.swift** — Swap command parsing, chat history persistence, HR zone calculations, nutrition targets, zone percentages
- **WeatherForecastTests.swift** — Determinism, seasonal progression, bounds checking, humidity/wind, daily variation, edge cases
- **PlanChangeToolTests.swift** — Tool-calling plan change parsing and execution
- **PlanDiffEngineTests.swift** — Plan diff enrichment, DayDiff/WeekDiff logic, volume delta calculations
- **ComplianceTests.swift** — Workout compliance tracking tests
- **OnboardingTests.swift** — Onboarding flow tests
- **RaceDateParsingTests.swift** — Race date parsing and validation against VerifiedRaceDatabase
- **TemplateSelectionTests.swift** — Plan template selection logic
- **WorkoutMatchingTests.swift** — HealthKit → planned workout matching; includes 10 tests for `unplannedActivityIndices` (extras on planned days, rest-day runs, brick-day bike/run handling, multi-extra ordering)
- **TrainingPlanManagerTests.swift** — Training plan manager logic
- **CheckInManagerTests.swift** — Morning check-in caching, tier logic, freshness validation
- **SleepFetchTests.swift** — HealthKit sleep data fetching and summarization
- **TrainingStatusServiceTests.swift** — 29 tests covering HRSS formula, EWA (CTL/ATL), intensity pattern classification, load spike, composite readiness scoring, aerobic decoupling, discipline gap detection, HRV trend direction, and contextString output (brief + full)
- **RaceCourseServiceTests.swift** — Course profile loading, phase context, altitude/pacing math
- **ThresholdCaptureTests.swift** — Performance threshold capture and inference
- **CIScriptTests.swift** — CI script validation (API key scan)

Disabled (pre-existing compile errors, wrapped in `#if false`):
- **PlanChangeTests.swift** — Legacy plan change tests (pre-tool-calling)

## Configuration

### Config.xcconfig Structure
```
// API Configuration - Local only, not committed to git
ANTHROPIC_API_KEY = sk-ant-api03-YOUR_KEY
LANGSMITH_API_KEY = lsv2_YOUR_KEY
```

### Environment Setup
1. Copy `Config.example.xcconfig` -> `Config.xcconfig`
2. Add Anthropic API key (get from api.anthropic.com)
3. Add LangSmith API key (get from smith.langchain.com)
4. **NEVER commit Config.xcconfig** (it's in .gitignore)
5. Xcode automatically loads environment variables from Config.xcconfig at build time

## Build & Run

```bash
# Build for simulator
xcodebuild build -scheme "IronmanTrainer" -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test -scheme "IronmanTrainer" -destination 'platform=iOS Simulator,name=iPhone 16'

# Install to running simulator
xcrun simctl install "iPhone 16" /path/to/Race1\ Trainer.app

# Launch app
xcrun simctl launch "iPhone 16" com.brent.ironmantrainer
```

## Known Working

- Week 1 shows correct workouts (Friday is Swim 1,800yd, not Rest)
- All 17 weeks have accurate training plan data
- HealthKit syncs automatically on app open
- Green checkmarks appear when HealthKit workouts match planned workouts
- Day detail view shows HealthKit workouts for that day only
- Analytics tab loads without crashing
- App builds and runs on iOS Simulator (iPhone 16)
- Chat interface works with proper keyboard handling
- Claude AI receives training context dynamically
- LangSmith traces Claude API calls when API key is configured

## Testing / Debugging

- Use Xcode Debugger to inspect @Published variables in managers
- Check Console for API error messages and print statements
- Test on physical device for accurate HealthKit sync (simulator may not reflect real Health app)
- Verify Claude responses include current week plan and workout history

## Security Notes

- API keys stored in Config.plist / Config.xcconfig (local only, gitignored)
- Never hardcode secrets in source files
- Both Anthropic and LangSmith API keys required for full functionality

## References

- [LangSmith Evaluation Quickstart](https://docs.langchain.com/langsmith/evaluation-quickstart)
- [LangSmith REST API](https://github.com/langchain-ai/langsmith-cookbook/blob/main/tracing-examples/rest/rest.ipynb)
- [Anthropic Claude API](https://docs.anthropic.com/)
- [HealthKit Documentation](https://developer.apple.com/healthkit/)
