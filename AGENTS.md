# AGENTS.md — harness-sdd

This is the canonical entrypoint for the portable Spec-Driven Development (SDD)
harness. Claude Code is the primary host, Codex second, OpenCode third. The
harness lives in its files; each role starts with a clean, curated context.

## Start every session

1. Run `./init.sh` **before any work**. If it exits non-zero, **STOP and report**;
   never repair the environment and continue in the same run. **One narrow exception,
   reporting only:** when that non-zero exit is a harness malfunction
   (`harness-malfunction`), the session may call the reporter **once**
   (`tools/harness-report.sh`, trigger `harness-malfunction`) as the *report*, and then
   stops. That call makes **no repair** and **no board write**, the session **does not
   continue**, and reporting is **never a way around the gate**. The local backend
   requires `python3` with stdlib `fcntl`; board writes use
   `python3 tools/tasks-lock.py`.
2. Read `harness.config.yaml` to select the TaskStore and DocStore backends.
3. Read `progress/lessons.md`, then `agents/orchestrator.md`; assume the
   **Orchestrator** role, read the TaskStore, and route the next actionable task.
4. Follow [the workflow](docs/WORKFLOW.md), delegating through files on disk.

## Workflow and gates

A **new product** plans before it builds: run `/sdd-plan` (`$sdd-plan` in Codex) for
whole-project inception (vision, architecture, ADRs, draft epics), then `/sdd-drill
<epic-id>` (`$sdd-drill` in Codex) to decompose an epic into features, then `/sdd-next`
(`$sdd-next` in Codex) to spec and build.
For **later work**, Inception is the front door before the Orchestrator loop: `/sdd-new` (`$sdd-new`
in Codex) turns an idea into a pending task and intent brief, and `/sdd-next`
specs and builds it.
The loop is Orchestrator → Architect → Builder → Reviewer; Scout
assists read-only. Role definitions live in `agents/`.

- Pass only the role, relevant specs/tasks, and `progress/` notes to a fresh role
  context. **Never forward another agent's chat history.** Read only what you
  need and write what you did to `progress/`.
- The Architect moves a spec from `pending` to `spec-ready` and **pauses**.
  A human or an explicitly autonomous task must authorize `in-progress` before
  the Builder writes code. See [human gates](docs/WORKFLOW.md).
- Only an **independent Reviewer** may verify completion: tests pass via
  `init.sh` and configured verification, and behavior matches the approved spec.
  An implementer's claim is never a `done` verdict.
- Prefer shell commands and files; keep tools minimal. Store contracts and
  adapters live in `store/`; the local board is `state/tasks.json`.
- The Orchestrator prints end-of-session telemetry (phase durations, review
  rounds, human-gate latency; no tokens or USD). Follow
  [Orchestrator → Telemetry](agents/orchestrator.md#telemetry).

## Reporting harness defects

Report exactly these four **harness defects** — the only reportable conditions — and nothing
else:

- **`harness-malfunction`** — a harness script such as `init.sh`, `harness-install.sh`,
  `tools/*`, or a TaskStore write fails while the project itself is healthy.
- **`contradictory-instruction`** — role prompts or docs conflict, or a gate cannot be
  satisfied as written.
- **`workaround`** — you had to leave the documented workflow to finish.
- **`missing-capability`** — a recurring situation has no path in the workflow.

A failure of the project's own code or tests, a transient network or auth error, and an
agent mistake the harness correctly caught are **not** triggers: **none of them produces a
report**.

**When.** File a report when the task ends **or** when the session stops early (aborted,
parked, or failed). Never file mid-flow.

**Who.** Only the **session-owning top-level role** — the Orchestrator, or Fixer / Inception /
Planner / Driller when it owns the session — invokes `/sdd-report` (Codex: `$sdd-report`), and
it mints `HARNESS_FEEDBACK_SESSION_ID` **once per session** (the telemetry `session-start`
`started_at` with every character outside `[A-Za-z0-9._-]` removed, or
`date -u +%Y%m%dT%H%M%SZ` when no marker exists) and reuses it for every report. Sub-agents
(Architect, Builder, Reviewer, Scout, Doc-critic, pr-fixer) **never** invoke the reporter: on
a trigger they append one entry to `progress/feedback/notes.md` — a `## <trigger>` heading
plus `symptom:` / `command:` / `phase:` (and an optional harness `file:`) — for the owning
role to pick up.

## Specifications and memory

`specs/product.md` is the product constitution; feature specs live under
`specs/epics/<epic>/<feature>/` as `.spec`, `.plan`, `.tasks`, and `.tests` files.
Use [the spec standard](docs/SPEC-FORMAT.md). Session output and earned lessons
live in `progress/`; append the durable changelog to `progress/history.md`.

| Reference | Purpose |
|---|---|
| `docs/RATIONALE.md` | Why the harness exists; the two-layer deletion ledger |
| `docs/WORKFLOW.md` | State transitions and human gates |
| `docs/SPEC-FORMAT.md` | EARS, four-file specs, and traceability |

## Branch, review, and release lifecycle

- Every new feature or bug gets its own branch. Update README and current docs
  before finishing a feature; after local verification and tests pass, create
  a PR for review.
- Wait for that branch to merge before starting another feature, unless the
  next task is explicitly autonomous. After merge, delete the local and remote
  feature branches and return to `main`.
- `VERSION` is a public installer contract. Bump it deliberately in the same PR
  when the installed body changes: `harness-install.sh`, `init.sh`, `agents/`,
  `docs/`, `store/`, `specs/_templates/`, `harness.config.yaml`, or `.claude/`
  glue. Docs-only, demo-spec, and CI changes do not need a bump.
- Use PATCH for body/installer fixes, MINOR for a capability, and MAJOR for a
  breaking layout or TaskStore schema change requiring target migration.
  Record the release in `CHANGELOG.md` and tag the merge commit `vX.Y.Z`.
