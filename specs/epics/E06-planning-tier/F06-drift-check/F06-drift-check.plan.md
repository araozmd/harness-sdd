# Drift check on epic rollup (Scout re-validates remaining epics) — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. This feature ships **prose + docs + one test suite** — there is no application
> code. The "drift check" is a contract that lives in the portable role files
> (`agents/orchestrator.md`, `agents/scout.md`), the store contract (`store/local.md`),
> and the workflow doc — no schema change, no new slash command, no installer wiring.

## Stack & dependencies
- Markdown prose: edits to two portable role files (`agents/orchestrator.md`,
  `agents/scout.md`), the store contract (`store/local.md`), and one workflow doc
  (`docs/WORKFLOW.md`).
- Verification: POSIX sh + grep + python3 here-docs (`tests/test_drift_check.sh`), wired
  into `verification.test_command`. One sandboxed seed→validate fixture exercises the F06
  shapes (a `done` epic whose features are all `done`; a `planned → draft` demotion)
  against the **live** schema, proving **no schema change** is needed.
- New dependencies: **none** (zero-dependency pillar holds; `jsonschema` stays optional).
- Reused, unchanged: F01's `draft`/`planned`/`pending` epic enum + `next()` gate, the
  Orchestrator's existing telemetry `phase: scout` span (D6), F03's `/sdd-drill` (the
  manual re-drill path), the existing feature-level rollup.

## Data model  (serves: R1, R7, R16)
**No schema change.** F06 only *uses* the F01 schema. Every shape F06 reads or writes
already validates against `store/tasks.schema.json` as-is:

| Entity | Field | Value | Notes |
|---|---|---|---|
| epic | `status` | `… → done` | derived+persisted when all features `done` (D4 / R1, R2) — already an enum value (F01) |
| epic | `status` | `planned`/`pending` → `draft` | the one automatic backward demotion (D1, D3 / R7) — both ends already enum values |
| feature | `status` | `done` | the rollup input — unchanged feature enum |

`draft`, `planned`, `pending`, and `done` are **all** already epic-enum values
(`store/tasks.schema.json` line 18 / F01). The epic-done rollup and the demotion both only
*set an existing enum value*; neither adds a status, a field, or a constraint. **No schema
edit is permitted by this feature** (R16).

## Artifacts produced by a drift-check run  (serves: R4, R6, R7, R11)
> These are written by the *running loop* (the Orchestrator + the drift-check Scout), not
> by the Builder. The Builder ships the role/store/doc prose that mandates them; the
> fixture below asserts the *state shapes* are valid, not that a session ran.

| Path | Produced by | Content | R-id |
|---|---|---|---|
| `progress/<run>/scout-drift-<completed-epic>.md` | drift-check Scout (read-only) | per remaining epic: still-valid / stale + signal (S1/S2/S3) + reason; or the "nothing to re-validate" note | R4, R5, R12, R13 |
| `state/tasks.json` epic `status` | Orchestrator (`set_status`) | the just-completed epic → `done` (rollup); a stale `planned`/`pending` epic → `draft` (demotion) | R2, R7 |
| `specs/epics/<id>-<slug>/epic.md` (append) | Orchestrator | **optional** single flag line `demoted on drift: <reason>` (never a content rewrite) | R11 |
| `telemetry.jsonl` `phase: scout` record | Orchestrator (best-effort) | times the drift-check Scout span — reuses the existing record (D6) | R3 (audit) |

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `store/local.md` | **modify**: in the rollup section, add (a) the **epic-done rollup** — all features `done` ⇒ epic `done`, derived then persisted then re-validated, no new status/schema (R1); and (b) the **drift check** that follows it — Scout re-validates remaining `draft`/`planned`/`pending` epics; Orchestrator demotes stale `planned`/`pending` → `draft`; `in-progress`/`done` never demoted (R9, R14) | R1, R9, R14 |
| `agents/orchestrator.md` | **modify**: in/near the rollup section, add the epic-done rollup + drift-check step — on all-features-`done`, derive+persist epic `done`, re-validate, then **trigger the drift check before selecting next** (R2); fires only on epic rollup to `done`, spawns the **read-only Scout** in drift-check mode (R3); the Scout **never** writes `state/tasks.json` — Orchestrator alone applies demotion (R8); demote stale `planned`/`pending` → `draft` + re-validate (R7); considers `planned`/`pending`/`draft`, never `in-progress`/`done` (R9); the **backward-only** invariant + re-drill stays manual (R10); report the re-drill pointer + optional flag-only `epic.md` note (R11); the no-op note when no remaining planning-state epics (R12) or no architecture (R13) | R2, R3, R7, R8, R9, R10, R11, R12, R13 |
| `agents/scout.md` | **modify**: add a **drift-check mode** — inputs (just-completed epic + remaining `draft`/`planned`/`pending` epics + `specs/architecture.md`/`specs/adr/*`), the findings-file path + per-epic verdict shape (R4); the concrete S1/S2/S3 staleness signals + "stale only when ≥1 fires" (R5); the **read-only** preservation — writes only `progress/`, never `state/tasks.json` (R6); the "nothing to re-validate" note for the no-architecture / no-remaining-epic no-op (R12, R13) | R4, R5, R6, R12, R13 |
| `docs/WORKFLOW.md` | **modify**: add a **new, distinct** "Drift check on epic rollup" section (separate from the `/sdd-plan`, `/sdd-drill`, architecture-alignment, `/sdd-fix` sections) — fires on epic rollup to `done`; Scout flags, Orchestrator demotes stale `planned`/`pending` → `draft`; re-drill (`/sdd-drill`) stays manual; demotion only ever moves backward | R15 |
| `tests/test_drift_check.sh` | **create**: static + fixture suite per `.tests.md` (grep contract assertions over the role/store/doc prose + one python seed→validate fixture for the F06 shapes + an `./init.sh` exit-0 run) | R1–R19 |
| `harness.config.yaml` | **modify**: append `&& sh tests/test_drift_check.sh` to `verification.test_command` and extend its trailing comment (e.g. `+ drift-check`) | R1–R19 (wiring) |
| `VERSION` | **modify**: one MINOR bump (current value + MINOR — read at build time, do not hard-code) | R19 |
| `CHANGELOG.md` | **modify**: new `## [<new version>]` entry describing the epic-done rollup, the Scout drift-check mode, and the `planned`/`pending` → `draft` demotion | R19 |

