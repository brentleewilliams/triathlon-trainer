# Architecture Issues

## Review — 2026-04-11

### [HIGH] OnboardingView is a 2299-line monolith
**File:** `IronmanTrainer/OnboardingView.swift:1-2299`
**Problem:** A single file manages HealthKit permissions, profile input, race search, goal setting, plan generation, and plan review. Each step is impossible to test in isolation.
**Fix:** Split into step-specific files: `OnboardingHealthKitStep`, `OnboardingProfileStep`, `OnboardingRaceSearchStep`, `OnboardingGoalStep`, `OnboardingPlanReviewStep`. Parent `OnboardingView` orchestrates transitions only (~100 lines).

---

### [HIGH] HomeView is a 1621-line monolith with duplicated logic
**File:** `IronmanTrainer/HomeView.swift:1-1621`
**Problem:** Handles week display, day detail, drag-drop, workout matching, and completion counting. `workoutTypeMatches()` and `extractWorkoutType()` are implemented twice inside this file, and a third time in `WorkoutMatchingHelpers.swift`.
**Fix:** Extract `DayListView`, `DayDetailView`, `WorkoutComplianceIndicator`. Delete the duplicate HomeView implementations of `workoutTypeMatches` and `extractWorkoutType` — import from `WorkoutMatchingHelpers.swift`.

---

### [HIGH] TrainingPlanManager violates single responsibility (677 lines)
**File:** `IronmanTrainer/TrainingPlanManager.swift:1-677`
**Problem:** One class manages plan state, Core Data versioning, secondary race card insertion, week calculation, and plan change application. Each is a separate concern that compounds testing difficulty.
**Fix:** Split into `TrainingPlanManager` (state + week calc only), `PlanVersionManager` (Core Data), and move `applyRescheduledPlan` to a `PlanChangeApplier` or keep it on the manager but remove Core Data responsibilities from it.

---

### [HIGH] Analytics calculations embedded in AnalyticsView
**File:** `IronmanTrainer/AnalyticsView.swift:21-139`
**Problem:** `recalculateAnalytics()`, `parseWorkoutDuration()`, `parseZone()`, and zone percentage logic live directly in the SwiftUI view. Untestable and re-runs on every render.
**Fix:** Move to `AnalyticsService` (file exists but is stub-only). Expose @Published computed properties. View observes and renders only.

---

### [MEDIUM] ClaudeService.swift is dead code
**File:** `IronmanTrainer/ClaudeService.swift:1-164`
**Problem:** ChatViewModel now calls `LLMProxyService` which routes through the Cloud Function. `ClaudeService` is superseded but still ships.
**Fix:** Verify zero import sites (`grep -r "ClaudeService" .`). If confirmed unused, delete.

---

### [MEDIUM] Workout type matching duplicated three times
**File:** `IronmanTrainer/HomeView.swift:293-335`, `IronmanTrainer/WorkoutMatchingHelpers.swift:65-97`, `IronmanTrainer/ChatViewModel.swift:149-170`
**Problem:** `workoutTypeMatches()` and `extractWorkoutType()` exist in at least three places with slightly different signatures. Changes to matching logic need to be made in all three.
**Fix:** `WorkoutMatchingHelpers.swift` is the canonical home. Delete HomeView copies. ChatViewModel's keyword-based variant (`workoutTypeMatches(_:keyword:)`) is distinct enough to stay but should import the base helpers.

---

### [MEDIUM] `parseWorkoutDuration()` implemented three times with different return types
**File:** `IronmanTrainer/HomeView.swift:338`, `IronmanTrainer/AnalyticsView.swift:85`, `IronmanTrainer/WorkoutMatchingHelpers.swift:11`
**Problem:** Returns `Int?` (minutes) in two places and `Double` (hours) in another. Divergence is a latent bug.
**Fix:** Single canonical function in `WorkoutMatchingHelpers` returning minutes as `Int?`. Callers that need hours divide by 60.0. Delete local copies.

---

### [MEDIUM] ChatViewModel optional dependencies can become nil mid-operation
**File:** `IronmanTrainer/ChatViewModel.swift:28-29`
**Problem:** `var trainingPlan: TrainingPlanManager?` and `var healthKit: HealthKitManager?` are injected via property assignment after init. If assignment is missed or GC fires, coaching calls silently fail with a guard-nil exit.
**Fix:** Require both in `ChatViewModel.init(trainingPlan:healthKit:)`. Remove optionality. Inject at construction site in `ContentView`.

---

### [MEDIUM] `@unchecked Sendable` on HealthKitManager papers over real concurrency risk
**File:** `IronmanTrainer/HealthKitManager.swift:5`
**Problem:** Multiple HKQuery callbacks mutate `@Published` properties via `DispatchQueue.main.async`. The `@unchecked Sendable` tells the compiler to trust this, but simultaneous zone-fetch completions can interleave updates.
**Fix:** Add `@MainActor` to the class declaration. Replace `DispatchQueue.main.async` callbacks with `await MainActor.run { }`. Remove `@unchecked Sendable`.

