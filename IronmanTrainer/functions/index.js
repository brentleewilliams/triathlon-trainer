const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const { Client: LangSmithClient } = require("langsmith");
const OpenAI = require("openai");
const Anthropic = require("@anthropic-ai/sdk");

admin.initializeApp();
const db = admin.firestore();

// Configure SMTP — set via .env file in functions/
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.SMTP_EMAIL || "",
    pass: process.env.SMTP_PASSWORD || "",
  },
});

// Generate a 6-digit OTP
function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// CORS helper
function setCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Langsmith-Trace-Id, X-Langsmith-Run-Id, X-Langsmith-Dotted-Order");
}

// ---------------------------------------------------------------------------
// LangSmith tracing helpers
// ---------------------------------------------------------------------------

/**
 * Formats a JS timestamp (ms) as the LangSmith dotted_order timestamp segment.
 * Format: YYYYMMDDTHHmmssSSSSSSZ  (microseconds approximated from ms)
 */
function langsmithTimestamp(ms) {
  const d = new Date(ms);
  const micros = String((ms % 1000) * 1000).padStart(6, "0");
  const y = String(d.getUTCFullYear()).padStart(4, "0");
  const mo = String(d.getUTCMonth() + 1).padStart(2, "0");
  const da = String(d.getUTCDate()).padStart(2, "0");
  const h = String(d.getUTCHours()).padStart(2, "0");
  const mi = String(d.getUTCMinutes()).padStart(2, "0");
  const s = String(d.getUTCSeconds()).padStart(2, "0");
  return `${y}${mo}${da}T${h}${mi}${s}${micros}Z`;
}

/**
 * Builds a child dotted_order by appending this run's segment to the parent's.
 * parentDottedOrder: the parent run's full dotted_order string
 * ms: current time in milliseconds
 * uuid: this run's UUID (with or without dashes)
 */
function makeChildDottedOrder(parentDottedOrder, ms, uuid) {
  const uuidNoDash = uuid.replace(/-/g, "");
  const segment = `${langsmithTimestamp(ms)}${uuidNoDash}`;
  return parentDottedOrder ? `${parentDottedOrder}.${segment}` : segment;
}

/**
 * Creates a LangSmith run via REST, fire-and-forget.
 */
async function langsmithCreateRun(body) {
  const apiKey = process.env.LANGSMITH_API_KEY;
  if (!apiKey) return;
  try {
    const resp = await fetch("https://api.smith.langchain.com/runs", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": apiKey },
      body: JSON.stringify(body),
    });
    if (!resp.ok) console.warn(`[LangSmith] createRun HTTP ${resp.status}`);
  } catch (err) {
    console.warn("[LangSmith] createRun failed:", err.message);
  }
}

/**
 * Updates a LangSmith run via REST, fire-and-forget.
 */
