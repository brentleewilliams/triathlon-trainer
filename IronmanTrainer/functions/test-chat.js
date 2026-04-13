// Test harness: replays chat messages through the SAME prompt + tool setup
// used by the llmProxy coaching handler, then validates tool_call output.
//
// Usage:  node test-chat.js
//
// Exercises all 4 PlanChangeAction types (add, drop, swap, replace) plus a
// multi-turn conversation, and prints pass/fail for each case.

const fs = require("fs");
const path = require("path");
const OpenAI = require("openai");
const { Client: LangSmithClient } = require("langsmith");

// --- Load functions/.env (no dotenv dependency) ---
const envPath = path.join(__dirname, ".env");
for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
}

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const lsClient = new LangSmithClient({ apiKey: process.env.LANGSMITH_API_KEY });

// --- Tool spec (mirrors index.js PROPOSE_PLAN_CHANGE_TOOL) ---
const PROPOSE_PLAN_CHANGE_TOOL = {
  name: "propose_plan_change",
  description:
    "Propose changes to the user's training plan. Call this whenever the user asks to add, remove, cancel, replace, or reschedule workouts. The user sees a confirmation dialog before any changes are applied. Past workouts CAN be modified — do not refuse past-dated changes.",
  parameters: {
    type: "object",
    properties: {
      summary: { type: "string" },
      changes: {
        type: "array",
        items: {
          type: "object",
          properties: {
            action: { type: "string", enum: ["add", "drop", "swap", "replace"] },
            week: { type: "integer" },
            day: { type: "string" },
            type: { type: "string" },
            duration: { type: "string" },
            zone: { type: "string" },
            notes: { type: "string" },
            from_day: { type: "string" },
            to_day: { type: "string" },
            from_type: { type: "string" },
          },
          required: ["action", "week"],
        },
      },
    },
    required: ["summary", "changes"],
  },
};

// --- Minimal training context (matches iOS client shape) ---
const TRAINING_CONTEXT = `TODAY'S DATE: Sunday, April 12, 2026

CURRENT WEEK PLAN:
Week 4 (Apr 13 - Apr 19, 2026): Build
- Mon: Rest
- Tue: 🏃 Run (45min • Z2)
- Wed: 🚴 Bike (1:00 • Z2)
- Thu: 🏊 Swim (2000yd • Z2) + 🏃 Run (30min • Z2)
- Fri: Rest
- Sat: 🚴 Bike (2:00 • Z2)
- Sun: 🏃 Run (1:15 • Z2)

TRAINING PLAN (current week ± 2):
Week 3 (Build): Tue: Run 40min Z2, Wed: Bike 0:55 Z2, Thu: Swim 1800yd Z2, Sat: Bike 1:45 Z2, Sun: Run 1:10 Z2
Week 4 (Build) ← CURRENT WEEK: Tue: Run 45min Z2, Wed: Bike 1:00 Z2, Thu: Swim 2000yd Z2 + Run 30min Z2, Sat: Bike 2:00 Z2, Sun: Run 1:15 Z2
Week 5 (Build): Tue: Run 50min Z2, Wed: Bike 1:05 Z2, Thu: Swim 2200yd Z2, Sat: Bike 2:15 Z2, Sun: Run 1:20 Z2
`;

// --- Pull coaching-chat prompt from LangSmith (same as runtime) ---
async function fetchCoachingPrompt() {
  const commit = await lsClient.pullPromptCommit("coaching-chat", { includeModel: true });
  const msgs =
    commit.manifest.kwargs?.first?.kwargs?.messages || commit.manifest.kwargs?.messages || [];
  const promptMessages = msgs.map((m) => {
    const id = m.id || [];
    let role = "system";
    if (id.includes("HumanMessage") || id.includes("HumanMessagePromptTemplate")) role = "user";
    else if (id.includes("AIMessage") || id.includes("AIMessagePromptTemplate")) role = "assistant";
    const raw = m.kwargs?.content || m.kwargs?.prompt?.kwargs?.template || "";
    return { role, template: raw };
  });

  // Walk manifest to find model config
  let model = "gpt-4.1-mini";
  function find(obj) {
    if (!obj || typeof obj !== "object") return null;
    if (obj.id && Array.isArray(obj.id) && (obj.id.includes("ChatOpenAI") || obj.id.includes("ChatAnthropic"))) return obj.kwargs;
    for (const v of Object.values(obj)) {
      const f = find(v);
      if (f) return f;
    }
    return null;
  }
  const kw = find(commit.manifest);
  if (kw?.model) model = kw.model;
  if (kw?.model_name) model = kw.model_name;

  return { promptMessages, model };
}

