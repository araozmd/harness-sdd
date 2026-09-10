#!/usr/bin/env node
// sync-board.mjs — one-way MIRROR: state/tasks.json  ->  an external project board.
//
// tasks.json is the SOURCE OF TRUTH. This is a downstream PROJECTION for humans, NOT a
// store backend: agents keep deciding "what's next" from local tasks.json and never need
// the board to be reachable to function. Re-runnable any time; idempotent.
//
//   node .harness/tools/sync-board.mjs            # sync the configured provider
//   node .harness/tools/sync-board.mjs --dry-run  # print intended changes, mutate nothing
//
// PROVIDER is chosen by `mirror.board.provider` in harness.config.yaml — INERT by default:
//   ""|none         -> disabled; prints a notice and exits 0 (the default; no board).
//   github-projects -> IMPLEMENTED (needs `gh` authed with `project` + `repo` scopes).
//                      Optionally assigns each issue to `mirror.board.assignee` once the
//                      feature is in-progress/in-review/done (cleared when not started).
//                      `assignee: "@me"` resolves dynamically to the authed `gh` user so
//                      this shared config never hard-codes one person.
//   jira            -> IMPLEMENTED (Jira Server/Data Center REST API + Bearer PAT, no MCP).
//                      Needs `mirror.board.{base_url,project_key}` and a PAT from the
//                      JIRA_PAT env var (precedence) or the gitignored pat_file
//                      (default `jira.pat`, resolved under the harness dir ⇒ `.harness/jira.pat`
//                      in a consumer). Status only; assignee is a no-op for
//                      jira in F01 (deferred to E10). See store/board-mirror.md.
//   azure-boards    -> STUB (recognized, not implemented yet — see store/board-mirror.md).
//
// All provider config lives in harness.config.yaml under `mirror.board` — nothing about a
// specific org/repo/tool is hard-coded here. Status columns default to the harness status
// names verbatim (identity map), so the board is not tied to any one team's column naming.

import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve, isAbsolute } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const CONFIG_PATH = resolve(HERE, '../harness.config.yaml');   // .harness/harness.config.yaml in a consumer
const TASKS_PATH = resolve(HERE, '../state/tasks.json');
const ARGV = process.argv.slice(2);
const DRY = ARGV.includes('--dry-run');
// TARGETED RECONCILE (E99-F156). `store/local.md` specifies the post-write hook
// NORMATIVELY as `<cmd> "<feature-id>" "<op>"`, and the Orchestrator has always passed
// both. This tool used to read only `--dry-run` and drop the positionals, so a hook the
// harness documents as targeted ran board-wide: every status write reconciled all ~N
// features, re-drove `assignee` across unrelated issues, and rewrote the whole Epic option
// set on behalf of one feature. The doc stated a contract nothing implemented.
//
// TARGETED requires BOTH positionals. An argument-less invocation stays byte-for-byte
// board-wide, which is what keeps every existing consumer — and every by-hand full
// reconcile — working exactly as before.
const POSITIONAL = ARGV.filter((a) => !a.startsWith('--'));
const targetFeatureId = POSITIONAL[0] || '';
const hookOp = POSITIONAL[1] || '';
const TARGETED = Boolean(targetFeatureId && hookOp);
const log = (...a) => console.log(...a);

