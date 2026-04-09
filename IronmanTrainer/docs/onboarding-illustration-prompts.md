# Onboarding Illustration Prompts

Image generation prompts for the 6 onboarding illustrations. Use these in Midjourney, DALL-E 3, or similar tools.

## Style Preamble (prepend to every prompt)

Use this prefix for consistency across all 6 images:

```
Flat vector illustration, modern app onboarding style, detailed human characters with simple friendly faces, slightly rounded proportions, clean outlines, soft shadows, light pastel background, no text, no UI elements, PNG with transparent background, centered composition with floating decorative elements around the main character, warm and approachable feel, high quality digital illustration --ar 1:1 --style raw
```

> **Tip:** In Midjourney, generate all 6 in one session for maximum style consistency. If style drifts, use `--sref [URL of first image]` on subsequent prompts to lock in the style.

---

## Step 1: Health Data — "Let's see where you are"

**Background color:** Warm coral (`#FF6B6B`)

```
Flat vector illustration, modern app onboarding style, detailed human characters with simple friendly faces, slightly rounded proportions, clean outlines, soft shadows, warm coral pastel background, no text, no UI elements, centered composition, warm and approachable feel, high quality digital illustration.

A friendly athletic woman in workout clothes doing a gentle standing stretch, wearing a smartwatch on her wrist. A glowing heart rate line (ECG waveform) floats above the watch in a gentle arc. Small floating elements surround her: a red heart icon, a small pulse wave, a tiny green checkmark. She looks relaxed and confident. Soft coral pink background. The mood is welcoming, like the start of a health journey.

--ar 1:1 --style raw
```

---

## Step 2: Profile — "A little about you"

**Background color:** Soft blue (`#4A90D9`)

```
Flat vector illustration, modern app onboarding style, detailed human characters with simple friendly faces, slightly rounded proportions, clean outlines, soft shadows, soft blue pastel background, no text, no UI elements, centered composition, warm and approachable feel, high quality digital illustration.

A friendly athletic man standing in a relaxed casual pose with arms slightly out, wearing athletic clothes. Floating around him: a small clipboard with lines on it, a tape measure curling gently in the air, a location pin icon, a tiny calendar. He looks approachable and at ease, like he's introducing himself. Soft blue background. The mood is calm and personal.

--ar 1:1 --style raw
```

---

## Step 3: Race Search — "Pick your race"

**Background color:** Vibrant orange/amber (`#FF9500`)

```
Flat vector illustration, modern app onboarding style, detailed human characters with simple friendly faces, slightly rounded proportions, clean outlines, soft shadows, warm orange amber pastel background, no text, no UI elements, centered composition, warm and approachable feel, high quality digital illustration.

An athletic woman joyfully crossing a race finish line, breaking through a finish tape with arms raised in celebration. Behind her, a subtle crowd of silhouetted spectators cheering. Small floating elements: confetti pieces, a tiny trophy, a checkered flag, a small medal. She looks triumphant and happy. Warm orange amber background. The mood is exciting and aspirational.

--ar 1:1 --style raw
```

---

## Step 4: Goals — "What does success look like?"

**Background color:** Fresh green (`#34C759`)

```
Flat vector illustration, modern app onboarding style, detailed human characters with simple friendly faces, slightly rounded proportions, clean outlines, soft shadows, fresh green pastel background, no text, no UI elements, centered composition, warm and approachable feel, high quality digital illustration.

An athletic man standing at a fork in a winding path, looking ahead thoughtfully with a hand on his chin. One path curves toward a floating stopwatch icon, the other curves toward a floating finish flag. Small floating elements around him: a target/bullseye, a star, a small mountain peak. He looks focused and optimistic. Fresh green background. The mood is decisive and forward-looking.

--ar 1:1 --style raw
```

---

## Step 5: Fitness Chat — "Let's chat about your fitness"

**Background color:** Teal/cyan (`#00C7BE`)

```
Flat vector illustration, modern app onboarding style, detailed human characters with simple friendly faces, slightly rounded proportions, clean outlines, soft shadows, teal cyan pastel background, no text, no UI elements, centered composition, warm and approachable feel, high quality digital illustration.

Two people sitting together in a relaxed conversational pose — a friendly coach figure and an athlete. Between them, three rounded speech bubbles float gently: one contains a small dumbbell icon, another a tiny calendar, another a running shoe. Both figures are smiling and engaged in conversation. They sit on a simple bench or chairs. Teal cyan background. The mood is warm, supportive, like talking to a knowledgeable friend.

--ar 1:1 --style raw
```

---

## Step 6: Plan Review — "Your plan is ready"

**Background color:** Deep purple to blue (`#5856D6`)

```
Flat vector illustration, modern app onboarding style, detailed human characters with simple friendly faces, slightly rounded proportions, clean outlines, soft shadows, deep purple blue pastel background, no text, no UI elements, centered composition, warm and approachable feel, high quality digital illustration.

An athletic woman running confidently along a winding road that curves into the distance. Along the road, small flag markers or milestone dots are spaced evenly, marking progress. At the far end of the road, a finish line arch is visible. Rolling hills or gentle mountains in the background. Small floating elements: a tiny map pin, a small sun, a calendar page. She looks determined and joyful. Deep purple blue background. The mood is a journey beginning, full of possibility.

--ar 1:1 --style raw
```

---

## Post-Generation Checklist

After generating all 6 images:

- [ ] Check style consistency — do the characters look like they belong in the same world?
- [ ] If not, regenerate outliers using `--sref` (Midjourney) or reference image (DALL-E) from the best result
- [ ] Remove any accidentally generated text (AI image tools sometimes add random text)
- [ ] Ensure backgrounds are clean enough to work on the gradient — may need to erase background in Figma/Photoshop if the tool didn't respect transparency
- [ ] Export at 1125x1125 (@3x) and 750x750 (@2x) as PNG
- [ ] Test each illustration on its gradient background in Figma before adding to Xcode
- [ ] Name files: `onboarding-health.png`, `onboarding-profile.png`, `onboarding-race.png`, `onboarding-goals.png`, `onboarding-chat.png`, `onboarding-plan.png`

## Figma Cleanup Steps

1. Create a 1125x1125 artboard per step
2. Set background to the step's gradient
3. Place the generated illustration centered
4. If the illustration has a baked-in background color that doesn't match, use Figma's "Remove background" plugin or manually mask the character
5. Add any missing floating elements as simple vector shapes (heart, star, checkmark — these are easy to draw)
6. Verify the illustration works at small sizes (preview at 375x375 to simulate iPhone screen)
7. Export @2x and @3x PNG with transparency (no background — the SwiftUI gradient handles that)

## Alternative: DALL-E 3 Adjustments

If using DALL-E 3 instead of Midjourney, remove the `--ar` and `--style` flags and add:

```
Square format, 1024x1024 pixels. Do not include any text, letters, words, or numbers in the image.
```

DALL-E 3 tends to add text more aggressively than Midjourney — explicitly stating "no text" multiple times helps.
