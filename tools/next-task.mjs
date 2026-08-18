#!/usr/bin/env node
// Deterministic, read-only TaskStore selector (E16-F03).

import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const HARNESS = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const FEATURE_RE = /^E(\d+)-F(\d+)$/;
const EPIC_RE = /^E(\d+)$/;
const SLICE_RE = /^E(\d+)-F(\d+)@([a-z0-9-]+)$/;
const EPIC_STATUSES = new Set(['draft', 'planned', 'pending', 'in-progress', 'done']);
const FEATURE_STATUSES = new Set(['pending', 'spec-ready', 'in-progress', 'in-review', 'done']);
const SLICE_STATUSES = new Set([...FEATURE_STATUSES, 'failed']);
const BLOCKED_SUMMARY = 'no actionable work: selection blocked; see reasons above';
// E99-F77: a park may name WHO releases it. `gate: "owner"` is the one case the board
// could not express — the automatable slice is finished and every remaining requirement
// is a person's (a console attestation, a deploy approval, a signature). `in-progress`
// routes a Builder at work that does not exist, `in-review` routes a Reviewer at an
// approved slice, `done` is false; so the item was selected, skipped by hand, and the
// reason re-derived from progress/history.md every session.
// A DISCRIMINATOR on the existing park, not a second mechanism: everything that already
// honours a park — both validators, set-status's refusal, the inline naming a dependent
// gets — honours this unchanged. A parallel `owner_gated` field would have to be taught
// to each of them separately, and any one that learned only the park would keep routing
// a gated item, which is precisely the bug being fixed.
const OWNER_GATE = 'owner';
// THE CLOSED ENUM IS THE GUARD, AND THAT IS TRUE ONLY WHILE THIS SET HAS ONE MEMBER.
// Measured, not asserted: loosening `isOwnerGated` below from `=== OWNER_GATE` to
// `!== undefined` left all 10 cases of tests/test_owner_gate.sh green (E99-F77 mutation
// M3) — the two are genuinely equivalent today, because validateBoard rejects every gate
// value except exactly `owner` BEFORE any blocker is computed. A sweep of 20
// JSON-expressible values (including null, [], {}, "__proto__", "constructor") produced a
// hard input-error for all but `owner`. Deleting the enum check instead (M4) killed the
// suite immediately, and M3+M4 together killed it — so the enforcement lives there.
// ⚠️ THE EQUIVALENCE EXPIRES THE MOMENT A SECOND GATE IS ADDED HERE. With `vendor` beside
// `owner`, the strict comparison becomes load-bearing and NO test currently catches its
// loosening. If you add one, add an assertion that a non-owner gate does NOT report as
// `gated-owner`, or you inherit a hole this comment is the only record of.
const PARK_GATES = new Set([OWNER_GATE]);
const isOwnerGated = (feature) => Boolean(feature.parked) && feature.parked.gate === OWNER_GATE;
// E99-F102 landing attestation. CLOSED, like the park gates and for the same reason: the
// three values say who proved what. Today only two are writable — `unchecked` (recorded,
// nothing checked it: tasks-lock performs no verification yet) and `declared` (there is no
// commit to prove). `ancestor` (resolved and proved reachable from the default branch) is
// accepted so a board from the verification follow-up, or a hand edit, still parses. A
// fourth value would be a check nothing performs.
const LANDED_VERIFIED = new Set(['ancestor', 'unchecked', 'declared']);

class ExpectedError extends Error {
  constructor(code, detail) {
    super(detail);
    this.code = code;
  }
}

function envelope(mode, outcome, selected, reason, blocked = [], summary = null) {
  return { schema_version: 1, mode, outcome, selected, reason, blocked, summary };
}

function emit(result, diagnostic = null, exitCode = 0) {
  process.stdout.write(`${JSON.stringify(result)}\n`);
  if (diagnostic) process.stderr.write(`next-task: ${diagnostic}\n`);
  if (exitCode) process.exitCode = exitCode;
}

