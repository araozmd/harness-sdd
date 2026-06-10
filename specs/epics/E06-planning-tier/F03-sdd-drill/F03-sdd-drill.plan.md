# /sdd-drill skill (decompose draft epic, ADR deltas, epic-level approval) — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. This feature ships **prose + docs + one test suite** — there is no application
> code. The "skill" is a portable role file plus a Claude slash-command wrapper,
> mirroring exactly how the Planner (E06-F02) is built.

## Stack & dependencies
- Markdown prose: a new portable role file (`agents/driller.md`), a Claude command
  (`.claude/commands/sdd-drill.md`), and two doc edits (`docs/WORKFLOW.md`, `README.md`).
- Verification: POSIX sh + grep + python3 here-docs (`tests/test_sdd_drill.sh`), wired
  into `verification.test_command`. One sandboxed seed→validate fixture exercises the
  decomposed shape (a `pending` feature inside a `planned` epic, stamped `autonomous`)
  against the live schema.
- New dependencies: **none** (zero-dependency pillar holds; `jsonschema` stays optional).
- Reused, unchanged: `specs/_templates/inbox-brief.md` (per-feature briefs — R9),
  `specs/_templates/adr.md` (ADR deltas — R11), the F01 schema (no change — R7/R13/R14),
  the existing Architect (specs each feature just-in-time — R17).

## Data model  (serves: R7, R10, R13, R14)
**No schema change.** F03 only *uses* the F01-extended schema. The schema already admits
every shape F03 writes:

| Entity | Field | Value | Notes |
|---|---|---|---|
| feature | `id` | `<E##>-F<NN>` | next-sequential within the epic, above max `F##` (D3/R7) |
| feature | `title` | string | one-line intent |
| feature | `status` | `"pending"` | F01 feature enum value (R7) |
| feature | `sdd` | `true` | default; the Architect specs it just-in-time |
| feature | `spec_path` | `specs/epics/<id>-<slug>/F<NN>-<slug>/` | matches id+slug (D3) |
| feature | `depends_on` | `[]` or sibling ids | intra-epic graph (D3/R7) |
| feature | `autonomous` | `true` (approve) / `false` (keep gated) | the single approval, all-or-nothing (D4, D6 / R13, R14) |
| epic | `status` | `draft → planned` | F01 transition, both branches (D4 / R13, R14) |

`autonomous` is already an optional boolean on a feature (`store/tasks.schema.json`
line 32); `planned` is already an epic enum value (F01). Both branches and the seeded
feature shape validate against the schema **as-is**. **No schema edit is permitted by
this feature.**

## Artifacts produced by a `/sdd-drill` run  (serves: R7, R8, R9, R11, R13, R14)
> These are written by the *running skill*, not by the Builder. The Builder ships the
> role + command that mandate them; the fixture below asserts the shapes are valid, not
> that a session ran.