function substitute(template, vars) {
  let out = template;
  for (const [k, v] of Object.entries(vars)) {
    out = out.replace(new RegExp(`\\{${k}\\}`, "g"), String(v));
  }
  return out.replace(/\{\{/g, "{").replace(/\}\}/g, "}");
}

// Mirror of server-side normalization (index.js handleCoaching onDone block).
function normalizeProposal(proposal) {
  if (!proposal || !Array.isArray(proposal.changes)) return proposal;
  for (const c of proposal.changes) {
    if (!c.type && c.to_type) c.type = c.to_type;
    if (!c.type && c.new_type) c.type = c.new_type;
    delete c.to_type; delete c.new_type;
    if (["modify", "update", "change", "edit"].includes(c.action)) c.action = "replace";
  }
  const grouped = {};
  const out = [];
  for (const c of proposal.changes) {
    if (c.action === "replace" && c.field && c.to !== undefined) {
      const key = `${c.week}|${c.day}|${c.from || c.from_type || ""}`;
      if (!grouped[key]) {
        grouped[key] = { action: "replace", week: c.week, day: c.day, from_type: c.from || c.from_type };
        out.push(grouped[key]);
      }
      const t = grouped[key];
      if (c.field === "type") t.type = c.to;
      else if (c.field === "duration") t.duration = c.to;
      else if (c.field === "zone") t.zone = c.to;
      else if (c.field === "notes") t.notes = c.to;
    } else {
      delete c.field; delete c.from; delete c.to;
      out.push(c);
    }
  }
  proposal.changes = out;
  return proposal;
}

async function runTurn({ promptMessages, model, userMessage, history = [], toolChoice = "required" }) {
  const variables = {
    context: TRAINING_CONTEXT,
    history: "",
    z2: 126, z3: 144, z4: 155, z5: 167,
    full_plan: "",
    current_date: "2026-04-12",
    prep_races: "",
    last_swap_info: "",
  };
  const messages = promptMessages.map((m) => ({ role: m.role, content: substitute(m.template, variables) }));
  for (const h of history) messages.push(h);
  messages.push({ role: "user", content: userMessage });

  const completion = await openai.chat.completions.create({
    model,
    temperature: 0.2,
    max_tokens: 2000,
    messages,
    tools: [{ type: "function", function: {
      name: PROPOSE_PLAN_CHANGE_TOOL.name,
      description: PROPOSE_PLAN_CHANGE_TOOL.description,
      parameters: PROPOSE_PLAN_CHANGE_TOOL.parameters,
    }}],
    tool_choice: toolChoice === "required" ? "required" : "auto",
  });

  const msg = completion.choices[0].message;
  const toolCall = msg.tool_calls?.[0];
  let input = null;
  if (toolCall) {
    try { input = normalizeProposal(JSON.parse(toolCall.function.arguments)); }
    catch (e) { input = { _parseError: e.message, raw: toolCall.function.arguments }; }
  }
  return { text: msg.content || "", toolCall: input, rawMessage: msg };
}

