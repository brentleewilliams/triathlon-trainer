# Onboarding Illustration Redesign Spec

*Last updated: 2026-04-08*

## Overview

Redesign the 6-step onboarding flow from SF Symbol + form-heavy screens to an illustration-led experience with bold color backgrounds, large hero artwork, and minimal text per screen.

**Design references:** Dribbble examples from Raquel Sanchez (recipe app), Sushama Patel (project management), Kretya Studio (AdaKita finance), Roman Lieli (Hedwig audiobook). Common patterns: flat vector characters, floating detail elements, bold single-color backgrounds, illustration takes ~55% of screen.

---

## Layout Structure (All Steps)

```
┌─────────────────────────┐
│ ▓▓▓▓▓▓▓▓░░░░  progress  │
│                         │
│   ┌─────────────────┐   │
│   │                 │   │
│   │   ILLUSTRATION  │   │  ~55% of screen
│   │   (hero area)   │   │
│   │                 │   │
│   └─────────────────┘   │
│                         │
│   Bold Title            │
│   Supporting text       │  ~25% of screen
│                         │
│   [ Action / Input ]    │  ~20% of screen
│                         │
│   ● ● ○ ○ ○ ○          │
│   Skip          Next →  │
└─────────────────────────┘
```

- Progress bar at top (keep existing blue bar, add dot indicators at bottom)
- Illustration area: full-width, aspect-fit, vertically centered
- Title: bold, large (title2 weight), white text on colored bg or dark text on light bg
- Subtitle: 1-2 lines max, secondary weight
- Action area: single primary button or minimal input
- Navigation: Skip (left) + Next (right) at bottom

---

## Per-Step Design

### Step 1: Health Data

| Property | Value |
|---|---|
| **Background** | Warm coral/red gradient (`#FF6B6B` → `#EE5A5A`) |
| **Illustration** | Athlete stretching with Apple Watch on wrist. Heart rate line floats above the watch. Small HealthKit heart icon drifts nearby. Athlete in relaxed pre-workout pose. |
| **Title** | "Let's see where you are" |
| **Subtitle** | "We'll pull your workouts and heart rate history to build your starting point" |
| **Action** | Single button: "Connect HealthKit" (white pill button on coral bg) |
| **Post-action** | Illustration transitions to show green checkmark floating over the watch. Subtitle changes to "Found X workouts — X months of data" |

### Step 2: Profile

| Property | Value |
|---|---|
| **Background** | Soft blue gradient (`#4A90D9` → `#6BB5F0`) |
| **Illustration** | Athlete standing casually, clipboard floating to one side, measuring tape and scale nearby as floating elements. Relaxed, friendly pose. |
| **Title** | "A little about you" |
| **Subtitle** | "Height, weight, and location help us dial in your zones and plan for your climate" |
| **Action** | "Continue" button → transitions to clean white/system background form screen with the existing input fields (zip, DOB, sex, height, weight) |
| **Note** | Split into two sub-screens: illustration intro → form inputs. The form screen uses the current design with rounded input fields. |

### Step 3: Race Search

| Property | Value |
|---|---|
| **Background** | Vibrant orange/amber gradient (`#FF9500` → `#FFB340`) |
| **Illustration** | Athlete crossing a finish line, banner overhead, crowd silhouettes in background, confetti floating. Finish tape breaking across chest. |
| **Title** | "Pick your race" |
| **Subtitle** | "We'll pull the course, elevation, weather, and build your plan around it" |
| **Action** | Search text field (white, rounded, centered) with search icon. Keeps current search → result card flow but on the orange background. |
| **Result state** | Race result card slides up from bottom as a white card overlay on the orange background. Trophy icon + race details. |

### Step 4: Goals

| Property | Value |
|---|---|
| **Background** | Fresh green gradient (`#34C759` → `#5DD27A`) |
| **Illustration** | Athlete at a fork in the road — one path leads to a clock/stopwatch, the other to a finish flag. Or: athlete on a podium with arms raised, looking at a floating stopwatch. |
| **Title** | "What does success look like?" |
| **Subtitle** | "Finish strong, hit a time goal, or tell us in your own words" |
| **Action** | Three tappable cards (white, stacked vertically, with small inline illustrations): |
| | - Finish flag illustration + "Just Complete It" |
| | - Stopwatch illustration + "Finish Time Goal" |
| | - Speech bubble illustration + "Custom Goal" |
| **Sub-screen** | After goal selection → skill level pickers on a clean white background (current segmented picker design) |

### Step 5: Fitness Chat

| Property | Value |
|---|---|
| **Background** | Teal/cyan gradient (`#00C7BE` → `#32D9D1`) |
| **Illustration** | Coach figure and athlete figure sitting together. Speech bubbles float between them — one bubble has a dumbbell icon, another has a calendar, another has a running shoe. Warm, conversational feel. |
| **Title** | "Let's chat about your fitness" |
| **Subtitle** | "A quick conversation so your coach knows your schedule, injuries, and gear" |
| **Action** | "Start Chat" button → transitions to the existing chat interface (dark/white background with quick reply bubbles). The chat UI itself doesn't change — only the intro screen. |

### Step 6: Plan Review