function parseArgs(argv) {
  const out = { mode: 'board', feature: null, tasks: null, config: null };
  const seen = new Set();
  const values = new Set(['--feature', '--tasks', '--config']);
  const flags = new Set(['--json', '--mine']);
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!flags.has(arg) && !values.has(arg)) {
      throw new ExpectedError('usage-error', `unknown or positional argument ${JSON.stringify(arg)}`);
    }
    if (seen.has(arg)) throw new ExpectedError('usage-error', `duplicate option ${arg}`);
    seen.add(arg);
    if (values.has(arg)) {
      const value = argv[++i];
      if (value === undefined || value === '' || value.startsWith('--')) {
        throw new ExpectedError('usage-error', `${arg} requires a non-empty value`);
      }
      if (arg === '--feature') out.feature = value;
      if (arg === '--tasks') out.tasks = value;
      if (arg === '--config') out.config = value;
    }
  }
  if (seen.has('--mine') && out.feature !== null) {
    throw new ExpectedError('usage-error', '--mine and --feature are mutually exclusive');
  }
  if (out.feature !== null) {
    if (!FEATURE_RE.test(out.feature)) throw new ExpectedError('usage-error', `invalid feature id ${out.feature}`);
    out.mode = 'target';
  } else if (seen.has('--mine')) {
    out.mode = 'mine';
  }
  return out;
}

function stripComment(value) {
  let quote = null;
  for (let i = 0; i < value.length; i += 1) {
    const ch = value[i];
    if ((ch === '"' || ch === "'") && (quote === null || quote === ch)) quote = quote === ch ? null : ch;
    if (ch === '#' && quote === null && (i === 0 || /\s/.test(value[i - 1]))) return value.slice(0, i);
  }
  if (quote !== null) throw new Error('unterminated quoted scalar');
  return value;
}

function scalar(raw, subject) {
  const value = stripComment(raw).trim();
  if (value === '') return '';
  if (value[0] === '"' || value[0] === "'") {
    if (value.at(-1) !== value[0]) throw new Error(`${subject} has an unterminated quoted scalar`);
    return value.slice(1, -1);
  }
  if (/[\[\]{}]/.test(value)) throw new Error(`${subject} must be a scalar`);
  return value;
}

