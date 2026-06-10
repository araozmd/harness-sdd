# /sdd-fix lightweight lane (maintenance epic, brief-only intake) — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. This feature ships **prose + docs + one test suite** — there is no application
> code. The "skill" is a portable role file plus a Claude slash-command wrapper, mirroring
> exactly how the Planner (E06-F02) and Driller (E06-F03) are built. F05 rides on the
> **existing** `sdd: false → Builder → Reviewer` primitive (F01) — it adds a front-end and
> a convention, never a new routing mechanism.

## Stack & dependencies
- Markdown prose: a new portable role file (`agents/fixer.md`), a Claude command
  (`.claude/commands/sdd-fix.md`), additive notes in two existing role files
  (`agents/builder.md`, `agents/reviewer.md`), and two doc edits (`docs/WORKFLOW.md`,
  `README.md`).
- Installer: a new command-generation block in `harness-install.sh` (`.claude/` +
  `.opencode/` mirror) and new assertions in `tests/test_install.sh` (R15, R16). The
  Fixer **role** installs automatically — `harness-install.sh` bulk-copies `agents/`
  into `.harness/agents/` (the `cp -R "$_src" "$_dst"` path), so a new `agents/fixer.md`
  lands at `.harness/agents/fixer.md` with no installer edit beyond the assertion.
- Verification: POSIX sh + grep + python3 here-docs (`tests/test_sdd_fix.sh`), wired into
  `verification.test_command`. One sandboxed seed→validate fixture exercises the seeded
  shape (an `sdd: false`, `autonomous: true` fix inside a `planned` `E99` epic) against
  the live schema.
- New dependencies: **none** (zero-dependency pillar holds; `jsonschema` stays optional).
- Reused, unchanged: the F01 `sdd: false` routing (`agents/orchestrator.md` step-4 table,
  `docs/WORKFLOW.md` "Selective SDD"), the existing `autonomous` flag, the F01 schema (no
  change), `specs/_templates/inbox-brief.md` (fix brief — R10).

## Data model  (serves: R4, R5, R6, R8, R9, R11)
**No schema change.** F05 only *uses* the existing schema. Every shape it writes already
validates:

| Entity | Field | Value | Notes |
|---|---|---|---|
| epic | `id` | `"E99"` | reserved high number; matches `^E[0-9]+$` (D1/R5) |
| epic | `title` | `"Maintenance (hotfixes & minor fixes)"` | (D1/R5) |
| epic | `status` | `"planned"` | F01 enum; `next()` selects its features (D1/R5/R7) |
| epic | `features` | `[]` on create, appended thereafter | empty-features shape is F02-established (R5/R6) |
| feature (fix) | `id` | `"E99-F<NN>"` | next-sequential above max `F##`, append-only (R8) |
| feature (fix) | `title` | one-line | from `$ARGUMENTS` (R8) |
| feature (fix) | `status` | `"pending"` | feature enum; Orchestrator routes `pending + sdd:false` → Builder (R8) |
| feature (fix) | `sdd` | `false` | the lane's defining flag — reuses F01 routing (R4/R8) |
| feature (fix) | `autonomous` | `true` (default) / `false` (opt-out) | existing flag; no new mechanism (R9) |
| feature (fix) | `spec_path` | `specs/epics/E99-maintenance/F<NN>-<slug>/` | recorded; **directory not created** (R10) |

`autonomous` is already an optional boolean on a feature (`store/tasks.schema.json`
line 32); `planned` is already an epic enum value (F01); `^E[0-9]+$` already admits `E99`.
The seeded fix shape validates against the schema **as-is**. **No schema edit is permitted
by this feature.**

## Artifacts produced by a `/sdd-fix` run  (serves: R5, R6, R8, R9, R10)
> Written by the *running skill*, not by the Builder. The Builder ships the role + command
> + installer wiring that mandate them; the fixture below asserts the shapes are valid, not
> that a session ran.

