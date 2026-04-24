/**
 * Updates the coaching-chat prompt in LangSmith by appending the
 * TRAINING STATUS CONTEXT section to the system prompt.
 *
 * Fetches the current live commit, modifies the system prompt template,
 * and creates a new commit.
 *
 * Run via GitHub Actions: .github/workflows/update-langsmith-prompt.yml
 */

const { Client } = require('langsmith');

const LANGSMITH_API_KEY = process.env.LANGSMITH_API_KEY;
if (!LANGSMITH_API_KEY) {
  console.error('ERROR: LANGSMITH_API_KEY environment variable is required');
  process.exit(1);
}

const DRY_RUN = process.env.DRY_RUN === 'true';
const PROMPT_NAME = 'coaching-chat';
const PRODUCTION_TAG = 'production';
const LANGSMITH_API_URL = 'https://api.smith.langchain.com';

async function ensureProductionTag(owner, repo, commitHash) {
  // The tag endpoint expects the commit's UUID (`id`), not the 64-char
  // `commit_hash` returned by pullPromptCommit. Look it up from the
  // commits list.
  const headers = { 'x-api-key': LANGSMITH_API_KEY, 'Content-Type': 'application/json' };
  const listRes = await fetch(`${LANGSMITH_API_URL}/commits/${owner}/${repo}?limit=20`, { headers });
  if (!listRes.ok) {
    throw new Error(`Failed to list commits: ${listRes.status} ${await listRes.text()}`);
  }
  const { commits } = await listRes.json();
  const match = (commits || []).find((c) => c.commit_hash === commitHash);
  if (!match) {
    throw new Error(`Commit ${commitHash.slice(0, 12)} not found in first 20 commits; can't map to UUID`);
  }
  const commitUuid = match.id;

  const base = `${LANGSMITH_API_URL}/api/v1/repos/${owner}/${repo}/tags`;
  const createRes = await fetch(base, {
    method: 'POST',
    headers,
    body: JSON.stringify({ tag_name: PRODUCTION_TAG, commit_id: commitUuid }),
  });
  if (createRes.ok) {
    console.log(`Created '${PRODUCTION_TAG}' tag on ${owner}/${repo}@${commitHash.slice(0, 8)}`);
    return;
  }
  // 409: tag exists (on this or another commit) — move it. 400 can also
  // indicate a conflict depending on server version.
  if (createRes.status === 409 || createRes.status === 400) {
    const moveRes = await fetch(`${base}/${PRODUCTION_TAG}`, {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ commit_id: commitUuid }),
    });
    if (!moveRes.ok) {
      throw new Error(`Failed to move tag: ${moveRes.status} ${await moveRes.text()}`);
    }
    console.log(`Moved '${PRODUCTION_TAG}' tag to ${owner}/${repo}@${commitHash.slice(0, 8)}`);
    return;
  }
  throw new Error(`Failed to create tag: ${createRes.status} ${await createRes.text()}`);
}

const TRAINING_STATUS_SECTION = `
TRAINING STATUS CONTEXT
The user's current training status is provided in a structured block starting with
"====== TRAINING STATUS ======". Use this to:
- Reference their CTL/ATL/Form (TSB) when discussing fatigue or readiness
- Call out DISCIPLINE GAPS proactively — if swim/bike/run hasn't been trained in 14+ days,
  flag it and suggest how to reintegrate it safely
- If intensity pattern is "thresholdHeavy", recommend more easy aerobic work
- If decoupling > 10%, recommend building aerobic base before adding intensity
- If readiness < 40, suggest easy/recovery session rather than hard workout
- Taper phase (TSB rising toward +15): affirm the athlete is on track, don't add load`;