## DO NOT TOUCH
- `store/tasks.schema.json` — R16: **no schema change**. `draft`/`planned`/`pending`/`done`
  are all already epic-enum values; the epic-done rollup and the demotion only *set* an
  existing value. Adding a status, a field, or a constraint would break backward
  compatibility.
- `agents/scout.md`'s existing read-only contract (lines 1–5: "read-only", "never modify
  files except to write your findings into `progress/`") — F06 **extends** the Scout with a
  drift-check **mode** that **preserves** this contract (R6); it must not weaken it or grant
  the Scout any `state/tasks.json` write authority.
- The existing **feature-level** rollup in `store/local.md` (~56–70) and
  `agents/orchestrator.md` (~205–218) — F06 adds the **epic-level** rollup **additively**,
  beside it; it must not regress the sliced-feature `done` derivation (R17).
- `agents/planner.md`, `agents/driller.md`, `agents/architect.md`, `agents/builder.md`,
  `agents/reviewer.md`, `agents/inception.md` — F06 touches only the Orchestrator + Scout
  role contracts; the producers (Planner/Driller), the Architect, and the build/review roles
  are unchanged. Re-drill stays F03's `/sdd-drill` (R10, R17).
- `.claude/commands/*` and `harness-install.sh` / `init.sh` — F06 adds **no** new slash
  command and **no** installer wiring (R18).
- F01's `next()` epic gate and the per-feature state machine — reused as-is; the demotion's
  effect (features non-selectable) is F01's existing gate, not a new rule (R7, R17).
- The telemetry record format / `schema_version` — F06 reuses the existing `phase: scout`
  record; it adds **no** new record type and **no** version bump (D6).
