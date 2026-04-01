# Onboarding & Auth Spec (V1.5)

## Overview

Add Apple Sign In authentication and a hybrid onboarding flow that collects everything needed to generate a personalized training plan for any running or triathlon race. The system maximizes HealthKit auto-pull, uses an LLM with live web search for race lookup, assesses feasibility, and generates a coach-style plan the user can review before committing.

---

## Authentication

**Method:** Apple Sign In only
**Backend:** Firebase (Auth + Firestore)
**Sync:** Single-device for V1.5 (multi-device sync is a V2 concern)

### Flow
1. App launch → check for existing Firebase auth session
2. If no session → show sign-in screen with Apple Sign In button
3. On success → store Firebase UID, check if onboarding is complete
4. If onboarding incomplete → start onboarding flow
5. If onboarding complete → go to main app (existing TabView)

### Firebase Setup
- Existing Firebase project (already created)
- Firebase Auth with Apple Sign In provider
- Firestore document per user: `users/{uid}` storing profile, race, and full plan data
- All data also persisted locally (Core Data) so the app works offline
- Firebase is source of truth for user identity and plan data (enables future multi-device sync)
- Full generated plan stored in Firestore (not just metadata)

---

## Onboarding Flow

### Design: Hybrid Wizard + Chat

**Phase 1 — Wizard (structured data collection)**
Screens with forms for data that has clear structure.

**Phase 2 — Chat (fitness assessment + plan refinement)**
Claude interviews the user conversationally to assess fitness and refine the plan.
Reuses existing `ChatView` with a mode flag and onboarding-specific system prompt + approve button.

---

### Phase 1: Wizard Screens

#### Screen 1: HealthKit Permissions
- Request HealthKit access (existing flow, expanded scope)
- Auto-pull all available data silently:
  - **Profile:** Date of birth, biological sex, height, weight
  - **Metrics:** Resting HR, VO2max (if available)
  - **Training history:** 6-12 months of swim/bike/run workouts (volume, frequency, duration trends)
- Show a loading indicator: "Analyzing your fitness data..."
- Store everything pulled; flag what was NOT available in HealthKit for manual collection in next screen

#### Screen 2: Profile (fill gaps only)
- Pre-fill anything pulled from HealthKit
- Only show fields for data NOT found in HealthKit:
  - Name (always ask — not in HealthKit)
  - Age / DOB (if not in HK)
  - Sex / Gender (if not in HK)
  - Height / Weight (if not in HK)
  - Resting HR (if not in HK)
  - Home location (city — for elevation and weather comparison)
- Skip this screen entirely if only Name is missing (just add name field to next screen)

#### Screen 3: Race Selection
- Single text input: "What race are you training for?"
- On submit → loading state ("Searching for race details...")
- Single Claude API call with web search tool finds race details (pre-search, show results)
- Display found details for confirmation:
  - Race name, date, location
  - Distances (swim/bike/run or just run, etc.)
  - Race type (triathlon, running, cycling, swimming)
  - Course type (road, trail, mixed)
  - Course elevation profile (flat, rolling, hilly, mountainous)
  - Elevation at race venue
  - Typical race-day weather (historical averages for that date/location)
- User confirms or edits the details
- If LLM can't find the race → fallback to manual entry form for all fields

#### Screen 4: Goal Setting
- Two goal types:
  - **Time target** — user enters a target finish time
  - **Just complete** — no time pressure, focus on finishing safely
- If time target selected, show input for hours:minutes

---

### Phase 2: Chat-Based Assessment

After wizard screens, transition to a Claude chat interface where the AI:

1. **Summarizes what it knows** — "Based on your HealthKit data, you've been running ~20mi/week and cycling ~50mi/week over the past 3 months. No swim data found."

2. **Asks targeted follow-up questions:**
   - Training experience for each discipline (especially if no HK data for one)
   - Injury history or current limitations
   - Available training hours per week
   - Access to equipment (pool, bike trainer, open water)
   - Previous race experience
   - Any schedule constraints (travel, work blocks)

3. **Delivers feasibility assessment:**
   - Compares current fitness (from HK data + conversation) against race demands
   - Compares weeks until race vs. weeks needed for safe preparation
   - Compares home elevation/weather vs. race conditions
   - If feasible: "You're in good shape for this. Here's what the plan will focus on..."
   - If NOT feasible: "A sub-6:00 finish in 8 weeks is risky given your current volume. A realistic target would be ~6:30. Want to adjust your goal, or proceed knowing it's aggressive?"
   - User can adjust goal or acknowledge the risk

4. **Generates plan preview:**
   - Shows high-level plan structure (phase breakdown, weekly volume progression)
   - User can ask questions or request adjustments ("Can we do more bike, less swim?", "I can't train on Tuesdays")
   - Once user approves → generate full week-by-week plan

---

## Fitness Assessment Logic

### Data Sources (priority order)
1. **HealthKit workout history (6-12 months)** — weekly volume trends, workout types, consistency
2. **HealthKit metrics** — VO2max, resting HR (direct fitness indicators)
3. **User self-report** — fills gaps via chat conversation

### Assessment Dimensions
| Dimension | How Assessed | Why It Matters |
|-----------|-------------|----------------|
| Weekly training volume | HK avg over last 3 months | Base for plan starting point |
| Sport-specific experience | HK workout type distribution + self-report | Identifies disciplines needing more ramp-up |
| Cardiovascular fitness | VO2max, resting HR from HK | Indicates aerobic capacity |
| Training consistency | HK workout frequency variance | Consistent athletes can handle more load |
| Elevation readiness | Home city elevation vs. race elevation | May need altitude-specific prep |
| Heat/weather readiness | Home climate vs. race-day historical weather | May need heat acclimation blocks |
| Time available | Weeks until race date | Determines if goal is feasible |