async function run() {
  const client = new Client({ apiKey: LANGSMITH_API_KEY });

  console.log(`Fetching current commit for prompt: ${PROMPT_NAME}`);
  let commit;
  try {
    commit = await client.pullPromptCommit(PROMPT_NAME, { includeModel: true });
  } catch (err) {
    console.error('Failed to pull prompt commit:', err.message);
    process.exit(1);
  }

  console.log(`Got commit hash: ${commit.commit_hash}`);
  console.log('Manifest keys:', Object.keys(commit.manifest));

  // Deep-clone the manifest so we can modify it
  const manifest = JSON.parse(JSON.stringify(commit.manifest));

  // Find and update the system message template.
  // The manifest is either a ChatPromptTemplate directly or a RunnableSequence
  // with first = ChatPromptTemplate (when includeModel=true).
  const messages =
    manifest.kwargs?.first?.kwargs?.messages ||
    manifest.kwargs?.messages ||
    [];

  console.log(`Found ${messages.length} messages in manifest`);

  let systemMessageFound = false;
  for (const msg of messages) {
    const id = msg.id || [];
    const isSystem =
      id.includes('SystemMessagePromptTemplate') ||
      id.includes('SystemMessage');

    if (isSystem) {
      // Get the template string
      let currentTemplate =
        msg.kwargs?.prompt?.kwargs?.template ||
        msg.kwargs?.content ||
        '';

      console.log('\n=== CURRENT SYSTEM PROMPT (last 500 chars) ===');
      console.log(currentTemplate.slice(-500));
      console.log('=== END CURRENT SYSTEM PROMPT ===\n');

      // Check if the section already exists — if so, skip the commit step
      // but still ensure the production tag points at the latest commit.
      if (currentTemplate.includes('TRAINING STATUS CONTEXT')) {
        console.log('TRAINING STATUS CONTEXT section already exists in the prompt. Skipping commit; will ensure production tag.');
        if (!DRY_RUN) {
          try {
            await ensureProductionTag(commit.owner, commit.repo, commit.commit_hash);
          } catch (err) {
            console.error('Failed to ensure production tag:', err.message);
            process.exit(1);
          }
        }
        process.exit(0);
      }

      // Append the new section
      const updatedTemplate = currentTemplate + TRAINING_STATUS_SECTION;

      console.log('\n=== UPDATED SYSTEM PROMPT (last 800 chars) ===');
      console.log(updatedTemplate.slice(-800));
      console.log('=== END UPDATED SYSTEM PROMPT ===\n');

      // Write back to the manifest
      if (msg.kwargs?.prompt?.kwargs?.template !== undefined) {
        msg.kwargs.prompt.kwargs.template = updatedTemplate;
        if (msg.kwargs.prompt.kwargs.input_variables !== undefined) {
          console.log('Template input_variables:', msg.kwargs.prompt.kwargs.input_variables);
        }
      } else if (msg.kwargs?.content !== undefined) {
        msg.kwargs.content = updatedTemplate;
      }

      systemMessageFound = true;
      break;
    }
  }

  if (!systemMessageFound) {
    console.error('ERROR: Could not find a system message in the prompt manifest.');
    console.error('Full manifest structure:');
    console.error(JSON.stringify(manifest, null, 2).substring(0, 2000));
    process.exit(1);
  }

  if (DRY_RUN) {
    console.log('DRY RUN: Not pushing to LangSmith.');
    console.log('Updated manifest (abbreviated):');
    console.log(JSON.stringify(manifest, null, 2).substring(0, 3000));
    process.exit(0);
  }

  console.log(`Pushing updated prompt to LangSmith as new commit on ${PROMPT_NAME}...`);
  try {
    const url = await client.createCommit(
      PROMPT_NAME,
      manifest,
      { parentCommitHash: commit.commit_hash }
    );
    console.log('SUCCESS! New prompt commit URL:', url);
  } catch (err) {
    console.error('Failed to create commit:', err.message);
    if (err.message.includes('403') || err.message.includes('Forbidden')) {
      console.error('Permission denied - check that LANGSMITH_API_KEY has write access to this prompt.');
    }
    process.exit(1);
  }

  // Tag the new commit as 'production' so pullPromptCommit("coaching-chat:production") resolves to it.
  try {
    const newHead = await client.pullPromptCommit(PROMPT_NAME, { includeModel: true });
    await ensureProductionTag(newHead.owner, newHead.repo, newHead.commit_hash);
  } catch (err) {
    console.error('Failed to tag commit as production:', err.message);
    process.exit(1);
  }

  // Verify by pulling the latest commit
  console.log('\nVerifying the update by pulling the latest commit...');
  try {
    const verify = await client.pullPromptCommit(PROMPT_NAME, { includeModel: true });
    const verifyMessages =
      verify.manifest.kwargs?.first?.kwargs?.messages ||
      verify.manifest.kwargs?.messages ||
      [];
    for (const msg of verifyMessages) {
      const id = msg.id || [];
      const isSystem =
        id.includes('SystemMessagePromptTemplate') ||
        id.includes('SystemMessage');
      if (isSystem) {
        const template =
          msg.kwargs?.prompt?.kwargs?.template ||
          msg.kwargs?.content ||
          '';
        const hasSection = template.includes('TRAINING STATUS CONTEXT');
        console.log(`Verification: TRAINING STATUS CONTEXT present in live prompt: ${hasSection}`);
        if (hasSection) {
          console.log('\nVERIFICATION PASSED: Prompt updated successfully.');
        } else {
          console.error('\nVERIFICATION FAILED: Section not found in live prompt after push.');
          process.exit(1);
        }
        break;
      }
    }
  } catch (err) {
    console.warn('Could not verify (non-fatal):', err.message);
  }
}

run();