| Path | Produced by skill | From template | R-id |
|---|---|---|---|
| `state/tasks.json` feature rows | per seeded feature (`status: pending`, `sdd: true`) | — | R7 |
| `specs/epics/<id>-<slug>/epic.md` feature table | filled in | — (existing epic.md) | R8 |
| `progress/inbox/<E##>-F<NN>.md` | per seeded feature (records touched `ADR-NNNN` ids) | `specs/_templates/inbox-brief.md` | R9 |
| `specs/adr/NNNN-<title>.md` | per per-epic ADR delta | `specs/_templates/adr.md` | R11 |
| `state/tasks.json` epic `status` + feature `autonomous` | on the approval decision | — | R13, R14 |

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `agents/driller.md` | **create**: portable Driller role contract — consumer that decomposes one `draft` epic; reads draft epic + vision/architecture/ADRs (R6); Q&A front-end (≤3 text-only options, never images) (R3); `<epic-id>` required + missing/non-`draft` refuse + amend (R4, R5); feature seeding with intra-epic ids/`depends_on` (R7); fill `epic.md` table (R8); per-feature inbox brief recording touched ADR ids (R9, D7); re-validate + fail-stop (R10); per-epic ADR deltas, no F02-ADR rewrite (R11, R12); approve branch (`draft → planned` + stamp all `autonomous: true`) (R13); keep-gated branch (`planned`, features stay `autonomous: false`) (R14); single epic-level gate via existing `autonomous` flag, no new status/mechanism (R15); only-path-past-draft + advances only the epic (R16); decomposes-never-specs (R17); portable for any AGENTS.md CLI (R1, R19) | R1, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15, R16, R17, R19 |
| `.claude/commands/sdd-drill.md` | **create**: slash-command wrapper that acts as Driller, points at `agents/driller.md`, reads `<epic-id>` from `$ARGUMENTS`, runs `./init.sh` first (STOP on non-zero), STOPs on empty/missing/non-`draft` target, carries the ≤3 text-only-options rule, and presents the single approve/keep-gated decision without spawning the Architect | R2, R3, R4, R5 |
| `docs/WORKFLOW.md` | **modify**: extend the "Whole-project inception (`/sdd-plan`)" / "Epic lifecycle" section with a "Per-epic drill-down (`/sdd-drill`)" note placing it between `/sdd-plan` and `/sdd-next` — decomposes a `draft` epic into features + ADR deltas, ends in one epic-level approval (approve → `planned` + `autonomous: true`; keep gated → `planned`, features gated), the only step that flips `draft → planned`, never writes feature specs | R20 |
| `README.md` | **modify**: one-line `/sdd-drill` description beside `/sdd-new` / `/sdd-plan` / `/sdd-next` | R21 |
| `tests/test_sdd_drill.sh` | **create**: static + fixture suite per `.tests.md` (grep contract assertions over the role/command/docs + one python seed→validate fixture for the decomposed shape + an `./init.sh` exit-0 run) | R1–R22 |
| `harness.config.yaml` | **modify**: append `&& sh tests/test_sdd_drill.sh` to `verification.test_command` and extend its trailing comment (e.g. `+ sdd-drill`) | R1–R22 (wiring) |
| `VERSION` | **modify**: one MINOR bump (current value + MINOR — read at build time, do not hard-code) | R22 |
| `CHANGELOG.md` | **modify**: new `## [<new version>]` entry describing `/sdd-drill`, the feature decomposition + ADR deltas, and the approve / keep-gated branches | R22 |

## DO NOT TOUCH
- `agents/planner.md` — D1: the Driller is a **sibling** of the Planner. The Planner's
  "never past draft" invariant (its R15) is *complemented* by F03, not edited. Not
  extended, not modified.
- `agents/architect.md` — D1/R17: the Architect still writes the four-file spec
  just-in-time during the autonomous run. The Driller does not extend or edit it and
  never spawns it.
- `agents/inception.md`, `.claude/commands/sdd-new.md`, `.claude/commands/sdd-plan.md`,
  `.claude/commands/sdd-next.md` — R18: existing intake/plan/loop are behaviorally
  unchanged. Only a **new** `sdd-drill.md` command is added.
- `store/tasks.schema.json` — R15/R18: no schema change for approval; `planned`,
  `autonomous`, and a `pending` feature all already validate. Adding a status or an
  approval field would break backward compatibility.
- `agents/orchestrator.md`, `store/local.md` — the F01 `next()` draft gate is reused
  as-is; F03 adds no gating rule and changes no selection logic.
- `specs/_templates/inbox-brief.md`, `specs/_templates/adr.md`, `specs/_templates/epic.md`
  — reused as-is; the Driller writes *from* them, it does not edit the templates.
