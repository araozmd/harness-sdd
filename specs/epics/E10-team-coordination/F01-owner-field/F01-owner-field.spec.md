---
id: E10-F01
title: "Ownership primitive: owner field in TaskStore + scoped /sdd-next"
epic: E10-team-coordination
status: done             # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false
depends_on: []
owner: araozmd
---

# Ownership primitive: `owner` field in TaskStore + scoped `/sdd-next` — Functional Spec

## Context
The harness serves a solo developer and a team from one install, but the team path
has a gap. `/sdd-next` (the Orchestrator) selects the next actionable feature
**across the whole board**, and the local TaskStore entry carries **no `owner`**
(only the one-way GitHub board-mirror knows an `assignee`, and agents never read the
mirror). In a shared-repo umbrella the `state/tasks.json` is shared state, so two
developers each running `/sdd-next` race on the same file or pick overlapping work.
This feature makes ownership a **first-class, backward-compatible** field in the
TaskStore and lets a developer **scope** `/sdd-next` to their own work. It must not
regress the solo developer: with **no `owner` anywhere**, behavior is exactly as
today (board-wide selection).

This is the **foundation-first** slice of epic E10. It lays down the ownership
*primitive* only. The team-claim *rules* (claim epic → drill unassigned → claim
feature on select), "board/backend configured ⇒ team" mode detection, and any
release/reassign UX are **E10-F02**. A live authoritative store backend with atomic
remote claims is **E10-F03**. The board mirror stays a one-way projection.

## Business rules
- **`owner` is optional and additive.** Absent everywhere ⇒ today's behavior exactly
  (board-wide selection). Adding the field must not require any migration and must
  not break existing `state/tasks.json` files that carry no `owner`.
- **Two levels, feature wins.** Ownership may be recorded at the **epic** level and/or
  the **feature** level. A feature's **effective owner** is its own `owner` when set,
  otherwise its parent epic's `owner`, otherwise *unowned*.
- **Identity is a configured, team-stable value.** The current developer's identity is
  read from `workflow.identity` in `harness.config.yaml`. Setting it to `"@me"` (or
  `"self"`) resolves **dynamically** to the authed `gh` user login (via `gh api user`),
  mirroring the board-mirror `assignee` pattern, so a **shared** config reflects
  whoever runs `/sdd-next`. Any other value is treated as a literal identity string.
- **Scoped selection is owned-only.** Scoped `/sdd-next` (via `--mine`, or via a
  configured identity in scoped mode) selects only features whose **effective owner**
  equals the current identity. It does **not** claim unassigned work — claim-on-select
  is E10-F02.
- **Ownership never overrides the existing gates.** Scoping is applied **after** every
  existing `next()` rule (epic gate, `depends_on`-done, actionable-status, human-gate).
  A feature the current developer owns is still skipped if it is not otherwise
  actionable.