function relevantConfig(text) {
  const wanted = new Map([
    ['workflow.require_spec_approval', 'true'],
    ['workflow.identity', ''],
    ['umbrella.manifest', ''],
  ]);
  const found = new Set();
  const foundParents = new Set();
  const stack = [];
  for (const [index, raw] of text.split(/\r?\n/).entries()) {
    if (!raw.trim() || /^\s*#/.test(raw)) continue;
    if (/\t/.test(raw.match(/^\s*/)?.[0] || '')) throw new Error(`config line ${index + 1} uses tab indentation`);
    const indent = raw.length - raw.replace(/^\s+/, '').length;
    const clean = stripComment(raw);
    while (stack.length && indent <= stack.at(-1).indent) stack.pop();
    const relevantParent = stack[0]?.key;
    if ((relevantParent === 'workflow' || relevantParent === 'umbrella') && stack.length) {
      const parent = stack.at(-1);
      if (parent.childIndent === null) {
        parent.childIndent = indent;
      } else if (indent !== parent.childIndent) {
        throw new Error(`invalid indentation in ${relevantParent} mapping at config line ${index + 1}`);
      }
    }
    const match = clean.match(/^\s*([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) {
      if ((relevantParent === 'workflow' || relevantParent === 'umbrella') &&
          indent > stack[0].indent) {
        throw new Error(`malformed ${relevantParent} mapping entry at config line ${index + 1}`);
      }
      continue;
    }
    const path = [...stack.map((item) => item.key), match[1]].join('.');
    if (indent === 0 && (match[1] === 'workflow' || match[1] === 'umbrella')) {
      if (foundParents.has(match[1])) throw new Error(`duplicate config key ${match[1]}`);
      foundParents.add(match[1]);
      if (match[2].trim() !== '') throw new Error(`config ${match[1]} must be a mapping`);
    }
    if (wanted.has(path)) {
      if (found.has(path)) throw new Error(`duplicate config key ${path}`);
      found.add(path);
      wanted.set(path, scalar(match[2], path));
    }
    if (match[2].trim() === '') stack.push({ indent, key: match[1], childIndent: null });
  }
  const approval = wanted.get('workflow.require_spec_approval');
  if (approval !== 'true' && approval !== 'false') {
    throw new Error('workflow.require_spec_approval must be true or false');
  }
  return {
    requireApproval: approval === 'true',
    identity: wanted.get('workflow.identity'),
    manifest: wanted.get('umbrella.manifest'),
  };
}

function manifestRepos(text) {
  const lines = text.split(/\r?\n/);
  let parentIndent = null;
  let childIndent = null;
  let seenRepos = false;
  const repos = new Set();
  for (let index = 0; index < lines.length; index += 1) {
    const raw = lines[index];
    if (!raw.trim() || /^\s*#/.test(raw)) continue;
    if (/\t/.test(raw.match(/^\s*/)?.[0] || '')) throw new Error(`manifest line ${index + 1} uses tab indentation`);
    const indent = raw.length - raw.replace(/^\s+/, '').length;
    const clean = stripComment(raw);
    const match = clean.match(/^\s*([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) {
      if (parentIndent !== null && indent > parentIndent) throw new Error(`malformed repos entry at manifest line ${index + 1}`);
      continue;
    }
    const [, key, rawValue] = match;
    if (parentIndent !== null && indent <= parentIndent) {
      parentIndent = null;
      childIndent = null;
    }
    if (parentIndent === null) {
      if (indent === 0 && key === 'repos') {
        if (seenRepos) throw new Error('duplicate manifest key repos');
        if (rawValue.trim() !== '') throw new Error('manifest repos must be a mapping');
        seenRepos = true;
        parentIndent = indent;
      }
      continue;
    }
    if (childIndent === null) childIndent = indent;
    if (indent === childIndent) {
      if (rawValue.trim() !== '') throw new Error(`manifest repo ${key} must be a mapping`);
      if (repos.has(key)) throw new Error(`duplicate manifest repo ${key}`);
      repos.add(key);
    }
  }
  if (!seenRepos) throw new Error('manifest is missing repos mapping');
  return repos;
}

function assertObject(value, subject) {
  if (value === null || Array.isArray(value) || typeof value !== 'object') throw new Error(`${subject} must be an object`);
}
function assertString(value, subject) {
  if (typeof value !== 'string' || value === '') throw new Error(`${subject} must be a non-empty string`);
}
function assertOptionalBoolean(value, subject) {
  if (value !== undefined && typeof value !== 'boolean') throw new Error(`${subject} must be boolean`);
}
function assertDependencies(value, subject) {
  if (value === undefined) return;
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string' || item === '')) {
    throw new Error(`${subject} must be an array of non-empty strings`);
  }
}

function validateBoard(board) {
  assertObject(board, 'TaskStore root');
  assertString(board.project, 'TaskStore project');
  if (!Array.isArray(board.epics)) throw new Error('TaskStore epics must be an array');
  const epicIds = new Set();
  const featureIds = new Set();
  const sliceIds = new Set();
  const epics = [];
  for (const [ei, epic] of board.epics.entries()) {
    const es = `epics[${ei}]`;
    assertObject(epic, es);
    assertString(epic.id, `${es}.id`);
    const em = EPIC_RE.exec(epic.id);
    if (!em) throw new Error(`${es}.id ${epic.id} is invalid`);
    if (epicIds.has(epic.id)) throw new Error(`duplicate epic id ${epic.id}`);
    epicIds.add(epic.id);
    assertString(epic.title, `${epic.id}.title`);
    if (!EPIC_STATUSES.has(epic.status)) throw new Error(`${epic.id}.status ${String(epic.status)} is unsupported`);
    if (epic.owner !== undefined && typeof epic.owner !== 'string') throw new Error(`${epic.id}.owner must be a string`);
    if (!Array.isArray(epic.features)) throw new Error(`${epic.id}.features must be an array`);
    const features = [];
    for (const [fi, feature] of epic.features.entries()) {
      const fs = `${epic.id}.features[${fi}]`;
      assertObject(feature, fs);
      assertString(feature.id, `${fs}.id`);
      const fm = FEATURE_RE.exec(feature.id);
      if (!fm) throw new Error(`${fs}.id ${feature.id} is invalid`);
      if (Number(fm[1]) !== Number(em[1])) throw new Error(`${feature.id} is inconsistent with containing epic ${epic.id}`);
      if (featureIds.has(feature.id)) throw new Error(`duplicate feature id ${feature.id}`);
      featureIds.add(feature.id);
      assertString(feature.title, `${feature.id}.title`);
      if (!FEATURE_STATUSES.has(feature.status)) throw new Error(`${feature.id}.status ${String(feature.status)} is unsupported`);
      if (typeof feature.sdd !== 'boolean') throw new Error(`${feature.id}.sdd must be boolean`);
      assertString(feature.spec_path, `${feature.id}.spec_path`);
      assertOptionalBoolean(feature.autonomous, `${feature.id}.autonomous`);
      if (feature.owner !== undefined && typeof feature.owner !== 'string') throw new Error(`${feature.id}.owner must be a string`);
      assertDependencies(feature.depends_on, `${feature.id}.depends_on`);
      // E06-F07: this selector carries its OWN validator, independent of the shared one
      // init.sh runs — so the park has to be checked here too, or a board reaching the
      // selector through --tasks (or edited after init.sh) is consumed unvalidated. The
      // consequences were concrete: `"parked": null` is falsy, so the park was silently
      // IGNORED and the feature selected; a string or `{}` produced a blocker reading
      // "undefined". Every one of those boards is already rejected by the schema and the
      // shared validator, so the selector was the only component disagreeing.
      if (feature.parked !== undefined) {
        assertObject(feature.parked, `${feature.id}.parked`);
        assertString(feature.parked.reason, `${feature.id}.parked.reason`);
        if (feature.parked.unblocked_by !== undefined) assertString(feature.parked.unblocked_by, `${feature.id}.parked.unblocked_by`);
        // E99-F77: an unrecognised gate is REJECTED, not degraded to a plain park. The
        // reason code is the deliverable; a typo that quietly reads as `parked` would
        // report the wrong one, which is worse than no gate at all. Checked here as well
        // as in the shared validator for the E06-F07 reason: a board arriving through
        // --tasks reaches this selector without passing the shared validator at all.
        if (feature.parked.gate !== undefined && !PARK_GATES.has(feature.parked.gate)) {
          throw new Error(`${feature.id}.parked.gate ${JSON.stringify(feature.parked.gate)} is unsupported (expected one of: ${[...PARK_GATES].join(', ')})`);
        }
        // A park means "not yet workable"; `done` means finished. The combination is
        // meaningless, and it is unreachable through the sanctioned path (set-status
        // refuses a transition while parked), so it can only arrive by hand-editing.
        // Left legal, it would also defeat the targeting contract: select() short-circuits
        // a done target to `target-complete` before any blocker is computed.
        if (feature.status === 'done') throw new Error(`${feature.id} is done and cannot be parked`);
      }
      // E99-F102: the landing attestation, checked here for the same reason the park is
      // — a board arriving through --tasks never passes the shared validator, so a
      // selector that accepted `"landed": {"verified": "probably"}` would be the one
      // component reading an attestation nobody performed as if somebody had.
      if (feature.landed !== undefined) {
        assertObject(feature.landed, `${feature.id}.landed`);
        assertString(feature.landed.ref, `${feature.id}.landed.ref`);
        if (!LANDED_VERIFIED.has(feature.landed.verified)) {
          throw new Error(`${feature.id}.landed.verified ${JSON.stringify(feature.landed.verified)} is unsupported (expected one of: ${[...LANDED_VERIFIED].join(', ')})`);
        }
        for (const k of ['repo', 'base', 'commit']) {
          if (feature.landed[k] !== undefined) assertString(feature.landed[k], `${feature.id}.landed.${k}`);
        }
        // E99-F129: an `ancestor` names the FULL proof set — `commit` (`ref` may be a
        // MOVING branch), `repo` (a commit id proves nothing until you know where to look
        // for it) and `base` (`ancestor of` has a second operand). Any one missing and the
        // claim cannot be re-checked, which is the defect, not a milder form of it.
        // Unsliced only — a sliced feature's `ref` is a joined summary of several
        // repositories and each slice carries its own set.
        if (feature.landed.verified === 'ancestor' && feature.landed.slices === undefined) {
          for (const k of ['commit', 'repo', 'base']) {
            if (!feature.landed[k]) {
              throw new Error(`${feature.id}.landed.verified ancestor has no ${k}: a proof must name the commit it was checked on, the repository it was checked in, and the base it was checked against`);
            }
          }
        }
        // A SLICED feature's evidence is bound per slice repository, so the record
        // carries one entry per repo — where a per-repository verdict will land.
        // Checked here for the same reason the rest of `landed` is — a board arriving
        // through --tasks never passes the shared validator — and held to the same
        // acceptance surface as the schema and validate-board.py.
        if (feature.landed.slices !== undefined) {
          if (!Array.isArray(feature.landed.slices) || feature.landed.slices.length === 0) {
            throw new Error(`${feature.id}.landed.slices must be a non-empty array`);
          }
          for (const [li, rec] of feature.landed.slices.entries()) {
            const ls = `${feature.id}.landed.slices[${li}]`;
            assertObject(rec, ls);
            assertString(rec.repo, `${ls}.repo`);
            assertString(rec.ref, `${ls}.ref`);
            if (rec.commit !== undefined) assertString(rec.commit, `${ls}.commit`);
            // The same full proof set as an unsliced feature-level record; `repo` is
            // already required above for every slice record, proved or not.
            if (rec.verified === 'ancestor') {
              for (const k of ['commit', 'base']) {
                if (!rec[k]) {
                  throw new Error(`${ls}.verified ancestor has no ${k}: a proof must name the commit it was checked on and the base it was checked against`);
                }
              }
            }
            if (!LANDED_VERIFIED.has(rec.verified)) {
              throw new Error(`${ls}.verified ${JSON.stringify(rec.verified)} is unsupported (expected one of: ${[...LANDED_VERIFIED].join(', ')})`);
            }
            if (rec.base !== undefined) assertString(rec.base, `${ls}.base`);
          }
          // The rollup is never stronger than its slices: one unproved slice and the
          // feature-level record cannot read `ancestor`.
          if (feature.landed.verified === 'ancestor' && feature.landed.slices.some((rec) => rec.verified !== 'ancestor')) {
            throw new Error(`${feature.id}.landed.verified ancestor claims more than was proved: a slice landing is not ancestor`);
          }
        }
      }
      const slices = [];
      if (feature.slices !== undefined) {
        if (!Array.isArray(feature.slices) || feature.slices.length === 0) throw new Error(`${feature.id}.slices must be a non-empty array`);
        for (const [si, slice] of feature.slices.entries()) {
          const ss = `${feature.id}.slices[${si}]`;
          assertObject(slice, ss);
          assertString(slice.id, `${ss}.id`);
          const sm = SLICE_RE.exec(slice.id);
          if (!sm || !slice.id.startsWith(`${feature.id}@`)) throw new Error(`${slice.id} is inconsistent with containing feature ${feature.id}`);
          if (sliceIds.has(slice.id)) throw new Error(`duplicate slice id ${slice.id}`);
          sliceIds.add(slice.id);
          assertString(slice.repo, `${slice.id}.repo`);
          if (slice.repo !== sm[3]) throw new Error(`${slice.id}.repo is inconsistent with its id`);
          if (!SLICE_STATUSES.has(slice.status)) throw new Error(`${slice.id}.status ${String(slice.status)} is unsupported`);
          assertOptionalBoolean(slice.merged, `${slice.id}.merged`);
          assertDependencies(slice.depends_on, `${slice.id}.depends_on`);
          slices.push({ ...slice, feature });
        }
        if (feature.status === 'done' && slices.some((slice) => slice.status !== 'done' || slice.merged !== true)) {
          throw new Error(`${feature.id}.status done requires every slice to be done and merged`);
        }
      }
      features.push({ ...feature, epic, slices });
    }
    epics.push({ ...epic, features });
  }
  return { epics, features: epics.flatMap((epic) => epic.features), slices: epics.flatMap((epic) => epic.features.flatMap((feature) => feature.slices)) };
}

function idKey(id) {
  let match = SLICE_RE.exec(id);
  if (match) return [Number(match[1]), Number(match[2]), 1, match[3], id];
  match = FEATURE_RE.exec(id);
  if (match) return [Number(match[1]), Number(match[2]), 0, '', id];
  match = EPIC_RE.exec(id);
  if (match) return [Number(match[1]), -1, -1, '', id];
  return [Number.MAX_SAFE_INTEGER, Number.MAX_SAFE_INTEGER, 2, String(id), String(id)];
}
function compareIds(a, b) {
  const ka = idKey(a), kb = idKey(b);
  for (let i = 0; i < ka.length; i += 1) {
    if (typeof ka[i] === 'number' && ka[i] !== kb[i]) return ka[i] - kb[i];
    if (typeof ka[i] === 'string' && ka[i] !== kb[i]) return ka[i] < kb[i] ? -1 : 1;
  }
  return 0;
}
const sortedUnique = (items) => [...new Set(items)].sort(compareIds);

function cycleMap(records, kind) {
  const byId = new Map(records.map((record) => [record.id, record]));
  const adjacency = new Map();
  for (const record of records) {
    adjacency.set(record.id, sortedUnique((record.depends_on || []).filter((id) => byId.has(id))));
  }
  // Iterative Kosaraju, matching tools/task-diagnostics.py.
  const ordered = [...byId.keys()].sort(compareIds);
  const seen = new Set(), finish = [];
  for (const start of ordered) {
    if (seen.has(start)) continue;
    seen.add(start);
    const stack = [[start, 0]];
    while (stack.length) {
      const top = stack.at(-1), neighbors = adjacency.get(top[0]);
      if (top[1] < neighbors.length) {
        const neighbor = neighbors[top[1]++];
        if (!seen.has(neighbor)) { seen.add(neighbor); stack.push([neighbor, 0]); }
      } else {
        finish.push(top[0]); stack.pop();
      }
    }
  }
  const reverse = new Map(ordered.map((id) => [id, []]));
  for (const [id, neighbors] of adjacency) for (const neighbor of neighbors) reverse.get(neighbor).push(id);
  for (const neighbors of reverse.values()) neighbors.sort(compareIds);
  seen.clear();
  const result = new Map();
  for (const start of [...finish].reverse()) {
    if (seen.has(start)) continue;
    const component = [], stack = [start]; seen.add(start);
    while (stack.length) {
      const id = stack.pop(); component.push(id);
      for (const neighbor of [...reverse.get(id)].reverse()) if (!seen.has(neighbor)) { seen.add(neighbor); stack.push(neighbor); }
    }
    component.sort(compareIds);
    if (component.length === 1 && !adjacency.get(component[0]).includes(component[0])) continue;
    const root = component[0], allowed = new Set(component);
    let witness;
    if (adjacency.get(root).includes(root)) witness = [root, root];
    else {
      const first = adjacency.get(root).filter((id) => allowed.has(id)).sort(compareIds)[0];
      const queue = [first], previous = new Map([[first, null]]);
      while (queue.length) {
        const id = queue.shift();
        if (id === root) break;
        for (const neighbor of adjacency.get(id)) {
          if (allowed.has(neighbor) && !previous.has(neighbor)) { previous.set(neighbor, id); queue.push(neighbor); }
        }
      }
      const path = [];
      for (let id = root; id !== null; id = previous.get(id)) path.push(id);
      witness = [root, ...path.reverse()];
    }
    const detail = `dependency cycle (${kind}): ${witness.join(' -> ')}`;
    for (const id of component) result.set(id, detail);
  }
  return result;
}

function featureRoute(feature, requireApproval) {
  if (feature.status === 'pending') {
    if (feature.sdd) return 'architect';
    return feature.autonomous === true ? 'builder' : null;
  }
  if (feature.status === 'spec-ready') return (!requireApproval || feature.autonomous === true) ? 'builder' : null;
  if (feature.status === 'in-progress') return 'builder';
  if (feature.status === 'in-review') return 'reviewer';
  return null;
}

// parkDetail — the reason a feature is held, plus what would release it when recorded.
// `reason` is guaranteed non-empty by the schema, so this never renders an empty park.
function parkDetail(feature) {
  const park = feature.parked;
  return park.unblocked_by ? `${park.reason} (unblocked by: ${park.unblocked_by})` : park.reason;
}

function featureBlockers(feature, featureById, cycles, requireApproval) {
  const records = [];
  if (cycles.has(feature.id)) records.push({ subject: feature.id, code: 'dependency-cycle', detail: cycles.get(feature.id) });
  if (feature.epic.status === 'draft') records.push({ subject: feature.id, code: 'gated-epic', detail: `epic ${feature.epic.id} is draft` });
  // E06-F07: a park is a BLOCKER, never a route. Pushed here — beside `gated-epic`, the
  // codebase's existing answer to "exists, understood, not actionable" — and deliberately
  // NOT reflected in featureRoute(): that is what makes "unparking restores exactly the
  // prior routing" true by construction, with no prior state to record or restore.
  // Listed before unmet-dependency because the park is the fact the reader needs first.
  // The detail names the route the feature would take once unparked. That is the question
  // an operator actually has while reading a park ("is this still classified as needing a
  // spec?") — the mislabelling it answers is the defect this whole feature exists to fix.
  // It is also what makes "a park is a blocker, NOT a route" observable: featureRoute is
  // called here with the park in place and must still return the real route. Nulling the
  // route when parked produces identical selection behaviour, so without this line that
  // design rule had no consequence any test could see.
  if (feature.parked) {
    const wouldRoute = featureRoute(feature, requireApproval) || 'none';
    // E99-F77: an owner gate reports as `gated-owner`, beside `gated-epic` and
    // `human-gate` in the E16-F01 vocabulary, so the Orchestrator can tell "come back
    // when the board moves" from "no agent will ever advance this" WITHOUT reading
    // progress/history.md. The route is still named — the release condition changes who
    // acts, not where the feature resumes.
    records.push(isOwnerGated(feature)
      ? { subject: feature.id, code: 'gated-owner', detail: `owner gate: ${parkDetail(feature)} [a person must act, not an agent; route when released: ${wouldRoute}]` }
      : { subject: feature.id, code: 'parked', detail: `${parkDetail(feature)} [route when unparked: ${wouldRoute}]` });
  }
  const unmet = sortedUnique((feature.depends_on || []).filter((id) => !featureById.has(id) || featureById.get(id).status !== 'done'));
  if (unmet.length) {
    // A parked dependency is named inline (E06-F07): without it a stalled chain reports a
    // generic `unmet-dependency` and the reason is invisible one hop away.
    const detail = unmet.map((id) => {
      if (!featureById.has(id)) return `${id}=missing`;
      const dep = featureById.get(id);
      if (!dep.parked) return `${id}=${dep.status}`;
      // E99-F77: name the gate KIND one hop away too. "parked" tells a reader to wait;
      // "owner gate" tells them waiting will never clear it.
      return `${id}=${dep.status} (${isOwnerGated(dep) ? 'owner gate' : 'parked'}: ${parkDetail(dep)})`;
    }).join(', ');
    records.push({ subject: feature.id, code: 'unmet-dependency', detail: `blocking dependencies: ${detail}` });
  }
  if (feature.status === 'spec-ready' && requireApproval && feature.autonomous !== true) {
    records.push({ subject: feature.id, code: 'human-gate', detail: 'spec-ready requires approval' });
  } else if (feature.status === 'pending' && !feature.sdd && feature.autonomous !== true) {
    records.push({ subject: feature.id, code: 'human-gate', detail: 'gated quick fix requires approval' });
  }
  return records;
}

function selectedRecord(feature, slice, route) {
  return {
    feature_id: feature.id,
    slice_id: slice ? slice.id : null,
    kind: slice ? 'slice' : 'feature',
    status: slice ? slice.status : feature.status,
    route,
  };
}
function selectedResult(mode, feature, slice, route, code) {
  const selected = selectedRecord(feature, slice, route);
  const selectedId = slice ? slice.id : feature.id;
  return envelope(mode, 'selected', selected, { code, detail: `route ${route} for ${selectedId} at status ${selected.status}` });
}

function slicePhase(mode, feature, repos) {
  const slices = [...feature.slices].sort((a, b) => compareIds(a.id, b.id));
  const byId = new Map(slices.map((slice) => [slice.id, slice]));
  const missingRepo = (slice) => {
    if (!repos.has(slice.repo)) throw new ExpectedError('manifest-error', `slice ${slice.id} references repository ${slice.repo} missing from umbrella manifest`);
  };
  const failed = slices.filter((slice) => slice.status === 'failed')[0];
  if (failed) {
    return envelope(mode, 'halted', null, { code: 'slice-failed', detail: `slice ${failed.id} is failed` });
  }
  const awaiting = slices.filter((slice) => slice.status === 'done' && slice.merged !== true)[0];
  if (awaiting) {
    missingRepo(awaiting);
    return selectedResult(mode, feature, awaiting, 'observe-merge', 'slice-awaiting-merge');
  }
  const unfinished = slices.filter((slice) => slice.status !== 'done');
  const cycles = cycleMap(slices, 'slice');
  for (const slice of unfinished) {
    const unmet = (slice.depends_on || []).filter((id) => !byId.has(id) || byId.get(id).status !== 'done' || byId.get(id).merged !== true);
    if (!cycles.has(slice.id) && unmet.length === 0) {
      missingRepo(slice);
      const route = slice.status === 'in-review' ? 'slice-review' : 'slice-loop';
      return selectedResult(mode, feature, slice, route, 'slice-actionable');
    }
  }
  if (unfinished.length === 0) return selectedResult(mode, feature, null, 'integration', 'integration-ready');
  const blocked = [];
  for (const slice of unfinished) {
    if (cycles.has(slice.id)) blocked.push({ subject: slice.id, code: 'dependency-cycle', detail: cycles.get(slice.id) });
    const unmet = sortedUnique((slice.depends_on || []).filter((id) => !byId.has(id) || byId.get(id).status !== 'done' || byId.get(id).merged !== true));
    if (unmet.length) {
      const detail = unmet.map((id) => {
        const dep = byId.get(id);
        if (!dep) return `${id}=missing`;
        if (dep.status !== 'done') return `${id}=${dep.status}`;
        return `${id}=done-but-unmerged`;
      }).join(', ');
      blocked.push({ subject: slice.id, code: 'unmet-dependency', detail: `blocking dependencies: ${detail}` });
    }
  }
  return envelope(mode, 'blocked', null, { code: 'selection-blocked', detail: `no actionable slice for ${feature.id}` }, blocked, BLOCKED_SUMMARY);
}

function resolveIdentity(identity) {
  if (identity === '') return { value: null, detail: 'workflow.identity=<empty>' };
  if (identity === '@me' || identity === 'self') {
    const result = spawnSync('gh', ['api', 'user', '--jq', '.login'], { encoding: 'utf8' });
    const value = result.status === 0 ? (result.stdout || '').trim() : '';
    if (!result.error && result.status === 0 && value) return { value, detail: null };
    return { value: null, detail: `workflow.identity=${identity} lookup failed` };
  }
  return { value: identity, detail: null };
}

function select(model, config, args, repos) {
  const mode = args.mode;
  const features = [...model.features].sort((a, b) => compareIds(a.id, b.id));
  const featureById = new Map(features.map((feature) => [feature.id, feature]));
  if (mode === 'target') {
    const target = featureById.get(args.feature);
    if (!target) throw new ExpectedError('input-error', `target feature ${args.feature} does not exist`);
    if (target.status === 'done') {
      return envelope(mode, 'complete', null, { code: 'target-complete', detail: `target ${target.id} is already done` }, [], `target ${target.id} is already done`);
    }
  } else if (features.length === 0 || features.every((feature) => feature.status === 'done')) {
    const summary = features.length === 0
      ? 'no actionable work [no-candidates]: board has no features'
      : 'no actionable work [no-candidates]: all features are done';
    return envelope(mode, 'complete', null, { code: 'no-candidates', detail: summary }, [], summary);
  }
  let identity = null;
  if (mode === 'mine') {
    const resolved = resolveIdentity(config.identity);
    if (resolved.value === null) {
      return envelope(mode, 'blocked', null, { code: 'selection-blocked', detail: 'scoped identity is unresolved' },
        [{ subject: '--mine', code: 'owner-unresolved', detail: resolved.detail }], BLOCKED_SUMMARY);
    }
    identity = resolved.value;
  }
  const candidates = mode === 'target' ? [featureById.get(args.feature)] : features.filter((feature) => feature.status !== 'done');
  const cycles = cycleMap(features, 'feature');
  const blocked = [];
  for (const feature of candidates) {
    const ordinary = featureBlockers(feature, featureById, cycles, config.requireApproval);
    const route = featureRoute(feature, config.requireApproval);
    const otherwiseActionable = ordinary.length === 0 && route !== null;
    if (otherwiseActionable && mode === 'mine') {
      const owner = feature.owner !== undefined ? feature.owner : feature.epic.owner;
      if (owner !== identity) {
        blocked.push({ subject: feature.id, code: 'owner-excluded', detail: `effective owner=${owner === undefined ? 'unowned' : owner}` });
        continue;
      }
    }
    if (otherwiseActionable) {
      if (route === 'builder' && feature.status === 'in-progress' && feature.slices.length && repos !== null) {
        return slicePhase(mode, feature, repos);
      }
      return selectedResult(mode, feature, null, route, 'feature-actionable');
    }
    blocked.push(...ordinary);
  }
  return envelope(mode, 'blocked', null, { code: 'selection-blocked', detail: mode === 'target' ? `target ${args.feature} is not actionable` : 'no actionable feature' }, blocked, BLOCKED_SUMMARY);
}

let args = { mode: 'board' };
try {
  args = parseArgs(process.argv.slice(2));
  const tasksPath = args.tasks ? resolve(process.cwd(), args.tasks) : resolve(HARNESS, 'state/tasks.json');
  const configPath = args.config ? resolve(process.cwd(), args.config) : resolve(HARNESS, 'harness.config.yaml');
  let boardText, configText;
  try { boardText = readFileSync(tasksPath, 'utf8'); } catch (error) { throw new ExpectedError('input-error', `cannot read TaskStore ${tasksPath}: ${error.message}`); }
  try { configText = readFileSync(configPath, 'utf8'); } catch (error) { throw new ExpectedError('input-error', `cannot read config ${configPath}: ${error.message}`); }
  let board;
  try { board = JSON.parse(boardText); } catch (error) { throw new ExpectedError('input-error', `invalid TaskStore JSON ${tasksPath}: ${error.message}`); }
  let config;
  try { config = relevantConfig(configText); } catch (error) { throw new ExpectedError('input-error', `invalid config ${configPath}: ${error.message}`); }
  let model;
  try { model = validateBoard(board); } catch (error) { throw new ExpectedError('input-error', `invalid TaskStore ${tasksPath}: ${error.message}`); }
  let repos = null;
  if (config.manifest !== '') {
    const manifestPath = resolve(HARNESS, config.manifest);
    if (existsSync(manifestPath)) {
      let manifestText;
      try { manifestText = readFileSync(manifestPath, 'utf8'); } catch (error) { throw new ExpectedError('manifest-error', `cannot read umbrella manifest ${manifestPath}: ${error.message}`); }
      try { repos = manifestRepos(manifestText); } catch (error) { throw new ExpectedError('manifest-error', `invalid umbrella manifest ${manifestPath}: ${error.message}`); }
    }
  }
  emit(select(model, config, args, repos));
} catch (error) {
  const code = error instanceof ExpectedError ? error.code : 'input-error';
  const detail = error instanceof Error ? error.message : String(error);
  emit(envelope(args.mode || 'board', 'error', null, { code, detail }), detail, code === 'usage-error' ? 2 : 1);
}