- Existing test suites (`tests/test_*.sh`) — additive only; do not edit them.
- `state/tasks.json` epic/feature statuses — the running *loop* owns the epic-done rollup
  and the demotion at runtime; the **Builder** flips no status while implementing this
  feature (the Orchestrator owns F06's own feature lifecycle).

## Approach notes
- **Mirror the F03/F04 build exactly.** These are portable, durable contracts plus doc edits
  plus one static+fixture test suite (house style, cf. `tests/test_sdd_drill.sh`,
  `tests/test_architect_adr.sh`). Use the exact phrases the spec pins (`drift`, `rollup`,
  `demote`/`demotion`, `draft`, `planned`, `pending`, `read-only`, `supersedes`,
  `nothing to re-validate`, `/sdd-drill`, `backward`) so the greps bind to normative text.
- **The trigger is the load-bearing addition (D4).** Inspection confirmed the epic-done
  rollup is **not** currently formalized — only the sliced-feature rollup is. F06 adds
  "all features `done` ⇒ epic `done`, derived then persisted" to `store/local.md` and
  `agents/orchestrator.md`, then chains the drift check off it. Place it **beside** the
  existing feature-rollup prose, not inside it, so the additive boundary is clean (R1, R2).
- **Scout flags, Orchestrator acts (D6 / R6, R8).** The single most important invariant to
  preserve: the Scout writes only `progress/`. The Scout's drift-check mode produces the
  findings file; the **Orchestrator** reads it and applies `set_status` for both the rollup
  and the demotion. The test asserts the Scout role *still* says "read-only / writes only to
  progress/ / never writes state/tasks.json" **after** the drift-check mode is added.
- **Concrete signals, not AI judgement (D2 / R5).** The Scout role enumerates S1
  (contradiction), S2 (removed/renamed reference), S3 (explicit `supersedes E0X`). "Stale
  only when ≥1 fires; otherwise still-valid" keeps the verdict conservative and testable. The
  test greps the Scout role for the three signals + the "supersedes" marker + the default.
- **Backward-only invariant (D1 / R10).** The one automatic epic-status move is
  `planned`/`pending` → `draft`. The role states it never advances an epic and never demotes
  `in-progress`/`done`; re-drill is a manual `/sdd-drill`. The test greps the Orchestrator
  role for "backward", "never … forward"/"never advance", "in-progress"/"done" excluded, and
  "/sdd-drill … manual".
- **No-op note, never silence (D5 / R12, R13).** Both no-op paths (no remaining
  planning-state epics; no architecture) emit a `nothing to re-validate` note. The test
  greps both the Scout role and the Orchestrator role for that phrase + the two reasons.
- **The load-bearing fixture (R1, R7, R16).** A **temp** store (carrying the required root
  `project` field) holds (a) a `done` epic whose every feature is `done` and (b) a `draft`
  epic — the post-demotion shape. Assert both validate against `store/tasks.schema.json`
  (jsonschema if present, else the structural fallback that mirrors `init.sh`). This proves
  the epic-done rollup target and the demotion target are schema-valid **as-is**, with **no
  schema change**. The fixture is created with `mktemp`, cleaned on exit, and **never**
  touches the live `state/tasks.json`.
- **CHANGELOG marker grep (anti-pattern, 4× recurred).** The test reads `VERSION` at
  runtime, asserts it is semver, asserts the `CHANGELOG.md` has a `## [<VERSION>]` heading,
  **and** asserts a stable **drift-check marker** (e.g. `drift check`/`drift-check`) appears
  **somewhere in `CHANGELOG.md`** — grepped across the whole file, **not** coupled to the
  current-top-version section — so a later version bump never breaks this suite.
- **Sequencing:** store contract → orchestrator role → scout role → workflow doc → tests →
  config wiring → VERSION + CHANGELOG last (so the CHANGELOG heading matches the final
  VERSION).
- **Portability (R18).** The contract lives entirely in the portable role/store/doc files;
  the test asserts the rule's *presence in the portable files*, never anything about
  `.claude/` contents, and asserts F06 adds no new `.claude/commands/*` file.

## Risks
- **Regressing the Scout read-only contract (highest risk).** Adding a "drift-check mode"
  could be misread as granting write authority. Mitigation: R6 + the DO-NOT-TOUCH note pin
  the Scout to "writes only `progress/`, never `state/tasks.json`"; the test asserts the
  read-only language survives, and R8 puts the demotion write on the Orchestrator.
- **Regressing the feature-level rollup.** The epic-done rollup is added beside the
  sliced-feature rollup; a careless edit could entangle them. Mitigation: place the new prose
  in a clearly additive block, keep the feature rollup as DO-NOT-TOUCH, and run the **full**
  `verification.test_command` (all suites) to prove nothing else moved (R17).
- **The demotion-only-moves-backward safety.** Wording that lets F06 advance an epic, or
  demote an `in-progress`/`done` epic, would violate the core safety property. Mitigation:
  R10 states the backward-only invariant explicitly and excludes `in-progress`/`done`; the
  test greps for "backward", "never advance/forward", and the excluded statuses.
- **Auto-demote surprising a human.** Auto-demote (D1) is the chosen default; the risk is a
  human surprised by a re-gated epic. Mitigation: it only ever *adds* a gate (no work lost),
  every demotion is reported with its reason + the `/sdd-drill <epic>` re-drill pointer
  (R11), and the durable findings file records the full verdict (R4).
- **Over-claiming staleness (false demotes).** A vague signal could demote a still-fine
  epic. Mitigation: D2/R5 enumerate concrete S1/S2/S3 signals and default to **still-valid**
  unless ≥1 fires; the worst case of a false demote is one extra human `/sdd-drill`.