// --- Test cases ---
const TESTS = [
  {
    name: "ADD — add a strength workout Monday",
    message: "Add a 30 min strength workout on Monday this week",
    expect: (t) => t.changes?.some((c) => c.action === "add" && /mon/i.test(c.day || "") && /strength/i.test(c.type || "")),
  },
  {
    name: "DROP — cancel Tuesday's run",
    message: "Cancel Tuesday's run this week",
    expect: (t) => t.changes?.some((c) => c.action === "drop" && /tue/i.test(c.day || "")),
  },
  {
    name: "SWAP — swap Saturday bike with Sunday run",
    message: "Swap Saturday's bike with Sunday's run this week",
    expect: (t) => t.changes?.some((c) => c.action === "swap" && /sat/i.test(c.from_day || c.fromDay || "") && /sun/i.test(c.to_day || c.toDay || "")),
  },
  {
    name: "REPLACE — change Sunday's long run to a hike",
    message: "Change this Sunday's run to a hike instead",
    expect: (t) => t.changes?.some((c) => c.action === "replace" && /sun/i.test(c.day || "") && /hik/i.test(c.type || c.to_type || "")),
  },
  {
    name: "REPLACE-SHORTEN — change Saturday's long bike to a 30min zone 2 run",
    message: "Change Saturday to a 30 min zone 2 run",
    expect: (t) => {
      const allValid = t.changes?.every((c) => ["add","drop","swap","replace"].includes(c.action));
      const replaceChange = t.changes?.find((c) => c.action === "replace" && /sat/i.test(c.day || ""));
      return allValid && replaceChange && /run/i.test(replaceChange.type || "") && /30/.test(replaceChange.duration || "");
    },
  },
];

async function main() {
  console.log("Fetching coaching-chat prompt from LangSmith...");
  const { promptMessages, model } = await fetchCoachingPrompt();
  console.log(`Using model: ${model}\n`);

  let passed = 0, failed = 0;

  for (const t of TESTS) {
    process.stdout.write(`▶ ${t.name}\n   "${t.message}"\n`);
    try {
      const { toolCall } = await runTurn({ promptMessages, model, userMessage: t.message });
      if (!toolCall) { console.log("   ✗ No tool call emitted\n"); failed++; continue; }
      if (toolCall._parseError) { console.log(`   ✗ Arg parse error: ${toolCall._parseError}\n`); failed++; continue; }
      const ok = t.expect(toolCall);
      console.log(`   ${ok ? "✓" : "✗"} tool input: ${JSON.stringify(toolCall).slice(0, 250)}\n`);
      if (ok) passed++; else failed++;
    } catch (err) {
      console.log(`   ✗ Exception: ${err.message}\n`);
      failed++;
    }
  }

  // Multi-turn: after first apply, second message should still tool-call cleanly
  console.log("▶ MULTI-TURN — two plan changes back-to-back");
  try {
    const first = await runTurn({ promptMessages, model, userMessage: "Cancel Tuesday's run this week" });
    console.log(`   turn 1 tool: ${first.toolCall ? "✓" : "✗"} ${JSON.stringify(first.toolCall).slice(0, 150)}`);
    const history = [
      { role: "user", content: "Cancel Tuesday's run this week" },
      { role: "assistant", content: "✅ Applied 1 change to your training plan. Dropped Tuesday's run." },
    ];
    const second = await runTurn({ promptMessages, model, userMessage: "Also swap Saturday and Sunday", history });
    console.log(`   turn 2 tool: ${second.toolCall ? "✓" : "✗"} ${JSON.stringify(second.toolCall).slice(0, 250)}`);
    if (first.toolCall && second.toolCall) passed++; else failed++;
  } catch (err) {
    console.log(`   ✗ Exception: ${err.message}`);
    failed++;
  }

  // Chat-only: "Hello" should NOT force a tool call with toolChoice=auto
  console.log("\n▶ CHAT-ONLY — 'Hello' with toolChoice=auto must produce text, not tool call");
  try {
    const { text, toolCall } = await runTurn({ promptMessages, model, userMessage: "Hello", toolChoice: "auto" });
    const ok = !toolCall && text.length > 0;
    console.log(`   ${ok ? "✓" : "✗"} text="${text.slice(0, 120)}" toolCall=${toolCall ? JSON.stringify(toolCall).slice(0, 120) : "null"}`);
    if (ok) passed++; else failed++;
  } catch (err) {
    console.log(`   ✗ Exception: ${err.message}`);
    failed++;
  }

  console.log(`\n=== ${passed} passed, ${failed} failed ===`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
