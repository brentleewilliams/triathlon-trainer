# IronmanTrainer

iOS app for Ironman 70.3 Oregon training with HealthKit sync, Claude AI coaching, and Firebase cloud sync.

**Race:** Ironman 70.3 Oregon — July 19, 2026 (Salem, OR)  
**Goal:** Sub-6:00 finish  
**Training:** 17 weeks, March 23 – July 19, 2026

---

## Features

- **Sign In with Apple** — Firebase auth with Firestore cloud sync
- **6-Step Onboarding** — HealthKit auto-fill → profile → race search → goals → AI fitness chat → plan review
- **17-Week Training Plan** — Hardcoded plan from official Ironman coaching PDF; AI-generated plans in progress
- **HealthKit Sync** — Auto-syncs swim/bike/run workouts on foreground; compliance tracking (±20%/±50% deviation)
- **Claude AI Coach** — Multi-turn coaching chat with training context, HR zones, and real HealthKit data
- **Plan Adaptation** — Ask Claude to swap days; undo/rollback support via CoreData versioning
- **HR Zone Analytics** — Per-workout zone breakdowns; dynamic zones derived from max HR
- **Per-Workout Nutrition Targets** — Progressive carb/hr goals (60g→100g) on long rides and bricks
- **LangSmith Tracing** — All Claude API calls logged for prompt evaluation
- **Push Notifications** — Configurable morning workout reminders with deep linking

---

## Setup

### Prerequisites
- Xcode 15.0+
- iOS 17.0+
- Anthropic API key
- Firebase project (Auth + Firestore) — already configured for this repo

### API Keys

1. Copy `IronmanTrainer/Config.example.xcconfig` → `IronmanTrainer/Config.xcconfig`
2. Fill in your keys:
   ```
   ANTHROPIC_API_KEY = sk-ant-api03-...
   LANGSMITH_API_KEY = lsv2_...   (optional, enables LangSmith tracing)
   ```
3. **Never commit `Config.xcconfig`** — it's in `.gitignore`

### Build & Run

```bash
# Build
xcodebuild build -scheme IronmanTrainer -destination 'platform=iOS Simulator,name=iPhone 16'

# Test
xcodebuild test -scheme IronmanTrainer -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or open `IronmanTrainer.xcodeproj` in Xcode and press ⌘R.

---

## Architecture

31 Swift files (~10,800 lines). Key files:

| File | Purpose |
|------|---------|
| `IronmanTrainerApp.swift` | App entry, Firebase init, HealthKit sync on foreground |
| `AuthService.swift` | Firebase Auth, Sign In with Apple, onboarding state |
| `OnboardingView.swift` | 6-step onboarding flow |
| `HomeView.swift` | Weekly plan, workout cards, race countdown, compliance status |
| `AnalyticsView.swift` | Zone distribution, volume charts |
| `ChatView.swift` / `ChatViewModel.swift` | Claude coaching chat with swap command parsing |
| `TrainingPlanManager.swift` | 17-week plan data, week navigation, CoreData versioning |
| `HealthKitManager.swift` | HealthKit sync, zone calculations |
| `WorkoutComplianceService.swift` | Green/yellow/red deviation tracking |
| `LLMProxyService.swift` | Cloud Function proxy for AI plan generation |
| `LangSmithTracer.swift` | Conversation observability |
| `FirestoreService.swift` | Cloud sync for profiles and plans |

For full architecture details, see `CLAUDE.md`.  
For product specs and roadmap, see `PRODUCT.md`.  
For competitive analysis, see `product-planning-and-differentiation.md`.

---

## Tests

64 tests passing across 2 active test files:
- `ChatSwapTests.swift` — swap parsing, HR zones, nutrition targets (42 tests)
- `WeatherForecastTests.swift` — forecast determinism, bounds, edge cases (22 tests)

Two test files are disabled (`#if false`) due to pre-existing compile errors — see `CLAUDE.md` for details.
