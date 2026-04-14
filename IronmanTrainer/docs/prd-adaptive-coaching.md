# IronmanTrainer PRD: Adaptive Coaching Features

**Version:** 1.0  
**Date:** April 13, 2026  
**Author:** Brent Williams  
**Target Race:** Ironman 70.3 Oregon | July 19, 2026  

---

## 1. Executive Summary

This PRD defines three adaptive coaching features for the IronmanTrainer iOS app: **Morning Check-In** (conversational readiness assessment), **Race Course Intelligence** (location-aware training adaptation), and **Plan Negotiation** (chat-based plan rescheduling). All three features leverage Claude as the AI engine to deliver coaching through conversation — a fundamentally different approach from the algorithmic plan adjustment used by every competitor in the market.

The core thesis: other apps adjust your numbers behind a black box. IronmanTrainer talks to you like a coach who knows your name, your race, your body, and your schedule. The adaptation happens in the conversation, not behind an algorithm.

**Target ship date:** May 25, 2026 (8 weeks before race day, allowing 6 weeks of real-world use during peak training)

**Target user:** Self-coached age-group triathletes training for a specific race, who want AI coaching guidance without paying $89–199/month for TriDot or hiring a human coach at $200–400/month.

### 1.1 Implementation Status (as of 2026-04-14)

| Feature | Status | Notes |
|---|---|---|
| **Feature 3: Plan Negotiation** (§5) | ✅ **Shipped** | Merged to `main` via commit `8d70cf6` (contents from `7e2bdce`). Includes `PlanDiffEngine`, `PlanDiffCard`, `NegotiationPhase` state machine, tool schema `rationale` field, 22 passing unit tests. |
| **Feature 1: Morning Check-In** (§3) | 📋 Spec only | No code. `CheckInManager`, `CheckInView`, HealthKit sleep/HRV/RHR queries, BGTask scheduler all still to build. |
| **Feature 2: Race Course Intelligence** (§4) | 📋 Spec only | No code. `RaceCourseProfile` data model, `RaceCourseService`, `CourseDetailView`, altitude adjustments, v1 Oregon hardcode all still to build. v2 adds the `courseResearch` Cloud Function. |
| **Prompt reliability system** (§7.5) | 🟡 Tier 1 shipped | `PROMPT_MANIFEST` + `validatePromptSchema` in `functions/index.js`. `eval-prompts.js` harness exists; fixture datasets not yet authored. Tier 3 not implemented. |

Everything else in this PRD is design-stage.

---

## 2. Technical Context & Existing Infrastructure

The following capabilities are already built and will be extended by these features:

### Chat System (ChatViewModel)

- Message model: `ChatMessage` with id, isUser, text, timestamp, imageData
- Context window includes: current week ±2, 4-week workout history with compliance data, HR zone boundaries, conversation history
- Tool calling already implemented: `PlanChangeProposal` with `PlanChange` array supporting add, drop, swap, and replace operations
- Streaming responses via `LLMProxyService` through Firebase Cloud Function proxy

### Health Data (HealthKitManager)

- Workout types: swimming, cycling, running, strength, hiking (last 30 days, 100 max)
- HR zones: Z1–Z5 derived from maxHR (69%, 79%, 85%, 92% boundaries)
- Per-workout zone breakdowns cached for last 14 days
- Age from HealthKit DateOfBirth; default fallback 38

### Training Plan (TrainingPlanManager + Core Data)

- Structure: `TrainingWeek` → `[DayWorkout]` with day, type, duration, zone, status, nutrition, notes
- Plan versioning via `WorkoutPlanVersion` entity (id, createdAt, isCurrent, source, changeDescription, weeklyPlanData)
- Rollback supported via `previousPlanVersion`
- `executePlanChanges(_ proposal: PlanChangeProposal)` already applies changes to weeks

### Other Relevant Infrastructure

- Weather forecast integration (7-day window + past day history)
- LangSmith tracing for all Claude API calls
- Drag-drop workout rescheduling in HomeView
- Race countdown, completion tracking, brick detection

---

## 3. Feature 1: Morning Check-In  📋 (spec only — no code)

### 3.1 Problem Statement

The current app is reactive: the athlete opens it to see what workout is planned, does (or skips) the workout, and HealthKit syncs the result. There is no proactive coaching interaction. The app doesn't know how you slept, whether you're stressed, if your legs are sore from yesterday, or if you're dreading today's session. Competitors like Athletica use HRV data passively; IronmanTrainer can do better by asking directly.

### 3.2 Solution Overview

A daily conversational check-in delivered via push notification that opens a focused chat interaction. Claude reviews available HealthKit data, the planned workout, recent training load, weather, and conversation history, then asks a brief contextual question. Based on the athlete's response, Claude may suggest modifications to today's workout.

### 3.3 User Flow

1. Athlete receives a push notification at their configured time (default 7:00 AM local). Notification text is contextual, not generic, e.g., "You've got a threshold ride today. How are the legs feeling?"
2. Tapping the notification opens the app directly to a focused check-in view (not the full chat). This is a single-purpose screen.
3. Claude's opening message is pre-generated (fetched when notification fires) and includes: today's planned workout summary, any relevant context from recent days, a specific question based on available signals.
4. The athlete responds conversationally. Claude may ask up to two clarifying questions total (the opening question plus one follow-up if the first answer is ambiguous), then must make a recommendation.
5. Claude provides a recommendation: confirm today's workout as planned, suggest a specific modification (intensity, duration, type swap), or recommend rest/active recovery with explanation.
6. If Claude suggests a modification, an "Accept Change" button appears. Tapping it executes the PlanChangeProposal through existing infrastructure. A "Keep Original" option is always visible.
7. The check-in conversation is saved to chat history and visible in the main Chat tab for reference.

### 3.4 Claude System Prompt Additions

The Morning Check-In requires a specialized system prompt extension. Claude should be instructed to:

- Open with a brief, specific observation (not a generic greeting). Reference yesterday's workout result if available, or upcoming key sessions.
- Ask one question at a time — never multiple questions in the same message. Up to two total exchanges are allowed (opening question + one follow-up if the first answer is ambiguous); after that, make the recommendation. The question should target the highest-signal unknown: subjective fatigue, sleep quality, injury status, or motivation.
- Keep responses under 100 words. This is a quick check-in, not a coaching lecture.
- If HealthKit shows poor sleep (<6 hours) or very high resting HR, proactively flag it: "I see you only got 5.5 hours of sleep. Today's intervals might do more harm than good."
- Never suggest skipping a workout without offering an alternative. Swap intensity or type rather than prescribing rest, unless cumulative load is genuinely dangerous.
- Always frame modifications as collaborative: "What if we..." rather than "You should..."
- When weather is relevant (rain, extreme heat, wind), factor it into recommendations without being asked.

### 3.5 Data Requirements

| Data Source | What We Need | Current Status |
|---|---|---|
| HealthKit Sleep | Sleep duration, time in bed, sleep stages if available | **NOT YET IMPLEMENTED.** Must add `HKCategoryType.sleepAnalysis` query. |
| HealthKit HRV | Most recent HRV reading (SDNN), trend over 7 days | **NOT YET IMPLEMENTED.** Must add `HKQuantityType.heartRateVariabilitySDNN` query. |
| HealthKit Resting HR | Today's resting heart rate | **NOT YET IMPLEMENTED.** Must add `HKQuantityType.restingHeartRate` query. |
| Yesterday's Workout | Completion status, actual vs planned duration, HR zone distribution | **AVAILABLE.** HealthKitManager already caches per-workout zone breakdowns for last 14 days. |
| Today's Plan | Planned workout type, duration, zone, nutrition targets | **AVAILABLE.** TrainingPlanManager provides current day's DayWorkout. |
| Weather | Today's forecast (temp, conditions, precipitation) | **AVAILABLE.** Weather integration exists for 7-day window. |
| Check-in History | Previous check-in conversations (last 7 days) | **NEEDS EXTENSION.** Chat history exists but needs tagging to distinguish check-ins from general chat. |
| Training Load | Rolling 7-day and 28-day volume by discipline | **PARTIALLY AVAILABLE.** HealthKit data exists; need computed rolling aggregates. |