### Feasibility Rules
- **Minimum lead time by race type:**
  - Sprint triathlon: 8 weeks (experienced), 12 weeks (beginner)
  - Olympic triathlon: 12 weeks (experienced), 16 weeks (beginner)
  - Half Ironman (70.3): 16 weeks (experienced), 24 weeks (beginner)
  - Full Ironman: 24 weeks (experienced), 36 weeks (beginner)
  - Marathon: 12 weeks (experienced), 18 weeks (beginner)
  - Half marathon: 8 weeks (experienced), 12 weeks (beginner)
- **Experience level** derived from: HK training volume, race history (self-reported), years in sport
- If weeks available < minimum → trigger adjusted goal suggestion

---

## Plan Generation

### Method
Claude generates the full week-by-week plan based on:
- All collected user data (profile, HK history, fitness assessment)
- Race requirements (distances, course, elevation, weather)
- User goal (time target or completion)
- Available training hours and schedule constraints
- Adjustments requested during chat review

### Plan Output Flow (Chat → Convert)
1. Claude describes the plan conversationally in the onboarding chat (phases, weekly volume, key workouts)
2. User reviews, asks questions, requests adjustments in chat
3. Once user approves → a second API call converts the chat-described plan into structured JSON matching `TrainingWeek`/`DayWorkout` schema
4. Parsed JSON saved to TrainingPlanManager

### Plan Structure (matches existing TrainingPlanManager format)
- Array of `TrainingWeek` objects, each with 7 days of `DayWorkout` arrays
- Each workout has: type, description, duration, distance, intensity notes, nutrition targets
- Plan includes periodization: base → build → peak → taper
- Nutrition targets auto-applied per existing rules (60+ min workouts)

### Review Before Commit
- Claude presents plan summary conversationally: total weeks, phase breakdown, peak week volume
- User can ask for changes in chat ("more rest days", "longer long run")
- User explicitly approves → conversion API call → plan saved to TrainingPlanManager
- Plan flagged as "AI-generated" in metadata

### Post-Approval Editing
- Individual workouts editable after plan is approved (reuses existing drag-and-drop/edit UI)
- Full "regenerate from here" deferred to V2

### Existing Plan Handling
- Current hardcoded 17-week Ironman 70.3 plan remains the default for Brent's account
- New users who complete onboarding get their generated plan
- Existing users can optionally re-onboard to get a new generated plan (but not required)

### Tracing
- Onboarding chat conversations tracked in LangSmith under a separate session (e.g., "IronmanTrainer-Onboarding") for independent evaluation
- No Firebase Analytics for V1.5 (added to V2 list)

---

## Data Model Additions

### User Profile (Firestore + Core Data)
```
UserProfile {
    uid: String                  // Firebase UID
    name: String
    dateOfBirth: Date
    biologicalSex: String        // male/female/other
    heightCm: Double
    weightKg: Double
    restingHR: Int?
    vo2Max: Double?
    homeCity: String
    homeElevationM: Double?
    onboardingComplete: Bool
    createdAt: Date
}
```

### Race (Firestore + Core Data)
```
Race {
    name: String
    date: Date
    location: String
    type: RaceType               // triathlon, running, cycling, swimming
    distances: [String: Double]  // e.g., {"swim": 1.2, "bike": 56, "run": 13.1} in miles
    courseType: String            // road, trail, mixed
    elevationGainM: Double?
    elevationAtVenueM: Double?
    historicalWeather: String?    // summary of typical conditions
    userGoal: GoalType           // .timeTarget(seconds) | .justComplete
}

enum RaceType { triathlon, running, cycling, swimming }
enum GoalType { timeTarget(TimeInterval), justComplete }
```

### Plan Metadata
```
PlanMetadata {
    generatedAt: Date
    generatedBy: String          // "hardcoded" | "claude-generated"
    raceId: String?
    userProfileSnapshot: Data?   // JSON of profile at generation time
    approved: Bool               // user reviewed and approved
}
```

---

## V2 Ideas (Not in V1.5 Scope)

- **A-race + B-race support** — build plans with tune-up races built in as training milestones
- **Multi-device sync** — Firebase Firestore real-time sync across devices
- **Plan rebuild mid-training** — "I got injured, rebuild from week 8" using current fitness state
- **Programmatic plan builder** — structured plan generation engine (not just LLM freeform) using templates + parameterization for more consistent plans
- **Age-group placement goal** — look up AG results from prior years to set realistic placement targets
- **Freeform goal entry** — "qualify for Kona", "beat my PR by 10 min" interpreted by LLM
- **Training load tracking** — TSS/ATL/CTL style metrics derived from HK data to auto-adjust plan intensity
- **Polished onboarding UI** — animations, illustrations, progress indicators, custom branding
- **Firebase Analytics** — onboarding funnel tracking (drop-off rates, time-to-complete)
- **Social features** — training partners, group challenges

---

## Implementation Order

1. **Firebase setup** — project creation, Auth config, Firestore rules
2. **Apple Sign In screen** — gate before main app
3. **HealthKit expanded pull** — add DOB, sex, height, weight, resting HR, VO2max, 6-12 month history
4. **Wizard screens** — profile fill-gaps, race search, goal setting
5. **Race lookup via Claude + web search** — LLM finds race details, user confirms
6. **Chat-based fitness assessment** — Claude conversation using HK data + follow-ups
7. **Feasibility check** — weeks available vs. needed, goal adjustment flow
8. **Plan generation + review** — Claude generates plan, user reviews in chat, approves
9. **Plan commit** — save generated plan to TrainingPlanManager, mark as AI-generated
10. **Polish** — loading states, error handling, skip/back navigation
