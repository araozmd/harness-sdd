---
feature: E07-F01
role: reviewer
action: re-spec review (round 2)
date: 2026-06-12
branch: feat/E07-F01-antigravity-support
commit: d78e40f
verdict: APPROVE
---

# E07-F01 re-spec — Reviewer verdict: APPROVE

Reviewed the `.agent/` → `.agents/` rename + confirmed-primitives persona model against
the REVISED spec (R1–R13). All checks green. Verdict: **APPROVE** → Orchestrator may set `done`.

## Environment
- `./init.sh` → exit 0 (`✅ environment ready`).
- Full `verification.test_command` chain (13 suites) → **exit 0**, all green. Antigravity
  pass lines observed: `Antigravity glue generated (R11)`, `--agents=antigravity writes
  GEMINI.md entrypoint (R1)`, `antigravity deselect is a no-op... (Codex r3 P1)`,
  `antigravity deselect deletes only byte-pristine .agents/ glue, keeps user files (Codex r2 P1)`,
  `GEMINI.md shared by gemini+antigravity: kept until both deselected`.

## Stray singular-path grep (required)
`grep -n "\.agent/" harness-install.sh tests/test_install.sh | grep -v "\.agents/"`
→ **no output** (exit 1). The rename is complete; no stray singular `.agent/` code path remains.
The only `.agent/` literals left are in spec/plan/tasks PROSE explaining the rename history —
not code. Glue generates under `.agents/{rules,agents,workflows}/`; manifest line (h-install.sh
:569), header comment (:11), and §4 GEMINI.md comment all say `.agents/`.

## Drift guard (R18, test_drift_check)
`grep -n "drift" harness-install.sh` → none. The literal "drift" is still absent. Green.

## Per-R-id traceability (every R traces to a passing, shape-not-existence assertion)
| R | Behavior | Assertion (tests/test_install.sh) | Status |
|---|---|---|---|
| R1 | GEMINI.md boots Orchestrator vs .harness/AGENTS.md, written for antigravity-only | L123-124 (group) + L289-301 (`--agents=antigravity`: GEMINI.md+block+.agents/ rule, NO CLAUDE.md/opencode.json) | PASS |
| R2 | `.agents/rules/harness.md` points at AGENTS.md + orchestrator role | L127-129 | PASS |
| R3 | Rule has no copied role body (absent sentinel) | L131 `grep $AG_SENTINEL && fail` | PASS |
| R4 | One persona/role under `.agents/agents/`, each `^description:` (shape only) | L138-140 | PASS |
| R5 | Persona defers to `.harness/agents/<r>.md` + init.sh + progress/, no fork | L141-144 | PASS |
| R6 | Five workflows under `.agents/workflows/` | L148-149 | PASS |
| R7 | Each workflow `^description:` | L150 | PASS |
| R8 | Each workflow resolves role vs `.harness/agents/*.md` + `$ARGUMENTS` | L151,155-159 | PASS |
| R9 | Workflow byte-identical to Claude command (`cmp -s`) | L162-163 | PASS |
| R10 | Version stamped + CHANGELOG/manifest `.agents/` | stamp check green; VERSION=0.22.0; CHANGELOG `## [0.22.0]` reads `.agents/`; manifest L569 plural | PASS |
| R11 | Antigravity group present, shape-not-existence, suite passes | L116-165 prints `pass ...(R11)`; suite exit 0 | PASS |
| R12 | Fallback: rule+workflows+progress/ working model documented, no spawn/registration claim | rule body (h-install.sh :692-698) states model explicitly; jointly evidenced by R2/R3/R6-R9 | PASS |
| R13 | Deselect removes only pristine `.agents/` glue, keeps user files, never `rm -rf` | L407-419 (user dir survives), L421-445 (byte-exact: user builder.md survives, pristine reviewer/sdd-next/rule removed, `.agents/` survives), L467-483 (GEMINI.md shared both directions) | PASS |