### 3.6 New Components Required

#### 3.6.1 CheckInManager

New `ObservableObject` responsible for orchestrating the check-in flow.

- `scheduleCheckIn()` — Registers daily local notification via `UNUserNotificationCenter` at user's preferred time
- `scheduleBackgroundRefresh()` — Registers a `BGAppRefreshTask` earliestBeginDate of 5:00am local so iOS can pre-generate tomorrow's opening message overnight
- `prepareCheckInContext() async` — Gathers all data sources (sleep, HRV, resting HR, yesterday's workout, today's plan, weather, recent check-in history) into a structured context object
- `generateOpeningMessage() async` — Calls `LLMProxyService` with check-in-specific system prompt + context; writes `cachedOpeningMessage` (text + `generatedAt` timestamp) to UserDefaults so notification-tap can read it synchronously
- `loadCachedOpeningMessage() → CachedOpeningMessage?` — Returns the last-generated message if `generatedAt` is within the freshness window (default 6 hours), else nil
- `isCheckInActive: Bool` — Published property to control UI state
- `isGeneratingOpeningMessage: Bool` — Published property to drive the CheckInView loading state when cache is stale and live regeneration is needed
- `completeCheckIn(accepted: Bool)` — Finalizes check-in, tags conversation in history, optionally executes plan change

#### 3.6.2 CheckInView

Focused SwiftUI view for the check-in interaction. Distinct from ChatView in the following ways:

- Single-purpose layout: no tab bar, no navigation chrome. Full-screen conversational focus.
- Today's workout card displayed as a persistent header showing planned workout, weather, and a small status indicator for sleep/readiness data
- Maximum 3 message exchanges visible (not a scrolling chat history). This is a quick interaction.
- Two action buttons after Claude's recommendation: "Accept Adjustment" (accent color) and "Keep as Planned" (secondary). Both dismiss the check-in.
- Dismiss gesture (swipe down) keeps original plan

#### 3.6.3 HealthKit Extensions

Add three new data queries to HealthKitManager:

- `fetchSleepData(for date: Date) async → SleepSummary` — Queries `HKCategoryType.sleepAnalysis` for the previous night. Returns total duration, time in bed, and sleep stage breakdown if available (Apple Watch required for stages).
- `fetchHRV(for date: Date) async → Double?` — Queries `HKQuantityType.heartRateVariabilitySDNN` for most recent reading. Also fetches 7-day rolling average for trend.
- `fetchRestingHR(for date: Date) async → Double?` — Queries `HKQuantityType.restingHeartRate` for today's reading.
- Add all three types to the HealthKit permission request in `requestAuthorization()`

```swift
struct SleepSummary: Codable, Equatable {
    let date: Date                // Night-of date (Apr 12 = night of Apr 12 → morning of Apr 13)
    let totalSleepMinutes: Int    // Sum of asleepCore + asleepDeep + asleepREM + asleepUnspecified
    let timeInBedMinutes: Int     // In-bed duration (may exceed total sleep)
    let deepSleepMinutes: Int?    // Apple Watch only; nil on iPhone-only setups
    let remSleepMinutes: Int?     // Apple Watch only
    let awakeMinutes: Int?        // Apple Watch only
    let source: String            // "Apple Watch", "iPhone", "Third-party app name"
}
```

### 3.7 Notification Strategy & Opening Message Timing

The notification must be contextual, not generic. A notification that says "Time for your morning check-in!" will be ignored within a week. A notification that says "You've got 90min on the bike today and it's going to be 72°F — perfect conditions. How are you feeling?" gets tapped.

Two pieces of content need to be generated: the **notification body** (short, displayed in the notification) and the **CheckInView opening message** (longer, displayed after the athlete taps). Both are cached together by `generateOpeningMessage()` so they stay consistent.

**Three-tier generation strategy** (pick one primary path, always have the fallback):

1. **Primary — BGTask at 5:00am local.** `CheckInManager.scheduleBackgroundRefresh()` submits a `BGAppRefreshTaskRequest` with `earliestBeginDate` 5:00am local. When iOS runs the task (typical window 4–7am if the user habitually uses the app), `generateOpeningMessage()` runs, writes both the notification body and opening message to UserDefaults with a `generatedAt` timestamp, and updates the pending `UNNotificationRequest` content. This is the happy path — by the time the 7:00am notification fires, cached content is <2 hours old.
2. **Secondary — live regenerate on tap if cache is stale.** When the athlete taps the notification, CheckInView calls `loadCachedOpeningMessage()`. If `generatedAt` is <6 hours old, display the cached message instantly. If older (BGTask didn't run, or the plan/weather changed significantly overnight), set `isGeneratingOpeningMessage = true`, show a lightweight loading indicator in the opening-message slot for <1s, and call `generateOpeningMessage()` live. The rest of CheckInView (today's workout card, data tiles) renders immediately around the loading state — no full-screen spinner.
3. **Tertiary — static fallback.** If live regeneration fails (network error, Claude unavailable, timeout >8s), display a static but specific message derived from plan data only: "[Workout type] today — [duration] [zone]. How are you feeling?" No LLM dependency. Log the failure to LangSmith with a `check_in_fallback` tag so we can track frequency.

**Notification body content** is always derived from cached content if present, otherwise from a plan-only template matching the tier-3 fallback. The notification request is re-scheduled every time `generateOpeningMessage()` succeeds so the preview matches what the athlete will see on tap.

**Foreground behavior.** If the app is in the foreground at the scheduled time, suppress the OS notification and show an in-app banner that taps to CheckInView. Same cache-staleness logic applies.

**Configurability.** Check-in time is configurable in Settings (default 7:00am). BGTask earliestBeginDate automatically adjusts to `checkInTime - 2 hours` so there's always a pre-generation window. If the user picks a check-in time earlier than 4:00am, we skip BGTask entirely and rely on live regeneration at tap time.

### 3.8 Acceptance Criteria

1. Athlete receives a contextual push notification at their configured time daily
2. Tapping notification opens CheckInView with Claude's pre-generated opening message displayed within 1 second
3. Claude's opening message references at least one real data point (sleep, yesterday's workout, weather, or plan)
4. Athlete can respond conversationally; Claude replies within 3 seconds
5. Claude's recommendation includes a concrete workout modification or confirmation (never vague)
6. If modification is accepted, PlanChangeProposal executes and plan updates immediately; change is visible in HomeView
7. If modification is rejected, original plan is unchanged
8. Check-in conversation appears in Chat tab history tagged as "Check-in"
9. HealthKit sleep data is displayed when available (Apple Watch users)
10. Check-in can be dismissed/skipped without consequence
11. Notification time is configurable in Settings (default 7:00 AM)
12. LangSmith traces all check-in interactions separately from general chat

---

## 4. Feature 2: Race Course Intelligence  📋 (spec only — no code)

### 4.1 Problem Statement

Every competitor generates generic triathlon training plans. No app adapts training to the specific race course, conditions, or the athlete's geographic context. For an athlete training in Denver (5,280ft) for a sea-level race in Salem, OR in July, the physiological variables are massive: altitude-adjusted HR zones, heat acclimation timing, course-specific power demands, and pacing strategy. These are exactly the things a human coach would address — and no AI coaching app currently does.

### 4.2 Solution Overview