| Path | Produced by skill | From template | R-id |
|---|---|---|---|
| `state/tasks.json` epic `E99` row | created on first use (else reused) | — | R5, R6 |
| `specs/epics/E99-maintenance/epic.md` | created on first use (title + brief) | `specs/_templates/epic.md` | R5 |
| `state/tasks.json` fix feature row | appended per fix (`sdd: false`, `autonomous: true`) | — | R8, R9 |
| `progress/inbox/E99-F<NN>.md` | one fix-oriented brief per fix | `specs/_templates/inbox-brief.md` | R10 |

No feature `.spec/.plan/.tasks/.tests` and no `spec_path` directory are created (R10).

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `agents/fixer.md` | **create**: portable Fixer role contract — brief-only intake that seeds **one** `sdd: false` fix under the reserved `E99` maintenance epic and hands it to the existing loop, for any AGENTS.md CLI (R1, R18); ≤3 text-only options, never images (R3); reuses existing `sdd: false → Builder → Reviewer` routing, no new routing/status/schema (R4); create-on-first-use `E99` epic (`planned`, `features: []`) + reuse-by-id thereafter (R5, R6); non-`draft` selectable status rationale (R7); append fix `sdd: false`/`pending`/`spec_path`/next-`F##`-above-max (R8); stamp `autonomous: true` by default + `--gated` opt-out (R9); one fix-oriented inbox brief, never a spec / never a `spec_path` dir / never spawn Architect (R10); re-validate + fail-stop (R11); hand off to the loop in-session (R14) | R1, R3, R4, R5, R6, R7, R8, R9, R10, R11, R14, R18 |
| `.claude/commands/sdd-fix.md` | **create**: slash-command wrapper that acts as Fixer, points at `agents/fixer.md`, reads the fix description from `$ARGUMENTS` (STOP if empty), runs `./init.sh` first (STOP on non-zero), carries the ≤3 text-only-options rule, seeds the `E99` fix, re-validates, then hands off to the existing `sdd: false` loop in-session — without writing any spec or spawning the Architect | R2, R3, R14 |
| `agents/builder.md` | **modify (additive)**: add a clause that for an `sdd: false` item with no `tasks.md`, the Builder works from the inbox brief (`progress/inbox/<id>.md`) as its worklist and still writes ≥1 test proving the fix — leaving the `sdd: true` four-file path unchanged | R12 |
| `agents/reviewer.md` | **modify (additive)**: add a clause that for an `sdd: false` item the Reviewer verifies behaviour + the fix's test and that the R-id traceability check (#2) does not apply when there are no R-ids — leaving the `sdd: true` path unchanged | R13 |
| `harness-install.sh` | **modify**: add a `cat > "$TARGET/.claude/commands/sdd-fix.md"` block (acts as Fixer, resolves `.harness/agents/fixer.md`, carries `$ARGUMENTS`); add the `.opencode/command/sdd-fix.md` mirror `cp`; extend the two "installed" `ok` lines to mention `/sdd-fix` | R15, R16 |
| `tests/test_install.sh` | **modify**: assert `.claude/commands/sdd-fix.md` exists + resolves `.harness/agents/fixer.md` + carries `$ARGUMENTS`; assert `.opencode/command/sdd-fix.md` exists + `cmp`-equals the `.claude/` copy; assert `.harness/agents/fixer.md` installed | R16 |
| `docs/WORKFLOW.md` | **modify**: extend the "Selective SDD (`sdd` flag)" section with a "Lightweight fix lane (`/sdd-fix`)" note — seeds an `sdd: false` fix under the reserved maintenance epic with only an inbox brief (no 4-file spec, no drill), runs the existing `sdd: false → Builder → Reviewer` path, adds no new status / no new routing | R19 |
| `README.md` | **modify**: one-line `/sdd-fix` description beside `/sdd-new` / `/sdd-plan` / `/sdd-drill` / `/sdd-next` | R20 |
| `tests/test_sdd_fix.sh` | **create**: static + fixture suite per `.tests.md` (grep contract over role/command/builder/reviewer/docs + one python seed→validate fixture for the seeded fix shape + an `./init.sh` exit-0 run) | R1–R21 |
| `harness.config.yaml` | **modify**: append `&& sh tests/test_sdd_fix.sh` to `verification.test_command` and extend its trailing comment (e.g. `+ sdd-fix`) | R1–R21 (wiring) |
| `VERSION` | **modify**: one MINOR bump (current value + MINOR — read at build time, do not hard-code) | R21 |
| `CHANGELOG.md` | **modify**: new `## [<new version>]` entry describing `/sdd-fix`, the maintenance-epic convention, brief-only `sdd: false` seeding, and the additive Builder/Reviewer notes | R21 |

