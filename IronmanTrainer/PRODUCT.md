# Race1 Trainer Product Spec

*Centralized product decisions, feature specs, and roadmap. Updated 2026-04-22.*
*For architecture/build details, see `CLAUDE.md`. For competitive analysis, see `product-planning-and-differentiation.md`.*

---

## Product Vision

An AI-powered race coaching app that knows your specific race — the course, the elevation, the aid stations, the weather — and builds training and race-day plans around it. Not a generic training platform. A coach for YOUR next race.

**Current state:** Race-agnostic architecture supporting triathlon, running, and custom race types. Tool-calling plan changes with visual diff negotiation UI (PlanDiffCard), secondary races, AI-generated plans via Cloud Functions + LangSmith prompt management. Morning check-in with daily push notification + focused coaching sheet. Race Course Intelligence v1 with bundled Oregon 70.3 profile. Firebase auth, Firestore sync, onboarding flow. Primary user: Brent's Ironman 70.3 Oregon (July 19, 2026, sub-6:00 goal).

**V2 vision:** Public product — any race, any athlete. Race course intelligence, post-race failure analysis, Apple Watch app.

---

## Feature Specs

### Race Profile Import (Designed 2026-04-02, Not Yet Built)

**Problem:** The Claude coach needs race-specific context (course details, elevation, aid stations, cutoffs, on-course nutrition) to give good advice. Currently hardcoded for Oregon 70.3. Needs to work for any race.

**Solution:** Let users import race data from athlete guide PDFs via an in-app WebView flow.