A race-specific intelligence layer that informs both the training plan and Claude's coaching conversations. Claude is provided with structured course data (elevation profile, swim conditions, typical weather, altitude delta from training location) and uses it to make context-aware recommendations throughout the training cycle. This is not a one-time plan adjustment — it's an ongoing thread that becomes more specific as race day approaches.

### 4.3 Race Course Data Model

#### 4.3.1 RaceCourseProfile

Minimal data model. Anything more detailed than this is either hard to source reliably or not actually used in coaching. Keep the surface small so it fits any race.

```swift
struct RaceCourseProfile: Codable {
    let raceId: String                    // e.g., "im703-oregon-2026"
    let raceName: String                  // "Ironman 70.3 Oregon"
    let venue: String                     // "Salem, OR"
    let raceDate: Date

    // Race shape
    let raceType: RaceType                // .triathlon703, .triathlonFull, .marathon, .halfMarathon, .ultraRun, ...
    let totalDistanceDescription: String  // Free text, e.g. "1.2mi swim / 56mi bike / 13.1mi run"

    // Terrain
    let terrain: TerrainProfile           // .flat, .rolling, .hilly, .mountainous
    let totalElevationGainFeet: Int       // Sum across all disciplines
    let venueElevationFeet: Int           // Elevation of the race venue above sea level

    // Expected weather on race day (historical for that date/location)
    let expectedWeather: ExpectedWeather

    // Metadata
    let dataSource: DataSource            // .llmResearch | .userEntered | .bundled
    let lastRefreshed: Date               // When the LLM research was run
}

enum TerrainProfile: String, Codable { case flat, rolling, hilly, mountainous }

struct ExpectedWeather: Codable {
    let tempHighF: Int
    let tempLowF: Int
    let conditionsSummary: String         // e.g. "Partly cloudy, low humidity, light winds"
}

enum DataSource: String, Codable { case llmResearch, userEntered, bundled }
```

#### 4.3.2 AthleteEnvironment

New data structure for the athlete's training context:

```swift
struct AthleteEnvironment: Codable {
    let trainingElevation: Int            // feet (Denver: 5,280)
    let trainingClimate: String           // e.g., "semi-arid, dry heat"
    let typicalTrainingTemp: TemperatureRange  // current month's range
    let poolAccess: Bool
    let openWaterAccess: Bool
    let trainerAccess: Bool               // indoor bike trainer
}
```

#### 4.3.3 Course Data Sourcing (Web Search + LLM + Cache)

`RaceCourseProfile` is populated on demand rather than hand-curated per race. Flow:

1. **Trigger.** First time an athlete picks a race (or taps "refresh course data" in CourseDetailView), the client calls a new Cloud Function endpoint: `POST /llmProxy { type: "courseResearch", raceName, venue, raceDate }`. Ships in **v2** — v1 hardcodes the Ironman 70.3 Oregon profile directly in the app bundle.
2. **Web search.** The Cloud Function uses OpenAI (gpt-4.1 or successor) with web-browsing tool access to gather race name, venue elevation, terrain description, and typical weather for that date/location. OpenAI-only to match the rest of the coaching stack (no Anthropic dependency; single-provider billing).
3. **Structured extraction.** The function makes a second OpenAI call that forces a `propose_course_profile` tool call, returning exactly the fields in `RaceCourseProfile` — nothing more. Schema-enforced so the client can decode without fragile text parsing.
4. **Cache in Firestore.** Write the result to `raceCourses/{raceId}` keyed by `raceId`. Any future athlete on the same race hits the cache first — no re-research cost.
5. **Cache TTL.** `lastRefreshed` on the document. If older than 90 days (or if the race is <2 weeks out and the cached weather is seasonal-only), re-run the research call. Users can also force a refresh from CourseDetailView.
6. **Fallbacks.**
   - If web search returns nothing usable, persist a `dataSource: .userEntered` placeholder with defaults and surface a lightweight form in CourseDetailView to let the athlete fill terrain/elevation/weather themselves.
   - If the LLM returns malformed JSON (tool-call normalization layer already handles this pattern from Phase 1), the Cloud Function logs the raw output to LangSmith and returns a soft error; client treats it as "course data unavailable" and falls back to generic coaching.
7. **Shape stays small.** We deliberately do NOT attempt to populate segment-by-segment bike breakdowns, swim current direction, or shade level via LLM — too much hallucination risk. The five fields we do capture (terrain, total elevation gain, venue elevation, expected weather, race type) are high-signal and easy to verify.

LangSmith traces: tag the research run with `course_research`, include the raceId, source URLs found by web search, and the final structured output for manual QA.

**v1 vs v2 split.** v1 ships with a single hardcoded `RaceCourseProfile` for Ironman 70.3 Oregon (bundled in app; `dataSource: .bundled`). The data model, phase-dependent context generation (§4.4.1–4.4.4), and CourseDetailView all work in v1. v2 adds the `courseResearch` Cloud Function endpoint and Firestore cache so any race can be researched on demand. Client code is forward-compatible: `RaceCourseService.loadCourseProfile(for:)` checks bundled profiles first, then (in v2) falls back to Firestore cache, then (in v2) calls `courseResearch` on miss.

### 4.4 Intelligence Layers

Race Course Intelligence operates across four distinct layers, each becoming more relevant as race day approaches:

#### 4.4.1 Plan-Phase Adaptation (Weeks 17–6)

General training emphasis based on course demands. Injected into Claude's system prompt as course context.

- **Flat/rolling bike course (Salem):** Emphasize sustained power at threshold, not climbing strength. Shift bike intervals toward flat terrain power (steady-state Z3/Z4) rather than hill repeats.
- **River swim with downstream current:** Train pacing without relying on current assist. Include sighting drills for river conditions.
- **Exposed run course:** Build heat resilience early. Include some midday runs during warmer training weeks.
- **Altitude delta (Denver → Salem):** HR zones trained at altitude will feel easier at sea level. Claude should note this in coaching: "Your Z2 effort at altitude will be a strong Z2 at sea level — expect to feel faster on race day."

#### 4.4.2 Race-Specific Preparation (Weeks 5–3)

Targeted preparation protocols that Claude suggests at the right time:

- **Heat acclimation protocol:** Starting 3 weeks pre-race, Claude suggests adding 20-30 min of heat exposure (sauna, hot bath post-workout, or training in warmer parts of the day). Claude references the expected 75-85°F race day temps in Salem vs. current Denver conditions.
- **Race pace sessions:** Bike and run workouts calibrated to race-day effort, adjusted for altitude. Default to HR zones and effort descriptors ("today's tempo ride: Z3 steady for 45 minutes — strong but sustainable; on race day at sea level this same effort will feel about one gear easier"). Specific watts/pace numbers only appear when the athlete has provided them (see §4.4.5).
- **Open water simulation:** If athlete has open water access, Claude suggests a river or lake swim to practice sighting and non-pool pacing.
- **Nutrition rehearsal:** Tie nutrition targets to course conditions. "At 80°F in Salem, you'll need 20-30oz/hour on the bike plus your 60-80g carbs/hr. Practice that ratio in today's long ride."

#### 4.4.3 Race Week Intelligence (Weeks 2–1)

Hyper-specific guidance as race day approaches:

- **Travel timing:** "You're flying from Denver (5,280ft) to Salem (~150ft). Arriving Thursday gives you 2 days to adjust. You'll feel extra oxygen-rich — don't let that trick you into going out too fast."
- **Taper adjustments:** Course-aware taper. "The bike is flat-to-rolling, so you don't need a big climbing effort this week. One short spin with 3x5min at race effort is enough."
- **Weather monitoring:** Pull actual forecast for Salem race weekend and adjust final guidance. "Race day forecast: 78°F, partly cloudy. Good news — cooler than average. Stick with your planned nutrition but you can ease off the extra hydration."
- **Pacing strategy:** Course-specific race plan using the effort language the athlete's data supports. If no threshold power/pace has been captured: "Swim: draft if you can, the river current will help — don't fight it. Bike: hold Z2 steady through the rolling miles 20-35, don't surge on the hills — save your legs for the run. Run: start conservative, Z2 effort — your altitude fitness gives you a cushion to negative split." If the athlete has provided thresholds (§4.4.5), Claude layers in specific numbers ("target 160-170W on the bike, start the run at 8:30/mile").

