# IronmanTrainer PRD: Adaptive Coaching Features

**Version:** 1.0  
**Date:** April 13, 2026  
**Author:** Brent Williams  
**Target Race:** Ironman 70.3 Oregon | July 19, 2026  

---

## 1. Executive Summary

This PRD defines two adaptive coaching features for the IronmanTrainer iOS app: **Morning Check-In** (conversational readiness assessment) and **Plan Negotiation** (chat-based plan rescheduling). Both features leverage Claude as the AI engine to deliver coaching through conversation — a fundamentally different approach from the algorithmic plan adjustment used by every competitor in the market.

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
- `prepareCheckInContext() async` — Gathers all data sources (sleep, HRV, resting HR, yesterday's workout, today's plan, weather, recent check-in history) into a structured context object
- `generateOpeningMessage() async` — Calls `LLMProxyService` with check-in-specific system prompt + context; caches response for instant display on notification tap
- `isCheckInActive: Bool` — Published property to control UI state
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

### 3.7 Notification Strategy

The notification must be contextual, not generic. A notification that says "Time for your morning check-in!" will be ignored within a week. A notification that says "You've got 90min on the bike today and it's going to be 72°F — perfect conditions. How are you feeling?" gets tapped.

- Use `UNMutableNotificationContent` with dynamic body text generated from today's plan + weather
- Notification is prepared the night before (or at configured time minus 30 minutes) via background task
- If app is in foreground, show an in-app banner instead of push notification
- Fallback: if context generation fails, use a simple but specific message: "[Workout type] day. Quick check-in before you start?"

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

## 4. Feature 3: Plan Negotiation

### 4.1 Problem Statement

The biggest competitive gap in IronmanTrainer is that every competitor dynamically adjusts training plans and yours is static. The existing `PlanChangeProposal` tool calling infrastructure is built but not exposed as a first-class user-facing feature. Athletes currently have no intuitive way to tell the app "my week changed" and get a restructured plan that protects key sessions while accommodating real-life constraints.

### 4.2 Solution Overview

Extend the existing chat interface to support explicit plan negotiation workflows. When an athlete describes a schedule change, Claude proposes specific plan modifications using the `PlanChangeProposal` tool, renders them as a visual diff for review, and executes on approval. The conversation is the adaptation engine.

This is deliberately not automatic adaptation. The athlete stays in control and understands why every change was made. This directly addresses the #1 user complaint about competitors: "the algorithm made changes I don't understand."

### 4.3 User Flow

#### 4.3.1 Initiating a Negotiation

Plan negotiation triggers when the athlete describes a constraint or schedule change in chat. There is no separate mode or button. Claude detects the intent from natural language.

Trigger examples:

- "I'm traveling Wednesday through Friday"
- "Can we move the long run to Sunday?"
- "I need to skip swimming this week"
- "My knee is bothering me, can we reduce run volume?"
- "Work is insane this week, can we do a lighter week?"

#### 4.3.2 Proposal Generation

1. Claude analyzes the constraint against the current week's plan (and adjacent weeks if needed)
2. Claude identifies which sessions are "key" (must-protect) vs. flexible based on training phase and race proximity
3. Claude generates a `PlanChangeProposal` with specific add/drop/swap/replace operations
4. Claude explains the reasoning for each change in conversational text before presenting the proposal

#### 4.3.3 Visual Diff & Approval

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

#### 4.3.4 Athlete Response Options

Below the diff card, three options:

- **Accept All** — Executes the full PlanChangeProposal. Plan updates immediately. Core Data version is saved. Undo button becomes available in HomeView.
- **Modify** — Athlete can respond with adjustments: "Actually, can we keep Thursday as a bike instead of dropping it?" Claude generates a revised proposal. This can iterate 2–3 times.
- **Reject** — Plan stays unchanged. Conversation is preserved for context.

### 4.4 Claude System Prompt Additions

The Plan Negotiation prompt extension instructs Claude to:

- Always identify the 1–2 "key sessions" of the week before making changes. Key session logic: the longest endurance session in each discipline, any race-specific workout, and any session in the peak training phase that builds on the previous week.
- Never drop more than 2 sessions in a single week without explicitly warning the athlete about training load impact.
- When dropping a swim, suggest a makeup swim within the same week or early the following week.
- When modifying intensity (threshold → endurance), explain the physiological tradeoff in one sentence.
- Frame all proposals as suggestions: "What I'd recommend" not "Your plan has been updated."
- If the constraint spans multiple weeks (e.g., a 2-week injury), generate proposals for all affected weeks in a single response.
- Include cumulative weekly volume totals (original vs. proposed) at the bottom of each proposal so the athlete can see the net impact.