**User Flow:**
1. Settings > "Import Race"
2. User enters race name naturally (e.g., "Ironman 70.3 Oregon") or pastes a race page URL
3. If natural language: send to Claude to resolve the official race page URL
4. App opens `WKWebView` to the race page (bypasses Cloudflare bot protection since it's a real WebKit browser)
5. User browses the page and taps the athlete guide PDF download link
6. App intercepts the PDF download via `WKDownloadDelegate` (iOS 14.5+)
7. App sends PDF pages to Claude API with extraction prompt
8. Claude returns structured `RaceProfile` JSON
9. User confirms extracted data
10. App stores `RaceProfile` locally, injects into coach system prompt

**Why WebView:** ironman.com (and most race sites) use Cloudflare bot protection. Direct URL fetching fails. `WKWebView` is a real browser that bypasses this. User interaction (clicking the PDF link) is natural and requires no file management.

**Fallback paths:**
- File picker (`.fileImporter`) if user already has the PDF downloaded
- Share Sheet extension so user can share a PDF directly from Safari/Mail into the app

**Data model — `RaceProfile`:**
```swift
struct RaceProfile: Codable {
    // Identity
    var raceName: String           // "IRONMAN 70.3 Oregon"
    var raceDate: Date             // July 19, 2026
    var location: String           // "Salem, Oregon"
    var venueAddress: String       // "Riverfront City Park, 200 Water St NE, Salem, OR 97301"

    // Course
    var swimDistance: Double        // 1.2 (miles)
    var swimType: String           // "Point-to-point, downstream river"
    var swimNotes: String          // "Willamette River, rolling start, 1.2mi walk to start"
    var bikeDistance: Double        // 56 (miles)
    var bikeElevationGain: Int     // 1149 (feet)
    var bikeType: String           // "Out and back"
    var bikeNotes: String          // "Three S-curve railroad overpasses, roads open to traffic"
    var runDistance: Double         // 13.1 (miles)
    var runElevationGain: Int      // 341 (feet)
    var runType: String            // "2 laps"
    var runNotes: String           // "Minto-Brown Island Park, very flat, shaded trails"

    // Cutoffs
    var totalCutoff: String        // "8 hours 30 minutes"
    var swimCutoff: String         // "1 hour 10 minutes"
    var bikeCutoff: String         // "5 hours 30 minutes after last swimmer enters water"
    var runCutoff: String          // "8 hours 30 minutes"
    var intermediateCutoffs: [String] // ["Bike mile 28 by 11 AM", "Run mile 6.6 by 2:45 PM"]

    // Aid Stations
    var bikeAidStations: [AidStation]
    var runAidStations: [AidStation]

    // On-Course Nutrition
    var bikeNutritionProducts: [String] // ["Mortal Hydration", "Maurten Gel 100", ...]
    var runNutritionProducts: [String]  // Same plus "cola", "chips", "pretzels", "oranges"

    // Logistics
    var raceStart: String          // "6:15 AM"
    var transitionOpen: String     // "5:00 AM"
    var checkInTimes: String       // "Fri 2-7 PM, Sat 9 AM-4 PM"
    var bikeCheckIn: String        // "Sat 9:30 AM-4:30 PM"

    // Rules
    var wetsuitRules: String       // "Legal up to 76.1F, optional 76.1-83.8F (no AG awards)"
    var draftingRules: String      // "No drafting, 12m zone, 25 sec to pass"
}

struct AidStation: Codable {
    var location: String           // "Mile 16" or "Every mile"
    var products: [String]
}
```

**Claude extraction prompt (draft):**
> Extract structured race data from this athlete guide. Return JSON matching this schema: [RaceProfile schema]. Focus on: course distances and terrain, elevation gain, aid station locations and products, cutoff times (overall and intermediate), race start time, transition logistics, wetsuit rules, drafting rules. Ignore sponsor ads and general IRONMAN policies.

**Key decisions:**
- LLM resolves race URLs (not a hardcoded race list) — works for any triathlon, not just IRONMAN
- WebView for PDF access (not scraping) — robust, legal, no maintenance
- Claude extracts structured data from PDF (not manual entry) — consistent format across athlete guides
- `RaceProfile` injected into coach system prompt alongside training plan and HealthKit data

**Oregon 70.3 reference data (from 2025 athlete guide):**
- Swim: 1.2mi downstream Willamette River, point-to-point, rolling start 6:15 AM
- Bike: 56mi out-and-back, 1,149 ft gain, aid at miles 16/30/45, 3 railroad overpasses
- Run: 13.1mi, 2 laps Minto-Brown Island Park, 341 ft gain, aid ~every mile
- Cutoffs: 8:30 total, 1:10 swim, 5:30 bike, intermediate at bike mi 28 / run mi 6.6
- Nutrition: Mortal Hydration, Maurten Gel 100/CAF, Maurten Solid 225/C, bars, bananas, cola (run), fruit
- Wetsuit legal up to 76.1F; no-drafting (12m zone)
- Check-in at Riverfront City Park, 200 Water St NE, Salem OR

---

### Unplanned Workout Visibility (Built — 2026-04-22)

**Problem:** HealthKit workouts that didn't match a planned session were silently dropped from the UI. If an athlete did a spontaneous run on a rest day, a strength session on an easy-bike day, or a hike for fun, none of it showed up on Home, the day detail, or analytics — even though the data was right there in the app.

**Solution:** A shared `findUnplannedWorkouts(on:plannedWorkouts:hkWorkouts:)` helper identifies HK workouts on a given date whose activity type doesn't match any of that day's planned workouts. Surfaced in three places:
- **Home day row:** small orange "N bonus" badge next to the weather icon for past/today days with off-plan activity.
- **Day detail:** dedicated "Other Activity" section (orange tint, "Not in plan" chip) listing each off-plan workout with duration, distance (miles or yards for swim), and calories.
- **Analytics Volume Summary:** footer shows total bonus hours with per-discipline breakdown (Swim/Bike/Run/Other) when the week includes off-plan activity.

Rest days count every HK workout as unplanned (nothing was expected). Brick/race-sim days treat both cycling and running as planned so the bike or run leg of a brick workout isn't mislabeled as bonus. Claude already saw "EXTRA" labeled workouts in its context (per-planned greedy matching in `ChatViewModel.getWorkoutHistoryForClaude`); no change there.

**Key details:**
- `unplannedActivityIndices(plannedTypes:actualTypes:hasBrick:)` is the pure, testable core — returns indices of unmatched activity types. 10 unit tests in `WorkoutMatchingTests.swift` cover all-matched, extras on planned days, rest days, brick day handling, and multi-extra ordering.
- `AnalyticsViewModel.cachedUnplannedVolume: (swim, bike, run, other)` computed per-day in `recalculate()`, reusing the same helper as the UI so the split stays consistent.
- Badge only shown for past/today days to avoid empty placeholders on future days.

---

### Plan Negotiation UI (Built — 2026-04-14)

**Problem:** The original plan change confirmation was a simple Apply/Dismiss button with no context about what was changing, why, or the impact on weekly volume.

**Solution:** PlanDiffEngine enriches Claude's tool-call proposals with per-day diff data and volume deltas. PlanDiffCard renders a color-coded visual diff: unchanged days grey, modified days amber, dropped days red, added days green. Key sessions (long runs, race-pace workouts) get badges. Each change shows Claude's `rationale` field. Accept/Modify/Reject replaces the old Apply/Dismiss.

**Key details:**
- `DayDiffStatus` enum: unchanged, modified, dropped, added, swapped
- `rationale` field added to PlanChange schema (Cloud Function tool updated)
- `EnrichedProposal` wraps original proposal with `[WeekDiff]` for rendering
- 22 unit tests in PlanDiffEngineTests.swift

---

### Morning Check-In v1 (Built — 2026-04-14)

**Problem:** The coach was reactive — athletes had to open the chat to get guidance. No proactive outreach when something changed (bad sleep, missed workout, high training load).

**Solution:** Daily push notification triggers a focused check-in sheet at user-configured time. CheckInManager generates a contextual opening message from HealthKit sleep data + yesterday's workout. Sheet limits to 3 message exchanges, then surfaces Accept/Keep-Original buttons to apply or discard any plan tweaks Claude suggests.

**User Flow:**
1. User enables check-in in Settings, sets preferred time
2. Cloud Function scheduleCheckInNotifications fires on cron (*/5 * * * *)
3. Push notification arrives with contextual preview
4. User taps → app opens CheckInView sheet (not main chat)
5. Claude's opening message: "You slept 6.2 hours — how are you feeling about today's long run?"
6. Max 3 exchanges, then Accept / Keep-Original buttons
7. Accepted changes routed through standard plan change flow (PlanDiffCard)

**Key details:**
- CheckInManager.shared: caches message 6h, tier-2/3 fallback for users without FCM token
- CheckInView: isolated from main chat (separate history, max 3 messages)
- ChatFilter enum in ChatView: All / Check-ins filter chips
- Fallback: local UNUserNotification when FCM token unavailable
- Sleep data: HealthKitManager.fetchSleepData + summarizeSleep

---

### Race Course Intelligence v1 (Built — 2026-04-14)

**Problem:** The coach gave generic pacing and effort advice without knowing the Oregon course — flat swim, rolling bike with overpasses, flat shaded run. Context-free advice misses race-specific preparation.

**Solution:** Bundled Oregon 70.3 course profile injected into Claude's system prompt at race-appropriate tiers. RaceCourseService provides phase-dependent context: general terrain always, altitude strategy at +5 weeks out, detailed segment pacing at +2 weeks. CourseDetailView shows athletes the course overview, altitude comparison, phase checklist, and race-week weather.

**Key details:**
- `RaceCourseProfile` struct: terrain, elevation gain, phase thresholds, pacing targets by discipline
- `TerrainProfile` enum: flat, rolling, hilly, mountainous
- Three context tiers: always (terrain overview), +5wk (altitude adjustment), +2wk (pacing targets)
- `AthleteEnvironment`: elevation, climate, timezone offset (UserDefaults persisted)
- `PerformanceThresholds`: FTP, lactate threshold, pace thresholds (inferred or user-entered)
- HomeView race countdown banner taps to CourseDetailView
- SettingsView: Training Environment section + Performance Thresholds disclosure
- v2 seam: BundledCourseProfiles.swift structured for Cloud Function research path + Firestore cache

---

### Tool-Calling Plan Changes (Built — 2026-04-09)

**Problem:** Original plan change approach used fragile JSON-in-text parsing — Claude would embed `PLAN_CHANGES` JSON in its response text, which was unreliable and hard to parse.

**Solution:** Migrated to proper Claude tool-calling. The coaching prompt includes a `modify_training_plan` tool definition. Claude proposes structured changes (swap days, replace workouts, add/remove workouts) via `tool_use` blocks. ChatViewModel parses these into a `PlanChangeProposal`, shows a confirmation UI, and executes on user approval. Changes persist via Core Data WorkoutPlanVersion across app launches.

**Key details:**
- Context window trimmed to current week ±2 to keep tool-call instructions prominent
- Per-message reminder ensures Claude calls the tool rather than describing changes in text
- Supports: swap, replace, add, remove actions
- Undo support via WorkoutPlanVersion rollback

---

### Secondary Races (Built — 2026-04-10)

**Problem:** Athletes often do tune-up races (sprint tri, local 5K) during their training cycle. No way to represent these in the plan.

**Solution:** Users can add secondary races. Race cards auto-insert into the plan timeline at the appropriate week. Plan adjustments (taper, recovery) can be suggested by the coach around secondary race dates.

---

### Race-Agnostic Architecture (Built — 2026-04-10)

**Problem:** App was hardcoded for Ironman 70.3 Oregon — phase labels, week caps, race display, and Claude prompts all assumed a specific race.

**Solution:** Made everything dynamic from user's onboarding data: race date from UserDefaults, dynamic phase labels, flexible week count, race-agnostic Claude prompts, expanded HealthKit matching for non-triathlon sports (yoga, strength, hiking, etc.).

---

### Plan-Wide Chat Changes (Not Yet Built)

**Problem:** Tool-calling currently supports per-workout operations (swap/replace/add/remove on a specific date). Athletes can't make sweeping requests like "move all swims to Tue/Thu" or "drop the Wednesday run every week" — they have to edit each week individually, and Claude only sees ±2 weeks of context.

**Solution:** Add an `apply_pattern_change` tool with arguments like `{workout_type, new_day_of_week, scope: "rest_of_plan" | "all_weeks"}`. The Cloud Function applies the change across every matching week and emits a single `EnrichedProposal` with a multi-week diff. PlanDiffCard gets a summary mode — "17 swim sessions will move — 9 to Tue, 8 to Thu" with drill-in to see every affected week.

**Open UX questions:**
- Show every affected week in the diff card (scrollable), or a summary with drill-in?
- Should the tool support scope `"this_week_only"` or is that covered by existing per-workout swap?

**Depends on:** nothing new — existing tool-calling infrastructure can carry this with a new tool definition.

---

### Adaptive Plan (React to Actual Performance) (Not Yet Built)

**Problem:** The plan is generated once at onboarding and never changes on its own. If an athlete misses workouts, runs 20% short, or shows cardiac drift (HR climbing at a fixed pace), nothing happens — the next week's plan still assumes the baseline is intact.

**Solution — three tiers:**
- **Reactive (per workout):** When a workout lands in yellow/red compliance, a proposal fires via `CheckInManager`-style coaching event ("You ran 20% short today — shift tomorrow's long run?").
- **Weekly roll-up:** Every Sunday, a "week review" uses compliance + HR trends to propose adjustments for next week (fatigue drift, missed volume, zone drift).
- **Trend-based:** Detect cardiac drift or overreaching patterns across 2-3 weeks and suggest a recovery week.

Extends `CheckInManager` into a general "coaching event" system triggered by workout completion, weekly boundary, or app launch. Proposals flow through the standard PlanDiffCard Accept/Reject UI.

**Open UX questions:**
- Always Accept/Reject, or auto-apply low-risk changes (shift tomorrow by ±10%) with a toast-level undo?
- Weekly roll-up: Sunday notification, or surfaced on first open Monday morning?

**Depends on:** Unplanned Workout Visibility (built) — so the data the adaptive engine reads is complete. Best paired with Plan-Wide Chat Changes so Claude can act at both scopes.

---

### App-Open Coaching Prompts (Not Yet Built)

**Problem:** Morning Check-In only fires via scheduled push notification. If the user opens the app mid-day after missing a workout, or a few days after last interacting, nothing prompts them — the coach stays silent until tomorrow morning.

**Solution:** `CoachingEventManager` checks on `scenePhase == .active`:
- Pending proposals from the adaptive plan engine
- Stale plan (>2 consecutive missed workouts)
- No coach interaction in >24h
If any are true, show a non-modal banner on HomeView ("Coach has an update — tap to review") that opens CheckInView. Rate-limited to once per day, skipped if Morning Check-In already ran that day.

**Open UX questions:**
- If Morning Check-In ran at 7am and user opens at 3pm after a missed workout, prompt again or wait until tomorrow?
- Banner placement: above the race countdown, or below the weekly plan?

**Depends on:** Adaptive Plan (to generate events worth surfacing).

---

### Weekly Volume Deviation Warning (Not Yet Built)

**Problem:** No alert when actual training hours fall significantly below planned hours for the week.

**Solution:** Compare actual HealthKit hours to planned hours, surface warning like "You're 22% under plan this week." WorkoutComplianceService already calculates per-workout deviation — extend to weekly aggregate.

---

### AI-Generated Training Plans (In Progress — Template + LLM Approach)

**Problem:** Fully custom LLM plan generation takes 2-5 min and produces unpredictable structure.

**Solution:** Template-based generation (tri + running templates with short/medium/long duration buckets) plus a single LLM customization pass (<30s target). Fully custom LLM path retained as fallback for unusual race types. Pipeline: LLMProxyService → Cloud Functions → LangSmith prompts → gpt-4.1-mini.

---

### Race-Day Execution Plan (Not Yet Built — V2)

**Problem:** No race-day pacing + nutrition plan. RaceDay app does this well (15-min interval pacing, product-level nutrition).

**Solution:** "Race Week" tab that generates a plan using Claude + `RaceProfile` course data. Pacing targets per segment, nutrition timing with specific products from aid stations.

---

## Key Product Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Training plan source | Template + LLM customization (in progress) | Fully custom LLM too slow (2-5 min); templates guarantee periodization, LLM adds personalization |
| Race data import | WebView + PDF extraction via Claude | ironman.com blocks scraping; PDF has richest data |
| Race discovery | LLM resolves URLs from natural language | No hardcoded race list to maintain |
| Workout matching | HealthKit only (V1), Strava/Garmin (V2) | Solve own problem first (Apple Watch user) |
| Nutrition coaching | Built into training plan, not a separate layer | Differentiator vs competitors who bolt nutrition on |
| Pricing target (V2) | $15-20/mo | Below TriDot ($89), matches Humango/MOTTIV |
| Plan changes | Tool-calling (not JSON-in-text) | Reliable structured changes with confirmation UI |
| App name | Race1 Trainer (renamed from IronmanTrainer) | Race-agnostic branding for V2 public product |
| Doc structure | PRODUCT.md (specs) + CLAUDE.md (architecture) | Separate what from how |

---

## Roadmap Summary

### Pre-Race (Now → July 19, 2026)
- [x] Tool-calling plan changes (swap/replace/add/remove)
- [x] Plan Negotiation UI (PlanDiffCard with color-coded diffs + rationale)
- [x] Morning Check-In v1 (daily push notification + focused coaching sheet)
- [x] Race Course Intelligence v1 (bundled Oregon profile + CourseDetailView)
- [x] Secondary races support
- [x] Race-agnostic architecture
- [x] VerifiedRaceDatabase for date validation
- [x] Home screen widget
- [x] Unplanned workout visibility (bonus badge, Other Activity, analytics footer)
- [ ] Plan-wide chat changes (`apply_pattern_change` tool — "move all swims to Tue/Thu")
- [ ] Adaptive plan — tier 1 reactive (propose adjustments after yellow/red compliance workouts)
- [ ] App-open coaching prompts (CoachingEventManager banner on HomeView)
- [ ] Adaptive plan — tier 2 weekly roll-up (Sunday review → next-week adjustments)
- [ ] Adaptive plan — tier 3 trend-based (cardiac drift, overreach detection)
- [ ] Race Profile Import (WebView + PDF extraction)
- [ ] Weekly volume deviation warning
- [ ] Hardcoded zone values override option

### V2: Public Product (Post-Race)
- [x] AI-generated training plans (in progress — template + LLM approach)
- [ ] Race-day execution plan generator
- [ ] Recovery/readiness signals (HRV, sleep)
- [ ] Apple Watch app with structured workouts
- [ ] Strava/Garmin Connect sync
- [ ] Multi-race lifecycle (next-race pipeline, off-season plans)
- [ ] Post-race analysis (ingest splits + nutrition log, generate report)
- [ ] Mid-training plan rebuild ("I got injured, rebuild from week 8")
- [ ] Training load tracking (TSS/ATL/CTL style metrics from HealthKit data)
- [ ] Age-group placement goal (look up AG results from prior years, set realistic placement targets)
- [ ] Firebase Analytics for onboarding funnel tracking
