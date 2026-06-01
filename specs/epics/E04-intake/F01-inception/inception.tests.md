# Inception role + /sdd-new intake — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete,
> executable check. The Reviewer fails the feature if any R-id lacks a passing check.
>
> This feature ships **prose, not runtime code** (a portable role file + a Claude
> slash command + two doc edits). So the contract is two layered checks:
> 1. **Static assertions** — scriptable file-existence / format / required-phrase
>    checks in the style of `tests/test_install.sh` (zero deps, POSIX sh + `grep` +
>    `python3` for schema validation). These go in a new `tests/test_inception.sh`.
> 2. **Manual `/sdd-new` walkthrough** — a documented, repeatable session on a sample
>    idea that must produce a schema-valid `pending` entry plus a well-formed inbox
>    brief. The Reviewer performs it once and records the result.

## Traceability matrix

| R-id | Behavior | Check (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | Portable Inception role file exists, defines the intake contract, is not Claude-specific | `tests/test_inception.sh::role_file_exists` (assert `agents/inception.md` exists; grep for "seed"/"pending"/"brief"; assert no Claude-only assumptions) | static | ⬜ |
| R2 | `/sdd-new` slash command exists, takes the idea, points at the role file | `tests/test_inception.sh::sdd_new_command` (assert `.claude/commands/sdd-new.md` exists; grep `agents/inception.md` and `$ARGUMENTS`) | static | ⬜ |
| R3 | Seed writes a valid `pending` feature entry with all required fields | manual walkthrough §A + `tests/test_inception.sh::seed_entry_schema_valid` (after walkthrough, validate the new entry has id/title/status:pending/sdd/autonomous/depends_on/spec_path) | static + manual | ⬜ |
| R4 | Seed writes `progress/inbox/<id>.md` whose name == the new entry id | manual walkthrough §A + `tests/test_inception.sh::inbox_brief_exists` (assert file at `progress/inbox/<id>.md` matching the seeded id) | static + manual | ⬜ |
| R5 | Brief has required frontmatter + sections | `tests/test_inception.sh::inbox_brief_format` (grep frontmatter `feature`, `seeded_by: inception`, `date`; grep the section headers) | static | ⬜ |
| R6 | tasks.json re-validated against schema after write | `tests/test_inception.sh::tasks_schema_valid` (`python3 -c "import json; json.load(open('state/tasks.json'))"` + jsonschema validate against `store/tasks.schema.json`) | static | ⬜ |
| R7 | Validation failure ⇒ reported as non-success | manual walkthrough §C (inject a deliberately invalid edit during a dry run; confirm the role instructs reporting failure, not "seeded") + grep role file for the fail-stop instruction | manual + static | ⬜ |
| R8 | Triage resolves to exactly one altitude | `tests/test_inception.sh::triage_documented` (grep role file for the three altitudes) + manual walkthrough §A/§B exercise two altitudes | static + manual | ⬜ |
| R9 | "New epic" creates epic entry + `epic.md` + first F01 | manual walkthrough §B (seed a brand-new epic; assert new `E##` entry, `specs/epics/<slug>/epic.md`, and `F01` exist) | manual | ⬜ |
| R10 | Ids are next-sequential, no reuse of vacated ids | `tests/test_inception.sh::id_policy_documented` (grep role file for next-sequential + no-reuse rule) + manual walkthrough §B (seeded id == max+1) | static + manual | ⬜ |
| R11 | Inception never writes any spec file | `tests/test_inception.sh::no_spec_writes` (grep role file states it must not write `.spec/.plan/.tasks/.tests`) + manual walkthrough §A asserts no such files appear | static + manual | ⬜ |
| R12 | Inception only writes `status: pending`, never advances | `tests/test_inception.sh::pending_only` (grep role file for "pending"-only + never-advance rule) + manual walkthrough §A asserts seeded status == `pending` | static + manual | ⬜ |
| R13 | No change to schema / orchestrator / architect; no new status | `tests/test_inception.sh::do_not_touch_clean` (assert `store/tasks.schema.json`, `agents/orchestrator.md`, `agents/architect.md` unchanged by this feature's diff; assert schema status enum unchanged) | static | ⬜ |
| R14 | Options/mockups are text-only, ≤3 | `tests/test_inception.sh::text_only_options` (grep role + command files for text-only + "at most 3" constraint) | static | ⬜ |
| R15 | Completion report names id + entry + inbox path + "run /sdd-next" | `tests/test_inception.sh::completion_report` (grep role/command for the report contract incl. `/sdd-next`) + manual walkthrough §A confirms it printed | static + manual | ⬜ |
| R16 | Docs describe the pre-`pending` intake step | `tests/test_inception.sh::docs_mention_intake` (grep `AGENTS.md` for Inception in the role list; grep `docs/WORKFLOW.md` for `/sdd-new` pre-`pending` step) | static | ⬜ |

## Behavioral / end-to-end checks (manual `/sdd-new` walkthrough)

The Reviewer runs `/sdd-new` once per scenario from a clean working tree and records
the result. (Run on a scratch branch / copy so the seeds can be reverted.)

- **§A — new feature under an existing epic.** Run `/sdd-new "add a CSV export to the
  dashboard"`, answer the Q&A. Then assert:
  - a new `pending` feature entry appears under the existing dashboard epic with all
    required fields (R3, R12);
  - `progress/inbox/<new-id>.md` exists and is well-formed (R4, R5);
  - `state/tasks.json` validates against the schema (R6);
  - no `.spec/.plan/.tasks/.tests` file was created (R11);
  - the completion report named the id, the entry, the inbox path, and "run /sdd-next"
    (R15); options offered (if any) were text-only and ≤3 (R14).
- **§B — new epic.** Run `/sdd-new "a brand-new billing area"`. Assert a new `E##`
  entry (== current max epic id + 1), a `specs/epics/<slug>/epic.md`, and a seeded
  `F01` (R8, R9, R10).
- **§C — validation fail-stop (dry run).** Confirm the role file's contract: if the
  post-write schema check fails, Inception reports the failure and does not claim a
  successful seed (R7). Optionally simulate by hand-corrupting a copy of
  `state/tasks.json` and confirming the documented check would flag it.

## Non-functional checks
- `./init.sh` exits zero with the new files in place.
- `tests/test_inception.sh` exits zero (run alongside the existing `tests/*.sh`).
- No diff to `store/tasks.schema.json`, `agents/orchestrator.md`, `agents/architect.md`
  in this feature's changeset (R13).
