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
//   jira            -> STUB (recognized, not implemented yet — see store/board-mirror.md).
//   azure-boards    -> STUB (recognized, not implemented yet — see store/board-mirror.md).
//
// All provider config lives in harness.config.yaml under `mirror.board` — nothing about a
// specific org/repo/tool is hard-coded here. Status columns default to the harness status
// names verbatim (identity map), so the board is not tied to any one team's column naming.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const CONFIG_PATH = resolve(HERE, '../harness.config.yaml');   // .harness/harness.config.yaml in a consumer
const TASKS_PATH = resolve(HERE, '../state/tasks.json');
const DRY = process.argv.includes('--dry-run');
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
if (provider === 'jira' || provider === 'azure-boards') {
  log(`[mirror] provider '${provider}' is recognized but NOT IMPLEMENTED yet (stub).`);
  log('[mirror] tasks.json is unchanged. See store/board-mirror.md to implement it.');
  process.exit(0);   // inert no-op: a known-but-unwired provider must never block the loop
}
if (provider !== 'github-projects') {
  console.error(`[mirror] unknown provider '${provider}'. Use one of: none, github-projects, jira, azure-boards.`);
  process.exit(1);
}

// ── provider: github-projects ────────────────────────────────────────────────
const OWNER = yamlGet(cfgText, ['mirror', 'board', 'owner']) || '';
const PROJECT_NUMBER = Number(yamlGet(cfgText, ['mirror', 'board', 'project_number']) || 0);
const REPO = yamlGet(cfgText, ['mirror', 'board', 'repo']) || '';
if (!OWNER || !PROJECT_NUMBER || !REPO) {
  console.error('[mirror] provider github-projects needs mirror.board.{owner,project_number,repo} set in harness.config.yaml.');
  process.exit(1);
}
try { execFileSync('gh', ['--version'], { stdio: 'ignore' }); }
catch { console.error("[mirror] `gh` CLI not found — github-projects needs gh authed with 'project' + 'repo' scopes."); process.exit(1); }

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

function gh(args, input) { return execFileSync('gh', args, { encoding: 'utf8', input, maxBuffer: 1 << 24 }); }
function ghJson(args) { return JSON.parse(gh(args)); }
function graphql(query, variables) {
  return JSON.parse(gh(['api', 'graphql', '--input', '-'], JSON.stringify({ query, variables })));
}

// --- load + flatten tasks.json ------------------------------------------------
const data = JSON.parse(readFileSync(TASKS_PATH, 'utf8'));
const epics = data.epics.map((e) => ({ id: e.id, label: `${e.id} — ${e.title}` }));
const features = data.epics.flatMap((e) =>
  (e.features || []).map((f) => ({
    id: f.id, title: `${f.id} — ${f.title}`, status: f.status, epicLabel: `${e.id} — ${e.title}`,
  })),
);
log(`[mirror] github-projects: ${epics.length} epics, ${features.length} features -> ${OWNER}/#${PROJECT_NUMBER}`);

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
const epicOptionId = ensureOptions('Epic', epics.map((e, i) => ({
  name: e.label, color: EPIC_COLORS[i % EPIC_COLORS.length],
})));
const STATUS_FIELD_ID = fieldByName('Status').id;
const EPIC_FIELD_ID = fieldByName('Epic').id;

// --- existing issues + items --------------------------------------------------
const issues = ghJson(['issue', 'list', '--repo', REPO, '--state', 'all', '--limit', '500',
  '--json', 'number,title,url,state']);
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
    issue = { number, title: f.title, url, state: 'OPEN' };
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

  // close done / reopen regressed
  const shouldClose = f.status === 'done';
  if (!DRY) {
    if (shouldClose && issue.state !== 'CLOSED') gh(['issue', 'close', String(issue.number), '--repo', REPO, '--reason', 'completed']);
    if (!shouldClose && issue.state === 'CLOSED') gh(['issue', 'reopen', String(issue.number), '--repo', REPO]);
  }
  log(`[mirror]   #${issue.number} ${f.title}  ->  ${STATUS[f.status]?.col}${shouldClose ? ' (closed)' : ''}`);
}
log(DRY ? '[mirror] dry-run complete — nothing changed.' : '[mirror] board synced.');
