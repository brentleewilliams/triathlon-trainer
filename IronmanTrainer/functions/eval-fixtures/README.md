# Prompt eval fixtures (PRD §7.5.2 — Tier 2)

Each file is `<prompt-name>.json` and follows the shape:

```json
{
  "examples": [
    {
      "name": "happy path — drop workout",
      "variables": { "context": "...", "history": "...", "current_date": "2026-04-12", "z2": 126, "z3": 144, "z4": 155, "z5": 167 },
      "userMessage": "Cancel Tuesday's run this week",
      "tools": [ { "name": "propose_plan_change", "description": "...", "parameters": {...} } ],
      "toolChoice": "required",
      "checks": [
        { "type": "toolCall", "toolName": "propose_plan_change" }
      ]
    }
  ]
}
```

Check types: `contains`, `regex`, `toolCall`, `variableUsed`.

Run: `node functions/eval-prompts.js [prompt-name]`
