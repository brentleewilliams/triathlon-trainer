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

## 3. Feature 1: Morning Check-In

### 3.1 Problem Statement

The current app is reactive: the athlete opens it to see what workout is planned, does (or skips) the workout, and HealthKit syncs the result. There is no proactive coaching interaction. The app doesn't know how you slept, whether you're stressed, if your legs are sore from yesterday, or if you're dreading today's session. Competitors like Athletica use HRV data passively; IronmanTrainer can do better by asking directly.

### 3.2 Solution Overview

A daily conversational check-in delivered via push notification that opens a focused chat interaction. Claude reviews available HealthKit data, the planned workout, recent training load, weather, and conversation history, then asks a brief contextual question. Based on the athlete's response, Claude may suggest modifications to today's workout.

### 3.3 User Flow

1. Athlete receives a push notification at their configured time (default 7:00 AM local). Notification text is contextual, not generic, e.g., "You've got a threshold ride today. How are the legs feeling?"
2. Tapping the notification opens the app directly to a focused check-in view (not the full chat). This is a single-purpose screen.
3. Claude's opening message is pre-generated (fetched when notification fires) and includes: today's planned workout summary, any relevant context from recent days, a specific question based on available signals.
4. The athlete responds conversationally. Claude may ask one follow-up question (max two exchanges before recommendation).
5. Claude provides a recommendation: confirm today's workout as planned, suggest a specific modification (intensity, duration, type swap), or recommend rest/active recovery with explanation.
6. If Claude suggests a modification, an "Accept Change" button appears. Tapping it executes the PlanChangeProposal through existing infrastructure. A "Keep Original" option is always visible.
7. The check-in conversation is saved to chat history and visible in the main Chat tab for reference.

### 3.4 Claude System Prompt Additions

The Morning Check-In requires a specialized system prompt extension. Claude should be instructed to:

- Open with a brief, specific observation (not a generic greeting). Reference yesterday's workout result if available, or upcoming key sessions.
- Ask exactly one question. Do not overwhelm with multiple questions. The question should target the highest-signal unknown: subjective fatigue, sleep quality, injury status, or motivation.
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

## 4. Feature 2: Race Course Intelligence

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

1. **Trigger.** First time an athlete picks a race (or taps "refresh course data" in CourseDetailView), the client calls a new Cloud Function endpoint: `POST /llmProxy { type: "courseResearch", raceName, venue, raceDate }`.
2. **Web search.** The Cloud Function uses the existing Anthropic web-search tool path (already wired for race date validation) to gather race name, venue elevation, terrain description, and typical weather for that date/location.
3. **Structured extraction.** The function makes a second LLM call that forces a `propose_course_profile` tool call, returning exactly the fields in `RaceCourseProfile` — nothing more. Schema-enforced so the client can decode without fragile text parsing.
4. **Cache in Firestore.** Write the result to `raceCourses/{raceId}` keyed by `raceId`. Any future athlete on the same race hits the cache first — no re-research cost.
5. **Cache TTL.** `lastRefreshed` on the document. If older than 90 days (or if the race is <2 weeks out and the cached weather is seasonal-only), re-run the research call. Users can also force a refresh from CourseDetailView.
6. **Fallbacks.**
   - If web search returns nothing usable, persist a `dataSource: .userEntered` placeholder with defaults and surface a lightweight form in CourseDetailView to let the athlete fill terrain/elevation/weather themselves.
   - If the LLM returns malformed JSON (tool-call normalization layer already handles this pattern from Phase 1), the Cloud Function logs the raw output to LangSmith and returns a soft error; client treats it as "course data unavailable" and falls back to generic coaching.
7. **Shape stays small.** We deliberately do NOT attempt to populate segment-by-segment bike breakdowns, swim current direction, or shade level via LLM — too much hallucination risk. The five fields we do capture (terrain, total elevation gain, venue elevation, expected weather, race type) are high-signal and easy to verify.

LangSmith traces: tag the research run with `course_research`, include the raceId, source URLs found by web search, and the final structured output for manual QA.

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
- **Race pace sessions:** Bike and run workouts calibrated to race-day targets, adjusted for altitude. "Today's tempo ride: hold 165W for 45 minutes. At sea level on race day, that same effort should yield ~172W."
- **Open water simulation:** If athlete has open water access, Claude suggests a river or lake swim to practice sighting and non-pool pacing.
- **Nutrition rehearsal:** Tie nutrition targets to course conditions. "At 80°F in Salem, you'll need 20-30oz/hour on the bike plus your 60-80g carbs/hr. Practice that ratio in today's long ride."