## DO NOT TOUCH
- `agents/inception.md`, `agents/planner.md`, `agents/driller.md` — D4: the Fixer is a
  **sibling**, not an extension of any of them. Not extended, not modified.
- `agents/architect.md` — D4/R10: the lane never spawns the Architect and writes no spec.
  Not edited.
- `agents/orchestrator.md`, `store/local.md` — R4: F05 reuses the **existing**
  `pending + sdd: false → Builder → Reviewer` routing and the F01 `next()`/epic gate
  verbatim; it adds no routing rule and no gating change.
- `store/tasks.schema.json` — R4: no schema change. `E99` already matches `^E[0-9]+$`;
  `planned`, `sdd: false`, and `autonomous` already validate. Adding a status, a marker
  field, or an approval field would break backward compatibility.
- `.claude/commands/sdd-new.md`, `sdd-plan.md`, `sdd-drill.md`, `sdd-next.md` and their
  `.opencode/` mirrors — R17: existing intake/plan/drill/loop are behaviorally unchanged;
  only a **new** `sdd-fix` command is added.
- The `sdd: true` four-file path inside `agents/builder.md` / `agents/reviewer.md` — R12/
  R13: the edits are **additive `sdd: false` clauses only**; the existing `sdd: true`
  instructions must read identically after the change.
- `specs/_templates/inbox-brief.md`, `specs/_templates/epic.md` — reused as-is; the Fixer
  writes *from* them, it does not edit the templates.
- Existing test suites (`tests/test_*.sh`) except `tests/test_install.sh` (which gets the
  additive R16 assertions) — additive only; do not edit the others.