All assertions test **shape** (correct plural dir, `description`, role resolves to
`.harness/agents/*.md`, absent-sentinel for no-fork, `cmp -s` byte-equality, deselect byte-
compare), never mere file existence. The original R11 file-existence defect is fixed.

## Adversarial: deselect data-loss safety (the r2/r3 P1 contract)
- Removal goes through `remove_if_pristine` (h-install.sh :742-752): `[ -f ]` guard, then
  `cmp -s` against a freshly-generated stamp; removes ONLY on byte-match, else leaves the file
  with a notice. **Never delete-by-name. Never `rm -rf`.** Dir pruning is `rmdir` only
  (:1196-1199), which fails (and is `|| true`-swallowed) on a non-empty dir — a surviving user
  file keeps `.agents/` alive.
- Verified behaviorally: test L432 overwrites a standard-named `.agents/agents/builder.md` with
  user content; after `--agents=claude` deselect it **survives with content** (L436-437), the
  pristine reviewer/sdd-next/rule are removed (L438-441), and `.agents/` survives (L443).
- GEMINI.md shared-ownership is guarded **both** directions: gemini deselect skips removal while
  antigravity is selected (:1140) and antigravity deselect skips while gemini is selected
  (:1205); removed only when neither owner remains (test L467-483). No regression to the r1 fix.

## Adversarial: persona-model honesty
- I installed `--agents=antigravity` into a temp target and inspected the generated tree
  directly. Personas/workflows/rule are pure pointers at `.harness/agents/*.md` — no canonical
  role prose pasted in.
- Grepped the generated `.agents/` for `subagent|register|task tool|spawn`: the only matches are
  (a) the orchestrator's internal role-routing vocabulary inside the workflow bodies, which are
  byte-identical to the already-shipped Claude commands, and (b) the rule's explicit DISCLAIMER:
  "NOT a Task-tool-style isolated spawn, and NOT an asserted bare-file subagent registration."
  Nothing in spec/tests/installer **claims** bare-file personas register as Antigravity subagents.
- No plugin-bundle packaging and no `.agents/skills/` surface were added (both human-confirmed
  out of scope; spec "Out of scope" + Open questions 2/3). Confirmed.

## VERSION + CHANGELOG
VERSION = **0.22.0**, NOT re-bumped (one MINOR over released 0.21.0 for this new capability,
per policy — installed body changed). CHANGELOG `## [0.22.0]` prose reads `.agents/` (plural)
throughout and is honest about the best-effort persona model. Correct.

## DO NOT TOUCH (honored)
- `git diff main...HEAD --name-only`: no canonical `agents/*.md`, no `store/tasks.schema.json`,
  no `init.sh`, no `store/` touched.
- `state/tasks.json` change is benign: E07-F01 → `in-progress` (the re-build) + a Unicode-arrow
  normalization in an unrelated E05 title. No new status enum value.
- Installer diff is scoped to additive Antigravity glue + comments; the only existing-flow edits
  are (a) `rm -rf "$CMDDIR"` relocated to after §7 (so the deselect compare can read the workflow
  source — confirmed still unconditional at :1216) and (b) the gemini-deselect `remove_pointer
  GEMINI.md` replaced by the shared-ownership guard (the intended R1 change). §5/§5b/opencode.json
  logic otherwise unchanged.

## Cross-file consistency
spec ↔ plan ↔ tasks ↔ tests ↔ implementation all cohere on `.agents/` (plural) and the
conditional/best-effort persona model. All 12 tasks ticked. No contradiction found.

## Verdict
**APPROVE.** Every R1–R13 traces to a passing shape-level assertion; the rename is complete and
clean; deselect data-loss safety and persona-model honesty hold under adversarial inspection;
VERSION/CHANGELOG/DO-NOT-TOUCH all correct. Recommend the Orchestrator set E07-F01 → `done`.