- **Owner comparison is literal.** Two identities match iff their resolved strings are
  equal. The harness performs no fuzzy/alias matching (git-name vs gh-login mapping is
  the operator's responsibility, resolved once via `workflow.identity`).
- **The board mirror stays one-way.** No agent reads the board to learn ownership;
  `state/tasks.json` remains the single source of truth. (Invariant preserved, not
  changed by this feature.)

## Architecture alignment
> This harness is a legacy-style repo that never ran `/sdd-plan`: there is **no**
> `specs/architecture.md` and **no** `specs/adr/` set. Per the Architect
> graceful-degradation rule, no citation is fabricated.

**ADRs touched: none** — the repo carries no `specs/architecture.md` and no
`specs/adr/*` (planning tier never ran), so there is no recorded decision to cite;
this spec proceeds from the inbox brief (`progress/inbox/E10-F01.md`) and the epic
notes (`specs/epics/E10-team-coordination/epic.md`) alone.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

- **R1** — The `store/tasks.schema.json` TaskStore schema shall define an **optional**
  string `owner` property on **epic** objects and on **feature** objects, and shall
  **not** add `owner` to either object's `required` list.
- **R2** — Where a `state/tasks.json` document carries **no** `owner` key on any epic
  or feature, the schema shall validate it as valid (byte-for-byte the pre-feature
  schema acceptance for owner-free documents), so the additive change breaks no
  existing store.
- **R3** — Where an epic or feature object carries an `owner` whose value is a string,
  the schema shall validate it as valid; if an `owner` value is present but is **not**
  a string, then the schema shall reject the document as invalid.
- **R4** — When `/sdd-next` is invoked with **no scope flag** and `workflow.identity`
  is unset/empty, the Orchestrator shall select the next actionable feature exactly as
  it does today (board-wide, unchanged `next()` ordering and gating), regardless of any
  `owner` values present.
- **R5** — When `/sdd-next --mine` is invoked, the Orchestrator shall consider **only**
  features whose **effective owner** (feature `owner`, else parent epic `owner`) equals
  the current resolved identity, and select the first such feature that is otherwise
  actionable by the existing `next()` rules.
- **R6** — The Orchestrator shall compute a feature's **effective owner** as its own
  `owner` when present, otherwise its parent epic's `owner`, otherwise treat the
  feature as **unowned**.
- **R7** — While `/sdd-next` is in scoped (`--mine`) mode, the Orchestrator shall
  **not** select an **unowned** feature and shall **not** claim, write, or mutate any
  `owner` value (no claim-on-select; that is E10-F02).
- **R8** — When resolving the current identity and `workflow.identity` is `"@me"` or
  `"self"`, the Orchestrator shall resolve it to the authed `gh` user login via
  `gh api user`; when it is any other non-empty value, it shall use that value
  verbatim as the identity string.
- **R9** — If scoped selection is requested (`--mine`) but the current identity cannot
  be resolved (`workflow.identity` unset/empty, or a `"@me"`/`"self"` lookup fails),
  then the Orchestrator shall **not** silently fall back to board-wide selection: it
  shall select no feature, report that the identity is unresolved, and change no state.
- **R10** — If scoped selection (`--mine`) yields **no** owned actionable feature, then
  the Orchestrator shall report "no owned actionable work" and change no state (it shall
  **not** widen to board-wide selection).
- **R11** — The Orchestrator contract change (`agents/orchestrator.md`) and the
  `/sdd-next` command body shall be expressed **tool-agnostically** (AGENTS.md-compatible
  wording, no Claude-Code-specific mechanism), so the same scoping behavior holds on
  every installed agent target.
- **R12** — The `/sdd-next` command glue carrying the scoped-selection front-end shall
  be **generated by `harness-install.sh`** into every selected agent target (Claude,
  OpenCode, Antigravity, Codex) from the single shared command body, byte-identical
  across targets.
- **R13** — The installed `/sdd-next` glue shall accept and forward the scope argument
  (`--mine`) through the command's `$ARGUMENTS`, and `tests/test_install.sh` shall
  **assert** that the generated `/sdd-next` body carries the scoped-selection wiring.
- **R14** — The documentation (`docs/WORKFLOW.md` and `store/local.md`) shall describe
  the optional `owner` field, the effective-owner resolution, the `workflow.identity`
  key, and scoped (`--mine`) selection, including the "no owner anywhere ⇒ today's
  behavior" guarantee.
- **R15** — Because this feature changes the installed body (`store/tasks.schema.json`,
  `agents/orchestrator.md`, the generated `/sdd-next` glue, docs), the `VERSION` file
  shall be bumped one **MINOR** step (additive, backward-compatible; SemVer MINOR, not
  MAJOR) in the same change.

## Out of scope
- Team-claim rules — claim an epic, drill *unassigned* features under it, claim a
  feature on `/sdd-next` — and "board/backend configured ⇒ team" mode detection with an
  explicit `mode: team|solo` override. **(E10-F02.)**
- Claiming/writing an `owner` on select (claim-on-select of unassigned work). **(E10-F02.)**
- Release / reassign / hand-over UX (unassigning a feature, moving work when a developer
  leaves). **(E10-F02.)**
- A live, read-authoritative store backend giving *atomic* remote claims
  (jira / gh-projects backend). **(E10-F03 — a store backend, not a mirror change.)**
- Making the board mirror bidirectional or having any agent read the board for
  ownership. **(Explicitly rejected — see epic notes.)**

## Open questions
- None blocking. The five brief open questions are **resolved** as design decisions
  (see `.plan.md` → "Resolved open questions"): (1) identity = configured
  `workflow.identity`, `@me`/`self` → `gh api user`, else literal; (2) both epic- and
  feature-level `owner`, feature wins; (3) scoping via `/sdd-next --mine` reading the
  configured identity; (4) scoped = owned-only, no claim-on-select (deferred to F02);
  (5) release/reassign deferred to F02. A human may still revisit the "unresolved
  identity fails closed" choice (R9/R10) at the approval gate.