| Property | Value |
|---|---|
| **Background** | Deep purple → blue gradient (`#5856D6` → `#4A90D9`) |
| **Illustration** | Athlete running along a winding road that curves into the distance. Weekly milestone markers (small flags/dots) line the path. Finish line arch visible far ahead. Mountains or landscape in background. |
| **Title** | "Your plan is ready" |
| **Subtitle** | "X weeks of personalized training, built for [Race Name]" |
| **Action** | "Start Training" button (white pill on purple bg) |
| **Loading state** | Illustration shows the road being "drawn" with a subtle animation. Text: "Building your personalized plan..." |
| **Loaded state** | Plan summary cards slide up from bottom (current design) over a white background, pushing the illustration to a smaller header area. |

---

## Illustration Style Guide

### Character Style
- **Flat vector**, not 3D — clean outlines, limited color palette per illustration (3-4 colors + white)
- **Human characters** — diverse athletes in action, slightly stylized/rounded proportions
- **No faces or minimal faces** — dot eyes or simple features, keeps it universal
- **Consistent character proportions** across all 6 steps — same "world"
- **Athletic but approachable** — not elite/intimidating body types

### Composition
- **Floating elements** — small objects orbit the main character (heart rate line, stopwatch, calendar, sneakers, water bottle) to add context without clutter
- **White/light elements on colored backgrounds** — illustrations pop against the bold backgrounds
- **Centered composition** — character is the focal point, floating elements provide context
- **Generous whitespace** — don't fill every corner, let the illustration breathe

### Color Rules
- Each illustration uses the step's background color as its dominant tone
- Characters wear neutral colors (white, light gray, dark blue) so they work on any background
- Floating elements use white or the step's accent color
- Subtle shadows (soft, not drop shadow) for depth

### Technical Specs
- **Canvas size:** 1125 x 1125 px (@3x) — rendered as aspect-fit in a frame ~55% of screen height
- **Format:** PNG with transparency (characters float on the gradient background)
- **Asset names in Xcode:**
  - `onboarding-health` (Step 1)
  - `onboarding-profile` (Step 2)
  - `onboarding-race` (Step 3)
  - `onboarding-goals` (Step 4)
  - `onboarding-chat` (Step 5)
  - `onboarding-plan` (Step 6)
- **Provide @2x and @3x** — Xcode asset catalog handles the rest

---

## Code Changes Required

### New Files
- `OnboardingIllustrationStep.swift` — Reusable view component for the illustration + title + subtitle + action layout

### Modified Files
- `OnboardingView.swift` — Replace each step's icon + form layout with the illustration layout for intro screens; split Profile and Goals into intro → form sub-screens
- `Assets.xcassets` — Add 6 new image sets for onboarding illustrations

### SwiftUI Component

```swift
struct OnboardingIllustrationStep: View {
    let illustration: String          // asset name
    let backgroundColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            LinearGradient(...)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(illustration)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
                    .padding(.horizontal, 32)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
                // Action button or input injected via ViewBuilder
            }
        }
    }
}
```

### Steps That Split Into Two Sub-Screens

**Step 2 (Profile):**
1. Illustration intro with "Continue" → 
2. Clean white form screen (existing input fields, no illustration)

**Step 4 (Goals):**
1. Illustration intro with 3 goal type cards →
2. Skill level pickers on clean white screen (existing segmented pickers)

**Step 5 (Fitness Chat):**
1. Illustration intro with "Start Chat" →
2. Existing chat interface (no visual change needed)

All other steps keep the illustration as a header area while showing their action/input inline.

---

## Transition Animations

- **Between steps:** Keep existing asymmetric slide (right-in, left-out)
- **Illustration entrance:** Fade in + slight scale up (0.95 → 1.0) over 0.4s
- **Floating elements:** Subtle continuous float animation (gentle Y-axis bob, 3s cycle, offset per element)
- **Sub-screen transition (Profile/Goals):** Illustration slides up and shrinks into a header bar as form fields slide in from below
- **Plan loading (Step 6):** Road illustration draws progressively (trim path animation) while plan generates

---

## What Doesn't Change

- Progress bar design (blue fill bar + step label)
- Form field styling (rounded borders, system colors)
- Chat interface (Step 5 chat screen)
- Plan review cards (Step 6 summary cards)
- Business logic, validation, data flow
- Navigation structure (6 steps, same order)

---

## Comparison: Current vs. Redesigned

| Aspect | Current | Redesigned |
|---|---|---|
| Visual anchor | 56-64pt SF Symbol | Full-width hero illustration |
| Background | White (systemBackground) | Bold per-step gradient |
| Text color | System primary (dark) | White on colored gradient |
| Personality | Clinical/form-like | Warm, friendly, human |
| Screen density | All inputs visible at once | Illustration intro → inputs on sub-screen |
| Brand feel | Generic iOS utility | Distinctive, memorable, premium |
| Asset requirements | None (SF Symbols only) | 6 custom illustrations |

---

## Production Options for Illustrations

1. **Hire an illustrator** — Dribbble, Fiverr, or Upwork. Budget: $200-600 for 6 illustrations in a consistent style. Best quality and consistency.
2. **AI image generation** — Use Midjourney/DALL-E with a consistent style prompt. Faster and cheaper but harder to maintain exact consistency across 6 images. May need manual cleanup in Figma/Illustrator.
3. **Illustration libraries** — Services like unDraw, Blush, or Storyset offer customizable flat vector illustrations. Free or cheap, but may look generic. Can mix-and-match characters from the same style pack for consistency.
4. **Hybrid** — Use an illustration library for base characters, then customize colors and add floating elements in Figma to match the per-step theme.

**Recommendation:** Option 4 (hybrid) for speed, or Option 1 for premium feel. The consistent character style across all 6 screens is the most important factor — inconsistent styles look worse than no illustrations at all.