#### 4.4.3 Race Week Intelligence (Weeks 2–1)

Hyper-specific guidance as race day approaches:

- **Travel timing:** "You're flying from Denver (5,280ft) to Salem (~150ft). Arriving Thursday gives you 2 days to adjust. You'll feel extra oxygen-rich — don't let that trick you into going out too fast."
- **Taper adjustments:** Course-aware taper. "The bike is flat-to-rolling, so you don't need a big climbing effort this week. One short spin with 3x5min at race effort is enough."
- **Weather monitoring:** Pull actual forecast for Salem race weekend and adjust final guidance. "Race day forecast: 78°F, partly cloudy. Good news — cooler than average. Stick with your planned nutrition but you can ease off the extra hydration."
- **Pacing strategy:** Course-specific race plan. "Swim: draft if you can, the river current will help — don't fight it. Bike: hold 160-170W steady through the rolling miles 20-35, don't surge on the hills. Run: start conservative at 8:30/mile — your altitude fitness gives you a cushion to negative split."

#### 4.4.4 Post-Race Analysis

After the race, Claude reviews actual performance against course-specific predictions:

- Actual vs. predicted splits by discipline
- Where the course-specific advice was helpful vs. where it missed
- What to adjust for the next race (if training continues)

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

## 5. Feature 3: Plan Negotiation

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
- Race course data is bundled in the app (no external API calls for course profiles)
- LangSmith traces may include anonymized conversation content for coaching quality evaluation

### 7.3 Edge Cases

#### Morning Check-In

- No HealthKit data available (user doesn't wear Apple Watch to bed): Claude proceeds without sleep/HRV data, relies on subjective question + workout history
- User doesn't respond to check-in: No plan changes. Next day's check-in notes the missed interaction.
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

### 7.4 Testing Strategy

- Unit tests for CheckInManager: context assembly, notification scheduling, check-in state machine
- Unit tests for RaceCourseService: phase context generation, altitude adjustment calculations, pacing strategy
- Unit tests for PlanDiffCard: rendering logic for all change types (add/drop/swap/replace), color coding, volume calculations
- Unit tests for PlanChangeProposal schema extensions: serialization/deserialization of new fields
- Integration tests for end-to-end check-in flow with mocked LLMProxyService responses
- Integration tests for course context injection across different training phases
- Integration tests for plan negotiation with tool call parsing and Core Data persistence
- LangSmith evaluation: tag check-in, course-aware, and negotiation traces; manually review 20+ conversations for coaching quality before ship

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

### Phase 3: Plan Negotiation (Week 3–5)

- Build PlanDiffCard SwiftUI component with color coding and action buttons
- Add NegotiationState to ChatViewModel
- Extend tool call rendering to detect and display PlanChangeProposal as PlanDiffCard
- Write and test the plan negotiation system prompt extension
- Test end-to-end: constraint description → proposal → approval → Core Data update → undo

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
| Training plan adherence | Improvement from current baseline | HealthKit completion vs. planned workouts, pre/post feature launch |

---

## 10. Open Questions

1. Should the Morning Check-In be opt-in (user enables in Settings) or opt-out (enabled by default with ability to disable)? Recommendation: opt-out — the feature only works if it's habitual, and users who don't want it can turn it off.
2. Should Plan Negotiation support modifications to weeks other than the current week? The infrastructure supports it (affectedWeek field), but the UX of negotiating future weeks is more complex. Recommendation: ship with current-week-only, add future-week support in v2.
3. How should the three features interact? If a Morning Check-In surfaces a need for plan changes, should it seamlessly transition to Plan Negotiation? If Claude references the course during a negotiation, should course context auto-expand? Recommendation: yes to both, seamless transitions.
4. What happens when Claude API is unavailable? Check-in should degrade gracefully to a simple "Today's workout: [plan]" card with no AI interaction. Plan negotiation should show an error and suggest manual drag-drop in HomeView. Course detail view works offline (static data).
5. Should check-in history influence plan negotiation? If Claude notices a pattern across check-ins (e.g., athlete consistently reports poor sleep on Mondays), should it proactively suggest a permanent schedule change? Recommendation: yes, but as a v2 enhancement.
6. How many races should have course profiles at launch? Recommendation: ship with Ironman 70.3 Oregon only. Build the infrastructure for expansion but don't invest in populating 100+ courses until the feature is validated.