---

### [MEDIUM] AuthService blocks launch with a `sleep`-based Firestore timeout
**File:** `IronmanTrainer/AuthService.swift:49-111`
**Problem:** `checkForExistingPlan()` uses `withThrowingTaskGroup` + a 5-second sleep as a timeout. On a slow network the app shows a frozen launch screen.
**Fix:** Replace sleep hack with `Task.sleep` on a cancellable child task, or use `withTimeout(seconds:)` from swift-async-algorithms. Reduce to 2 seconds. Show a loading indicator in the root view during this window.

---

### [MEDIUM] No dependency injection — singletons block unit testing
**File:** `IronmanTrainer/ClaudeService.swift`, `HealthKitManager.swift`, `LLMProxyService.swift`, `AuthService.swift`
**Problem:** All services use `static let shared`. Tests cannot inject mocks, making isolated unit tests for anything touching network or HealthKit impossible.
**Fix:** Define protocols (`CoachingService`, `HealthDataProvider`). Add `init(dependencies:)` to each service. Keep `.shared` for app code, but pass protocol types through ViewModels.

---

### [MEDIUM] Zone boundary calculation duplicated
**File:** `IronmanTrainer/HealthKitManager.swift:153-160`, `IronmanTrainer/ClaudeService.swift:92-95`
**Problem:** `HealthKitManager.zoneBoundaries` is the authoritative computed property. `ClaudeService` has a hardcoded fallback that will drift if the formula changes.
**Fix:** Pass `healthKit.zoneBoundaries` into `ClaudeService` at call time. Remove the hardcoded fallback.

---

### [LOW] AnalyticsService.swift is a console-logging stub
**File:** `IronmanTrainer/AnalyticsService.swift:1-116`
**Problem:** Every method is a `print("[Analytics]...")` call. Firebase Analytics is not linked. Dead code ships in production.
**Fix:** Either wire up Firebase Analytics properly, or delete the file. Don't ship 116 lines of print statements.

---

### [LOW] OpenAIService.swift — audit for live usage
**File:** `IronmanTrainer/OpenAIService.swift:1-189`
**Problem:** PlanGenerationService also constructs OpenAI requests directly. Unclear whether `OpenAIService` is the entry point or a legacy duplicate.
**Fix:** `grep -r "OpenAIService" .` — if zero call sites, delete. If used, consolidate plan generation through it.

---

### [LOW] HR zone boundaries computed twice
**File:** `IronmanTrainer/HealthKitManager.swift:153`, `IronmanTrainer/ClaudeService.swift:92`
**Problem:** Zone thresholds (Z1 <69%, Z2 69-79%, etc.) exist in two places. One change = two edits.
**Fix:** Single source in `HealthKitManager.zoneBoundaries`. Pass into anything that needs it.

---

### [LOW] Chat image data silently dropped on persist
**File:** `IronmanTrainer/ChatViewModel.swift:289`
**Problem:** Messages are saved to UserDefaults with `imageData: nil`. Images sent in chat are lost on relaunch, creating a confusing partial history.
**Fix:** Either persist images to `Documents/` and store paths, or accept images are ephemeral and document that clearly.

---

### [LOW] No Task cancellation in sendMessage
**File:** `IronmanTrainer/ChatViewModel.swift:178-247`
**Problem:** Long-running coaching Task has no cancellation. If user navigates away, streaming continues in the background.
**Fix:** Store `var currentSendTask: Task<Void, Never>?`. Cancel in `deinit`. Add `guard !Task.isCancelled` checkpoints after each await.

---

### [LOW] API key loading has two code paths (xcconfig + Config.plist fallback)
**File:** `IronmanTrainer/AppConstants.swift:73-113`
**Problem:** Each key tries `Info.plist` first, then falls back to `Config.plist`. The dual path makes it non-obvious which file is authoritative, and both must be kept in sync.
**Fix:** Pick one. xcconfig → Info.plist is the standard Xcode pattern. Remove the Config.plist fallback once xcconfig is confirmed working everywhere.

---

### Summary

The biggest systemic issues are **god objects** and **duplication**. Three files — `OnboardingView` (2299 lines), `HomeView` (1621 lines), and `TrainingPlanManager` (677 lines) — each do the work of 3–5 classes. The same workout-matching and duration-parsing logic is implemented 3x across the codebase with diverging signatures. The quickest wins with the highest payoff: (1) delete `ClaudeService.swift` if unused, (2) consolidate the three `workoutTypeMatches`/`parseDuration` duplicates into `WorkoutMatchingHelpers`, (3) add `@MainActor` to `HealthKitManager` and remove `@unchecked Sendable`. The god objects are real problems but require larger refactors — start with the duplication and dead code, which are pure cleanup with no risk.