// --- minimal, dependency-free YAML reader (same ethos as the shell _cfg_* awk helpers):
// walk indentation, return the scalar at a dotted key path; undefined if absent.
const unquote = (s) => s.trim().replace(/^["']|["']$/g, '');
function yamlGet(text, pathKeys) {
  const stack = [];
  for (const raw of text.split(/\r?\n/)) {
    if (!raw.trim() || /^\s*#/.test(raw)) continue;
    const indent = raw.length - raw.replace(/^\s+/, '').length;
    const m = raw.replace(/\s+#.*$/, '').match(/^\s*([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m) continue;
    const [, key, rawVal] = m;
    while (stack.length && indent <= stack[stack.length - 1].indent) stack.pop();
    const path = [...stack.map((s) => s.key), key];
    if (path.length === pathKeys.length && path.every((k, i) => k === pathKeys[i])) {
      return unquote(rawVal);
    }
    stack.push({ indent, key });
  }
  return undefined;
}

// Return the immediate scalar children {key: value} of the map at a dotted key path,
// or {} if the section is absent/empty. Used for the optional status_map.
function yamlGetMap(text, pathKeys) {
  const out = {};
  const stack = [];
  let parentIndent = null, childIndent = null;
  for (const raw of text.split(/\r?\n/)) {
    if (!raw.trim() || /^\s*#/.test(raw)) continue;
    const indent = raw.length - raw.replace(/^\s+/, '').length;
    const m = raw.replace(/\s+#.*$/, '').match(/^\s*([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m) continue;
    const [, key, rawVal] = m;
    if (parentIndent !== null) {                 // collecting children of the matched section
      if (indent <= parentIndent) break;          // section ended
      if (childIndent === null) childIndent = indent;
      if (indent === childIndent && rawVal.trim() !== '') out[key] = unquote(rawVal);
      continue;
    }
    while (stack.length && indent <= stack[stack.length - 1].indent) stack.pop();
    const path = [...stack.map((s) => s.key), key];
    if (path.length === pathKeys.length && path.every((k, i) => k === pathKeys[i])) {
      parentIndent = indent; continue;            // start collecting its children
    }
    stack.push({ indent, key });
  }
  return out;
}

// --- resolve provider config -------------------------------------------------
let cfgText = '';
try { cfgText = readFileSync(CONFIG_PATH, 'utf8'); }
catch { /* no config -> treated as disabled below */ }

const provider = (yamlGet(cfgText, ['mirror', 'board', 'provider']) || '').toLowerCase();

if (provider === '' || provider === 'none') {
  log('[mirror] board mirror disabled (mirror.board.provider is empty) — nothing to do.');
  process.exit(0);
}
if (provider === 'azure-boards') {
  log(`[mirror] provider '${provider}' is recognized but NOT IMPLEMENTED yet (stub).`);
  log('[mirror] tasks.json is unchanged. See store/board-mirror.md to implement it.');
  process.exit(0);   // inert no-op: a known-but-unwired provider must never block the loop
}

// ── provider: jira ───────────────────────────────────────────────────────────
// One-way MIRROR to a Jira Server / Data Center project via the REST API + a Bearer PAT.
// NO MCP transport of any kind. Status only in F01 (assignee is a recognized no-op for
// jira, deferred to E10). Config is validated and the PAT resolved BEFORE any network call
// (fail-closed), so a misconfigured / unauthenticated run never half-mutates Jira.
if (provider === 'jira') {
  await runJira(cfgText);
  process.exit(0);
}

if (provider !== 'github-projects') {
  console.error(`[mirror] unknown provider '${provider}'. Use one of: none, github-projects, jira, azure-boards.`);
  process.exit(1);
}

// ── provider: github-projects ────────────────────────────────────────────────
const OWNER = yamlGet(cfgText, ['mirror', 'board', 'owner']) || '';
const PROJECT_NUMBER = Number(yamlGet(cfgText, ['mirror', 'board', 'project_number']) || 0);
const REPO = yamlGet(cfgText, ['mirror', 'board', 'repo']) || '';
let ASSIGNEE = yamlGet(cfgText, ['mirror', 'board', 'assignee']) || '';
if (!OWNER || !PROJECT_NUMBER || !REPO) {
  console.error('[mirror] provider github-projects needs mirror.board.{owner,project_number,repo} set in harness.config.yaml.');
  process.exit(1);
}
// ── PREFLIGHT (R7): transport is `gh` CLI ONLY (never MCP). Fail CLOSED, with an
// actionable message, BEFORE any board-mutating `gh` call, if `gh` is (a) absent,
// (b) below the minimum version that ships the Projects-v2 `gh project` commands, or
// (c) missing the `project` + `repo` auth scopes. This runs after the config check and
// before the first project/issue query, so a preflight failure never mutates the board.
const GH_MIN = '2.31.0';   // first gh release with stable `gh project` (Projects v2) subcommands
const SCOPE_HINT =
  "run `gh auth refresh -s project -s repo` (or `gh auth login` with those scopes) so gh can reach GitHub Projects (v2)";
const cmp = (a, b) => {   // semver-ish numeric compare: -1 / 0 / 1
  const pa = a.split('.').map(Number), pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) { const d = (pa[i] || 0) - (pb[i] || 0); if (d) return d < 0 ? -1 : 1; }
  return 0;
};
let ghVersionOut;
try { ghVersionOut = execFileSync('gh', ['--version'], { encoding: 'utf8' }); }
catch {
  console.error(`[mirror] \`gh\` CLI not found — github-projects targets GitHub Projects (v2) via \`gh\` and needs gh >= ${GH_MIN} authed with 'project' + 'repo' scopes. Install gh (https://cli.github.com), then ${SCOPE_HINT}.`);
  process.exit(1);
}
const ghVer = (ghVersionOut.match(/gh version (\d+\.\d+\.\d+)/) || [])[1];
if (!ghVer || cmp(ghVer, GH_MIN) < 0) {
  console.error(`[mirror] \`gh\`${ghVer ? ` ${ghVer}` : ''} is too old for GitHub Projects (v2) — the \`gh project\` commands need gh >= ${GH_MIN}. Upgrade gh (https://cli.github.com), then ${SCOPE_HINT}.`);
  process.exit(1);
}
// Verify the required auth scopes without mutating anything: `gh auth status` reports the
// token's scopes. Fail closed if it can't confirm both `project` and `repo` are present.
// gh < 2.33 writes `gh auth status` output to STDERR, not stdout (cli/cli#7920), so on the
// documented minimum (2.31) a SUCCESSFUL status has an empty stdout. Capture BOTH streams and
// scan their concatenation for the `Token scopes:` line so the scope check works on gh 2.31+
// regardless of which stream gh uses.
const authRes = spawnSync('gh', ['auth', 'status'], { encoding: 'utf8' });
if (authRes.error || authRes.status !== 0) {
  const detail = (authRes.stderr || authRes.stdout || (authRes.error && authRes.error.message) || '').toString();
  console.error(`[mirror] \`gh\` is not authenticated for GitHub Projects (v2) — ${SCOPE_HINT}.${detail ? `\n${detail.trim()}` : ''}`);
  process.exit(1);
}
const authOut = (authRes.stdout || '') + '\n' + (authRes.stderr || '');
const scopesLine = (authOut.match(/Token scopes:.*$/m) || [''])[0];
// Tokenize the scope list into EXACT scope strings, then require exact membership — never a
// substring/regex match. GitHub lists narrower OAuth scopes (`repo:status`, `repo_deployment`,
// `public_repo`, `repo:invite`, `read:project`) as separate tokens; only the bare `repo` and
// bare `project` grant the read/write access this mirror needs, so anything qualified must FAIL
// CLOSED (R7). Take the text after `Token scopes:`, split on commas, and strip surrounding
// whitespace + surrounding quotes from each part (handles both `'project', 'repo'` and the
// unquoted `project, repo` forms); drop empties.
const scopeSet = new Set(
  scopesLine
    .replace(/^.*Token scopes:/, '')
    .split(',')
    .map((s) => s.trim().replace(/^['"]|['"]$/g, ''))
    .filter(Boolean),
);
const hasScope = (s) => scopeSet.has(s);
const missingScopes = ['project', 'repo'].filter((s) => !hasScope(s));
if (missingScopes.length) {
  console.error(`[mirror] \`gh\` auth is missing required scope(s) for GitHub Projects (v2): ${missingScopes.join(', ')} — ${SCOPE_HINT}.`);
  process.exit(1);
}

// feature state machine -> board column. Column NAMES default to IDENTITY (column ==
// harness status) and can be overridden per status via `mirror.board.status_map` in
// harness.config.yaml — so a team keeps its existing board columns (e.g. "Todo", "Done")
// WITHOUT editing this file. Colors are fixed defaults (cosmetic).
const STATUS_COLORS = { 'pending': 'GRAY', 'spec-ready': 'PURPLE', 'in-progress': 'BLUE', 'in-review': 'YELLOW', 'done': 'GREEN' };
const statusMapCfg = yamlGetMap(cfgText, ['mirror', 'board', 'status_map']);
const STATUS = Object.fromEntries(Object.keys(STATUS_COLORS).map((s) => [
  s, { col: statusMapCfg[s] || s, color: STATUS_COLORS[s] },
]));
const STATUS_COLS = Object.values(STATUS).map((s) => s.col);
const EPIC_COLORS = ['BLUE', 'GREEN', 'PURPLE', 'ORANGE', 'PINK', 'RED', 'YELLOW', 'GRAY'];
// A feature gets ASSIGNEE attached once work has actually started; statuses before that
// (pending/spec-ready) stay unassigned so the board reflects who is doing what right now.
const ASSIGNED_STATUSES = new Set(['in-progress', 'in-review', 'done']);

function gh(args, input) { return execFileSync('gh', args, { encoding: 'utf8', input, maxBuffer: 1 << 24 }); }
function ghJson(args) { return JSON.parse(gh(args)); }
function graphql(query, variables) {
  return JSON.parse(gh(['api', 'graphql', '--input', '-'], JSON.stringify({ query, variables })));
}

// Dynamic assignee: `@me`/`self` (or `$me`) means "whoever is running this sync" — resolve
// to the authed gh login so each developer's board reflects their own ownership without
// hard-coding one shared login in this shared-repo config. We resolve to the real login
// (not pass `@me` straight to gh) so the idempotency + unassign comparisons below — which
// match on `issue.assignees[].login` — keep working. Resolution failure degrades to "skip".
if (['@me', 'self', '$me'].includes(ASSIGNEE.toLowerCase())) {
  try {
    ASSIGNEE = gh(['api', 'user', '--jq', '.login']).trim();
    log(`[mirror] assignee '@me' -> ${ASSIGNEE} (authed gh user)`);
  } catch {
    console.error("[mirror] assignee '@me' set but `gh api user` failed — skipping assignment this run.");
    ASSIGNEE = '';
  }
}

// --- load + flatten tasks.json ------------------------------------------------
const data = JSON.parse(readFileSync(TASKS_PATH, 'utf8'));
const epics = data.epics.map((e) => ({ id: e.id, label: `${e.id} — ${e.title}` }));
const allFeatures = data.epics.flatMap((e) =>
  (e.features || []).map((f) => ({
    id: f.id, title: `${f.id} — ${f.title}`, status: f.status, epicLabel: `${e.id} — ${e.title}`,
  })),
);
// Resolve the target BEFORE any gh write, so a bad id costs nothing.
//
// An EPIC id is a legitimate hook argument: set_status writes epic status too, and
// store/local.md says "the id selects the object kind". Epics have no feature issue, so
// that is a clean NO-OP with exit 0 — not an error. An id that is neither IS an error:
// silently reconciling the whole board because the id was misspelled is precisely the
// behaviour this feature removes.
const targetFeature = TARGETED ? allFeatures.find((f) => f.id === targetFeatureId) : undefined;
const targetEpic = TARGETED ? epics.find((e) => e.id === targetFeatureId) : undefined;
if (TARGETED && !targetFeature && targetEpic) {
  log(`[mirror] targeted ${hookOp}: ${targetFeatureId} is an epic; no feature issue to sync.`);
  process.exit(0);
}
if (TARGETED && !targetFeature) {
  console.error(`[mirror] targeted ${hookOp} requested unknown feature '${targetFeatureId}' — no board change was made.`);
  process.exit(1);
}
const features = TARGETED ? [targetFeature] : allFeatures;
log(TARGETED
  ? `[mirror] github-projects targeted ${hookOp}: ${targetFeatureId} (1/${allFeatures.length} features) -> ${OWNER}/#${PROJECT_NUMBER}`
  : `[mirror] github-projects: ${epics.length} epics, ${features.length} features -> ${OWNER}/#${PROJECT_NUMBER}`);

// --- project + fields ---------------------------------------------------------
const project = ghJson(['project', 'view', String(PROJECT_NUMBER), '--owner', OWNER, '--format', 'json']);
const PID = project.id;
const fields = () => ghJson(['project', 'field-list', String(PROJECT_NUMBER), '--owner', OWNER, '--format', 'json']).fields;
let FIELDS = fields();
const fieldByName = (n) => FIELDS.find((f) => f.name === n);

// Ensure a single-select field's options EXACTLY match `desired`. Only mutates on a name-set
// diff (avoids churn). Returns a fresh {name -> optionId}.
function ensureOptions(fieldName, desired) {
  const field = fieldByName(fieldName);
  if (!field) throw new Error(`field "${fieldName}" not found on project ${OWNER}/#${PROJECT_NUMBER}`);
  const have = (field.options || []).map((o) => o.name);
  const want = desired.map((d) => d.name);
  const matches = have.length === want.length && want.every((n) => have.includes(n));
  if (!matches) {
    if (DRY) { log(`[dry-run] would set ${fieldName} options -> ${want.join(', ')}`); }
    else {
      const opts = desired.map((d) => ({ name: d.name, color: d.color, description: '' }));
      graphql(
        `mutation($f:ID!,$o:[ProjectV2SingleSelectFieldOptionInput!]!){updateProjectV2Field(input:{fieldId:$f,singleSelectOptions:$o}){projectV2Field{__typename}}}`,
        { f: field.id, o: opts },
      );
      log(`[mirror] ${fieldName} options set -> ${want.join(', ')}`);
      FIELDS = fields();
    }
  }
  const fresh = FIELDS.find((f) => f.name === fieldName);
  return Object.fromEntries((fresh.options || []).map((o) => [o.name, o.id]));
}

const statusOptionId = ensureOptions('Status', STATUS_COLS.map((c) => ({
  name: c, color: Object.values(STATUS).find((s) => s.col === c).color,
})));
// Read a single-select field's current options WITHOUT mutating it.
function currentOptionIds(fieldName) {
  const field = fieldByName(fieldName);
  if (!field) throw new Error(`field "${fieldName}" not found on project ${OWNER}/#${PROJECT_NUMBER}`);
  return Object.fromEntries((field.options || []).map((o) => [o.name, o.id]));
}
// A targeted run must not rewrite the whole Epic option set: ensureOptions replaces the
// option list wholesale, so one feature's status write RENAMED every existing board
// column to whatever the current labels happened to be. When the target's epic option
// already exists there is nothing to add — read the ids and leave the field alone. Fall
// back to ensureOptions only when the option is genuinely new (or the run is board-wide).
const epicOptionsNow = TARGETED ? currentOptionIds('Epic') : null;
const epicOptionId = (epicOptionsNow && epicOptionsNow[targetFeature.epicLabel])
  ? epicOptionsNow
  : ensureOptions('Epic', epics.map((e, i) => ({
    name: e.label, color: EPIC_COLORS[i % EPIC_COLORS.length],
  })));
const STATUS_FIELD_ID = fieldByName('Status').id;
const EPIC_FIELD_ID = fieldByName('Epic').id;

// --- existing issues + items --------------------------------------------------
// Targeted: ask GitHub for the addressed feature's issue instead of paging 500.
// `--limit` CAPS THE FETCH, it does not filter: the `--search` below only narrows to
// titles CONTAINING the id, so many follow-up issues can share that substring. A
// targeted limit LOWER than the board-wide one could push the exact canonical title out
// of the result set, the exact-title map would read it as absent, and the reconcile loop
// would CREATE A DUPLICATE issue. Same cap for both paths; the search is the saving.
const issueListArgs = ['issue', 'list', '--repo', REPO, '--state', 'all',
  '--limit', '500', '--json', 'number,title,url,state,assignees'];
if (TARGETED) issueListArgs.push('--search', `${targetFeatureId} in:title`);
const issues = ghJson(issueListArgs);
const issueByTitle = new Map(issues.map((i) => [i.title, i]));
const items = ghJson(['project', 'item-list', String(PROJECT_NUMBER), '--owner', OWNER,
  '--format', 'json', '--limit', '500']).items;
const itemByNumber = new Map(items.filter((i) => i.content?.number != null).map((i) => [i.content.number, i.id]));

// --- reconcile each feature ---------------------------------------------------
for (const f of features) {
  let issue = issueByTitle.get(f.title);
  if (!issue) {
    if (DRY) { log(`[dry-run] would create issue: ${f.title}`); continue; }
    const body = `**Epic:** ${f.epicLabel}\n**Status (tasks.json):** ${f.status}\n\nSeeded from \`state/tasks.json\` by \`sync-board.mjs\`.`;
    const url = gh(['issue', 'create', '--repo', REPO, '--title', f.title, '--body', body]).trim().split('\n').pop();
    const number = Number(url.split('/').pop());
    issue = { number, title: f.title, url, state: 'OPEN', assignees: [] };
    log(`[mirror] created issue #${number}: ${f.title}`);
  }

  let itemId = itemByNumber.get(issue.number);
  if (!itemId) {
    if (DRY) { log(`[dry-run] would add #${issue.number} to project`); }
    else {
      itemId = ghJson(['project', 'item-add', String(PROJECT_NUMBER), '--owner', OWNER, '--url', issue.url, '--format', 'json']).id;
      log(`[mirror] added #${issue.number} to project`);
    }
  }

  const wantStatusOpt = statusOptionId[STATUS[f.status]?.col];
  const wantEpicOpt = epicOptionId[f.epicLabel];
  if (!DRY && itemId) {
    const setField = (fieldId, optId) => optId && gh(['project', 'item-edit', '--project-id', PID,
      '--id', itemId, '--field-id', fieldId, '--single-select-option-id', optId]);
    setField(STATUS_FIELD_ID, wantStatusOpt);
    setField(EPIC_FIELD_ID, wantEpicOpt);
  }

  // When ASSIGNEE is configured the mirror OWNS the Assignees field for its items, so it
  // RECONCILES the field to the exact desired set every sync: a started feature
  // (in-progress/in-review/done) should have EXACTLY the configured login; a not-started
  // one (pending/spec-ready) none. That means both directions: ADD the configured login
  // where missing AND REMOVE every other login — so a teammate left over from a shared `@me`
  // sync (e.g. Alice, then Bob runs it) is cleared off a started item too, not only when it
  // later regresses. Idempotent: one `gh issue edit` only when the sets actually differ.
  if (ASSIGNEE) {
    const current = (issue.assignees || []).map((a) => a.login);
    const want = ASSIGNED_STATUSES.has(f.status) ? [ASSIGNEE] : [];
    // GitHub logins are case-INSENSITIVE, so diff on lowercased logins — otherwise a config
    // `octocat` vs an API-returned `OctoCat` would look both missing AND foreign and the sync
    // would forever `--add octocat`/`--remove OctoCat` the same account (never idempotent). We
    // keep the ORIGINAL spelling for the actual flags: the configured spelling for --add, the
    // existing-issue spelling for --remove.
    const lc = (s) => s.toLowerCase();
    const currentLc = current.map(lc);
    const wantLc = want.map(lc);
    const toAdd = want.filter((l) => !currentLc.includes(lc(l)));
    const toRemove = current.filter((l) => !wantLc.includes(lc(l)));
    if (toAdd.length || toRemove.length) {
      if (DRY) {
        if (toAdd.length)    log(`[dry-run] would assign #${issue.number} -> ${toAdd.join(', ')}`);
        if (toRemove.length) log(`[dry-run] would unassign #${issue.number} <- ${toRemove.join(', ')}`);
      } else {
        gh(['issue', 'edit', String(issue.number), '--repo', REPO,
          ...toAdd.flatMap((l) => ['--add-assignee', l]),
          ...toRemove.flatMap((l) => ['--remove-assignee', l])]);
        if (toAdd.length)    log(`[mirror]   #${issue.number} assigned -> ${toAdd.join(', ')}`);
        if (toRemove.length) log(`[mirror]   #${issue.number} unassigned ${toRemove.join(', ')}`);
      }
    }
  }

  // close done / reopen regressed
  const shouldClose = f.status === 'done';
  if (!DRY) {
    if (shouldClose && issue.state !== 'CLOSED') gh(['issue', 'close', String(issue.number), '--repo', REPO, '--reason', 'completed']);
    if (!shouldClose && issue.state === 'CLOSED') gh(['issue', 'reopen', String(issue.number), '--repo', REPO]);
  }
  log(`[mirror]   #${issue.number} ${f.title}  ->  ${STATUS[f.status]?.col}${shouldClose ? ' (closed)' : ''}`);
}
log(DRY ? '[mirror] dry-run complete — nothing changed.' : '[mirror] board synced.');

// ═══════════════════════════════════════════════════════════════════════════════
// provider: jira — REST + Bearer PAT (Server / Data Center). NO MCP. Status only.
// ═══════════════════════════════════════════════════════════════════════════════

// Redact a resolved secret from any string BEFORE it reaches stderr/stdout, so a Jira
// response body that echoes the request headers (misconfigured URL, debug proxy, non-401/403
// error) can never print `Authorization: Bearer <PAT>` — the spec's hard "PAT never leaks to
// logs" invariant. Replaces (a) the raw PAT value, (b) the same value with a leading `Bearer `,
// and (c) any residual `Authorization: <...>` / `Bearer <token>` header echo, with a placeholder.
// Used at EVERY stderr site that can include a response body. No-op when pat is empty/absent.
function redactSecret(text, pat) {
  let out = String(text ?? '');
  const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (pat) {
    out = out.replace(new RegExp(`Bearer\\s+${escapeRe(pat)}`, 'g'), 'Bearer ***REDACTED***');
    out = out.replace(new RegExp(escapeRe(pat), 'g'), '***REDACTED***');
  }
  // Defensive: scrub any lingering Bearer-token / Authorization-header echo regardless of value.
  out = out.replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/g, 'Bearer ***REDACTED***');
  out = out.replace(/(Authorization"?\s*[:=]\s*"?)[^",}\s][^",}]*/gi, '$1***REDACTED***');
  return out;
}

// Resolve the PAT: JIRA_PAT env (precedence) else the gitignored pat_file (trimmed).
// Returns the token string, or null if neither is available. The VALUE is never logged.
function resolveJiraPat(patFile) {
  const env = process.env.JIRA_PAT;
  if (env && env.trim() !== '') return env.trim();
  try {
    if (patFile && existsSync(patFile)) {
      const v = readFileSync(patFile, 'utf8').replace(/\r?\n$/, '').trim();
      if (v !== '') return v;
    }
  } catch { /* unreadable file ⇒ treated as absent below */ }
  return null;
}

async function runJira(cfgText) {
  // --- config (validated BEFORE any network call / PAT read) ------------------
  const BASE_URL = (yamlGet(cfgText, ['mirror', 'board', 'base_url']) || '').replace(/\/+$/, '');
  const PROJECT_KEY = yamlGet(cfgText, ['mirror', 'board', 'project_key']) || '';
  const missing = [];
  if (!BASE_URL) missing.push('base_url');
  if (!PROJECT_KEY) missing.push('project_key');
  if (missing.length) {
    console.error(`[mirror] provider jira needs mirror.board.${missing.length > 1 ? `{${missing.join(',')}}` : missing[0]} set in harness.config.yaml (Jira Server/DC base URL + project key) — no Jira request was made.`);
    process.exit(1);
  }

  // --- transport scheme: HTTPS, enforced (E99-F157) ---------------------------
  // The PAT travels as `Authorization: Bearer <PAT>` on every request below, so a
  // plaintext base_url hands a long-lived credential to anyone on the path. Until this
  // check existed, three records ASSERTED https — the transport comment below, the
  // `mirror.board.base_url` docs in store/board-mirror.md, and the example config — and
  // none ENFORCED it, so a one-character typo silently downgraded the transport and the
  // sync kept working.
  //
  // Placed HERE, ahead of resolveJiraPat(), on purpose: store/board-mirror.md documents a
  // fail-closed ordering (config validated, THEN the PAT read), and honoring it means a
  // refused config never reads the credential off disk at all — not merely never sends it.
  // That is what the refusal messages below are able to promise.
  let baseUrl;
  try {
    baseUrl = new URL(BASE_URL);
  } catch {
    console.error(`[mirror] mirror.board.base_url is not an absolute URL (got '${BASE_URL}') — expected e.g. https://jira.acme.internal. No PAT was read and no Jira request was made.`);
    process.exit(1);
  }
  // LOOPBACK CARVE-OUT. Plaintext to loopback never reaches a network, so the threat this
  // guard closes has no path to be on — the same reasoning that makes loopback a secure
  // context in a browser. It is also what keeps the provider testable: this repo's own
  // jira suite drives a plaintext 127.0.0.1 stub, and `fetch` will not accept a
  // self-signed cert, so a strict rule would delete its own acceptance surface.
  //
  // Matched on the PARSED hostname against three literals, never on the raw string: a
  // `startsWith('http://127.0.0.1')` test passes `http://127.0.0.1.evil.com`, which is a
  // remote host with a reassuring prefix.
  const LOOPBACK_HOSTS = ['127.0.0.1', '::1', 'localhost'];
  const isLoopback = LOOPBACK_HOSTS.includes(baseUrl.hostname.replace(/^\[|\]$/g, ''));
  // `URL.protocol` is already lowercased, so `HTTPS://…` compares equal here while a
  // grep of the raw config text for 'https' would both miss it and accept `httpsx://`.
  if (baseUrl.protocol !== 'https:' && !isLoopback) {
    console.error(`[mirror] mirror.board.base_url must use https:// (got '${baseUrl.protocol}//') — the Jira PAT is sent as a Bearer token and must never travel in plaintext. Plain http:// is accepted only for loopback (${LOOPBACK_HOSTS.join(', ')}). No PAT was read and no Jira request was made.`);
    process.exit(1);
  }

  // --- PAT resolve + fail-closed preflight (before ANY network call) ----------
  // pat_file resolves relative to HARNESS_DIR (HERE/.. — same base as CONFIG_PATH/TASKS_PATH),
  // so the default is a BARE `jira.pat` that lands at <HARNESS_DIR>/jira.pat: `.harness/jira.pat`
  // in a consumer (the installer gitignores exactly that), `<repo>/jira.pat` in source. Do NOT
  // default to `.harness/jira.pat` — that would double-nest to `.harness/.harness/jira.pat` in a
  // consumer. An explicit override should likewise be bare-relative (or absolute) to avoid nesting.
  const rawPatFile = yamlGet(cfgText, ['mirror', 'board', 'pat_file']) || 'jira.pat';
  const patFile = isAbsolute(rawPatFile) ? rawPatFile : resolve(HERE, '..', rawPatFile);
  const PAT = resolveJiraPat(patFile);
  if (!PAT) {
    console.error(`[mirror] provider jira has no PAT — set the JIRA_PAT environment variable or create the gitignored PAT file '${rawPatFile}'. No Jira request was made. (The PAT value is never printed, committed, or written to tasks.json.)`);
    process.exit(1);
  }

  // --- issue-type + status maps (configurable, not hard-coded) ----------------
  // epic → Epic, feature → Story by default; overridable via mirror.board.issue_type_map.
  const issueTypeMap = yamlGetMap(cfgText, ['mirror', 'board', 'issue_type_map']);
  const EPIC_TYPE = issueTypeMap.epic || 'Epic';
  const FEATURE_TYPE = issueTypeMap.feature || 'Story';
  // Optional Jira Server/DC "Epic Name" custom field id (e.g. customfield_10011). On Software
  // Server/DC projects this field is often REQUIRED on the Epic create screen, so a create with
  // only project/summary/type/labels returns HTTP 400 and halts the sync. When set, we populate
  // it (with the epic summary) on epic creates only. Empty/absent ⇒ omitted (inert default).
  const EPIC_NAME_FIELD = (yamlGet(cfgText, ['mirror', 'board', 'epic_name_field']) || '').trim();
  // feature status → Jira workflow state via the provider-neutral status_map (identity default).
  const jiraStatusMap = yamlGetMap(cfgText, ['mirror', 'board', 'status_map']);
  const mapStatus = (s) => jiraStatusMap[s] || s;
  // assignee is a RECOGNIZED NO-OP for jira in F01 (status only; owner→assignee deferred to
  // E10-F03). We read it only to report the deferral; it is never sent to Jira.
  const assigneeCfg = yamlGet(cfgText, ['mirror', 'board', 'assignee']) || '';
  if (assigneeCfg) {
    log(`[mirror] jira: mirror.board.assignee is set but is a NO-OP for jira in F01 (owner→assignee deferred to E10-F03) — not wiring Jira's assignee field.`);
  }

  // --- REST transport: HTTPS to base_url with Authorization: Bearer <PAT> ------
  // Dependency-free: Node's built-in fetch. NO MCP, no new npm package. The PAT is only
  // ever placed in the Authorization header — never logged, never persisted.
  const API = `${BASE_URL}/rest/api/2`;
  const authHeader = () => ({ Authorization: `Bearer ${PAT}` });
  async function jiraFetch(method, path, body) {
    const headers = { ...authHeader(), Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const res = await fetch(`${API}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    if (res.status === 401 || res.status === 403) {
      // Fail closed with an actionable, PAT-FREE message (never echo the token).
      console.error(`[mirror] Jira returned HTTP ${res.status} (authentication/authorization failed). Check that the PAT (JIRA_PAT env or pat_file) is valid and has permission on project ${PROJECT_KEY} at ${BASE_URL}. The PAT value is not shown.`);
      process.exit(1);
    }
    if (!res.ok) {
      // A non-401/403 body can echo the request headers (bad URL / debug proxy) and print the
      // Bearer PAT — scrub the resolved PAT (and any Bearer/Authorization echo) before logging.
      const rawDetail = await res.text().catch(() => '');
      const detail = redactSecret(rawDetail, PAT).slice(0, 300);
      console.error(`[mirror] Jira REST ${method} ${path} failed: HTTP ${res.status}${detail ? ` — ${detail}` : ''}`);
      process.exit(1);
    }
    const text = await res.text();
    return text ? JSON.parse(text) : {};
  }

  // --- load + flatten tasks.json (READ ONLY — one-way; never written back) ----
  const data = JSON.parse(readFileSync(TASKS_PATH, 'utf8'));
  const epics = data.epics.map((e) => ({
    id: e.id, summary: `${e.id} — ${e.title}`, kind: 'epic', type: EPIC_TYPE, status: undefined,
  }));
  const features = data.epics.flatMap((e) =>
    (e.features || []).map((f) => ({
      id: f.id, summary: `${f.id} — ${f.title}`, kind: 'feature', type: FEATURE_TYPE, status: f.status,
    })),
  );
  const objects = [...epics, ...features];
  log(`[mirror] jira: ${epics.length} epics, ${features.length} features -> ${BASE_URL} project ${PROJECT_KEY}${DRY ? ' (dry-run)' : ''}`);

  // Reconcile match key: a stable per-id label `harness:<id>` stored on the issue, searched
  // via JQL. Idempotent — a re-run finds the existing issue and transitions it in place.
  const labelFor = (id) => `harness:${id}`;

  for (const obj of objects) {
    const label = labelFor(obj.id);
    // find-or-create by the stable feature-id label (idempotent reconcile).
    const jql = `project = ${PROJECT_KEY} AND labels = ${label}`;
    const found = await jiraFetch('GET', `/search?jql=${encodeURIComponent(jql)}&fields=status&maxResults=1`);
    let issueKey = (found.issues && found.issues[0] && found.issues[0].key) || null;

    if (!issueKey) {
      if (DRY) {
        log(`[dry-run] would create ${obj.type} issue for ${obj.id}: "${obj.summary}" (label ${label})`);
      } else {
        const fields = {
          project: { key: PROJECT_KEY },
          summary: obj.summary,
          issuetype: { name: obj.type },
          labels: [label],
        };
        // Populate the optional "Epic Name" custom field on EPIC creates only, when configured.
        // Avoids HTTP 400 on Server/DC projects that require it; inert when unset.
        if (obj.kind === 'epic' && EPIC_NAME_FIELD) {
          fields[EPIC_NAME_FIELD] = obj.summary;
        }
        const created = await jiraFetch('POST', '/issue', { fields });
        issueKey = created.key;
        log(`[mirror] jira: created ${obj.type} ${issueKey} for ${obj.id}`);
      }
    } else {
      log(`[mirror] jira: reconciling existing ${issueKey} for ${obj.id} (no duplicate)`);
    }

    // Transition status — features only (epics carry no feature status/column). The target
    // workflow-state name comes from status_map (identity default); nothing hard-coded.
    if (obj.kind === 'feature') {
      const wantState = mapStatus(obj.status);
      if (DRY) {
        log(`[dry-run] would transition ${issueKey || `<${obj.id}>`} -> "${wantState}"`);
      } else if (issueKey) {
        const tr = await jiraFetch('GET', `/issue/${issueKey}/transitions`);
        // Match by DESTINATION workflow state only: accept a transition ONLY when its
        // `to.name` is the mapped wantState. A transition whose action `name` happens to equal
        // wantState but lands on a DIFFERENT `to.name` must never be selected — otherwise the
        // mirror moves the issue to the wrong state while logging success. No name-based
        // fallback. If none lands on wantState, leave the issue unchanged and say so.
        const t = (tr.transitions || []).find((x) => x.to && x.to.name === wantState);
        if (t) {
          await jiraFetch('POST', `/issue/${issueKey}/transitions`, { transition: { id: t.id } });
          log(`[mirror] jira: ${issueKey} -> "${wantState}"`);
        } else {
          log(`[mirror] jira: ${issueKey} no matching transition to "${wantState}" (already there or unavailable — left as-is)`);
        }
      }
    }
  }
  log(DRY ? '[mirror] jira dry-run complete — nothing changed.' : '[mirror] jira board synced.');
}