#### 4.4.4 Post-Race Analysis

After the race, Claude reviews actual performance against course-specific predictions:

- Actual vs. predicted splits by discipline
- Where the course-specific advice was helpful vs. where it missed
- What to adjust for the next race (if training continues)

#### 4.4.5 Opportunistic Threshold Capture

Performance thresholds (FTP, threshold pace, swim CSS) are NOT collected upfront in onboarding — they are too technical for the average race runner and gate-keep features for casual users. Default coaching is HR-zone + effort-descriptor based and works without any thresholds.

When the athlete asks a question that would benefit from a specific number ("what pace should I target?" / "what watts should I hold?"), Claude asks once in-line:

> "Do you know your threshold pace? If so I'll give you a specific target. If not, I'll give you a feel-based target instead."

If the athlete responds with a number, Claude extracts it via a lightweight `capture_threshold` tool call and the app stores it on `UserProfile`:

```swift
struct PerformanceThresholds: Codable {
    var ftpWatts: Int?
    var thresholdPaceSecondsPerMile: Int?
    var cssSecondsPer100yd: Int?
    var capturedAt: Date?
    var source: ThresholdSource  // .userEntered, .inferredFromHistory (future)
}
```

If the athlete doesn't know or declines, Claude remembers that for the session and stops asking. The `ThresholdSource.inferredFromHistory` option is reserved for a v2 feature that estimates thresholds from HealthKit race history.

Settings exposes the stored values in an "Advanced → Performance Thresholds" section (hidden by default, collapsed under an "Advanced" disclosure). Casual users never see it.

### 4.5 Claude System Prompt Additions

Race Course Intelligence adds structured context to Claude's system prompt. The context is phase-dependent — more detail closer to race day.

**Always included:**

- Race name, date, venue, elevation
- Athlete training elevation and climate
- Altitude delta and its physiological implications
- Course profile summary (swim type, bike terrain, run surface/shade)

**Added at 5 weeks out:**

- Heat acclimation protocol details
- Race-pace target calculations (altitude-adjusted)
- Specific course segments and how to train for them

**Added at 2 weeks out:**

- Travel and arrival recommendations
- Actual weather forecast (when available)
- Detailed pacing strategy by discipline
- Race-day nutrition plan calibrated to conditions

**Key prompt instructions:**

- When suggesting workouts, reference the course: "This flat tempo ride simulates the Salem bike course" rather than generic "tempo ride"
- When reviewing HealthKit data, contextualize for altitude: "Your HR was 155 on that Z2 run — that's expected at 5,280ft. At sea level, that same effort would be around 145."
- Don't front-load race-specific anxiety. In early weeks, course awareness is background context. It becomes foreground only in the final 3-5 weeks.
- Always frame altitude as an advantage: "Training at altitude gives you a free fitness boost at sea level" — this is motivating and physiologically accurate.

### 4.6 New Components Required

#### 4.6.1 RaceCourseService

New service responsible for managing course data and injecting it into Claude's context.

- `loadCourseProfile(for raceId: String) → RaceCourseProfile` — Loads course data. Initially hardcoded for Ironman 70.3 Oregon; structured for future API/database expansion.
- `getPhaseContext(weeksToRace: Int) → String` — Returns the appropriate level of course detail for Claude's system prompt based on proximity to race day.
- `getAltitudeAdjustment(trainingElevation: Int, raceElevation: Int) → AltitudeContext` — Computes altitude delta and returns HR adjustment factors, pace adjustment estimates, and acclimation recommendations.
- `getPacingStrategy(profile: RaceCourseProfile, athleteData: AthleteData) → PacingPlan` — Generates discipline-specific pacing targets adjusted for course and athlete fitness.

#### 4.6.2 CourseDetailView

New SwiftUI view accessible from HomeView (tap on race countdown banner) showing:

- Course overview with swim/bike/run profiles
- Altitude comparison visualization (training elevation vs. race elevation)
- Phase-appropriate preparation checklist (heat acclimation status, race-specific workouts completed, gear checklist)
- Weather forecast for race weekend (when within 7-day window)

#### 4.6.3 System Prompt Context Builder Extension

Extend ChatViewModel's context building to include race course data:

- Add `buildCourseContext()` method that calls `RaceCourseService.getPhaseContext()`
- Inject course context into the system prompt alongside existing training context
- Ensure context stays within token budget (course context should be ~200-400 tokens depending on phase)

### 4.7 Acceptance Criteria

1. Claude's coaching responses reference the specific race course when relevant (not generic triathlon advice)
2. Altitude delta is reflected in HR zone commentary ("expected at altitude" when reviewing HealthKit data)
3. Heat acclimation suggestions appear automatically starting 3 weeks before race day
4. Race-pace workouts include altitude-adjusted target numbers
5. Race week guidance includes travel timing, taper adjustments, and course-specific pacing strategy
6. CourseDetailView displays course profile, altitude comparison, and phase-appropriate prep checklist
7. Weather forecast for race weekend appears in CourseDetailView when within 7-day window
8. Course context does not appear in early-cycle coaching unless directly relevant (no premature race anxiety)
9. All course-aware coaching interactions are traced via LangSmith with course context metadata
10. RaceCourseProfile is structured for future expansion to other races (not hardcoded to Oregon)

---

## 5. Feature 3: Plan Negotiation  ✅ (shipped in `8d70cf6`)

### 5.1 Problem Statement

The biggest competitive gap in IronmanTrainer is that every competitor dynamically adjusts training plans and yours is static. The existing `PlanChangeProposal` tool calling infrastructure is built but not exposed as a first-class user-facing feature. Athletes currently have no intuitive way to tell the app "my week changed" and get a restructured plan that protects key sessions while accommodating real-life constraints.

### 5.2 Solution Overview

Extend the existing chat interface to support explicit plan negotiation workflows. When an athlete describes a schedule change, Claude proposes specific plan modifications using the `PlanChangeProposal` tool, renders them as a visual diff for review, and executes on approval. The conversation is the adaptation engine.

This is deliberately not automatic adaptation. The athlete stays in control and understands why every change was made. This directly addresses the #1 user complaint about competitors: "the algorithm made changes I don't understand."

### 5.3 User Flow

#### 5.3.1 Initiating a Negotiation

Plan negotiation triggers when the athlete describes a constraint or schedule change in chat. There is no separate mode or button. Claude detects the intent from natural language.

Trigger examples:

- "I'm traveling Wednesday through Friday"
- "Can we move the long run to Sunday?"
- "I need to skip swimming this week"
- "My knee is bothering me, can we reduce run volume?"
- "Work is insane this week, can we do a lighter week?"

#### 5.3.2 Proposal Generation

1. Claude analyzes the constraint against the current week's plan (and adjacent weeks if needed)
2. Claude identifies which sessions are "key" (must-protect) vs. flexible based on training phase and race proximity
3. Claude generates a `PlanChangeProposal` with specific add/drop/swap/replace operations
4. Claude explains the reasoning for each change in conversational text before presenting the proposal

#### 5.3.3 Visual Diff & Approval

When Claude returns a `PlanChangeProposal` via tool calling, the chat renders a structured plan diff card:

| Day | Current Plan | Proposed Change |
|---|---|---|
| Mon | Swim 2,400yd (Z2) | Swim 2,400yd (Z2) — no change |
| Tue | Bike 1:30 (Z3 intervals) | Bike 1:00 (Z2 endurance) — reduced for travel |
| Wed | Run 0:50 (Z2) | Run 0:50 (Z2) hotel treadmill — kept, gym available |
| Thu | Swim 2,000yd (Z3) | DROPPED — no pool access |
| Fri | Rest | Rest — no change |
| Sat | Bike 2:30 (Z2) | Bike 2:30 (Z2) KEY SESSION — protected |
| Sun | Run 1:15 (Z2 long) | Swim 1,500yd + Run 1:15 (Z2) — makeup swim added |

The diff card includes:

- Color coding: green for unchanged, yellow for modified, red for dropped, blue for added
- "KEY SESSION" label on sessions Claude identified as must-protect
- Brief rationale for each change inline

#### 5.3.4 Athlete Response Options

Below the diff card, three options:

- **Accept All** — Executes the full PlanChangeProposal. Plan updates immediately. Core Data version is saved. Undo button becomes available in HomeView.
- **Modify** — Athlete can respond with adjustments: "Actually, can we keep Thursday as a bike instead of dropping it?" Claude generates a revised proposal. This can iterate 2–3 times.
- **Reject** — Plan stays unchanged. Conversation is preserved for context.

### 5.4 Claude System Prompt Additions

The Plan Negotiation prompt extension instructs Claude to:

- Always identify the 1–2 "key sessions" of the week before making changes. Key session logic is defined explicitly (see §5.4.1) so Claude and the app agree on what counts as a key session.
- Never drop more than 2 sessions in a single week without explicitly warning the athlete about training load impact.
- When dropping a swim, suggest a makeup swim within the same week or early the following week.
- When modifying intensity (threshold → endurance), explain the physiological tradeoff in one sentence.
- Frame all proposals as suggestions: "What I'd recommend" not "Your plan has been updated."
- If the constraint spans multiple weeks (e.g., a 2-week injury), generate proposals for all affected weeks in a single response.
- Include cumulative weekly volume totals (original vs. proposed) at the bottom of each proposal so the athlete can see the net impact.

#### 5.4.1 Key Session Definition

Key sessions are computed on the client and passed to Claude in the system prompt so both sides apply the same definition. A `DayWorkout` qualifies as a key session if ANY of the following hold:

- `.longestEnduranceInDiscipline` — The single longest workout for that discipline in the current week (one per discipline: swim, bike, run).
- `.raceSpecific` — Workout explicitly tagged as race-pace, brick, or race-simulation (inferred from `type` string matches on "brick", "race pace", "race sim", "tempo", or "threshold" when within the peak training phase).
- `.peakPhaseBuilder` — Any session during weeks within 6 weeks of race day whose planned volume is ≥90% of the prior week's equivalent session (indicates progressive overload that should not be skipped).

Swift representation:

```swift
enum KeySessionReason: String, Codable {
    case longestEnduranceInDiscipline
    case raceSpecific
    case peakPhaseBuilder
}

extension DayWorkout {
    func keySessionReason(in week: TrainingWeek, weeksToRace: Int, priorWeek: TrainingWeek?) -> KeySessionReason?
}
```

The list of key sessions (with reason codes) is injected into Claude's system prompt alongside the current-week plan so Claude can reference them by reason when explaining proposals (e.g. "Saturday's long ride is this week's key bike session — I'm protecting it").

### 5.5 PlanChangeProposal Schema Extension

The existing `PlanChangeProposal` supports add, drop, swap, and replace. The following extensions are needed:

#### New Fields on PlanChange

| Field | Type | Description |
|---|---|---|
| rationale | String | One-sentence explanation of why this change was made. Displayed in diff card. |
| isKeySession | Bool | Whether this session was identified as a must-protect key session. |
| volumeImpact | Int (minutes) | Net change in training minutes for this operation (+15, -30, 0). |

Note: the existing `week` field on `PlanChange` already supports multi-week proposals — no additional `affectedWeek` field is needed.

#### New Fields on PlanChangeProposal

| Field | Type | Description |
|---|---|---|
| originalWeeklyVolume | Int (minutes) | Total planned training minutes before changes. |
| proposedWeeklyVolume | Int (minutes) | Total planned training minutes after changes. |
| keySessionsProtected | [String] | List of key sessions that were preserved. |
| negotiationRound | Int | Which iteration of negotiation this is (1 = first proposal, 2 = revised, etc.). |

### 5.6 New Components Required

#### 5.6.1 PlanDiffCard (SwiftUI View)

A structured card view rendered inline in the chat when Claude returns a `PlanChangeProposal`.

- Renders the day-by-day diff table with color coding (green/yellow/red/blue)
- Shows original vs. proposed weekly volume summary at the bottom
- Highlights key sessions with a shield/lock icon
- Three action buttons: Accept All, Modify, Reject
- Tapping Accept triggers `executePlanChanges()` on ChatViewModel and saves Core Data version
- Tapping Modify refocuses the text input with a prompt placeholder: "Tell me what to adjust..."

#### 5.6.2 NegotiationState (on ChatViewModel)

Track negotiation state within the chat session:

- `activeProposal: PlanChangeProposal?` — The current pending proposal, if any
- `negotiationRound: Int` — How many iterations of negotiation have occurred
- `originalPlanSnapshot: [DayWorkout]` — Snapshot of the plan before any negotiation changes (for Reject to restore)
- `isNegotiating: Bool` — Published property to adjust UI (e.g., show diff card, disable regular send)

#### 5.6.3 Tool Call Rendering Extension

The existing chat system processes `[TOOL_CALL:{...}]` tokens from streaming responses. Extend this to:

- Detect `PlanChangeProposal` tool calls
- Parse the JSON payload into a `PlanChangeProposal` struct
- Render `PlanDiffCard` inline in the message bubble instead of raw text
- Wire up the action buttons to `ChatViewModel.executePlanChanges()` and state management

### 5.7 Acceptance Criteria

1. Athlete can describe a schedule constraint in natural language in the Chat tab and receive a structured plan modification proposal
2. Claude's proposal is rendered as a visual PlanDiffCard showing day-by-day original vs. proposed with color coding
3. Each proposed change includes a one-sentence rationale
4. Key sessions are identified and labeled in the diff card
5. Weekly volume summary (original vs. proposed) is displayed
6. Accepting a proposal executes PlanChangeProposal and updates the plan in Core Data with versioning
7. Undo/rollback button appears in HomeView after plan modification
8. Athlete can request modifications to a proposal (iterate up to 3 rounds)
9. Rejecting a proposal leaves the plan completely unchanged
10. Multi-week constraints (e.g., 2-week injury) generate proposals for all affected weeks
11. Plan negotiation works alongside Morning Check-In (check-in can trigger a negotiation if needed)
12. All negotiation interactions are traced via LangSmith with metadata distinguishing them from general chat

---

## 6. Feature Interactions

The three features are designed to work together. The most important cross-feature path: a Morning Check-In may surface a constraint ("my knee is sore," "I slept 4 hours") that warrants a plan change. Rather than rebuilding the negotiation flow inside CheckInView, the check-in hands off to the existing Phase-1 negotiation state machine.

### 6.1 Check-In → Plan Negotiation handoff

1. Inside CheckInView, if Claude decides the situation requires a plan change, it emits a `propose_plan_change` tool call exactly like general chat. This is the same tool path — no new prompt surface.
2. `ChatViewModel.negotiationState` transitions to `.reviewing(proposal)` (already defined in Phase 1). CheckInView observes the same ViewModel and renders a compact `PlanDiffCard` inline below today's workout header instead of the three-bubble check-in strip. No new state machine.
3. Accept / Reject / Modify on the card behave identically to the Chat tab. Modify keeps the athlete inside CheckInView for one revision round, then auto-dismisses back to Home on Accept. This avoids dragging the athlete into the full Chat tab mid-check-in.
4. The resulting conversation (check-in + negotiation turns) is saved to chat history tagged as both `checkIn` and `negotiation` so LangSmith metrics can track the funnel: check-in → negotiation triggered → proposal rendered → accepted.
5. If the athlete dismisses CheckInView while a proposal is pending, the proposal is discarded (not left stranded in `negotiationState`) and a "proposal cancelled" entry is added to chat history for audit.