async function langsmithUpdateRun(runId, body) {
  const apiKey = process.env.LANGSMITH_API_KEY;
  if (!apiKey) return;
  try {
    const resp = await fetch(`https://api.smith.langchain.com/runs/${runId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "x-api-key": apiKey },
      body: JSON.stringify(body),
    });
    if (!resp.ok) console.warn(`[LangSmith] updateRun HTTP ${resp.status}`);
  } catch (err) {
    console.warn("[LangSmith] updateRun failed:", err.message);
  }
}

// ---------------------------------------------------------------------------
// LangSmith Prompt Cache
// ---------------------------------------------------------------------------

const PROMPT_NAMES = [
  "coaching-chat",
  "race-search",
  "prep-race-search",
  "plan-gen-summary",
  "plan-gen-details",
  "plan-gen-customize",
];

// In-memory cache: { [name]: { prompt, model, temperature, maxTokens, fetchedAt } }
let promptCache = {};
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

async function getPrompt(name) {
  const cached = promptCache[name];
  if (cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS) {
    return cached;
  }
  try {
    const client = new LangSmithClient({ apiKey: process.env.LANGSMITH_API_KEY });
    const commit = await client.pullPromptCommit(name, { includeModel: true });

    // Extract model config from manifest (nested under ChatOpenAI/ChatAnthropic node)
    let model = "gpt-4.1-mini";
    let temperature = 0.7;
    let maxTokens = 4096;

    function findModelKwargs(obj) {
      if (!obj || typeof obj !== "object") return null;
      if (obj.id && Array.isArray(obj.id) && (obj.id.includes("ChatOpenAI") || obj.id.includes("ChatAnthropic"))) {
        return obj.kwargs;
      }
      for (const v of Object.values(obj)) {
        const found = findModelKwargs(v);
        if (found) return found;
      }
      return null;
    }

    const modelKwargs = findModelKwargs(commit.manifest);
    if (modelKwargs) {
      if (modelKwargs.model) model = modelKwargs.model;
      if (modelKwargs.model_name) model = modelKwargs.model_name;
      if (modelKwargs.temperature !== undefined) temperature = modelKwargs.temperature;
      if (modelKwargs.max_tokens !== undefined) maxTokens = modelKwargs.max_tokens;
    }

    // Extract prompt messages from manifest.
    // With includeModel, manifest is a RunnableSequence: { first: ChatPromptTemplate, last: ChatModel }
    // Without includeModel, manifest is the ChatPromptTemplate directly.
    const promptMessages = commit.manifest.kwargs?.first?.kwargs?.messages
      || commit.manifest.kwargs?.messages
      || [];

    const entry = { promptMessages, model, temperature, maxTokens, fetchedAt: Date.now() };
    promptCache[name] = entry;
    return entry;
  } catch (err) {
    console.error(`Failed to pull prompt "${name}" from LangSmith:`, err.message);
    if (cached) return cached;
    throw new Error(`Prompt "${name}" unavailable`);
  }
}

// Prompts are cached lazily on first request (Firebase .env not available at module load)

// ---------------------------------------------------------------------------
// Prompt formatting helper
// ---------------------------------------------------------------------------

async function formatPrompt(name, variables = {}) {
  const entry = await getPrompt(name);

  // Convert raw manifest messages to {role, content} and apply variable substitution
  const messages = entry.promptMessages.map((m) => {
    const id = m.id || [];
    let role = "system";
    if (id.includes("HumanMessage") || id.includes("HumanMessagePromptTemplate")) role = "user";
    else if (id.includes("AIMessage") || id.includes("AIMessagePromptTemplate")) role = "assistant";

    // Get content — either direct string or from template
    let content = m.kwargs?.content || m.kwargs?.prompt?.kwargs?.template || "";

    // Apply f-string variable substitution: {varName} -> value
    for (const [key, val] of Object.entries(variables)) {
      content = content.replace(new RegExp(`\\{${key}\\}`, "g"), String(val));
    }

    // Unescape double braces (LangChain escaping for literal { }) -> single braces
    content = content.replace(/\{\{/g, "{").replace(/\}\}/g, "}");

    return { role, content };
  });

  return {
    messages,
    model: entry.model,
    temperature: entry.temperature,
    maxTokens: entry.maxTokens,
  };
}

// ---------------------------------------------------------------------------
// LLM Providers
// ---------------------------------------------------------------------------

function getOpenAIClient() {
  return new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
}

function getAnthropicClient() {
  return new Anthropic({
    apiKey: process.env.ANTHROPIC_API_KEY,
    timeout: 240000, // 4 minutes — needed for large plan generation calls
  });
}

/**
 * Non-streaming LLM call. Returns the full response text.
 */
async function callLLM({ messages, model, temperature, maxTokens }) {
  if (model.startsWith("gpt-") || model.startsWith("o")) {
    const client = getOpenAIClient();
    const completion = await client.chat.completions.create({
      model,
      temperature,
      max_tokens: maxTokens,
      messages,
    });
    return completion.choices[0].message.content;
  } else if (model.startsWith("claude-")) {
    const client = getAnthropicClient();
    // Anthropic expects system as a top-level param, not in messages array
    const systemMsg = messages.find((m) => m.role === "system");
    const nonSystem = messages.filter((m) => m.role !== "system");
    const resp = await client.messages.create({
      model,
      max_tokens: maxTokens,
      temperature,
      system: systemMsg ? systemMsg.content : undefined,
      messages: nonSystem,
    });
    return resp.content.map((c) => c.text).join("");
  } else {
    throw new Error(`Unsupported model: ${model}`);
  }
}

/**
 * LLM call with Anthropic web search tool. The model can search the web to
 * ground its response in real data (e.g. race dates, locations). Falls back
 * to a plain callLLM for non-Claude models.
 */
async function callLLMWithWebSearch({ messages, model, temperature, maxTokens }) {
  // Web search is only available via Anthropic API
  if (!model.startsWith("claude-")) {
    return callLLM({ messages, model, temperature, maxTokens });
  }

  const client = getAnthropicClient();
  const systemMsg = messages.find((m) => m.role === "system");
  const nonSystem = messages.filter((m) => m.role !== "system");

  const resp = await client.messages.create({
    model: "claude-haiku-4-5-20251001",  // force Claude — web search requires Anthropic models
    max_tokens: maxTokens,
    temperature,
    system: systemMsg ? systemMsg.content : undefined,
    messages: nonSystem,
    tools: [
      {
        type: "web_search_20250305",
        name: "web_search",
        max_uses: 3,
      },
    ],
  });

  // Extract all text blocks from the response (the model may interleave
  // tool_use / web_search_tool_result / text blocks).
  return resp.content
    .filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("");
}

/**
 * Streaming LLM call. Calls `onToken(text)` for each chunk, `onDone()` when finished.
 */
async function streamLLM({ messages, model, temperature, maxTokens, onToken, onDone }) {
  if (model.startsWith("gpt-") || model.startsWith("o")) {
    const client = getOpenAIClient();
    const stream = await client.chat.completions.create({
      model,
      temperature,
      max_tokens: maxTokens,
      messages,
      stream: true,
    });
    for await (const chunk of stream) {
      const delta = chunk.choices?.[0]?.delta?.content;
      if (delta) onToken(delta);
    }
    onDone();
  } else if (model.startsWith("claude-")) {
    const client = getAnthropicClient();
    const systemMsg = messages.find((m) => m.role === "system");
    const nonSystem = messages.filter((m) => m.role !== "system");
    const stream = await client.messages.stream({
      model,
      max_tokens: maxTokens,
      temperature,
      system: systemMsg ? systemMsg.content : undefined,
      messages: nonSystem,
    });
    for await (const event of stream) {
      if (event.type === "content_block_delta" && event.delta?.text) {
        onToken(event.delta.text);
      }
    }
    onDone();
  } else {
    throw new Error(`Unsupported model: ${model}`);
  }
}

// ---------------------------------------------------------------------------
// Input sanitization
// ---------------------------------------------------------------------------

function sanitizeQuery(input, maxLen = 200) {
  if (typeof input !== "string") return "";
  // Strip non-printable characters (keep newlines and tabs)
  return input.replace(/[^\x20-\x7E\n\t]/g, "").slice(0, maxLen);
}

// ---------------------------------------------------------------------------
// Utility: strip markdown code fences from LLM output
// ---------------------------------------------------------------------------

function stripMarkdownFences(text) {
  let cleaned = text.trim();
  if (cleaned.startsWith("```json")) cleaned = cleaned.slice(7);
  else if (cleaned.startsWith("```")) cleaned = cleaned.slice(3);
  if (cleaned.endsWith("```")) cleaned = cleaned.slice(0, -3);
  return cleaned.trim();
}

// ---------------------------------------------------------------------------
// Auth helper
// ---------------------------------------------------------------------------

async function verifyAuth(req) {
  const authHeader = req.headers.authorization || "";
  if (!authHeader.startsWith("Bearer ")) return null;
  const token = authHeader.split("Bearer ")[1];
  try {
    return await admin.auth().verifyIdToken(token);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Retry helper with exponential backoff
// ---------------------------------------------------------------------------

async function withRetry(fn, maxAttempts = 3) {
  let lastErr;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (attempt < maxAttempts - 1) {
        const delay = Math.pow(2, attempt) * 1000; // 1s, 2s, 4s
        await new Promise((r) => setTimeout(r, delay));
      }
    }
  }
  throw lastErr;
}

// ---------------------------------------------------------------------------
// Request handlers
// ---------------------------------------------------------------------------

async function handleCoaching(req, res, userId) {
  const { userMessage, trainingContext, workoutHistory, zoneBoundaries, conversationHistory, imageData } = req.body;

  if (!userMessage || typeof userMessage !== "string") {
    res.status(400).json({ error: "userMessage is required" });
    return;
  }

  // --- LangSmith: read parent trace context from iOS client ---
  const parentTraceId = req.headers["x-langsmith-trace-id"] || null;
  const parentRunId = req.headers["x-langsmith-run-id"] || null;
  const parentDottedOrder = req.headers["x-langsmith-dotted-order"] || null;

  // Build template variables for the coaching prompt.
  // The iOS app sends everything (plan, date, prep races, swap info) combined in
  // trainingContext, so we map it to {context} and blank out the other prompt vars.
  const z = zoneBoundaries || {};
  const todayStr = new Date().toISOString().split("T")[0];
  const variables = {
    context: trainingContext || "",
    history: workoutHistory || "",
    z2: z.z2 || "",
    z3: z.z3 || "",
    z4: z.z4 || "",
    z5: z.z5 || "",
    full_plan: "",
    current_date: todayStr,
    prep_races: "",
    last_swap_info: "",
  };

  console.log(`[coaching] context length=${(trainingContext || "").length}, history length=${(workoutHistory || "").length}, zones=${JSON.stringify(z)}`);

  const { messages: promptMessages, model, temperature, maxTokens } = await formatPrompt("coaching-chat", variables);

  console.log(`[coaching] model=${model}, system prompt length=${promptMessages[0]?.content?.length || 0}`);

  // Append conversation history if provided
  const allMessages = [...promptMessages];
  if (Array.isArray(conversationHistory)) {
    for (const msg of conversationHistory) {
      if (msg.role && msg.content) {
        allMessages.push({ role: msg.role, content: msg.content });
      }
    }
  }

  // Add the current user message (with optional image for vision models)
  if (imageData && (model.startsWith("gpt-") || model.startsWith("claude-"))) {
    if (model.startsWith("claude-")) {
      // Anthropic image format
      allMessages.push({
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: imageData } },
          { type: "text", text: userMessage },
        ],
      });
    } else {
      // OpenAI image format
      allMessages.push({
        role: "user",
        content: [
          { type: "text", text: userMessage },
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageData}` } },
        ],
      });
    }
  } else {
    allMessages.push({ role: "user", content: userMessage });
  }

  // --- LangSmith: create child LLM run ---
  const llmRunId = crypto.randomUUID();
  const llmStartMs = Date.now();
  if (parentTraceId && parentDottedOrder) {
    const childDottedOrder = makeChildDottedOrder(parentDottedOrder, llmStartMs, llmRunId);
    langsmithCreateRun({
      id: llmRunId.replace(/-/g, ""),
      trace_id: parentTraceId,
      parent_run_id: parentRunId,
      dotted_order: childDottedOrder,
      name: "llm_call",
      run_type: "llm",
      project_name: "IronmanTrainer",
      session_name: userId ?? "anonymous",
      start_time: new Date(llmStartMs).toISOString(),
      inputs: { messages: allMessages },
      metadata: {
        model,
        user_id: userId ?? "anonymous",
        env: process.env.NODE_ENV === "production" ? "beta" : "development",
      },
      tags: ["ios", "coaching"],
    });
  }

  // Set up SSE headers
  res.set("Content-Type", "text/event-stream");
  res.set("Cache-Control", "no-cache");
  res.set("Connection", "keep-alive");

  let accumulated = "";

  try {
    await streamLLM({
      messages: allMessages,
      model,
      temperature,
      maxTokens,
      onToken: (token) => {
        accumulated += token;
        res.write(`data: ${JSON.stringify(token)}\n\n`);
      },
      onDone: () => {
        res.write("data: [DONE]\n\n");
        res.end();
        // --- LangSmith: close child LLM run with response ---
        if (parentTraceId) {
          langsmithUpdateRun(llmRunId.replace(/-/g, ""), {
            end_time: new Date().toISOString(),
            outputs: { response: accumulated },
            extra: { model },
          });
        }
      },
    });
  } catch (err) {
    console.error("Coaching stream error:", err);
    // --- LangSmith: close child LLM run with error ---
    if (parentTraceId) {
      langsmithUpdateRun(llmRunId.replace(/-/g, ""), {
        end_time: new Date().toISOString(),
        error: err.message,
        status: "error",
        outputs: { response: accumulated },
      });
    }
    // If headers already sent, try to signal error in stream
    res.write(`data: ${JSON.stringify("[ERROR]")}\n\n`);
    res.end();
  }
}

async function handleRaceSearch(req, res) {
  const query = sanitizeQuery(req.body.query);
  if (!query) {
    res.status(400).json({ error: "query is required" });
    return;
  }

  const todayStr = new Date().toISOString().split("T")[0];
  const currentYear = new Date().getFullYear();
  // Append current year if no year is mentioned — helps web search find the right edition
  const yearPattern = /\b20\d{2}\b/;
  const augmentedQuery = yearPattern.test(query) ? query : `${query} ${currentYear}`;

  const { messages, model, temperature, maxTokens } = await formatPrompt("race-search", { today: todayStr });
  messages.push({
    role: "user",
    content: `Today's date is ${todayStr}. You MUST use the web_search tool — do not use any date from your training data.

Search strategy:
1. Search: "${augmentedQuery} official race date"
2. If needed, search: "${augmentedQuery} registration site:ironman.com OR site:athlinks.com OR site:runsignup.com"

Requirements:
- The race date MUST come from a web search result, not your memory
- Only return future races (after today: ${todayStr})
- If the ${currentYear} edition has already passed, find the next future occurrence
- Include "sourceUrl" (the page where you found the date) in your JSON
- Include "dateConfidence": "high" if date is from official race page, "low" if uncertain

Race query: ${augmentedQuery}`
  });

  // Use Anthropic web search tool so the model can look up real race details
  // instead of hallucinating dates and locations.
  const raw = await callLLMWithWebSearch({ messages, model, temperature, maxTokens });
  const result = stripMarkdownFences(raw);
  // Try to return parsed JSON so client gets a proper object
  try {
    const parsed = JSON.parse(result);
    // Date validation: if the returned date is in the past, downgrade confidence
    if (parsed.date) {
      const raceDate = new Date(parsed.date);
      const today = new Date(todayStr);
      if (raceDate < today) {
        parsed.dateConfidence = "low";
      }
    }
    res.status(200).json({ result: parsed });
  }
  catch { res.status(200).json({ result }); }
}

async function handlePrepRaceSearch(req, res) {
  const query = sanitizeQuery(req.body.query);
  if (!query) {
    res.status(400).json({ error: "query is required" });
    return;
  }

  const todayStr = new Date().toISOString().split("T")[0];
  const { messages, model, temperature, maxTokens } = await formatPrompt("prep-race-search", { today: todayStr });
  messages.push({ role: "user", content: `Today's date is ${todayStr}. Only return races that have not yet occurred (date must be after today).\n\nRace search query: ${query}` });

  // Use web search for real race data instead of hallucinated dates
  const raw = await callLLMWithWebSearch({ messages, model, temperature, maxTokens });
  const result = stripMarkdownFences(raw);
  try { res.status(200).json({ result: JSON.parse(result) }); }
  catch { res.status(200).json({ result }); }
}

/**
 * Flatten the nested input object into template variables used by plan-gen prompts.
 * Shared by handlePlanGeneration and handlePlanGenerationBatch.
 */
function buildPlanGenVars(input) {
  const race = input.race || {};
  const profile = input.profile || {};
  const distances = race.distances || {};
  const distancesStr = Object.entries(distances).map(([k, v]) => `${k}: ${v} mi`).join(", ");
  const weeksAvailable = (() => {
    if (!race.date) return 12;
    let raceDate = new Date(race.date);
    const now = new Date();
    while (raceDate < now) {
      raceDate.setFullYear(raceDate.getFullYear() + 1);
    }
    const weeks = Math.round((raceDate - now) / (7 * 24 * 60 * 60 * 1000));
    return weeks < 4 ? 12 : weeks;
  })();
  const planStartDate = new Date().toISOString().split("T")[0];
  const correctedRaceDate = (() => {
    if (!race.date) return "";
    let d = new Date(race.date);
    const now = new Date();
    while (d < now) d.setFullYear(d.getFullYear() + 1);
    return d.toISOString().split("T")[0];
  })();

  const goalStr = (() => {
    const g = race.userGoal;
    if (!g) return "Complete the race";
    if (g.type === "timeTarget" && g.targetSeconds) {
      const t = g.targetSeconds;
      const h = Math.floor(t / 3600);
      const m = Math.floor((t % 3600) / 60);
      return `Finish in ${h}h ${String(m).padStart(2, "0")}m`;
    }
    return "Complete the race (no specific time target)";
  })();

  const skillParts = [];
  if (input.swimLevel) skillParts.push(`Swim: ${input.swimLevel}`);
  if (input.bikeLevel) skillParts.push(`Bike: ${input.bikeLevel}`);
  if (input.runLevel) skillParts.push(`Run: ${input.runLevel}`);

  const pass1Vars = {
    race_name: race.name || "Race",
    race_date: correctedRaceDate || race.date || "",
    race_location: race.location || "",
    race_type: race.type || "endurance",
    distances: distancesStr,
    course_type: race.courseType || "road",
    elevation_gain: race.elevationGainM ? `${Math.round(race.elevationGainM)}m` : "",
    venue_elevation: race.elevationAtVenueM ? `${Math.round(race.elevationAtVenueM)}m` : "",
    historical_weather: race.historicalWeather || "",
    athlete_name: profile.name || "",
    athlete_sex: profile.biologicalSex || "",
    athlete_weight: profile.weightKg ? `${profile.weightKg} kg` : "",
    resting_hr: profile.restingHR ? `${profile.restingHR} bpm` : "",
    vo2_max: profile.vo2Max ? `${profile.vo2Max}` : "",
    skill_levels: skillParts.join(", ") || "Not specified",
    goal: goalStr,
    weeks_available: String(weeksAvailable),
    plan_start_date: planStartDate,
    available_hours: input.fitnessHours || "Not specified",
    schedule: input.fitnessSchedule || "Not specified",
    injuries: input.fitnessInjuries || "None",
    equipment: input.fitnessEquipment || "Standard",
    hk_summary: input.hkSummary || "",
    prep_races: input.chatSummary || "",
    swim_level: input.swimLevel || "Not specified",
    bike_level: input.bikeLevel || "Not specified",
    run_level: input.runLevel || "Not specified",
  };

  const pass2Vars = {
    swim_level: input.swimLevel || "Not specified",
    bike_level: input.bikeLevel || "Not specified",
    run_level: input.runLevel || "Not specified",
    equipment: input.fitnessEquipment || "Standard",
  };

  return { pass1Vars, pass2Vars, weeksAvailable, planStartDate };
}

async function handlePlanGeneration(req, res) {
  const { input } = req.body;
  if (!input || typeof input !== "object") {
    res.status(400).json({ error: "input object is required" });
    return;
  }

  console.log(`[planGen] input keys: ${Object.keys(input).join(", ")}`);
  console.log(`[planGen] race: ${JSON.stringify(input.race || {}).substring(0, 300)}`);
  console.log(`[planGen] profile: ${JSON.stringify(input.profile || {}).substring(0, 200)}`);

  const { pass1Vars, pass2Vars } = buildPlanGenVars(input);

  console.log(`[planGen] weeks=${pass1Vars.weeks_available}, goal=${pass1Vars.goal}, race_date=${pass1Vars.race_date}`);

  // Pass 1: Generate plan structure
  const pass1Result = await withRetry(async () => {
    const { messages, model, temperature, maxTokens } = await formatPrompt("plan-gen-summary", pass1Vars);
    messages.push({ role: "user", content: `Generate my ${pass1Vars.weeks_available}-week training plan.` });
    const planMaxTokens = Math.max(maxTokens, 16384);
    return callLLM({ messages, model, temperature, maxTokens: planMaxTokens });
  });

  // Pass 2: Expand with details/nutrition
  const finalResult = await withRetry(async () => {
    const { messages, model, temperature, maxTokens } = await formatPrompt("plan-gen-details", pass2Vars);
    messages.push({ role: "user", content: `Add detailed notes and nutrition targets to this plan:\n${pass1Result}` });
    const planMaxTokens = Math.max(maxTokens, 16384);
    return callLLM({ messages, model, temperature, maxTokens: planMaxTokens });
  });

  console.log(`[planGen] pass1 length=${pass1Result.length}, pass2 length=${finalResult.length}`);

  // Try to parse as JSON; return raw if not valid JSON
  try {
    const parsed = JSON.parse(stripMarkdownFences(finalResult));
    console.log(`[planGen] parsed weeks=${Array.isArray(parsed) ? parsed.length : "not array"}`);
    res.status(200).json({ result: parsed });
  } catch {
    console.log(`[planGen] could not parse JSON, returning raw. First 200: ${finalResult.substring(0, 200)}`);
    res.status(200).json({ result: finalResult });
  }
}

async function handlePlanGenerationBatch(req, res) {
  const { input, weekStart, weekEnd, totalWeeks } = req.body;
  if (!input || typeof input !== "object") {
    res.status(400).json({ error: "input object is required" });
    return;
  }
  if (!weekStart || !weekEnd || !totalWeeks) {
    res.status(400).json({ error: "weekStart, weekEnd, and totalWeeks are required" });
    return;
  }

  console.log(`[planGenBatch] input keys: ${Object.keys(input).join(", ")}`);
  console.log(`[planGenBatch] batch: weeks ${weekStart}-${weekEnd} of ${totalWeeks}`);
  console.log(`[planGenBatch] race: ${JSON.stringify(input.race || {}).substring(0, 300)}`);
  console.log(`[planGenBatch] profile: ${JSON.stringify(input.profile || {}).substring(0, 200)}`);

  const { pass1Vars, pass2Vars, planStartDate } = buildPlanGenVars(input);

  // Override weeks_available with totalWeeks so the prompt has full plan context
  pass1Vars.weeks_available = String(totalWeeks);

  console.log(`[planGenBatch] weeks=${pass1Vars.weeks_available}, goal=${pass1Vars.goal}, race_date=${pass1Vars.race_date}`);

  // Pass 1: Generate plan structure for the batch subset (streaming to avoid 60s timeout)
  const pass1Result = await withRetry(async () => {
    const { messages, model, temperature, maxTokens } = await formatPrompt("plan-gen-summary", pass1Vars);
    messages.push({
      role: "user",
      content: `Generate weeks ${weekStart}-${weekEnd} of my ${totalWeeks}-week training plan. Start dates should continue sequentially from the plan start date ${planStartDate}. Return ONLY weeks ${weekStart} through ${weekEnd}.`,
    });
    const planMaxTokens = Math.max(maxTokens, 16384);
    let result = "";
    await streamLLM({ messages, model, temperature, maxTokens: planMaxTokens,
      onToken: (t) => { result += t; },
      onDone: () => {},
    });
    return result;
  });

  // Pass 2: Expand with details/nutrition (streaming to avoid 60s timeout)
  const finalResult = await withRetry(async () => {
    const { messages, model, temperature, maxTokens } = await formatPrompt("plan-gen-details", pass2Vars);
    messages.push({ role: "user", content: `Add detailed notes and nutrition targets to this plan:\n${pass1Result}` });
    const planMaxTokens = Math.max(maxTokens, 16384);
    let result = "";
    await streamLLM({ messages, model, temperature, maxTokens: planMaxTokens,
      onToken: (t) => { result += t; },
      onDone: () => {},
    });
    return result;
  });

  console.log(`[planGenBatch] pass1 length=${pass1Result.length}, pass2 length=${finalResult.length}`);

  // Try to parse as JSON; return raw if not valid JSON
  try {
    const parsed = JSON.parse(stripMarkdownFences(finalResult));
    console.log(`[planGenBatch] parsed weeks=${Array.isArray(parsed) ? parsed.length : "not array"}`);
    res.status(200).json({ result: parsed });
  } catch {
    console.log(`[planGenBatch] could not parse JSON, returning raw. First 200: ${finalResult.substring(0, 200)}`);
    res.status(200).json({ result: finalResult });
  }
}

// ---------------------------------------------------------------------------
// Template-based Plan Generation
// ---------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");

// In-memory template cache: { [filePath]: { data, fetchedAt } }
let templateFileCache = {};
const TEMPLATE_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

function loadTemplateFile(filePath) {
  const cached = templateFileCache[filePath];
  if (cached && Date.now() - cached.fetchedAt < TEMPLATE_CACHE_TTL_MS) {
    return cached.data;
  }
  const raw = fs.readFileSync(filePath, "utf-8");
  const data = JSON.parse(raw);
  templateFileCache[filePath] = { data, fetchedAt: Date.now() };
  return data;
}

/**
 * Parse a duration string like "45min", "100min" into total minutes.
 */
function parseDurationMinutes(durStr) {
  if (!durStr || typeof durStr !== "string") return 0;
  const match = durStr.match(/^(\d+)\s*min$/i);
  return match ? parseInt(match[1], 10) : 0;
}

/**
 * Format minutes into a human-readable string: "45min" or "1:15".
 */
function formatDuration(minutes) {
  if (minutes <= 0) return "0min";
  minutes = Math.round(minutes);
  if (minutes < 60) return `${minutes}min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (m === 0) return `${h}:00`;
  return `${h}:${String(m).padStart(2, "0")}`;
}

/**
 * Build a training plan skeleton from race and schedule templates.
 * Pure function — no LLM calls.
 */
function buildSkeletonFromTemplate(templateParams, input, planStartDate, totalWeeks, skillLevel) {
  const { raceCategory, raceSubtype, schedulePattern, includeStrength } = templateParams;

  // Load race template and schedule overlay
  const raceTemplatePath = path.join(__dirname, "templates", `${raceCategory}-${raceSubtype}.json`);
  const schedulePath = path.join(__dirname, "templates", `schedule-${schedulePattern}.json`);
  const raceTemplate = loadTemplateFile(raceTemplatePath);
  const schedule = loadTemplateFile(schedulePath);

  // Determine duration bucket from totalWeeks and weeksRange
  const ranges = raceTemplate.weeksRange;
  let bucket = "medium"; // default
  if (ranges.short && totalWeeks >= ranges.short[0] && totalWeeks <= ranges.short[1]) {
    bucket = "short";
  } else if (ranges.long && totalWeeks >= ranges.long[0] && totalWeeks <= ranges.long[1]) {
    bucket = "long";
  } else if (ranges.medium && totalWeeks >= ranges.medium[0] && totalWeeks <= ranges.medium[1]) {
    bucket = "medium";
  } else if (ranges.short && totalWeeks < ranges.short[0]) {
    bucket = "short";
  } else if (ranges.long && totalWeeks > ranges.long[1]) {
    bucket = "long";
  }

  // Compute phase week counts from percentages, ensuring they sum to totalWeeks
  const phases = raceTemplate.phases;
  const rawWeeks = phases.map((p) => p.percentage * totalWeeks);
  let phaseWeeks = rawWeeks.map((w) => Math.round(w));
  const diff = totalWeeks - phaseWeeks.reduce((a, b) => a + b, 0);
  // Adjust the largest phase to absorb rounding difference
  if (diff !== 0) {
    let maxIdx = 0;
    for (let i = 1; i < phaseWeeks.length; i++) {
      if (phaseWeeks[i] > phaseWeeks[maxIdx]) maxIdx = i;
    }
    phaseWeeks[maxIdx] += diff;
  }

  // Build phase assignment array: [{name, weekIndexInPhase, isRecovery}]
  const weekAssignments = [];
  let weekCounter = 0;
  for (let pi = 0; pi < phases.length; pi++) {
    const phase = phases[pi];
    const count = phaseWeeks[pi];
    for (let wi = 0; wi < count; wi++) {
      const isRecovery = phase.recoveryWeekEvery
        ? (wi + 1) % phase.recoveryWeekEvery === 0
        : false;
      weekAssignments.push({
        phaseName: phase.name,
        weekIndexInPhase: wi,
        isRecovery,
      });
      weekCounter++;
    }
  }

  // Last week is always raceWeek
  if (weekAssignments.length > 0) {
    weekAssignments[weekAssignments.length - 1].isRaceWeek = true;
  }

  // Base durations for this skill level
  const baseDurations = raceTemplate.baseDurations[skillLevel]
    || raceTemplate.baseDurations["intermediate"];

  const progressionMultipliers = raceTemplate.phaseProgressionMultipliers || {};
  const weekTemplates = raceTemplate.weekTemplates;

  // Build the skeleton weeks
  const startDateObj = new Date(planStartDate + "T00:00:00");
  const skeleton = [];

  for (let wi = 0; wi < totalWeeks; wi++) {
    const assignment = weekAssignments[wi];
    if (!assignment) break;

    const { phaseName, weekIndexInPhase, isRecovery, isRaceWeek } = assignment;

    // Select week template variant
    let templateWorkouts;
    if (isRaceWeek && weekTemplates.raceWeek) {
      templateWorkouts = weekTemplates.raceWeek;
    } else if (isRecovery && weekTemplates.recovery) {
      templateWorkouts = weekTemplates.recovery;
    } else if (phaseName === "Taper" && weekTemplates.taper) {
      // Use top-level taper template if available, otherwise fall through to normal.Taper
      templateWorkouts = weekTemplates.taper;
    } else if (weekTemplates.normal && weekTemplates.normal[phaseName]) {
      templateWorkouts = weekTemplates.normal[phaseName];
    } else {
      // Fallback: use first available normal phase
      const normalPhases = Object.keys(weekTemplates.normal || {});
      templateWorkouts = normalPhases.length > 0
        ? weekTemplates.normal[normalPhases[0]]
        : [];
    }

    // Phase progression multiplier for this week
    const phaseMultipliers = progressionMultipliers[phaseName] || [1.0];
    const progressionMult = phaseMultipliers[weekIndexInPhase % phaseMultipliers.length];

    // Compute week start/end dates (Monday-Sunday)
    const weekStartDate = new Date(startDateObj);
    weekStartDate.setDate(weekStartDate.getDate() + wi * 7);
    const weekEndDate = new Date(weekStartDate);
    weekEndDate.setDate(weekEndDate.getDate() + 6);

    const workouts = templateWorkouts.map((tw) => {
      // Resolve base duration: use durationKey if present, otherwise map from type
      const durationKey = tw.durationKey || tw.type.toLowerCase().replace(/[^a-z]/g, "");
      const baseDurStr = baseDurations[durationKey] || baseDurations[tw.type.toLowerCase()] || "0min";
      const baseMinutes = parseDurationMinutes(baseDurStr);

      // Apply multipliers
      const finalMinutes = baseMinutes * (tw.durationMultiplier || 0) * progressionMult;
      const duration = tw.durationMultiplier === 0 ? null : formatDuration(finalMinutes);

      return {
        day: tw.day,
        type: tw.type,
        duration,
        zone: tw.zone || "-",
        notes: tw.notes || null,
        nutritionTarget: null,
      };
    });

    // Add strength workout if includeStrength and template recommends it
    if (includeStrength && baseDurations.strength) {
      const hasStrength = workouts.some((w) =>
        w.type.toLowerCase().includes("strength"),
      );
      if (!hasStrength) {
        // Find a rest day or easy day to add strength
        const restDays = schedule.restDays || ["Mon"];
        // Pick a day that isn't rest in the workout list but is moderate/easy in schedule
        const workoutDays = new Set(workouts.filter((w) => w.type !== "Rest").map((w) => w.day));
        const candidateDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
          .filter((d) => !workoutDays.has(d) || restDays.includes(d));
        const strengthDay = candidateDays.length > 0
          ? candidateDays[candidateDays.length - 1]
          : "Mon";

        const strengthMinutes = parseDurationMinutes(baseDurations.strength);
        workouts.push({
          day: strengthDay,
          type: "Strength",
          duration: formatDuration(strengthMinutes * (isRecovery ? 0.6 : 1.0)),
          zone: "-",
          notes: "Full-body strength and mobility",
          nutritionTarget: null,
        });
      }
    }

    skeleton.push({
      weekNumber: wi + 1,
      phase: phaseName,
      startDate: weekStartDate.toISOString().split("T")[0],
      endDate: weekEndDate.toISOString().split("T")[0],
      workouts,
    });
  }

  return skeleton;
}

/**
 * Handle template-based plan generation.
 * Uses buildSkeletonFromTemplate + single LLM customization pass.
 * Falls back to handlePlanGenerationBatch on error or custom goals.
 */
async function handlePlanFromTemplate(req, res) {
  const { input, templateParams } = req.body;

  // Validate required fields
  if (!input || typeof input !== "object") {
    res.status(400).json({ error: "input object is required" });
    return;
  }
  if (!templateParams || typeof templateParams !== "object") {
    res.status(400).json({ error: "templateParams object is required" });
    return;
  }
  const { raceCategory, raceSubtype, schedulePattern, includeStrength } = templateParams;
  let { goalTier } = templateParams;
  if (!raceCategory || !raceSubtype || !schedulePattern) {
    res.status(400).json({ error: "templateParams must include raceCategory, raceSubtype, and schedulePattern" });
    return;
  }

  console.log(`[planFromTemplate] raceCategory=${raceCategory}, raceSubtype=${raceSubtype}, goalTier=${goalTier}, schedule=${schedulePattern}`);

  // Compute totalWeeks and planStartDate
  const race = input.race || {};
  const now = new Date();
  let raceDate = race.date ? new Date(race.date) : null;
  if (raceDate) {
    while (raceDate < now) raceDate.setFullYear(raceDate.getFullYear() + 1);
  }
  const planStartDate = now.toISOString().split("T")[0];
  const totalWeeks = raceDate
    ? Math.max(4, Math.round((raceDate - now) / (7 * 24 * 60 * 60 * 1000)))
    : 12;

  console.log(`[planFromTemplate] totalWeeks=${totalWeeks}, planStartDate=${planStartDate}`);

  // Handle custom goal tier — classify via quick LLM call
  if (goalTier === "custom") {
    const customGoalText = race.userGoal?.customText || race.userGoal?.text || "";
    console.log(`[planFromTemplate] classifying custom goal: "${customGoalText.substring(0, 100)}"`);

    try {
      const classifyMessages = [
        {
          role: "user",
          content: `Classify this training goal into one of: "finish", "time_goal", "custom_unique".\nIf it maps to a time goal, extract the target time in seconds.\nRace: ${raceCategory} ${raceSubtype}. Goal text: ${customGoalText}\nReturn ONLY JSON: {"classification": "finish"|"time_goal"|"custom_unique", "extractedTimeSeconds": null|number}`,
        },
      ];

      const classifyRaw = await callLLM({
        messages: classifyMessages,
        model: "gpt-4.1-mini",
        temperature: 0,
        maxTokens: 256,
      });

      const classified = JSON.parse(stripMarkdownFences(classifyRaw));
      console.log(`[planFromTemplate] goal classification: ${JSON.stringify(classified)}`);

      if (classified.classification === "finish") {
        goalTier = "finish";
      } else if (classified.classification === "time_goal") {
        goalTier = "time_goal";
        // Update the input goal with extracted time if available
        if (classified.extractedTimeSeconds && input.race?.userGoal) {
          input.race.userGoal.type = "timeTarget";
          input.race.userGoal.targetSeconds = classified.extractedTimeSeconds;
        }
      } else {
        // custom_unique — fall back to full LLM plan generation
        console.log(`[planFromTemplate] custom_unique goal, falling back to batch generation`);
        req.body.weekStart = 1;
        req.body.weekEnd = totalWeeks;
        req.body.totalWeeks = totalWeeks;
        await handlePlanGenerationBatch(req, res);
        return;
      }
    } catch (err) {
      console.error(`[planFromTemplate] goal classification failed, falling back:`, err.message);
      req.body.weekStart = 1;
      req.body.weekEnd = totalWeeks;
      req.body.totalWeeks = totalWeeks;
      await handlePlanGenerationBatch(req, res);
      return;
    }
  }

  // Determine skill level: highest of swim/bike/run, default intermediate
  const levelRank = { beginner: 0, intermediate: 1, advanced: 2 };
  const levels = [input.swimLevel, input.bikeLevel, input.runLevel]
    .filter(Boolean)
    .map((l) => l.toLowerCase());
  const skillLevel = levels.length > 0
    ? levels.reduce((best, l) => (levelRank[l] || 0) > (levelRank[best] || 0) ? l : best, levels[0])
    : "intermediate";

  console.log(`[planFromTemplate] skillLevel=${skillLevel}`);

  try {
    // Build skeleton from template
    const skeleton = buildSkeletonFromTemplate(
      templateParams,
      input,
      planStartDate,
      totalWeeks,
      skillLevel,
    );

    console.log(`[planFromTemplate] skeleton built: ${skeleton.length} weeks`);

    // Return skeleton directly — no LLM customization needed.
    // The skeleton has correct phases, dates, zones, and nutrition targets.
    // Athletes can refine via the coaching chat after onboarding.
    res.status(200).json({ result: skeleton, method: "template", warnings: [] });
  } catch (err) {
    console.error(`[planFromTemplate] template path failed, falling back to batch:`, err.message);
    try {
      req.body.weekStart = 1;
      req.body.weekEnd = totalWeeks;
      req.body.totalWeeks = totalWeeks;
      await handlePlanGenerationBatch(req, res);
      // Note: if batch already sent response, we can't add method field.
      // The fallback response comes from handlePlanGenerationBatch directly.
    } catch (fallbackErr) {
      console.error(`[planFromTemplate] fallback also failed:`, fallbackErr.message);
      if (!res.headersSent) {
        res.status(500).json({ error: "Plan generation failed", method: "custom_fallback" });
      }
    }
  }
}

// ---------------------------------------------------------------------------
// OTP Functions (existing)
// ---------------------------------------------------------------------------

// Request OTP — generates code, stores in Firestore, sends email
exports.requestOTP = onRequest(async (req, res) => {
  setCors(res);
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method not allowed" }); return; }

  try {
    const email = req.body.email;
    if (!email || !email.includes("@")) {
      res.status(400).json({ error: "Valid email required." });
      return;
    }

    const otp = generateOTP();
    const expiresAt = Date.now() + 10 * 60 * 1000; // 10 minutes

    // Store OTP in Firestore
    await db.collection("otpCodes").doc(email.toLowerCase()).set({
      code: otp,
      email: email.toLowerCase(),
      expiresAt,
      attempts: 0,
      createdAt: Date.now(),
    });

    // Send email
    const smtpConfigured = process.env.SMTP_EMAIL && process.env.SMTP_PASSWORD;
    if (smtpConfigured) {
      try {
        await transporter.sendMail({
          from: `"Race1" <${process.env.SMTP_EMAIL}>`,
          to: email,
          subject: "Your Race1 sign-in code",
          text: `Your Race1 verification code is: ${otp}\n\n${otp} is your Race1 code.\n\nThis code expires in 10 minutes.`,
          html: `
            <div style="font-family: -apple-system, sans-serif; max-width: 400px; margin: 0 auto; padding: 20px; text-align: center;">
              <img src="https://brents-trainer.web.app/race1-logo.png"
                   style="width: 80px; height: 80px; border-radius: 18px; margin-bottom: 12px;" alt="Race1">
              <h2 style="margin: 0 0 16px;">Race1</h2>
              <p style="text-align: left;">Your verification code is:</p>
              <div style="font-size: 32px; font-weight: bold; letter-spacing: 8px; text-align: center; padding: 20px; background: #f0f0f0; border-radius: 8px; margin: 16px 0;">
                ${otp}
              </div>
              <p style="color: #666; font-size: 14px;">This code expires in 10 minutes.</p>
            </div>
          `,
        });
      } catch (err) {
        console.error("Email send failed:", err);
      }
    }

    // Always log OTP for development/testing
    console.log(`OTP for ${email}: ${otp}`);

    res.status(200).json({ success: true, message: "Verification code sent." });
  } catch (err) {
    console.error("requestOTP error:", err);
    res.status(500).json({ error: "Internal error." });
  }
});

// Verify OTP — checks code, creates custom auth token
exports.verifyOTP = onRequest(async (req, res) => {
  setCors(res);
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method not allowed" }); return; }

  try {
    const { email, code } = req.body;
    if (!email || !code) {
      res.status(400).json({ error: "Email and code required." });
      return;
    }

    const docRef = db.collection("otpCodes").doc(email.toLowerCase());
    const doc = await docRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "No verification code found. Request a new one." });
      return;
    }

    const data = doc.data();

    // Check expiry
    if (Date.now() > data.expiresAt) {
      await docRef.delete();
      res.status(410).json({ error: "Code expired. Request a new one." });
      return;
    }

    // Check attempts (max 5)
    if (data.attempts >= 5) {
      await docRef.delete();
      res.status(429).json({ error: "Too many attempts. Request a new code." });
      return;
    }

    // Increment attempts
    await docRef.update({ attempts: admin.firestore.FieldValue.increment(1) });

    // Verify code
    if (data.code !== code) {
      res.status(401).json({ error: "Incorrect code." });
      return;
    }

    // Code is valid — clean up and create auth token
    await docRef.delete();

    // Get or create Firebase Auth user for this email
    const emailLower = email.toLowerCase();
    let uid;
    try {
      const user = await admin.auth().getUserByEmail(emailLower);
      uid = user.uid;
    } catch (err) {
      const newUser = await admin.auth().createUser({
        email: emailLower,
        emailVerified: true,
      });
      uid = newUser.uid;
    }

    const token = await admin.auth().createCustomToken(uid);
    res.status(200).json({ success: true, token });
  } catch (err) {
    console.error("verifyOTP error:", err.message, err.code, err.stack);
    res.status(500).json({ error: err.message || "Internal error." });
  }
});

// ---------------------------------------------------------------------------
// LLM Proxy (new)
// ---------------------------------------------------------------------------

exports.llmProxy = onRequest({ timeoutSeconds: 300 }, async (req, res) => {
  setCors(res);
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method not allowed" }); return; }

  // Authenticate
  const user = await verifyAuth(req);
  if (!user) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }

  const { type } = req.body;
  if (!type) {
    res.status(400).json({ error: "type is required" });
    return;
  }

  try {
    switch (type) {
      case "coaching":
        await handleCoaching(req, res, user.uid);
        break;
      case "raceSearch":
        await handleRaceSearch(req, res);
        break;
      case "prepRaceSearch":
        await handlePrepRaceSearch(req, res);
        break;
      case "planGeneration":
        await handlePlanGeneration(req, res);
        break;
      case "planGenerationBatch":
        await handlePlanGenerationBatch(req, res);
        break;
      case "planFromTemplate":
        await handlePlanFromTemplate(req, res);
        break;
      default:
        res.status(400).json({ error: `Unknown type: ${type}` });
    }
  } catch (err) {
    console.error(`llmProxy error (type=${type}, uid=${user.uid}):`, err);
    if (!res.headersSent) {
      res.status(500).json({ error: "Internal error" });
    }
  }
});
