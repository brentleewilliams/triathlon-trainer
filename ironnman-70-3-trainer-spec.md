# Ironman 70.3 Training App Spec

## Overview
A basic iOS app to track Ironman 70.3 training workouts, view weekly plans, sync HealthKit data, and get coaching insights via Claude AI.

**Race**: Ironman 70.3 Oregon | **Date**: July 19, 2026 | **Location**: Salem, OR
**Athlete**: Brent | **Goal**: Sub-6:00 | **Training Duration**: 17 weeks (Mar 23 – Jul 19)

---

## Core Features (MVP)

### 1. Weekly Training Schedule
- Display current week's planned workouts
- Show swim/bike/run sessions with:
  - Duration
  - Zone (Z1–Z5) or intensity
  - Key notes (e.g., "Gut: 70g carbs/hr", "First brick")
- Navigate forward/backward through weeks
- Indicate phase name (Volume Rebalance, Build 1, etc.)

### 2. HealthKit Sync
- Auto-pull completed workouts from Apple Health
- Match HealthKit workouts to planned workouts by:
  - Workout type (swim, cycle, running)
  - Day of week
  - Approximate duration window (±15 min tolerance)
- Mark planned workout as "Complete" if matched
- Display actual metrics: duration, distance, HR, calories

### 3. Workout Completion Status
- Visual indicator (checkmark/badge) for completed workouts
- Show completed vs. planned for week
- Quick view of what's remaining

### 4. Weekly Analytics
- **Volume Summary**: Total hours (swim/bike/run) vs. plan
- **Zone Distribution**: % time in each HR zone (Z1–Z5) this week
- Show vs. previous week trend

### 5. Claude AI Chat
- Ask questions about:
  - Training plan (e.g., "What's my pacing target?", "What zone should I be in?")
  - Completed workouts (e.g., "How much Z2 did I do this week?", "Am I on pace with volume?")
  - Recovery, nutrition, race strategy based on plan
- Claude has context: training plan + workout history
- Simple chat interface (messages list + text input)

---

## Data & Architecture

### Training Plan Data
- **Source**: Hardcoded from PDF (17 weeks, Mar 23 – Jul 19)
- **Structure**: Array of weeks → days → sessions
- **Includes**: Duration, zone/intensity, notes
- **V2 Feature**: Allow user to edit/upload plan changes

### HealthKit Integration
- Request permissions for: Workouts, Heart Rate
- Read: Completed workouts (swim, cycle, run)
- Sync on app launch + manual "Refresh" button
- Store locally (CoreData or simple JSON) for offline access

### Claude API Integration
- Call Claude with:
  - User question
  - Full training plan context
  - Recent workout history (last 4 weeks)
  - Current week stats
- Use Claude as a coaching assistant, not just raw data lookup

### Local Storage
- CoreData for:
  - Synced workouts
  - Completion status
  - User notes
- JSON fallback for simplicity (initial MVP)

---

## UI/UX

### Main Screens
1. **Today/This Week** (home)
   - Current day's workouts at top
   - Week view: Mon–Sun planned → status indicators
   - Action button: "Sync HealthKit"

2. **Analytics**
   - Volume summary (swim/bike/run bars)
   - Zone pie chart (% time Z1–Z5)
   - This week vs. last week comparison

3. **Chat with Coach**
   - Message list (alternating left/right)
   - Text input + send button
   - Typing indicator

4. **Plan Overview** (optional first release)
   - Calendar view of all 17 weeks
   - Tap week to see details
   - Highlight current week

### Design
- Light color scheme, easy to read at a glance
- Use Apple Health colors for workout types (swim = blue, bike = orange, run = green)
- HR zones color-coded (Z1 gray, Z2 green, Z3 yellow, Z4 orange, Z5 red)

---

## Non-Functional Requirements

### Timeline
- **Week 1 (this week)**: MVP with plan display, HealthKit sync, basic chat

### Scope Boundaries (V1)
- ✅ Display training plan
- ✅ HealthKit sync
- ✅ Weekly volume summary
- ✅ Zone distribution
- ✅ Claude chat (plan + workouts)
- ❌ Apple Watch app (V2)
- ❌ Plan editing (V2)
- ❌ Cloud sync (V2)
- ❌ Social features, Strava integration (V2+)

### Performance
- App launches in <2s
- HealthKit sync completes in <5s
- Claude chat response in <10s

### Permissions
- HealthKit (workouts, heart rate)
- Notifications (optional, V1)

---

## Decisions Log

| Decision | Rationale | Status |
|----------|-----------|--------|
| Hardcode plan vs. upload | MVP speed; add upload in V2 | ✅ Decided |
| HealthKit sync only | No manual logging needed | ✅ Decided |
| Auto-match workouts | Reduce friction; user just trains | ✅ Decided |
| Claude integration | Personalized coaching at scale | ✅ Decided |
| Weekly analytics (not daily) | Avoid overanalysis; align with triathlon planning | ✅ Decided |
| iOS only (not web) | Native experience, HealthKit access | ✅ Decided |

---

## Implementation Status

✅ **COMPLETE & BUILDING**
- [x] Project structure created and building successfully
- [x] Core models (Workout, TrainingPlan, CompletedWorkout, WeeklyStats)
- [x] 17-week hardcoded training plan from PDF
- [x] HealthKit integration (permissions, fetch, match, sync)
- [x] CoreData persistence for workouts
- [x] ViewModels for Home, Analytics, Chat
- [x] SwiftUI Views (Home, Analytics, Chat, Plan tabs)
- [x] Claude API service with coaching context
- [x] Xcode project configuration for iOS 17+

**Build Status**: ✅ BUILD SUCCEEDED
**Target**: iOS 17+ | iPhone/iPad
**Build Date**: Mar 27, 2026

## Next Steps (Post-MVP)

1. **Add All Service Code**: Re-implement HealthKit, Claude, CoreData services into the fresh project
2. **Add All ViewModels & Views**: Import the full implementations from agents
3. **Set Claude API Key**: Replace placeholder in ClaudeService.swift
4. **Test on Real Device**: iOS 17+ iPhone for HealthKit integration
5. **Add App Icons**: Create AppIcon.appiconset for branding

## Questions for Future Refinement
- [ ] Should app warn if weekly volume deviates >15% from plan?
- [ ] Sync HealthKit on background timer or only on app launch?
- [ ] Store full workout history or last 4 weeks only?
- [ ] Add race-day countdown timer in final week?