### 6.2 Race Course Intelligence injection

Course context (§4.5) is injected into the system prompt for ALL coaching calls — general chat, check-in, and negotiation — not just Chat-tab conversations. The `RaceCourseService.getPhaseContext()` call happens once per `sendCoachingMessage` so every surface sees the same phase-appropriate detail. No feature-specific course context builder.

### 6.3 Shared conversation tagging

All three features write to the same `messages` array on `ChatViewModel`. Each message carries a `source` tag (`.general`, `.checkIn`, `.negotiation`) introduced in Phase 1 groundwork (§7 Phase 1). The Chat tab filters by source when rendering history so check-in conversations can be shown separately or merged per user preference.

---

## 7. Shared Requirements & Constraints

### 7.1 Performance

- Claude response latency: <3 seconds for check-in opening message (pre-generated), <5 seconds for plan negotiation proposals and course-aware responses (more complex context)
- Plan change execution: <500ms from acceptance to Core Data persistence and UI update
- Notification delivery: contextual body text must be generated within 30 seconds of scheduled preparation time
- Course context injection: <200ms to assemble phase-appropriate course context for system prompt

### 7.2 Privacy & Data

- All new HealthKit data types (sleep, HRV, resting HR) must be added to the Info.plist usage descriptions with clear, user-friendly explanations
- HealthKit data is never sent to Claude in raw form — only aggregated summaries (e.g., "6.5 hours of sleep" not raw sleep stage timestamps)
- Check-in conversations are stored locally only (same as existing chat history)
- Race course data is bundled in the app (v1) or fetched via `courseResearch` Cloud Function (v2); no per-athlete data leaves the device in either case
- LangSmith traces may include anonymized conversation content for coaching quality evaluation. HealthKit-derived data injected into prompts (sleep minutes, HRV, RHR, zone %s) is numeric and not PII on its own; user ID fields are hashed in traces. Conversations can contain PII **only if the user types it** (e.g., mentions their name, location, medical history). We do not scrub user-typed content — document this in the Settings privacy disclosure so athletes know their chat text goes to LangSmith. If PII scrubbing becomes necessary later, it's a server-side pre-trace redaction step, not a v1 blocker.

### 7.3 Edge Cases

#### Morning Check-In