- Existing test suites (`tests/test_*.sh`) — additive only; do not edit them.
- `state/tasks.json` epic/feature statuses — the running *skill* owns the `draft →
  planned` flip and the `autonomous` stamp at runtime; the **Builder** flips no status
  while implementing this feature (the Orchestrator owns the F03 feature's own lifecycle).

## Approach notes
- **Mirror the Planner build exactly** (E06-F02). The role file is the portable, durable
  contract; the Claude command is the thin interactive wrapper that points at it. Tests
  are static greps over the role + command + docs (house style, cf.
  `tests/test_sdd_plan.sh`), plus one python fixture that proves the decomposed shape is
  schema-valid. Use the exact phrases the spec pins (`draft`, `planned`, `autonomous`,
  `pending`, `decompose`, `never spec`, `ADR delta`, `only`/`past draft`) so the greps
  bind to normative text.
- **The decomposed shape is the load-bearing fixture.** Where F02's fixture proved a
  `draft` epic with `features: []` validates, F03's fixture proves a **`planned` epic**
  containing a **`pending` feature** with `sdd: true`, a `spec_path`, and `autonomous:
  true` validates against `store/tasks.schema.json` (jsonschema if installed, else the
  structural fallback that mirrors `init.sh`). The fixture is a temp file carrying the
  required root `project` field — it never mutates the live `state/tasks.json`. (Omitting
  `project` was a Codex P2 on F02; include it.)
- **Single human gate via the existing flag (R15).** There is no new runtime guard to
  build: the gate is the human decision the command presents, and its *effect* is the
  `autonomous` value stamped on the seeded features. The schema already carries
  `autonomous`; F01 already carries `planned`. The test greps the role for the two-branch
  contract and "no new status / no new approval mechanism".
- **ADR-delta numbering reuses F02's convention (R11/D5).** `specs/adr/NNNN-<title>.md`,
  4-digit zero-padded, above the current max ADR number, no reuse — identical to the
  Planner's rule, but scoped to *per-epic* deltas. The role states it must not rewrite or
  renumber F02's existing ADRs. The test greps the role for the path, 4-digit/above-max
  numbering, and the "per-epic delta, not feature-level design" boundary.
- **Refuse-by-default guards (R4/R5/D2).** The role/command state: `<epic-id>` required
  (STOP on empty); STOP if the id is missing or the epic is not `draft`; the amend opt-in
  appends features/ADRs above the current max without renumbering or re-flipping. This is
  prose the test greps for; there is no runtime parser to implement beyond the contract.
- **Docs wording.** Use "`/sdd-drill`" verbatim, plus `draft`, `planned`, `autonomous`,
  and "feature spec" in `docs/WORKFLOW.md` and "`/sdd-drill`" in `README.md` so greps are
  simple; place the WORKFLOW note adjacent to the existing `/sdd-plan` note so the flow
  reads `/sdd-plan` (sketch) → `/sdd-drill` (deepen one epic, flip `draft → planned`) →
  `/sdd-next` (execute).
- **Sequencing:** role file → command → docs → tests → config wiring → VERSION +
  CHANGELOG last (so the CHANGELOG heading matches the final VERSION).
- **Portability (R19).** Do not require an opencode agent entry as a hard gate —
  portability is satisfied by the normative contract living in `agents/driller.md` +
  AGENTS.md. The test asserts the rule's *presence in the portable role file*, never
  anything about `.claude/` contents.

## Risks
- **State-mutation correctness (the highest risk).** On approval the running skill must
  perform two coupled mutations — flip the **epic** `draft → planned` AND stamp
  `autonomous` on **every** seeded feature (all-or-nothing, D6) — and then re-validate.
  Mitigation: the role mandates re-validation against the schema after the write and a
  hard fail-stop on any validation error (R10), so a half-applied state (epic flipped but
  some features unstamped, or vice-versa) is never reported as success. The role also
  pins that **only the epic** advances to `planned` — never a sibling epic, never a
  feature's own status (R16) — so the flip cannot leak across epics.
- **Re-drill / amend drift.** Re-running on a `planned` epic must append, never
  renumber or re-flip (D2/R5). Mitigation: the role states append-above-max for both
  feature ids and ADR ids, and explicitly forbids renumbering existing features or
  re-flipping epic state.
- **Contradicting the Planner invariant.** F03 is the *only* path past `draft`; getting
  the wording wrong could appear to license the Planner to advance epics. Mitigation: R16
  states F03 is the only path and is *consistent with* `agents/planner.md`'s "never past
  draft", and `agents/planner.md` is DO-NOT-TOUCH.
- **Accidental scope creep into speccing.** Decomposition is close to speccing; the
  Driller could drift into writing EARS. Mitigation: R17 "decomposes, never specs"
  forbids any `.spec/.plan/.tasks/.tests` write and any Architect spawn, mirroring the
  Planner's seeds-never-specs guardrail; the test greps each forbidden extension.