### 4.5 PlanChangeProposal Schema Extension

The existing `PlanChangeProposal` supports add, drop, swap, and replace. The following extensions are needed:

#### New Fields on PlanChange

| Field | Type | Description |
|---|---|---|
| rationale | String | One-sentence explanation of why this change was made. Displayed in diff card. |
| isKeySession | Bool | Whether this session was identified as a must-protect key session. |
| volumeImpact | Int (minutes) | Net change in training minutes for this operation (+15, -30, 0). |
| affectedWeek | Int | Week number (1–17) this change applies to. Enables multi-week proposals. |

#### New Fields on PlanChangeProposal

| Field | Type | Description |
|---|---|---|
| originalWeeklyVolume | Int (minutes) | Total planned training minutes before changes. |
| proposedWeeklyVolume | Int (minutes) | Total planned training minutes after changes. |
| keySessionsProtected | [String] | List of key sessions that were preserved. |
| negotiationRound | Int | Which iteration of negotiation this is (1 = first proposal, 2 = revised, etc.). |

### 4.6 New Components Required

#### 4.6.1 PlanDiffCard (SwiftUI View)

A structured card view rendered inline in the chat when Claude returns a `PlanChangeProposal`.

- Renders the day-by-day diff table with color coding (green/yellow/red/blue)
- Shows original vs. proposed weekly volume summary at the bottom
- Highlights key sessions with a shield/lock icon
- Three action buttons: Accept All, Modify, Reject
- Tapping Accept triggers `executePlanChanges()` on ChatViewModel and saves Core Data version
- Tapping Modify refocuses the text input with a prompt placeholder: "Tell me what to adjust..."

#### 4.6.2 NegotiationState (on ChatViewModel)

Track negotiation state within the chat session:

- `activeProposal: PlanChangeProposal?` — The current pending proposal, if any
- `negotiationRound: Int` — How many iterations of negotiation have occurred
- `originalPlanSnapshot: [DayWorkout]` — Snapshot of the plan before any negotiation changes (for Reject to restore)
- `isNegotiating: Bool` — Published property to adjust UI (e.g., show diff card, disable regular send)

#### 4.6.3 Tool Call Rendering Extension

The existing chat system processes `[TOOL_CALL:{...}]` tokens from streaming responses. Extend this to:

- Detect `PlanChangeProposal` tool calls
- Parse the JSON payload into a `PlanChangeProposal` struct
- Render `PlanDiffCard` inline in the message bubble instead of raw text
- Wire up the action buttons to `ChatViewModel.executePlanChanges()` and state management

### 4.7 Acceptance Criteria

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

## 5. Shared Requirements & Constraints

### 5.1 Performance

- Claude response latency: <3 seconds for check-in opening message (pre-generated), <5 seconds for plan negotiation proposals (more complex context)
- Plan change execution: <500ms from acceptance to Core Data persistence and UI update
- Notification delivery: contextual body text must be generated within 30 seconds of scheduled preparation time

### 5.2 Privacy & Data

- All new HealthKit data types (sleep, HRV, resting HR) must be added to the Info.plist usage descriptions with clear, user-friendly explanations
- HealthKit data is never sent to Claude in raw form — only aggregated summaries (e.g., "6.5 hours of sleep" not raw sleep stage timestamps)
- Check-in conversations are stored locally only (same as existing chat history)
- LangSmith traces may include anonymized conversation content for coaching quality evaluation

### 5.3 Edge Cases

#### Morning Check-In