- `state/tasks.json` live store — the running *skill* owns the `E99` epic create + fix
  append at runtime; the **Builder** building *this* feature seeds no fix and creates no
  maintenance epic (the F05 feature's own lifecycle is Orchestrator-owned). Tests use a
  **temp** store only.

## Approach notes
- **Mirror the Driller/Planner build exactly** (E06-F03 / E06-F02). The role file is the
  portable, durable contract; the Claude command is the thin interactive wrapper that
  points at it. Tests are static greps over the role + command + builder/reviewer notes +
  docs (house style, cf. `tests/test_sdd_drill.sh`), plus one python fixture proving the
  seeded fix shape is schema-valid. Use the exact phrases the spec pins (`sdd: false`,
  `autonomous`, `E99`, `maintenance`, `planned`, `brief-only`/`inbox brief`, `never
  spec`, `hand off`) so the greps bind to normative text.
- **The seeded fix shape is the load-bearing fixture.** Where F03's fixture proved a
  `pending` feature in a `planned` epic stamped `autonomous: true`, F05's fixture proves
  an **`sdd: false`** fix with `autonomous: true` inside a **`planned` `E99` maintenance
  epic** validates against `store/tasks.schema.json` (jsonschema if installed, else the
  structural fallback that mirrors `init.sh`). The fixture is a temp file carrying the
  required root `project` field — it never mutates the live `state/tasks.json`. (Omitting
  `project` was a Codex P2 on F02; include it.)
- **Idempotent maintenance epic (the highest-risk area — see Risks).** The role must
  state create-on-first-use, reuse-by-id-`E99` thereafter, and append-only fix ids, so a
  second `/sdd-fix` run never forks a second bucket or renumbers existing fixes. The test
  greps the role for `E99`, "create … if absent"/"first use", "reuse"/"by id", and
  "append"/"above … max".
- **`autonomous: true` is the default, via the existing flag (R9).** There is no new
  runtime guard: the default is the `autonomous` value the Fixer stamps; the `--gated`
  opt-out flips it to `false`. The test greps the role for `autonomous: true` default and
  the gated opt-out, plus "no new approval mechanism".
- **Additive Builder/Reviewer edits must not regress the `sdd: true` path (R12/R13).** Add
  a clearly-scoped `sdd: false` clause to each role; the test asserts the new `sdd: false`
  clause exists **and** that the existing `sdd: true` four-file instructions are still
  present (so the edit is additive, not a rewrite).
- **Installer wiring is a first-class task (R15/R16) — do NOT omit it.** The missing
  installer-generation + `test_install.sh` assertion was a Codex P1 on F02. F05 adds the
  `cat > sdd-fix.md` block, the `.opencode` `cp`, and the three `test_install.sh`
  assertions (command exists + resolves `.harness/agents/fixer.md` + `$ARGUMENTS`;
  opencode mirror equals claude copy; `.harness/agents/fixer.md` installed). The Fixer
  role itself rides the existing `agents/` bulk copy — assert it lands, but no per-file
  emit block is needed for the role.
- **Docs wording.** Use "`/sdd-fix`" verbatim plus `sdd: false`, `maintenance`,
  `autonomous`, "inbox brief", and "no 4-file spec"/"no spec" in `docs/WORKFLOW.md`, and
  "`/sdd-fix`" in `README.md`, so greps are simple. Place the WORKFLOW note adjacent to
  the existing "Selective SDD (`sdd` flag)" section so the flow reads:
  full SDD (`sdd: true`) ↔ lightweight fix lane (`/sdd-fix`, `sdd: false`).
- **Sequencing:** role file → command → builder/reviewer additive notes → installer +
  test_install → docs → tests → config wiring → VERSION + CHANGELOG last (so the CHANGELOG
  heading matches the final VERSION).
- **Portability (R18).** Do not require an opencode agent entry as a hard gate —
  portability is satisfied by the normative contract living in `agents/fixer.md` +
  AGENTS.md. The test asserts the rule's *presence in the portable role file*, never
  anything about `.claude/` contents (the `.claude/`/`.opencode/` checks are the
  installer's R15/R16, which are about *generation*, not the contract location).

## Risks
- **Maintenance-epic idempotency / identification (highest risk).** A second `/sdd-fix`
  must reuse the **same** `E99` epic and never fork a duplicate bucket or renumber
  existing fixes. Mitigation: the role mandates reuse-by-id-`E99` (D2/R6), append-only fix
  ids strictly above the current max (R8), and re-validation after every write (R11). The
  fixture proves the `planned`-`E99`-with-`sdd:false`-fix shape is valid; a hand-walk
  (Reviewer) confirms the "create-once, reuse-by-id, append-only" wording is unambiguous.
- **Reserved-id collision.** If a future `/sdd-plan` block ever reached `E99`, the
  maintenance epic could collide. Mitigation: `E99` is deliberately at the **top** of the
  space while `/sdd-plan`/`/sdd-drill` allocate from low numbers upward (`max + 1`), so a
  collision requires ~99 epics — far beyond any realistic roadmap; the role documents
  `E99` as reserved. (No schema reservation is possible without a schema change, which is
  out of scope.)
- **Regressing the `sdd: true` path via the Builder/Reviewer edits (R12/R13).** The edits
  are close to the existing instructions. Mitigation: the edits are **additive `sdd:
  false` clauses**; the test asserts both the new clause **and** the still-present
  `sdd: true` four-file instructions, and the `.plan` lists the `sdd: true` path as
  DO-NOT-TOUCH inside those files.
- **Accidentally inventing new routing.** The temptation is to add an Orchestrator rule
  for the fix lane. Mitigation: R4 forbids any new routing/status/schema; the role states
  it **reuses** the existing `sdd: false` primitive; `agents/orchestrator.md` and
  `store/tasks.schema.json` are DO-NOT-TOUCH; the test greps the role for "no new …
  routing / status / schema".
- **Hand-off scope creep (R14).** "Hand off to the loop in-session" must not become a
  re-implementation of routing. Mitigation: the role states it *triggers the existing*
  `sdd: false → Builder → Reviewer` routing (via the Orchestrator / `/sdd-next`
  behaviour), and writes no production code itself; the Architect is never spawned.
