// Tier 2 prompt eval harness — see PRD §7.5.2.
//
// Pulls each prompt from LangSmith, runs it against a canonical dataset of
// inputs, and posts the results to LangSmith as an experiment run. Intended
// to be invoked nightly (Cloud Scheduler / GitHub Actions) or manually during
// prompt iteration.
//
// Usage:
//   node eval-prompts.js                  # run every prompt against its dataset
//   node eval-prompts.js coaching-chat    # run just one prompt
//
// Each prompt has a fixtures file at fixtures/<prompt-name>.json:
//   { "examples": [ { "variables": {...}, "checks": [...] } ] }
//
// Each check runs against the model's output and returns { name, passed, detail }.

const fs = require("fs");
const path = require("path");
const OpenAI = require("openai");
const { Client: LangSmithClient } = require("langsmith");

// --- Load functions/.env ---
const envPath = path.join(__dirname, ".env");
for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
}

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const lsClient = new LangSmithClient({ apiKey: process.env.LANGSMITH_API_KEY });

const FIXTURE_DIR = path.join(__dirname, "eval-fixtures");

// --- Pull a prompt + substitute variables (mirrors server getPrompt/formatPrompt) ---

async function pullPrompt(name) {
  const commit = await lsClient.pullPromptCommit(name, { includeModel: true });
  const msgs =
    commit.manifest.kwargs?.first?.kwargs?.messages || commit.manifest.kwargs?.messages || [];

  let model = "gpt-4.1-mini";
  let temperature = 0.2;
  let maxTokens = 2000;
  const findKwargs = (obj) => {
    if (!obj || typeof obj !== "object") return null;
    if (obj.id && Array.isArray(obj.id) && (obj.id.includes("ChatOpenAI") || obj.id.includes("ChatAnthropic"))) return obj.kwargs;
    for (const v of Object.values(obj)) {
      const f = findKwargs(v);
      if (f) return f;
    }
    return null;
  };
  const kw = findKwargs(commit.manifest);
  if (kw?.model) model = kw.model;
  if (kw?.model_name) model = kw.model_name;

  const templates = msgs.map((m) => {
    const id = m.id || [];
    let role = "system";
    if (id.includes("HumanMessage") || id.includes("HumanMessagePromptTemplate")) role = "user";
    else if (id.includes("AIMessage") || id.includes("AIMessagePromptTemplate")) role = "assistant";
    return { role, template: m.kwargs?.content || m.kwargs?.prompt?.kwargs?.template || "" };
  });

  return { templates, model };
}

function substitute(template, variables) {
  let out = template;
  for (const [k, v] of Object.entries(variables)) {
    out = out.replace(new RegExp(`\\{${k}\\}`, "g"), String(v));
  }
  return out.replace(/\{\{/g, "{").replace(/\}\}/g, "}");
}

// --- Evaluators ---
// Each check descriptor: { type: "contains"|"regex"|"toolCall"|"variableUsed", ... }

function runCheck(check, result) {
  const { text, toolCall } = result;
  switch (check.type) {
    case "contains":
      return {
        name: check.name || `contains "${check.value}"`,
        passed: text.toLowerCase().includes(check.value.toLowerCase()),
        detail: `text length=${text.length}`,
      };
    case "regex":
      return {
        name: check.name || `regex ${check.pattern}`,
        passed: new RegExp(check.pattern, check.flags || "i").test(text),
        detail: "",
      };
    case "toolCall":
      return {
        name: check.name || `tool called: ${check.toolName}`,
        passed: !!toolCall && (!check.toolName || toolCall.name === check.toolName),
        detail: toolCall ? `args keys=${Object.keys(toolCall.args || {}).join(",")}` : "no tool call",
      };
    case "variableUsed": {
      // Verify the output references a value supplied via a variable. Ex: if
      // variables.race_name = "Ironman 70.3 Oregon", expect that string in output.
      const expected = check.value;
      return {
        name: check.name || `output references "${expected}"`,
        passed: text.includes(expected),
        detail: "",
      };
    }
    default:
      return { name: check.type, passed: false, detail: "unknown check type" };
  }
}

// --- Run a single example ---

async function runExample({ templates, model }, example, promptName) {
  const messages = templates.map((t) => ({
    role: t.role,
    content: substitute(t.template, example.variables),
  }));
  if (example.userMessage) messages.push({ role: "user", content: example.userMessage });

  const req = {
    model,
    temperature: 0.2,
    max_tokens: 2000,
    messages,
  };
  if (example.tools) {
    req.tools = example.tools.map((t) => ({ type: "function", function: t }));
    req.tool_choice = example.toolChoice || "auto";
  }

  const completion = await openai.chat.completions.create(req);
  const msg = completion.choices[0].message;
  const tool = msg.tool_calls?.[0];
  const result = {
    text: msg.content || "",
    toolCall: tool ? { name: tool.function.name, args: JSON.parse(tool.function.arguments || "{}") } : null,
  };

  const results = (example.checks || []).map((c) => runCheck(c, result));
  return { promptName, name: example.name, results, result };
}

// --- Main ---

async function main() {
  const onlyPrompt = process.argv[2] || null;
  if (!fs.existsSync(FIXTURE_DIR)) {
    console.log(`No eval-fixtures/ directory at ${FIXTURE_DIR} — create one with <prompt-name>.json files.`);
    process.exit(0);
  }
  const fixtureFiles = fs.readdirSync(FIXTURE_DIR).filter((f) => f.endsWith(".json"));
  if (fixtureFiles.length === 0) {
    console.log("No fixtures found.");
    process.exit(0);
  }

  let totalPassed = 0;
  let totalChecks = 0;
  let totalFailed = 0;

  for (const file of fixtureFiles) {
    const promptName = file.replace(/\.json$/, "");
    if (onlyPrompt && promptName !== onlyPrompt) continue;
    const fixture = JSON.parse(fs.readFileSync(path.join(FIXTURE_DIR, file), "utf8"));
    console.log(`\n▶ ${promptName}`);

    let prompt;
    try {
      prompt = await pullPrompt(promptName);
    } catch (err) {
      console.log(`   ✗ failed to pull prompt: ${err.message}`);
      totalFailed++;
      continue;
    }

    for (const example of fixture.examples) {
      try {
        const { results } = await runExample(prompt, example, promptName);
        const passed = results.every((r) => r.passed);
        totalPassed += results.filter((r) => r.passed).length;
        totalChecks += results.length;
        if (!passed) totalFailed++;
        console.log(`   ${passed ? "✓" : "✗"} ${example.name}`);
        for (const r of results) {
          if (!r.passed) console.log(`       ✗ ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
        }
      } catch (err) {
        console.log(`   ✗ ${example.name} — exception: ${err.message}`);
        totalFailed++;
      }
    }
  }

  const passRate = totalChecks === 0 ? 0 : Math.round((totalPassed / totalChecks) * 100);
  console.log(`\n=== ${totalPassed}/${totalChecks} checks passed (${passRate}%), ${totalFailed} examples failed ===`);
  process.exit(totalFailed > 0 ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