- No HealthKit data available (user doesn't wear Apple Watch to bed): Claude proceeds without sleep/HRV data, relies on subjective question + workout history
- User doesn't respond to check-in: No plan changes. Next day's check-in notes the missed interaction.
- Multiple workouts in a day (brick day): Check-in addresses the primary session; brick-specific guidance deferred to workout detail
- Rest day: Check-in is lighter — "Rest day today. How's recovery going? Anything I should know before tomorrow's [workout]?"

#### Plan Negotiation

- Athlete requests change to a past day: Claude declines gracefully, offers to adjust remaining days
- Athlete requests change that would drop all key sessions: Claude warns explicitly and requires confirmation
- Concurrent check-in and negotiation: If a check-in recommendation triggers a plan change, it uses the same PlanChangeProposal pipeline
- Race week (Week 17): Claude is extra conservative; modifications default to maintaining taper protocol
- Already-modified plan: If plan was already negotiated earlier in the week, Claude references previous changes and builds on them

### 5.4 Testing Strategy

- Unit tests for CheckInManager: context assembly, notification scheduling, check-in state machine
- Unit tests for PlanDiffCard: rendering logic for all change types (add/drop/swap/replace), color coding, volume calculations
- Unit tests for PlanChangeProposal schema extensions: serialization/deserialization of new fields
- Integration tests for end-to-end check-in flow with mocked LLMProxyService responses
- Integration tests for plan negotiation with tool call parsing and Core Data persistence
- LangSmith evaluation: tag check-in and negotiation traces; manually review 20+ conversations for coaching quality before ship

---

## 6. Implementation Sequence

Recommended build order, accounting for dependencies:

### Phase 1: Foundation (Week 1–2)

- Add HealthKit sleep, HRV, and resting HR queries to HealthKitManager
- Add rolling training load computation (7-day and 28-day volume by discipline)
- Extend PlanChangeProposal schema with new fields (rationale, isKeySession, volumeImpact, affectedWeek)
- Tag chat messages with source type (general, check-in, negotiation) for history filtering and LangSmith tracing

### Phase 2: Plan Negotiation (Week 2–4)

- Build PlanDiffCard SwiftUI component with color coding and action buttons
- Add NegotiationState to ChatViewModel
- Extend tool call rendering to detect and display PlanChangeProposal as PlanDiffCard
- Write and test the plan negotiation system prompt extension
- Test end-to-end: constraint description → proposal → approval → Core Data update → undo

### Phase 3: Morning Check-In (Week 4–6)

- Build CheckInManager with notification scheduling and context assembly
- Build CheckInView (focused single-purpose screen)
- Write and test the check-in system prompt extension
- Implement notification content generation via background task
- Add check-in time configuration to SettingsView
- Test with real HealthKit data on physical device

### Phase 4: Polish & Evaluation (Week 6–8)

- LangSmith evaluation pass: review 20+ check-in and negotiation conversations, tune prompts
- Edge case testing: rest days, brick days, no HealthKit data, race week, multi-week constraints
- Performance optimization: pre-generation timing, response latency
- Unit and integration test suite for both features

---

## 7. Success Metrics

| Metric | Target | Measurement |
|---|---|---|
| Daily check-in completion rate | >60% of days (5+ days/week) | Count check-in conversations vs. active days |
| Check-in modification acceptance rate | 30–60% (too high = overtrained, too low = irrelevant suggestions) | Accept vs. Keep Original taps |
| Plan negotiation usage | 1–2 negotiations per week | Count PlanChangeProposal tool calls per week |
| Negotiation approval rate | >70% of proposals accepted (first or revised) | Accept vs. Reject actions on PlanDiffCard |
| Rollback rate | <10% of accepted proposals rolled back | Undo button taps after plan negotiation |
| Training plan adherence | Improvement from current baseline (track weekly compliance %) | HealthKit completion vs. planned workouts, pre/post feature launch |

---

## 8. Open Questions

1. Should the Morning Check-In be opt-in (user enables in Settings) or opt-out (enabled by default with ability to disable)? Recommendation: opt-out — the feature only works if it's habitual, and users who don't want it can turn it off.
2. Should Plan Negotiation support modifications to weeks other than the current week? The infrastructure supports it (affectedWeek field), but the UX of negotiating future weeks is more complex. Recommendation: ship with current-week-only, add future-week support in v2.
3. How should the two features interact? If a Morning Check-In surfaces a need for plan changes (e.g., "I'm sick, probably out all week"), should it seamlessly transition to Plan Negotiation within the same check-in flow? Recommendation: yes, this should be seamless.
4. What happens when Claude API is unavailable? Check-in should degrade gracefully to a simple "Today's workout: [plan]" card with no AI interaction. Plan negotiation should show an error and suggest manual drag-drop in HomeView.
5. Should check-in history influence plan negotiation? If Claude notices a pattern across check-ins (e.g., athlete consistently reports poor sleep on Mondays), should it proactively suggest a permanent schedule change? Recommendation: yes, but as a v2 enhancement.
