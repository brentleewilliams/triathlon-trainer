# LangSmith Race Date Feedback Loop (Plan C)

## Problem

The race search AI returns incorrect dates for lesser-known regional races (e.g., Steamboat Springs Half Marathon returned 9/12/26 and 5/15/26 instead of 6/7/26). We need a systematic way to:
1. Detect when the model returns a wrong date
2. Log those failures
3. Feed corrections back to improve the prompt over time

## What's Already Done (A + B)

- **A**: `VerifiedRaceDatabase.swift` — local lookup that bypasses AI for 25 known races
- **B**: Both LangSmith prompts (`race-search`, `prep-race-search`) now include all 25 verified races as few-shot examples

## Plan C: Feedback Loop

### Step 1 — Log All Race Searches to LangSmith

When a race search completes (hit or miss), log it as a LangSmith run so we have a record:

**Where:** `LLMProxyService.searchPrepRace()` and `OnboardingViewModel.searchRace()`

**What to log:**
- Input: user query
- Output: name, date, distance returned
- Tag: `"race-search"` or `"prep-race-search"`
- Metadata: `source: "local_db"` vs `source: "llm"`

**How:** Use `LangSmithTracer.shared.startRun / endRun` (already used for coaching calls).

---

### Step 2 — Capture User Corrections

When a user manually edits a race date (in `AddPrepRaceSheet` or onboarding date picker), that's a signal the AI was wrong.

**Where:** The date field edit handlers in `OnboardingView.swift` (AddPrepRaceSheet) and the main race onboarding date picker.

**What to do:**
- Compare the edited date to the AI-returned date
- If they differ by more than 1 day, log a correction event to LangSmith with:
  - Original query
  - AI-returned date (wrong)
  - User-corrected date (right)
  - Tag: `"date-correction"`

---

### Step 3 — Build a LangSmith Evaluation Dataset

In LangSmith, create a dataset called `"race-date-accuracy"`:

```
Input: { "query": "Steamboat Springs Half Marathon" }
Expected output: { "date": "2026-06-07", "name": "Steamboat Springs Half Marathon" }
```

**Seed it with:** The 25 races already in `VerifiedRaceDatabase.swift` + any corrections captured in Step 2.

**Run evaluations** against `race-search` and `prep-race-search` prompts on this dataset after each prompt change to measure accuracy.

---

### Step 4 — Promote Corrections to VerifiedRaceDatabase

When a correction is logged and verified:
1. Add the race to `VerifiedRaceDatabase.swift` (permanent fix, zero latency)
2. Add it to the few-shot examples in both LangSmith prompts
3. Add it to `RaceDateParsingTests.swift` as a verified entry

**Trigger:** Any correction where confidence is high (user manually set date, or correction confirmed from official source).

---

### Step 5 — Periodic Prompt Review

Monthly cadence:
1. Pull all `"date-correction"` runs from LangSmith
2. Identify races the model consistently gets wrong
3. Add them to `VerifiedRaceDatabase` + prompts
4. Re-run the `race-date-accuracy` evaluation dataset to confirm improvement

---

## Implementation Priority

| Step | Effort | Impact |
|------|--------|--------|
| Step 1 (logging) | Small — reuse LangSmithTracer | Gives visibility |
| Step 2 (capture corrections) | Medium — add edit handlers | Direct signal |
| Step 3 (dataset) | Small — manual setup in LangSmith UI | Enables evals |
| Step 4 (promote to DB) | Small per correction | Permanent fix |
| Step 5 (monthly review) | Low ongoing effort | Continuous improvement |

## Key Files

- `IronmanTrainer/LLMProxyService.swift` — add logging to searchRace / searchPrepRace
- `IronmanTrainer/LangSmithTracer.swift` — existing tracer to reuse
- `IronmanTrainer/VerifiedRaceDatabase.swift` — add new confirmed races here
- `IronmanTrainerTests/RaceDateParsingTests.swift` — add new races to test dataset
- LangSmith prompts: `race-search`, `prep-race-search`
- LangSmith dataset: `race-date-accuracy` (to be created)
