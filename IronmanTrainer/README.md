# Ironman 70.3 Oregon Training App

An iOS app for tracking Ironman 70.3 Oregon training with HealthKit sync and Claude AI coaching.

**Race:** Ironman 70.3 Oregon, July 19, 2026 (Salem, OR)
**Goal:** Sub-6:00 finish
**Training Duration:** 17 weeks (March 23 - July 19, 2026)

## Features

- **HealthKit Integration** — Automatic workout sync from Apple Health
- **17-Week Training Plan** — Accurate plan from official Ironman coaching PDF
- **Week Navigation** — Switch between weeks with completion tracking
- **Analytics Dashboard** — Volume and zone distribution tracking
- **Claude AI Coach** — Personalized coaching with access to your training context and history
- **Day Detail View** — Planned workouts + synced HealthKit data + notes
- **App Icon** — Custom Ironman branding

## Setup

### Prerequisites
- Xcode 15.0+
- iOS 17.0+
- Anthropic API key (for Claude coaching)

### Installation

1. Clone the repository
2. **Configure API Keys:**
   - Copy `IronmanTrainer/Config.example.plist` to `IronmanTrainer/Config.plist`
   - Open `Config.plist` and add your API keys:
     - `ANTHROPIC_API_KEY` — Your Anthropic Claude API key
     - `LANGSMITH_API_KEY` — (Optional) Your LangSmith API key for evaluation
   - **Do NOT commit `Config.plist` to version control** (it's in `.gitignore`)
3. Open `IronmanTrainer.xcodeproj` in Xcode
4. Build and run on simulator or device

### Getting an Anthropic API Key
1. Visit [api.anthropic.com](https://api.anthropic.com)
2. Sign up and add credits to your account
3. Copy your API key from the dashboard
4. Paste the key into `IronmanTrainer/Config.plist` under `ANTHROPIC_API_KEY`

## Architecture

- **ContentView.swift** — Main app logic, all views, data managers
- **IronmanTrainerApp.swift** — App lifecycle, HealthKit sync on foreground
- **IronmanTrainer.entitlements** — HealthKit capability
- **Config.plist** — API configuration (gitignored for security)

## Training Plan Structure

The app hardcodes all 17 weeks of training data with:
- Daily workouts (swim, bike, run, brick)
- Durations and training zones (Z1-Z5)
- Rest days and recovery weeks
- Training phases (Ramp Up → Build → Taper → Race Prep → Race Week)

## Claude AI Coach

The coach has access to:
- Your current week's planned workouts
- Last 4 weeks of completed workouts from HealthKit
- Training zones and race goals
- Provides personalized feedback on compliance and strategy

## Notes

- **Timezone:** App respects local device timezone for date handling
- **HealthKit Matching:** Filters by exact workout type (no cross-matching between swim/bike/run)
- **Week Calculation:** Automatic based on start date (Mar 23, 2026)
- **Completion Tracking:** Green checkmarks for completed workouts from HealthKit