- No HealthKit data available (user doesn't wear Apple Watch to bed): Claude proceeds without sleep/HRV data, relies on subjective question + workout history
- User doesn't respond to check-in: No plan changes. Next day's check-in notes the missed interaction. Notification-fatigue back-off (e.g. skip-every-other-day after 3 consecutive ignores) is deferred to **v2** — ship v1 with a daily notification and a clear Settings toggle to disable entirely.
- Multiple workouts in a day (brick day): Check-in addresses the primary session; brick-specific guidance deferred to workout detail
- Rest day: Check-in is lighter — "Rest day today. How's recovery going? Anything I should know before tomorrow's [workout]?"

#### Race Course Intelligence

- Athlete changes target race mid-cycle: RaceCourseProfile updates, Claude context refreshes, previous course-specific advice is noted as superseded
- No course profile available for selected race: Claude falls back to generic coaching; surface a prompt to request course data be added
- Athlete trains at same elevation as race: Altitude context is suppressed (no adjustment needed); focus shifts to other course specifics
- Race is cancelled or postponed: CourseDetailView reflects new date; Claude adjusts training timeline

#### Plan Negotiation

- Athlete requests change to a past day: Claude declines gracefully, offers to adjust remaining days
- Athlete requests change that would drop all key sessions: Claude warns explicitly and requires confirmation
- Concurrent check-in and negotiation: If a check-in recommendation triggers a plan change, it uses the same PlanChangeProposal pipeline
- Race week (Week 17): Claude is extra conservative; modifications default to maintaining taper protocol
- Already-modified plan: If plan was already negotiated earlier in the week, Claude references previous changes and builds on them
- Widget staleness after chat change: `executePlanChanges` must call `AppGroupConstants.syncWeeksToWidget(newWeeks)` and trigger `WidgetCenter.shared.reloadAllTimelines()` so the home screen widget reflects the updated plan without waiting for the next scheduled timeline refresh. Manual verification step before shipping: apply a chat change, lock the phone, observe the widget updates within ~15 seconds.

### 7.4 Testing Strategy

- Unit tests for CheckInManager: context assembly, notification scheduling, check-in state machine
- Unit tests for RaceCourseService: phase context generation, altitude adjustment calculations, pacing strategy
- Unit tests for PlanDiffCard: rendering logic for all change types (add/drop/swap/replace), color coding, volume calculations
- Unit tests for PlanChangeProposal schema extensions: serialization/deserialization of new fields
- Integration tests for end-to-end check-in flow with mocked LLMProxyService responses
- Integration tests for course context injection across different training phases
- Integration tests for plan negotiation with tool call parsing and Core Data persistence
- LangSmith evaluation: tag check-in, course-aware, and negotiation traces; manually review 20+ conversations for coaching quality before ship

### 7.5 Prompt Reliability System

All coaching, plan generation, and research prompts live in LangSmith and are pulled at runtime by the Cloud Function with f-string variable substitution. A rename, removed placeholder, or semantically drifted prompt silently degrades output because the substitution at `getPrompt()` never throws on missing variables. This section specifies a graduated reliability system that covers every prompt, not just the adaptive-coaching features.

The layered approach avoids alert fatigue: cheap static checks run on every cold start, more expensive eval checks run nightly, and full production sampling runs weekly.

#### 7.5.1 Tier 1 — Fail-fast schema validation (every cold start)

Each prompt has a declared **expected-variables manifest** in source. When `getPrompt()` pulls a commit from LangSmith, the concatenated template text is scanned for `{variable}` placeholders and diffed against the manifest.

- **Missing required placeholder** (manifest says `{context}` is required, template doesn't contain it): throw on fetch, fall back to the last cached commit, log an error with the missing-variable list to Cloud Function logs + LangSmith metadata.
- **Extra placeholder** (template references `{unknown_var}` the code doesn't substitute): warn only. The f-string loop will leave the literal `{unknown_var}` in the prompt, which the model will see — still a bug, but safe to keep serving while the author fixes the prompt.
- **Unused variable** (code substitutes `{prep_races}` but template doesn't reference it): info-log only. Not a failure, but surfaces dead variables for cleanup.

Manifest lives alongside prompt names, keyed per prompt:

```js
const PROMPT_MANIFEST = {
  "coaching-chat": {
    required: ["context", "history", "z2", "z3", "z4", "z5", "current_date"],
    optional: ["full_plan", "prep_races", "last_swap_info"],
  },
  "plan-generation": { required: [/* ... */], optional: [] },
  "course-research": { required: ["race_name", "venue", "race_date"], optional: [] },
  // etc.
};
```

Validation cost: ~1ms per cold start. No per-request overhead.

#### 7.5.2 Tier 2 — Nightly prompt eval against canonical dataset

Each prompt has a small LangSmith dataset (5–10 examples) covering:
- Happy-path cases (normal input, expected output shape)
- Edge cases (missing optional data, empty history, race-week timing)
- Failure modes we've seen in production (the exact bugs fixed in commits `f621b97` and `8d70cf6` become regression tests)

A nightly job (initially a manually-triggered `functions/eval-prompts.js` harness, later wired to Cloud Scheduler or GitHub Actions) pulls each prompt from LangSmith, runs every dataset example through the production model + prompt, and posts an experiment result to LangSmith. Evaluators check:
- **Schema evaluator**: for tool-calling prompts, did the LLM emit a tool call with valid schema? (catches the "modify" action regression.)
- **Variable-use evaluator**: does the output reference at least one value from each required context variable? (catches prompts that silently stopped using `{prep_races}`.)
- **Structural evaluator**: for free-text prompts, does the output match expected markers (e.g., contains a number for pacing, references today's date)?

Failure threshold: >20% regression on any evaluator blocks prompt promotion. Pass/fail summary delivered as a Cloud Function log line that the team reads in a shared Slack channel (no dedicated alerting infra initially).

This tier is a first-class feature, not an afterthought. Every new prompt MUST ship with a Tier 2 dataset before promotion to production.

#### 7.5.3 Tier 3 — Production trace sampling (weekly, optional)

A weekly script pulls 50 random production traces per prompt from LangSmith and scans the input/output for:
- Unsubstituted placeholders in the final prompt (e.g. literal `{context}` appearing in a prod trace)
- Responses that contain no reference to any context variable (strong signal of prompt drift)
- Tool-call response rate vs expected baseline (if coaching-chat suddenly drops from 40% tool-calling to 5%, someone broke the tool description)

Not implemented initially. Spec is captured here so we know the eventual shape.

#### 7.5.4 Acceptance Criteria for §7.5

1. Every prompt fetched via `getPrompt()` is validated against its manifest at cold start; missing required variables cause fetch to throw
2. PROMPT_MANIFEST covers all currently-used prompts (`coaching-chat`, `plan-generation`, `plan-generation-batch`, `plan-from-template`, `race-search`, `prep-race-search`, and any new prompts added for Features 1/2)
3. A Tier 2 eval harness script exists at `functions/eval-prompts.js` and can be run manually to evaluate one or all prompts against their datasets
4. Each new prompt shipped for Features 1/2 has a Tier 2 dataset with at least 5 canonical examples
5. Tier 2 regression failures (>20% eval delta from previous baseline) block prompt promotion until resolved

---

## 8. Implementation Sequence

Recommended build order, accounting for dependencies:

### Phase 1: Foundation (Week 1–2)

- Add HealthKit sleep, HRV, and resting HR queries to HealthKitManager
- Add rolling training load computation (7-day and 28-day volume by discipline)
- Extend PlanChangeProposal schema with new fields (rationale, isKeySession, volumeImpact, affectedWeek)
- Tag chat messages with source type (general, check-in, negotiation) for history filtering and LangSmith tracing
- Build RaceCourseProfile data model and hardcode Ironman 70.3 Oregon course data
- Build AthleteEnvironment model and populate from UserProfile (training location, elevation)

### Phase 2: Race Course Intelligence (Week 2–3)

- Build Cloud Function `courseResearch` endpoint: web search → structured `propose_course_profile` tool call → Firestore `raceCourses/{raceId}` cache with 90-day TTL (see §4.3.3)
- Wire client `RaceCourseService` to call `courseResearch` on first race selection and on user-triggered refresh
- Build RaceCourseService with phase-dependent context generation
- Build altitude adjustment calculations (HR zone offsets, pace estimates)
- Extend ChatViewModel's context builder to inject course context into system prompt
- Build CourseDetailView with course overview, altitude comparison, and prep checklist (+ user-entered fallback form when LLM research fails)
- Wire CourseDetailView to race countdown banner in HomeView
- Write and test course-aware system prompt extensions
- Test phase transitions (verify context changes as weeks count down)

### Phase 3: Plan Negotiation (Week 3–5) ✅ SHIPPED (`8d70cf6`)

- ✅ Built PlanDiffCard SwiftUI component with color coding and Accept All / Modify / Reject action buttons
- ✅ Added `NegotiationPhase` state machine (`.idle / .reviewing / .modifying / .applying`) on ChatViewModel
- ✅ Extended tool call rendering to detect and display PlanChangeProposal as PlanDiffCard
- ✅ Added `PlanDiffEngine` enrichment layer (key session detection, volume deltas, simulated week state)
- ✅ `rationale` field added to PlanChange schema + Cloud Function tool schema
- ✅ End-to-end tested: constraint description → proposal → approval → Core Data update → undo
- ✅ 22 `PlanDiffEngineTests` covering enrichment, key sessions, volume math — all passing

### Phase 4: Morning Check-In (Week 5–7)

- Build CheckInManager with notification scheduling and context assembly
- Build CheckInView (focused single-purpose screen)
- Write and test the check-in system prompt extension
- Implement notification content generation via background task
- Add check-in time configuration to SettingsView
- Test with real HealthKit data on physical device

### Phase 5: Polish & Evaluation (Week 7–8)

- LangSmith evaluation pass: review 20+ check-in, course-aware, and negotiation conversations, tune prompts
- Edge case testing: rest days, brick days, no HealthKit data, race week, multi-week constraints, race change
- Performance optimization: pre-generation timing, response latency
- Unit and integration test suite for all three features

---

## 9. Success Metrics

| Metric | Target | Measurement |
|---|---|---|
| Daily check-in completion rate | >60% of days (5+ days/week) | Count check-in conversations vs. active days |
| Check-in modification acceptance rate | 30–60% (too high = overtrained, too low = irrelevant) | Accept vs. Keep Original taps |
| Plan negotiation usage | 1–2 negotiations per week | Count PlanChangeProposal tool calls per week |
| Negotiation approval rate | >70% of proposals accepted (first or revised) | Accept vs. Reject actions on PlanDiffCard |
| Negotiation tool-call funnel | >95% of `propose_plan_change` tool calls render a PlanDiffCard | Compare Cloud Function `tool called: propose_plan_change` log count to client-side `[LLM PROXY] proposal decoded` count. Catches silent decode failures before they become user-visible regressions. |
| Rollback rate | <10% of accepted proposals rolled back | Undo button taps after plan negotiation |
| Course-specific coaching relevance | >80% of course references rated useful (self-eval) | Manual review of LangSmith traces with course context |
| Training plan adherence | ≥80% weekly workout completion sustained across the training block | HealthKit completion vs. planned workouts (absolute target — no pre-launch baseline exists) |

---

## 10. Open Questions

1. Should the Morning Check-In be opt-in (user enables in Settings) or opt-out (enabled by default with ability to disable)? Recommendation: opt-out — the feature only works if it's habitual, and users who don't want it can turn it off.
2. Should Plan Negotiation support modifications to weeks other than the current week? The infrastructure supports it (affectedWeek field), but the UX of negotiating future weeks is more complex. Recommendation: ship with current-week-only, add future-week support in v2.
3. How should the three features interact? If a Morning Check-In surfaces a need for plan changes, should it seamlessly transition to Plan Negotiation? If Claude references the course during a negotiation, should course context auto-expand? Recommendation: yes to both, seamless transitions.
4. What happens when Claude API is unavailable? Check-in should degrade gracefully to a simple "Today's workout: [plan]" card with no AI interaction. Plan negotiation should show an error and suggest manual drag-drop in HomeView. Course detail view works offline (static data).
5. Should check-in history influence plan negotiation? If Claude notices a pattern across check-ins (e.g., athlete consistently reports poor sleep on Mondays), should it proactively suggest a permanent schedule change? Recommendation: yes, but as a v2 enhancement.
6. How many races should have course profiles at launch? Recommendation: ship with Ironman 70.3 Oregon only. Build the infrastructure for expansion but don't invest in populating 100+ courses until the feature is validated.

---

## 11. Implementation Plan (v1 build scope)

This section narrows the full PRD scope in §3 and §4 into an implementable v1 (and, for Feature 2, v2). Anything not explicitly listed below is deferred.

### 11.1 Morning Check-In — v1

**Scope locked in v1:**

- Live-regeneration path only (tier 2 from §3.7). No `BGAppRefreshTask`. Opening message is generated on notification tap if cache is stale (>6h) or missing. Static fallback (tier 3) still ships.
- Single HealthKit signal: **sleep duration** only. HRV and resting HR deferred. `fetchSleepData(for:)` sources from any available HealthKit sleep source (Apple Watch, iPhone, third-party) — the source string is captured but the UI treats all sources equivalently.
- Check-in messages are **tagged** on save (`ChatMessage.kind = .checkIn`) and surface in the main Chat tab with a filter chip ("All / Check-ins").
- Notification delivery: **FCM backend-scheduled push** from a new Cloud Function cron (`scheduleCheckInNotifications`, runs every 5 minutes, fires for users whose configured check-in time falls in the window). The cron delivers the notification; the opening-message generation still happens client-side on tap. Fallback: if FCM registration fails at signup, fall back to local `UNUserNotificationCenter` scheduling so the feature still works.
- Configurable check-in time in Settings (default 7:00 AM local). FCM payload includes the raceId + a `kind: "check_in"` tag so the tap handler routes to CheckInView.
- Two-exchange max (§3.4). Accept / Keep-Original buttons reuse the existing `PlanChangeProposal` pipeline.

**Deferred to v2:** HRV + resting HR signals, `BGAppRefreshTask` pre-generation, in-app foreground banner (v1 suppresses when app is foregrounded, no replacement UI), sleep-stage breakdown display.

**Test strategy:**

- Unit tests for `CheckInManager.loadCachedOpeningMessage` staleness logic (fresh, expired, missing).
- Unit tests for `HealthKitManager.fetchSleepData` with mocked `HKCategoryType.sleepAnalysis` samples covering: Apple Watch source, iPhone source, third-party source, no-data case.
- Unit tests for the chat-tag filter predicate on the Chat tab.
- LangSmith eval fixtures: 8 seeded check-in scenarios (good sleep + hard workout, poor sleep + easy workout, missing sleep data, rain on planned outdoor session, back-to-back hard days, rest day, race week, post-long-run recovery day). Assertions: opening message references at least one real data point, recommendation is concrete (never "rest or train, your call"), ≤100 words, ≤1 question per message.

**Files to create / modify:**

- `IronmanTrainer/CheckInManager.swift` (new)
- `IronmanTrainer/CheckInView.swift` (new)
- `IronmanTrainer/HealthKitManager.swift` — add `fetchSleepData(for:)` and `SleepSummary` struct
- `IronmanTrainer/ChatViewModel.swift` — add `.checkIn` message kind, persist tag
- `IronmanTrainer/ChatView.swift` — add filter chip (All / Check-ins)
- `IronmanTrainer/SettingsView.swift` — add check-in time row + enable toggle
- `IronmanTrainer/AppConstants.swift` — add notification name for check-in tap routing
- `IronmanTrainer/IronmanTrainerApp.swift` — handle FCM payload, route to CheckInView on tap
- `functions/src/scheduleCheckInNotifications.ts` (new) — Cloud Function cron
- Tests: `IronmanTrainerTests/CheckInManagerTests.swift`, `IronmanTrainerTests/SleepFetchTests.swift`
- Prompts: `prompts/check-in-system.md` (LangSmith-managed), eval fixtures under `prompts/evals/check-in/`

### 11.2 Race Course Intelligence — v1 + v2

**v1 scope (ships now):**

- `RaceCourseProfile` + `AthleteEnvironment` + `PerformanceThresholds` data models (§4.3.1–4.3.2, §4.4.5).
- Single bundled profile: Ironman 70.3 Oregon. `dataSource: .bundled`. Lives in `RaceCourseService.bundledProfiles`.
- `RaceCourseService` with `loadCourseProfile(for:)`, `getPhaseContext(weeksToRace:)`, `getAltitudeAdjustment(trainingElevation:raceElevation:)`. `getPacingStrategy` ships v1 but returns effort-descriptor pacing by default; watt/pace numbers only appear when `PerformanceThresholds` is populated.
- `CourseDetailView` accessible from HomeView via tapping the race countdown banner. Shows course overview, altitude comparison, phase-appropriate prep checklist, race-week weather when within 7-day window.
- `AthleteEnvironment` is **inferred** on first launch from the user's `CLLocation` (current `trainingElevation` via CoreLocation altitude + reverse-geocode for climate classification) and **editable** in Settings → "Training Environment". Fields: elevation, climate (picker: `semi-arid, dry heat`/`humid subtropical`/`temperate marine`/`arid desert`/`continental`/`tropical`), pool/open-water/trainer access toggles.
- **Opportunistic threshold capture (§4.4.5) ships in v1.** New `capture_threshold` tool call wired through `ChatViewModel`. Settings → "Advanced → Performance Thresholds" disclosure (collapsed by default) shows stored values.
- System prompt extension via `buildCourseContext()` in `ChatViewModel`. Phase-dependent tokens per §4.5.

**v2 scope (follow-on):**

- `POST /llmProxy { type: "courseResearch", ... }` Cloud Function endpoint using OpenAI `gpt-4.1` with web-search tool access.
- Second OpenAI call forces a `propose_course_profile` tool call for schema-enforced extraction.
- Firestore cache at `raceCourses/{raceId}` with 90-day TTL. Client reads bundle → Firestore → Cloud Function (on miss).
- "Refresh course data" button in CourseDetailView triggers v2 path.
- User-entered fallback form when research returns unusable data.
- LangSmith tracing tagged `course_research`.

**Test strategy:**

- Unit tests for `RaceCourseService.getAltitudeAdjustment` (Denver→Salem, sea-level→Mexico City, same-elevation cases).
- Unit tests for `RaceCourseService.getPhaseContext` returning correct detail level at 12/5/2/0 weeks out.
- Unit tests for `capture_threshold` tool-call parsing and persistence on `UserProfile`.
- Snapshot test for `CourseDetailView` at 3 race-week phases.
- v2 only: integration test for `courseResearch` Cloud Function with mocked OpenAI responses (valid, malformed tool call, empty search results).

**Files to create / modify:**

v1:
- `IronmanTrainer/RaceCourseProfile.swift` (new) — profile + `AthleteEnvironment` + `PerformanceThresholds` + `AltitudeContext` + `PacingPlan`
- `IronmanTrainer/RaceCourseService.swift` (new)
- `IronmanTrainer/CourseDetailView.swift` (new)
- `IronmanTrainer/HomeView.swift` — race countdown banner becomes tappable → CourseDetailView
- `IronmanTrainer/ChatViewModel.swift` — `buildCourseContext()`, `capture_threshold` tool handler
- `IronmanTrainer/SettingsView.swift` — Training Environment section + Advanced → Performance Thresholds disclosure
- `IronmanTrainer/UserProfile.swift` — add `PerformanceThresholds` and `AthleteEnvironment` properties
- `IronmanTrainer/BundledCourseProfiles.swift` (new) — hardcoded IM 70.3 Oregon profile
- Tests: `IronmanTrainerTests/RaceCourseServiceTests.swift`, `IronmanTrainerTests/ThresholdCaptureTests.swift`

v2 (not built now):
- `functions/src/courseResearch.ts` (new)
- `IronmanTrainer/RaceCourseService.swift` — add Firestore + Cloud Function fallback branches
- `IronmanTrainer/CourseDetailView.swift` — add refresh button + user-entered fallback form

### 11.3 Build Order

1. **Morning Check-In v1** and **Race Course Intelligence v1** build in parallel (separate files, minimal overlap — only `ChatViewModel.swift` touched by both).
2. Race Course v2 (Cloud Function + Firestore cache) is a follow-on PR after v1 ships and one real athlete (Brent) has used CourseDetailView against the bundled Oregon profile.
