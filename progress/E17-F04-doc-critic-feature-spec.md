---
feature: E17-F04
agent: doc-critic
target-type: feature-spec
date: 2026-08-12
---
# Doc-critic — E17-F04 four-file spec (advisory)

## Files reviewed

- `specs/epics/E17-model-routing/F04-worker-roster/E17-F04.spec.md`
- `specs/epics/E17-model-routing/F04-worker-roster/E17-F04.plan.md`
- `specs/epics/E17-model-routing/F04-worker-roster/E17-F04.tasks.md`
- `specs/epics/E17-model-routing/F04-worker-roster/E17-F04.tests.md`

Context read: `progress/inbox/E17-F04.md`, `progress/E17-F04-scout.md`,
`specs/epics/E17-model-routing/epic.md`, `agents/architect.md`, `docs/SPEC-FORMAT.md`,
all four ADRs under `specs/adr/`, `harness.config.yaml`, and `harness-install.sh`
(`AGENT_KEYS`, `HOST_MARKERS` + provenance, `detect_host`, `write_escalation_arming`,
`escalation_arming_is_symlinked`, `migrate_config`, `seed_pr_loop_optin`, the `_ignores`
seeding of `.harness/.gitignore`, `install_one` call sites) plus
`tests/test_agents_host.sh` and `tests/test_installer_toggles.sh`.

## Factual claims about `harness-install.sh` — VERIFIED TRUE

- `grep -n "command -v" harness-install.sh` → exactly 4 hits, none a front-end CLI:
  `stty` (1420), `node` inside a commented example (2417), `git` (3959, 5860).
- `HOST_MARKERS` (958) is consumed only by `detect_host`; its comment block states the
  session-markers-only rule, the R6 forbidden-name list and the R8 empirical-verification
  rule. It answers "who launched me", not "what is installed". Confirmed.
- `write_escalation_arming` (3206, called from `install_one` at 5165) is genuinely the
  closest precedent: symlink guard first (`escalation_arming_is_symlinked`, 3112), then a
  gate, then reclaim-with-`info` when the gate is off, and `$AGENT_KEYS`-order emission for
  byte-stability. Confirmed.
- `migrate_config`'s `telemetry:` case (164) is a top-level append-only EOF block, and
  `seed_pr_loop_optin` (514) forces the opt-in default on seed. Both true as cited.
- `_ignores` (2533) seeds/ensures `.harness/.gitignore`. True — but it runs
  **unconditionally**, which the plan does not account for (finding C2).

## ADRs touched: none — JUDGED CORRECT

Read all four. ADR-0001 (deterministic `next()` selection) — the roster selects no work.
ADR-0002 (`builder-heavy` is a tier) — no role, no tier, no `MODEL_ROLES` entry.
ADR-0003 (one shared `.agents/skills/` unit) — no skill unit. ADR-0004 (umbrella pointer
stubs) — nearest miss: its consequences say "the tier line must be defended per file",
but `.harness/workers.json` is installer-generated local state, not a copied body file,
the same status `telemetry.jsonl` and `.escalation-arming` hold. Declaration stands; one
clause naming ADR-0004 and that reasoning would make it audit-proof.

## Size budget

12 distinct R-ids (R1–R12), each referenced by at least one task and one test row; every
R-id appears in `.plan.md` and `.tasks.md`. Count is right, budget is met exactly.
The demotion of "roster JSON validity" is defensible on redundancy grounds (R4/R5/R7 all
require parsing the file), but the spec states the wrong *reason* for it (S3).

## Findings (14, advisory)

Consistency: C1 R2's byte-identity claim contradicts the plan's config key and gitignore
line; C2 R11 is gated while T8's `_ignores` is unconditional; C3 the plan's
`write_escalation_arming` model filters by `agent_selected` and the roster must not, which
is unstated and untested; C4 `harness-frontend` is constant across every entry by
construction; C5 the new provenance comment placed "beside `HOST_MARKERS`" can be absorbed
by `tests/test_agents_host.sh`'s positional `/^# PROVENANCE/ … /^HOST_MARKERS="/` range;
C6 the epic says "non-host CLIs" and the roster includes the host; C7 the R6 quote is
misattributed; C8 "a human toggling `AGENT_KEYS`" misdescribes the picker.

Completeness: P1 no seeded-vs-migrated convergence rule or test for the new `workers:`
block; P2 no R-id governs capability *content* — R7 is vacuously satisfiable; P3 no R-id
requires an entry to name the CLI it describes; P4 R8's test has no positive control that
the roster path ran.

Scope/YAGNI: S1 umbrella cascade writes N identical rosters, unaddressed; S2 `host-detectable`
is weakly motivated for a router; S3 the JSON-validity demotion is justified by budget
rather than by redundancy.

Full text, with quotes and recommended fixes, returned to the Architect in the invocation
response. No spec file was edited by this pass — fixes are the Architect's to apply inline.
