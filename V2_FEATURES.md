# V2 Features

Deferred features — placeholder UI has been removed. Build these when ready.

---

## Manage Plan
**Where it was:** Plan tab → "Manage Plan" button (now hidden)

In-app plan customization controls:
- Intensity distribution sliders (polarized / pyramidal / threshold-heavy)
- Weekly volume cap overrides per discipline
- Periodization style selector (3:1, 2:1, 4:1 build:recovery)
- Training block focus (base / build / peak / taper)

---

## Adaptive Planning
Auto-adjust the training plan each week based on actual training status, without requiring Claude chat input:
- Read CTL/ATL/TSB from `TrainingStatusService` at end of week
- Compare completed volume and intensity to plan targets
- Propose next-week adjustments automatically (reduce if TSB < −30, add if CTL trending low)
- Surface as a check-in-style prompt with Accept/Skip — uses same `PlanDiffCard` flow as manual coaching

---

## Strava Integration
**Where it was:** Plan tab → Connected Apps → Strava row ("Coming Soon")

- OAuth2 login via `https://www.strava.com/oauth/authorize`
- Sync completed activities to supplement HealthKit (covers GPS routes, power data)
- Post completed workouts to Strava feed (optional toggle)

---

## Garmin Integration
**Where it was:** Plan tab → Connected Apps → Garmin row ("Coming Soon")

- Garmin Connect IQ OAuth flow
- Pull HR, power, pace from Garmin device workouts
- HRV morning readiness data from Garmin Body Battery

---

## Reset Week
**Where it was:** Calendar tab → week context menu → "Reset Week" (shows toast "Reset coming soon")

- Reset a week's workouts to their original plan state, discarding all Claude-made modifications
- Uses `WorkoutPlanVersion` Core Data stack — diff current version against the original seed
- Prompt for confirmation; show count of workouts that will revert

---

## Connected Apps: Real HealthKit Toggle
Currently HealthKit is always-connected with no way to disconnect from the app. V2:
- Show "Revoke" option that redirects to iOS Settings → Privacy → Health
- Explain what data access is used for

---

## Move Plan Regeneration Through the Proxy
**Current:** `SettingsView` → `PlanGenerationService.regenerateSurroundingWeeks()` → `OpenAIService` → OpenAI directly from the app (model hardcoded client-side).

**V2:** Route through `LLMProxyService` like coaching and plan generation already do, so model selection lives in LangSmith server-side and the app stays model-agnostic end-to-end. `PlanGenerationService.swift` and `OpenAIService.swift` can then be deleted.

---

## Settings Reorganization
**Current:** Settings sections are not logically grouped — Race Date lives inside About, notifications are split, Health fields are scattered.

**Proposed section order for V2:**

1. **Your Race** — Race Date + Secondary Races (promoted to top; most-visited setting)
2. **Notifications** — Morning Workout Reminder + Morning Check-In toggle + time picker (merged into one section)
3. **Coaching** — Swim Drills toggle
4. **Health** — Max HR, Age, HR Zones (consolidated; derived from each other so grouped)
5. **Training Environment** — Training Elevation, Climate, Pool/Open Water/Trainer toggles
6. **Plan Management** — Generate Plan, Regenerate, Restore Previous Plan
7. **Advanced** — Performance Thresholds disclosure group
8. **Account** — User ID, Sign Out, Delete Account
9. **About** — Version number only (bottom, standard iOS placement; Race Date moved to Your Race)
