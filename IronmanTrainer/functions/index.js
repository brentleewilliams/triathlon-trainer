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
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
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

async function handleCoaching(req, res) {
  const { userMessage, trainingContext, workoutHistory, zoneBoundaries, conversationHistory, imageData } = req.body;

  if (!userMessage || typeof userMessage !== "string") {
    res.status(400).json({ error: "userMessage is required" });
    return;
  }

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

  // Set up SSE headers
  res.set("Content-Type", "text/event-stream");
  res.set("Cache-Control", "no-cache");
  res.set("Connection", "keep-alive");

  try {
    await streamLLM({
      messages: allMessages,
      model,
      temperature,
      maxTokens,
      onToken: (token) => {
        res.write(`data: ${JSON.stringify(token)}\n\n`);
      },
      onDone: () => {
        res.write("data: [DONE]\n\n");
        res.end();
      },
    });
  } catch (err) {
    console.error("Coaching stream error:", err);
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
    race_type: race.type || "triathlon",
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
              <img src="data:image/png;base64,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"
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
        await handleCoaching(req, res);
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
