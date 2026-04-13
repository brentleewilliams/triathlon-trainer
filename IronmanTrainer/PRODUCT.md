# Race1 Trainer Product Spec

*Centralized product decisions, feature specs, and roadmap. Updated 2026-04-13.*
*For architecture/build details, see `CLAUDE.md`. For competitive analysis, see `product-planning-and-differentiation.md`.*

---

## Product Vision

An AI-powered race coaching app that knows your specific race — the course, the elevation, the aid stations, the weather — and builds training and race-day plans around it. Not a generic training platform. A coach for YOUR next race.

**Current state:** Race-agnostic architecture supporting triathlon, running, and custom race types. Tool-calling plan changes, secondary races, AI-generated plans via Cloud Functions + LangSmith prompt management. Firebase auth, Firestore sync, onboarding flow. Primary user: Brent's Ironman 70.3 Oregon (July 19, 2026, sub-6:00 goal).

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
- [x] Secondary races support
- [x] Race-agnostic architecture
- [x] VerifiedRaceDatabase for date validation
- [x] Home screen widget
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
