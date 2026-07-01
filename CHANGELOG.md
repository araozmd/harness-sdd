# Changelog

All notable changes to the harness body are recorded here. Versions follow
[SemVer](https://semver.org/) and are stamped into every install's
`.harness/.harness-version` (see `CLAUDE.md` → Versioning).

## [0.24.0] — 2026-07-01

### Added — ✨ Board mirror: status-gated issue assignee (`mirror.board.assignee`)
- **`assignee` config key (`tools/sync-board.mjs`)** — the board mirror can now fill the
  provider's assignee/owner field from a new, provider-neutral `mirror.board.assignee` key.
  Assignment is **status-gated**: a feature's item gets the assignee once work has started
  (`in-progress`/`in-review`/`done`) and is **cleared** when it regresses to a not-started
  state (`pending`/`spec-ready`), so the board reflects who owns each item *right now*. When
  `assignee` is set the mirror **owns** the Assignees field for its items — the clear removes
  *every* current assignee, so under a shared `@me` config any runner also clears a teammate's
  stale assignment on a regressed item. Empty (the default) ⇒ the mirror never touches
  assignees, so a preserved config behaves exactly as before. Implemented for the
  `github-projects` provider; the `jira`/`azure-boards` stubs ignore it until wired.
- **Dynamic `"@me"` resolution** — `assignee: "@me"` (or `"self"`) resolves at sync time to
  the authed `gh` user via `gh api user`, so a shared-repo config reflects whoever runs the
  sync instead of hard-coding one login. Resolution failure degrades to "skip assignment this
  run" rather than erroring, and assignment is idempotent (the API call is skipped when the
  item already has the right assignee).
- **Docs + template parity** — `store/board-mirror.md` documents the key as provider-neutral
  (each tracker maps it to its own assignee/owner field) and the stub-provider guide tells
  new providers to honor it; `harness.config.yaml` and the installer's `migrate_config` mirror
  template both gain the commented `assignee: ""` default (append-only, existing configs
  preserved). `tests/test_mirror.sh` gains coverage: `@me` resolution + status-gated
  assign/unassign, and the assignee-unset back-compat no-op. **`VERSION` 0.23.1 → 0.24.0**
  (MINOR: new backward-compatible capability). Upstreamed from a downstream install so the
  canonical body now owns it and future upgrades no longer clobber a hand-carried copy.

## [0.23.1] — 2026-07-01

### Added — ✨ claude-mem-context block
- **Memory context block (`AGENTS.md`)** — adds `claude-mem-context` to the orchestrator documentation to maintain memory of recent context.

## [0.23.0] — 2026-06-12

### Added — ✨ Installer agent picker: arrow-key + spacebar checkbox UI (E99-F01)
- **Cursor-driven checkbox picker (`harness-install.sh` `tui_select`)** — on a raw-capable
  interactive TTY the agent front-end selector now renders the four agent keys
  (`claude gemini opencode antigravity`) as a checkbox list: ↑/↓ (or `k`/`j`) move a `>`
  cursor, **Space** toggles the highlighted row's `[x]`/`[ ]`, **Enter** confirms (`q`/Esc
  also confirm the current selection). This replaces the awkward type-a-number toggle model
  as the preferred interactive path. Pre-check state still seeds from the saved
  `.harness/.agents` set (or ALL on a fresh install), and only the resolved sorted keys
  (one per line) reach stdout, so the captured `SELECTED` contract is unchanged.
- **Graceful fallback (`tui_capable`)** — a capability probe detects whether `stty` can save +
  enter + restore raw mode on an interactive TTY. When raw mode is unavailable (no `stty`,
  non-interactive / piped stdin, sandboxed), `resolve_agents` falls back to the existing
  numbered `toggle_select`. The install never hard-fails on a terminal that can't do raw mode.
- **Guaranteed terminal restore** — raw mode is entered with `stty` and UNCONDITIONALLY
  restored via an `EXIT`/`INT`/`TERM` trap (plus an explicit restore on the normal completion
  path), so Ctrl-C or quitting never leaves the user's terminal stuck in raw mode; the cursor
  is re-shown too. All prompts/UI go to **stderr**.
- **No behavior change off the interactive path** — the no-TTY "ALL agents" default and the
  `--agents=` / `HARNESS_AGENTS=` override path are untouched; the picker only changes the
  interactive presentation. Portable POSIX sh, **no new binary dependencies**. `VERSION`
  bumped 0.22.0 → 0.23.0 (MINOR). `tests/test_install.sh` gains an E99-F01 group asserting the
  picker + capability probe + fallback wiring (the numbered fallback is what the suite
  exercises non-interactively). `tests/test_sdd_fix.sh` R17 now checks the installer-SEEDED
  store (throwaway target) for "no pre-seeded E99" instead of the mutable live
  `state/tasks.json`, which this repo legitimately populates while dogfooding its own
  `/sdd-fix` lane (permanent-suite anti-pattern fix). No canonical `agents/*.md` role file is
  touched.

## [0.22.0] — 2026-06-12

### Added — ✨ Antigravity native support
- **Antigravity glue (`harness-install.sh` §5c)** — Google Antigravity (a Gemini-based
  agentic IDE) is now a first-class, selectable harness target. On every run (gated on the
  `antigravity` agent key), the installer stamps a workspace-local `.agents/` tree that POINTS
  at the canonical `.harness/agents/*.md` roles — it never forks, copies, or redefines a role
  body. Antigravity natively reads `<root>/.agents/{rules,agents,workflows}/*.md` (plural —
  the dir its current build scans).
- **Entrypoint rule (`.agents/rules/harness.md`)** — a thin rule that loads the harness for an
  Antigravity session (Antigravity does not auto-load `AGENTS.md`): it points at
  `.harness/AGENTS.md` (source of truth) and `.harness/agents/orchestrator.md` (entry role),
  mandates `.harness/init.sh` first, and documents the working model. The root `GEMINI.md`
  pointer block (already written by §4) also serves Antigravity as the in-repo entrypoint.
- **Personas (`.agents/agents/{orchestrator,architect,builder,reviewer,scout}.md`) —
  best-effort** — one per harness role, each carrying a `description` and a body that
  defers to `.harness/agents/<role>.md`, runs `.harness/init.sh` first (halt on non-zero), and
  hands off via `.harness/progress/` files — no copied role body. Bare-file persona discovery
  is unconfirmed, so the personas are written (cheap, possibly honored) but the harness does
  NOT claim they register as Antigravity subagents.
- **Workflows (`.agents/workflows/{sdd-next,sdd-new,sdd-plan,sdd-drill,sdd-fix}.md`)** — the
  same five SDD slash commands, COPIED from the shared command bodies (mirroring the OpenCode
  block) so they stay byte-identical to the Claude/OpenCode copies and never drift. Each
  already carries the `description` frontmatter Antigravity needs to register `/<name>`.
- **Durable working model** — the confirmed primitives are the `.agents/rules/` entrypoint rule
  + the `description`-gated `.agents/workflows/` slash commands + `.harness/progress/` files as
  the hand-off / isolation boundary (not a Task-tool-style spawn, not an asserted bare-file
  subagent registration); the personas above are a best-effort layer on top.
- **No new dependencies; harness-owned + idempotent** — the `.agents/` glue is regenerated each
  run (like `.claude/` / `.opencode/`); deselecting `antigravity` removes ONLY harness-owned
  files that are byte-identical to a freshly-generated stamp (pristine) — never a user file that
  merely shares a standard name, and never `rm -rf` of a user `.agents/` dir. `VERSION`
  bumped 0.21.0 → 0.22.0 (MINOR). `tests/test_install.sh` gains an Antigravity assertion group
  covering R1–R13; no canonical `agents/*.md` role file is touched.

## [0.21.0] — 2026-06-11

### Added — ✨ Selectable agent targets (interactive selection + re-prompt on update)
- **Declarative agent registry (`harness-install.sh`)** — the four selectable coding-agent
  front-ends (`claude`, `gemini`, `opencode`, `antigravity`) are modeled as a small registry
  (`AGENT_KEYS`); each EXISTING per-agent stamp block is now **gated** on selection rather than
  always running. The shared portable entrypoint `AGENTS.md` is never gated — it is always
  written and never removed.
- **Interactive selection (zero new deps)** — on an interactive TTY with no override, the
  installer presents a pure-`read` numbered toggle list pre-checked from the saved selection
  (or ALL on a fresh install) and stamps only the chosen agents.
- **Non-interactive override + back-compat** — `--agents=<csv>` / `HARNESS_AGENTS=<csv>` resolve
  the set without prompting (the override always wins; an unknown key aborts non-zero, naming the
  token, with no changes). No-TTY + no override still stamps **ALL** agents, preserving the
  historical behavior so existing CI is unchanged.
- **Persistence + re-prompt-on-update** — the resolved set is persisted to `.harness/.agents`
  (one sorted key per line; dot-prefixed to avoid colliding with the `.harness/agents/` role-bodies
  dir), beside `.harness/.harness-version`. Every re-run re-resolves and reconciles **decoupled
  from VERSION/upgrade detection**: an **added** agent is stamped, a **deselected** agent's
  harness-owned regenerated glue is deleted — **scoped to the specific generated files**
  (its pointer block, the `orchestrator/architect/builder/reviewer/scout` shims, the `sdd-*`
  commands, a generated `opencode.json`); user-authored files sharing `.claude/`/`.opencode/`
  are preserved and those dirs are pruned only when left empty. `opencode.json` is removed only
  when **byte-identical** to the generated stamp — any user edit (e.g. an added `model`/providers
  key) leaves it in place with a warning — and each removed path is warned about. `AGENTS.md` and the
  `.harness/` body are never removed. Deselecting `antigravity` is a **no-op** while its stamp
  is a placeholder (E07-F01), so a user-authored `.agent/` directory is never deleted.
  An existing install with **no** persisted `.harness/.agents` (a pre-0.21 install that stamped
  all front-ends) is treated as the **all-agents baseline**, so the first selective upgrade can
  actually remove the now-deselected glue instead of leaving it stale.
- **Docs + tests** — `tests/test_install.sh` gains an assertion group covering R1–R15 (selected-only
  stamping, no-TTY ALL default, explicit override + precedence, unknown-key rejection, persistence
  round-trip, an add+remove re-run at the same VERSION, and the legacy-upgrade baseline removal).

## [0.20.0] — 2026-06-11

### Added — ✨ Drift check on epic rollup (Scout re-validates remaining draft/planned epics)
- **Epic-done rollup formalized (`store/local.md`, `agents/orchestrator.md`)** — when every
  feature of an epic is `done`, the Orchestrator now **derives and persists** the epic's `done`
  status and **re-validates** `state/tasks.json` — additively, beside the existing
  feature-level rollup, mirroring its "derive, then persist" discipline. No new status value,
  no schema change (`done` was already an epic enum value).
- **Scout drift-check mode (`agents/scout.md`)** — on that epic rollup the read-only Scout
  re-validates the remaining `draft`/`planned`/`pending` epics against what the completed epic
  produced and writes a per-epic still-valid/stale findings file to
  `progress/<run>/scout-drift-<epic>.md`. Staleness uses concrete signals only — **(S1)** a new
  ADR contradicts the brief, **(S2)** the brief references a removed/renamed thing, **(S3)** an
  explicit `supersedes E0X` / `obsoletes E0X` marker — stale only when ≥1 fires. The Scout's
  **read-only** contract is preserved: it writes only to `progress/`, never `state/tasks.json`.
- **Orchestrator-applied demotion (`agents/orchestrator.md`)** — the Orchestrator (not the
  Scout) demotes a stale `planned`/`pending` epic to `draft` via `set_status` and re-validates.
  Demotion only ever moves an epic **backward**; `in-progress`/`done` epics are never demoted;
  re-drilling a demoted epic back to `planned` stays a manual `/sdd-drill` step, reported as a
  pointer with an optional flag-only `demoted on drift:` `epic.md` note. The no-op paths (no
  remaining planning-tier epics, or no architecture) emit a clear "nothing to re-validate" note
  and change nothing — this drift check never fails silently.
- **Docs + tests** — `docs/WORKFLOW.md` gains a distinct "Drift check on epic rollup" section;
  `tests/test_drift_check.sh` (POSIX sh + python3, zero new deps) is wired into
  `verification.test_command`.

## [0.19.0] — 2026-06-10

### Added — ✨ Architect ADR-citation contract (architecture.md mandatory-when-present input; specs cite the ADRs they touch)
- **Amended Architect contract (`agents/architect.md`)** — the Architect now **consumes**
  the planning tier's durable design. When `specs/architecture.md` + `specs/adr/NNNN-*.md`
  are **present**, they are a **mandatory input** alongside the inbox brief, and the
  Architect reuses the **F03-D7 hook** (the touched `ADR-NNNN` ids the Driller already
  recorded in the brief) as the seed. Every feature `.spec.md` it writes carries a
  **`## Architecture alignment`** section citing each touched `ADR-NNNN` + a one-line "how
  this honors it"; **`ADRs touched: none`** is the explicit, legitimate no-touch state; a
  divergence is **stated in the section** (never an authored ADR delta — that stays F03's
  job).
- **Graceful degradation** — `present` means the file exists **and** carries real content
  (a bare/template-stub counts as **absent**). When architecture is absent (legacy repo or
  `/sdd-new` altitude-3), the Architect records the absence and proceeds from the brief
  alone — no fabricated citation, no failure, section not required. Existing pre-contract
  specs stay valid (no retro-fit). The rule also applies to umbrella shared specs,
  orthogonal to the contract-artifact reference.
- **`## Architecture alignment` template section** — `specs/_templates/feature.spec.md`
  gains the section (between `## Business rules` and `## Acceptance criteria (EARS)`) with
  the `ADRs touched: none` fallback, so every new spec has a consistent, checkable slot.
- **Additive Reviewer clause (`agents/reviewer.md`)** — a new
  `## ADR-citation check (architecture-aligned specs)` section that fires **only where**
  `specs/architecture.md` + ≥1 ADR exist **and** the feature is `sdd: true`; it confirms
  the `.spec.md` has a `## Architecture alignment` section citing ≥1 `ADR-NNNN` or stating
  `ADRs touched: none`. A missing/empty section is a **soft flag**, not a hard reject; the
  clause does not fire for legacy/no-architecture features or `sdd: false` brief-only items.
- **Docs** — `docs/SPEC-FORMAT.md` documents the section + cite-your-ADRs rule;
  `docs/WORKFLOW.md` gains a distinct "Architecture-aligned specs (the Architect cites
  ADRs)" section placing the contract relative to `/sdd-plan` + `/sdd-drill`; `README.md`
  gains a one-line note that feature specs cite the ADRs they touch.
- **Verification** — `tests/test_architect_adr.sh` (wired into
  `verification.test_command`): grep contract assertions over the role/reviewer/template/docs,
  a temp-dir markdown fixture proving the `## Architecture alignment` shape (both citing an
  ADR and `ADRs touched: none`) is internally consistent, and a temp JSON store fixture
  proving the citation needs **no** `store/tasks.schema.json` change.
- Purely additive / consume-only: F02 `/sdd-plan`, F03 `/sdd-drill`, the ADR
  format/numbering, the architecture/adr templates, `store/tasks.schema.json`, and every
  `/sdd-*` command are unchanged; a repo with no `specs/architecture.md` behaves exactly as
  today.

## [0.18.0] — 2026-06-10

### Added — ✨ `/sdd-fix` lightweight fix lane (maintenance epic, brief-only `sdd: false` intake)
- **New portable Fixer role (`agents/fixer.md`)** — a sibling of Inception / Planner /
  Driller that is the **brief-only intake** for the lightweight fix lane. It seeds **one**
  `sdd: false` fix under a single reserved maintenance epic, carrying only a one-paragraph
  inbox brief, and **hands it off to the existing `sdd: false → Builder → Reviewer` loop**.
  It is a thin front-end over the existing F01 primitive: **no new Orchestrator routing, no
  new TaskStore status, and no `store/tasks.schema.json` change**. It seeds and hands off —
  it never specs and writes no production code itself.
- **Reserved maintenance epic convention (`E99`)** — `/sdd-fix` creates the maintenance
  epic on first use (`id: "E99"`, slug `maintenance`, title "Maintenance (hotfixes & minor
  fixes)", `status: "planned"`, `features: []`, plus `specs/epics/E99-maintenance/epic.md`)
  and re-identifies the **same** epic **by id `E99`** on every later run (never a second
  bucket, never a renumber). `E99` is a deliberately high reserved number that already
  satisfies the `^E[0-9]+$` schema pattern (no schema change); `planned` is a selectable,
  non-`draft` status so the `next()` gate returns its fixes.
- **Brief-only `sdd: false` fix seeding** — each fix is appended as the next-sequential
  `F##` strictly above the epic's max (append-only, no reuse) with `sdd: false`,
  `status: "pending"`, a one-line title, and a recorded `spec_path` (directory **not**
  created), stamped **`autonomous: true` by default** (runs end-to-end) with a `--gated`
  opt-out that stamps `autonomous: false`. Exactly one fix-oriented inbox brief is written
  at `progress/inbox/<id>.md` from `specs/_templates/inbox-brief.md` — never a feature
  `.spec/.plan/.tasks/.tests`, never a `spec_path` directory, never the Architect. The
  Fixer re-validates `state/tasks.json` against `store/tasks.schema.json` after each write
  and fail-stops on an invalid store.
- **New `/sdd-fix` slash command (`.claude/commands/sdd-fix.md`)** — the interactive
  wrapper that acts as Fixer, reads the description from `$ARGUMENTS` (STOP if empty),
  offers ≤3 text-only options (never images), seeds the `E99` fix, re-validates, and hands
  off to the existing `sdd: false` loop in-session. Generated by `harness-install.sh` into
  `.claude/commands/sdd-fix.md` (resolving `.harness/agents/fixer.md`) and mirrored to
  `.opencode/command/sdd-fix.md`.
- **Additive Builder/Reviewer clarifications (`sdd: false` only)** — `agents/builder.md`
  now states that for an `sdd: false` item with no `tasks.md` the Builder works from the
  inbox brief as its worklist and still writes a test proving the fix; `agents/reviewer.md`
  now states that for an `sdd: false` item the Reviewer verifies behaviourally + the fix's
  test and that its R-id traceability check does not apply when there are no R-ids. Both
  edits are strictly additive — the `sdd: true` four-file path is unchanged.
- **`sdd: false` routing split by `autonomous` (coherence fix)** — the Orchestrator's
  `pending + sdd: false` route is split in two: `autonomous: true` **sets the feature to
  `in-progress`** (so the Builder's Loop A `in-progress` precondition holds) then spawns
  the Builder directly → `in-review`; `autonomous: false` (e.g. `/sdd-fix --gated`)
  **parks at the human gate** (not actionable until a human approves), so `--gated` is a
  real opt-out instead of a no-op. `agents/builder.md`, `agents/fixer.md`,
  `store/local.md`, and `docs/WORKFLOW.md` are aligned to this split.
- **Docs + tests** — `docs/WORKFLOW.md` documents the lightweight fix lane alongside
  "Selective SDD" (adds no new status, no new routing); `README.md` carries a one-line
  `/sdd-fix` mention beside the existing `/sdd-new` / `/sdd-plan` / `/sdd-drill` /
  `/sdd-next` command family; `tests/test_sdd_fix.sh` (wired into
  `verification.test_command`) covers the role/command/builder/reviewer/docs contract plus
  a schema fixture for the seeded `sdd: false`/`autonomous: true` fix inside a `planned`
  `E99` epic; R15/R16 installer assertions live in `tests/test_install.sh`. `/sdd-fix` is
  a lighter sibling of the heavier `/sdd-plan` and `/sdd-drill` planning skills — it never
  writes a feature spec or runs a drill.

## [0.17.0] — 2026-06-10

### Added — ✨ `/sdd-drill` per-epic drill-down skill (decompose draft epic, ADR deltas, epic-level approval)
- **New portable Driller role (`agents/driller.md`)** — a sibling of the Planner and the
  Architect that operates at the per-epic altitude. It is the **consumer that decomposes,
  never specs**: it takes exactly one `draft` epic, seeds `pending` feature entries (ids,
  one-line intents, `depends_on`, `sdd: true`, `spec_path`) into the epic's `features`
  array, fills the `epic.md` feature table, and writes a per-feature inbox brief under
  `progress/inbox/` (recording the `ADR-NNNN` ids each feature must honor). It allocates
  feature ids as a next-sequential block strictly above the epic's max `F##` (append-only,
  no reuse) and never writes a feature `.spec/.plan/.tasks/.tests` or spawns the Architect.
- **ADR deltas** — the Driller appends per-epic design decisions as one-decision ADRs at
  `specs/adr/NNNN-<title>.md` (4-digit, above the max existing ADR number, no reuse),
  scoped one level below F02's whole-system upfront ADRs, and never rewrites or renumbers
  F02's existing ADRs.
- **Single epic-level approval (approve / keep-gated branches)** — the drill ends in
  exactly one human decision at the epic granularity, realized solely through F01's
  `planned` state and the existing `autonomous` flag (no new status, no new approval
  mechanism, no schema change). **Approve** flips the epic `draft → planned` and stamps
  `autonomous: true` on every seeded feature (all-or-nothing); **keep gated** flips the
  epic `draft → planned` while leaving every feature `autonomous: false` so each parks at
  the per-feature spec-approval gate. `/sdd-drill` is the only step that flips an epic
  `draft → planned`.
- **New `/sdd-drill` slash command (`.claude/commands/sdd-drill.md`)** — the interactive
  wrapper that acts as Driller, reads the `<epic-id>` from `$ARGUMENTS`, STOPs on an
  empty/missing/non-`draft` target, runs the ≤3 text-only adaptive Q&A, and presents the
  single approve / keep-gated decision.
- **Docs** — `docs/WORKFLOW.md` gains a "Per-epic drill-down (`/sdd-drill`)" note placing
  it between `/sdd-plan` and `/sdd-next`; `README.md` gains a one-line `/sdd-drill` mention.
- **Verification** — `tests/test_sdd_drill.sh` (wired into `verification.test_command`):
  grep contract assertions over the role/command/docs plus one python fixture proving the
  decomposed shape (a `pending` feature inside a `planned` epic, stamped `autonomous: true`,
  with the required root `project` field) validates against `store/tasks.schema.json`.
- Purely additive: `/sdd-new`, `/sdd-plan`, `/sdd-next`, Inception, and the Planner are
  behaviorally unchanged; no schema change. MINOR `VERSION` bump → `0.17.0`.

## [0.16.0] — 2026-06-10

### Added — ✨ `/sdd-plan` whole-project inception skill (vision + architecture + draft epics)
- **New portable Planner role (`agents/planner.md`)** — a sibling of Inception that
  operates at the whole-roadmap altitude. It is a **producer that never specs**: it
  writes `specs/vision.md`, `specs/architecture.md` + one-decision ADRs at
  `specs/adr/NNNN-<title>.md`, and seeds a block of `draft` epics — and it never writes
  a feature `.spec/.plan/.tasks/.tests`, never spawns the Architect, and never advances
  an epic past `draft` (F03 `/sdd-drill` owns the `draft → planned` flip).
- **New `/sdd-plan` slash command (`.claude/commands/sdd-plan.md`)** — the interactive
  wrapper that acts as Planner, reads the idea from `$ARGUMENTS`, runs the ≤3 text-only
  adaptive Q&A, and reports the seeded epics + artifact paths.
- **New artifact templates** — `specs/_templates/vision.md` (problem/users/outcomes/
  non-goals; complements `product.md`/`glossary.md`), `specs/_templates/architecture.md`
  (system shape + stable upfront decisions + ADR index by `ADR-NNNN` id), and
  `specs/_templates/adr.md` (one-decision context/decision/consequences).
- **Draft-epic seeding** writes each epic with `status: "draft"` and `features: []` —
  the schema-valid empty-features shape (no placeholder `F01`, the deliberate difference
  from `/sdd-new`'s new-epic altitude) — allocating ids as a next-sequential block above
  the current maximum, append-only, no reuse.
- Purely **additive / backward-compatible**: `/sdd-new`, `/sdd-next`, and Inception are
  unchanged; a repo that never runs `/sdd-plan` validates and behaves exactly as before.
  `docs/WORKFLOW.md` + `README.md` updated; new suite `tests/test_sdd_plan.sh` wired into
  `verification.test_command`.

## [0.15.0] — 2026-06-10

### Added — ✨ Human-readable telemetry durations (`HH:MM:SS`) + table total row
- **`tools/telemetry-report.py` renders every duration as `HH:MM:SS`** instead of
  raw seconds (e.g. `00:13:11` not `791s`), across the session view and all calendar
  rollups — per-phase durations and human-gate latency alike. Hours are not capped at
  24 (a multi-day gate latency shows e.g. `48:00:00`), keeping the format unambiguous.
- **Per-phase breakdown tables gain a `**total**` row** (count + summed duration) so
  the session total lives in the table itself, not only the prose bullet below it.
- The change is output-only and backward-compatible: the JSONL telemetry record format
  (`duration_s`/`human_latency_s` in seconds) is unchanged; only the rendered report
  differs. Suite `tests/test_telemetry.sh` updated (R4/R9/R10 expectations) with a new
  `R4b` covering the `HH:MM:SS` format and the total row.

## [0.14.0] — 2026-06-10

### Added — ✨ Epic lifecycle: `draft`/`planned` states + `next()` draft gate
- **Epic `status` enum gains `draft` and `planned`** (`store/tasks.schema.json`,
  purely additive): canonical lifecycle is now `draft → planned → in-progress → done`,
  with epic-level `pending` kept indefinitely as a **legacy alias of `planned`**
  (gating-equivalent). Feature/slice status enums are unchanged; existing consumer
  `tasks.json` files validate as-is — no migration.
- **`next()` draft gate** (normative in `store/local.md` + `agents/orchestrator.md`,
  the portable contract files): features of a `draft` epic are **never actionable** —
  the Orchestrator never selects them, regardless of the feature's own
  `status`/`sdd`/`autonomous`/`depends_on` (`autonomous: true` skips the *human
  approval* gate, not this *planning* gate). `pending`/`planned`/`in-progress`/`done`
  epics impose no new gate.
- **Warn-only `init.sh` invariant**: a `draft` epic containing a feature whose status
  is not `pending` prints a ⚠️ warning naming the epic and feature, and still exits 0
  (the gate already neutralizes it; schema validation does not reject it). The
  zero-dependency fallback validator accepts the new epic statuses.
- Docs/template updates: epic-lifecycle section in `docs/WORKFLOW.md`, lifecycle
  status comment in `specs/_templates/epic.md`, and a `store/board-mirror.md` note
  that epic statuses (including `draft`/`planned`) never map to board columns.
- New test suite `tests/test_epic_lifecycle.sh` (R1–R14), wired into
  `verification.test_command`.

## [0.13.0] — 2026-06-08

### Added — ✨ `mirror.board.status_map` — keep existing board columns via config
- **`tools/sync-board.mjs` now reads an optional `mirror.board.status_map`** mapping each
  harness status to a board **column name** (e.g. `pending: "Todo"`, `done: "Done"`).
  Omitted ⇒ identity columns (unchanged default). This lets a team whose board already has
  custom columns adopt the shipped mirror **without editing `sync-board.mjs`** — so a
  `harness-install.sh` upgrade never clobbers the customization. Backed by a new
  dependency-free nested-map YAML reader (`yamlGetMap`). Config migration seeds a commented
  `status_map` example into the `mirror:` block.

## [0.12.0] — 2026-06-08

### Added — ✨ Pluggable board mirror + generic post-write sync hook
- **`tools/sync-board.mjs`** — a generic, provider-pluggable one-way **mirror** that
  projects `state/tasks.json` onto an external project board (issue/work-item per feature,
  Status + Epic fields, closes done / reopens regressed). `tasks.json` stays the source of
  truth; the board is a downstream projection agents never read. **Inert by default.**
  - Provider chosen by `mirror.board.provider`: `""`/`none` ⇒ no-op exit 0;
    **`github-projects`** implemented (config-driven `owner`/`project_number`/`repo`, needs
    `gh`); **`jira`** + **`azure-boards`** recognized as no-op **stubs**. No org/repo/tool is
    hard-coded; status columns default to the harness status names verbatim (identity map).
- **`store.on_write_command`** — a generic, **VCS/PM-neutral** post-write hook. When
  non-empty the Orchestrator runs it after any persisted store write
  (`<cmd> "<feature-id>" "<op>"`, cwd = `HARNESS_DIR`); empty (default) ⇒ no hook. Best-effort:
  a non-zero exit never rolls back `tasks.json` and never blocks the loop. The harness never
  learns what the command does (git push, board mirror, both). A team wires `sync-board.mjs`
  into it via config — the mirror tool is never hard-coded into the loop.
- Config migration seeds both `store.on_write_command` and the `mirror:` block on upgrade
  (append-only, value-preserving); `sync-board.mjs` is installed + `chmod +x` like the
  telemetry tool.

### Docs
- **New `store/board-mirror.md`** — the mirror contract, provider table, and the
  **mirror-vs-backend** distinction (one-way projection vs where state lives).
- **`store/README.md`** gains a "Mirrors vs backends" section; **`store/jira.md`** gets a
  backend-not-mirror cross-link; **`store/local.md`** documents "Post-write sync";
  **`agents/orchestrator.md`** gains the best-effort post-write-sync step.

## [0.11.0] — 2026-06-08

### Added — ✨ `--shared-repo`: version-control the umbrella as a shared spec repository
- **`harness-install.sh --umbrella <dir> --shared-repo`** makes the umbrella ROOT its own
  git repo — a *shared spec repository* that tracks `.harness/` (specs, `state/tasks.json`,
  progress) + the umbrella docs and **git-ignores the product child repos** (each stays its
  own repo, never a gitlink). Solves the "planning state stranded on one laptop" gap a team
  hits when several developers work the same umbrella. **Opt-in and inert by default**:
  without the flag the umbrella stays a non-git parent dir, byte-for-byte as before.
  - `git init` runs **only if the umbrella root has no `.git`** — an existing repo is never
    re-initialized; if `git` is absent the install continues and seeds the `.gitignore`.
  - The umbrella-root `.gitignore` is **append-seeded** with exactly the child repos the
    cascade discovered (never a blanket rule; never clobbers an existing file).
  - Works with `--dry-run` to preview the `git init` + ignore plan. Umbrella-mode only
    (`--shared-repo` without `--umbrella` is rejected).
- **New `umbrella.gitignore.example`** (shipped at the harness root, beside
  `umbrella.manifest.example.yaml`) documents the intended shared-spec-repo `.gitignore`
  shape: product repos ignored, `.harness/` + docs tracked, personal state ignored.

### Docs
- **`docs/UMBRELLA.md`** softens the absolute "No new git repo is introduced" claim into a
  default-vs-opt-in statement and gains a **"Shared spec repository (opt-in)"** section.
- **`docs/INSTALL.md`** gains a `--shared-repo` subsection under umbrella mode.

## [0.10.0] — 2026-06-08

### Added — ✨ Seed a project-root `.gitignore` for personal/runtime agent state
- **`harness-install.sh` now append-seeds the project-root `.gitignore`** with per-developer
  agent state — `.claude/settings.local.json`, `.claude/scheduled_tasks.lock`, and a
  commented `.playwright-mcp/` — so a **shared** spec/umbrella repo (a team clones the
  install) never carries one developer's local config. The seed is **append-only and
  idempotent**: it never clobbers an existing root `.gitignore` and only adds an entry that
  is missing, mirroring the existing `.harness/.gitignore` telemetry seeding. It ignores
  **specific files** under `.claude/`, never the whole dir, so the harness-generated
  `.claude/agents` and `.claude/commands` stay tracked and shared.

### Docs
- **New `docs/CONFIG-LAYERING.md`** — the shared-vs-personal config model (project layer =
  committed `CLAUDE.md`/`.harness`/`.claude` glue; personal layer = gitignored
  `settings.local.json`; user-global = `~/.claude/CLAUDE.md`). Directly answers "should every
  developer share the same `CLAUDE.md`?" (yes — keep it shared; push personal prefs to the
  user-global layer).
- **INSTALL.md** ownership table gains the project-root `.gitignore` under runtime/local and a
  pointer to `CONFIG-LAYERING.md`.

## [0.9.0] — 2026-06-07

### Added — ✨ Install `/sdd-next` + `/sdd-new` as OpenCode commands too
- **`harness-install.sh` now emits the slash commands to `.opencode/command/` as well as
  `.claude/commands/`.** Previously the commands were written only to the Claude Code
  command dir, so targets driven through OpenCode saw the agents but had no `/sdd-next`
  or `/sdd-new`. The command bodies are now authored once and written to both locations
  (identical content; no `agent:` frontmatter, so they run under the primary
  orchestrator agent defined in the generated `opencode.json`). Regenerated on every
  install/upgrade. Manifest updated to list `.opencode/command/*` as harness-owned.

## [0.8.0] — 2026-06-06

### Added
- **Config migration seeds the `telemetry:` block on upgrade.** `harness-install.sh`'s
  append-only `migrate_config` now adds the `telemetry:` block (`enabled` kill-switch +
  `log:` path) to a preserved pre-telemetry config, so an upgraded consumer gains the
  same discoverable config surface as a fresh install (a config without the block already
  worked — it defaults to enabled + `telemetry.jsonl`). Covered by `tests/test_cascade.sh`.

### Docs
- **README** gains an **Observability (telemetry)** section (report commands, local-only
  gitignored storage, the `telemetry:` config + `enabled` kill-switch, cost-out scope), a
  note on the Reviewer's cross-file consistency check + multi-round build↔review loop, and
  `tools/` in the layout.
- **INSTALL.md** documents the installed `tools/`, the seeded `.harness/.gitignore` + local-only
  `telemetry.jsonl`, the telemetry config migration, and a pre-v0.7.0 upgrade note; adds a
  `runtime/local` row to the ownership table.

## [0.7.0] — 2026-06-06

### Added — ✨ Sub-agent & human-gate telemetry with rollup reports (E05-F02)
- **Telemetry contract (`agents/orchestrator.md` "## Telemetry").** The Orchestrator —
  the single writer — now appends structured, best-effort, append-only JSONL records at
  every delegation boundary and gate transition: a `phase` record per sub-agent span
  (`architect`/`builder`/`reviewer`/`scout`/`inception`/`slice-dispatch`) with
  `start`/`end`/`duration_s`/`outcome`/`round`/`slice`, a two-line `gate` open/close pair
  carrying `human_latency_s` (the human spec-approval interval, with an `autonomous` flag),
  and a `session-start` marker delimiting each session. Timestamps are ISO-8601 UTC via
  `date -u`. Capture is **never on the critical path** — a failed/absent write never
  blocks a gate or build. Token/USD accounting is **out of scope**; a reserved `cost`
  field (null today) lets a future instrumented runtime populate it without a format
  migration.
- **Storage = local-only runtime data.** The log resolves to `<HARNESS_DIR>/telemetry.jsonl`
  (overridable via the new optional `telemetry:` block in `harness.config.yaml`;
  `enabled: false` is the kill-switch). It is **gitignored / never committed**: the source
  `.gitignore` ignores `/telemetry.jsonl`, and `harness-install.sh` seeds a targeted
  `.harness/.gitignore` (containing `telemetry.jsonl`, seed-once / never clobbered) so a
  consumer's committed harness body coexists with a local-only log.
- **Report script (`tools/telemetry-report.py`, python3 stdlib only).** Reads the JSONL
  log and emits text/markdown rollup tables at `daily`/`weekly`/`monthly`/`quarterly`/
  `semester`/`annual` granularity (default: an all-granularity summary), plus a `session`
  view scoped to the latest `session-start` marker that reproduces the Orchestrator's
  end-of-session summary (per-phase durations, build↔review round count, mean/median
  human-gate latency excluding autonomous transitions). Malformed lines are skipped; an
  absent/empty log exits 0 with a "no telemetry yet" notice.
- **Portable end-of-session summary.** The summary instruction lives in
  `agents/orchestrator.md` (plain prose + `python3 tools/telemetry-report.py session`,
  no Claude-Code-specific dependency) with a one-line pointer in `AGENTS.md`, so every
  AGENTS.md-compatible CLI surfaces the same text-only table.
- **Tests:** `tests/test_telemetry.sh` covering R1–R27 (fixture-driven rollups, best-
  effort/empty no-op, schema/format, the two gitignores, the AGENTS.md pointer), wired
  into `verification.test_command`.

## [0.6.0] — 2026-06-06

### Added — Reviewer cross-file consistency + explicit build↔review rounds
- **Cross-file consistency check (`agents/reviewer.md`).** The in-loop Reviewer now
  has a named "What you check" item for cross-file consistency: for any change to a
  role/contract/prose file it loads the **collaborators the diff references** (the
  unchanged files the change invokes), scoped to those references
  (curate-don't-dump, never a whole-repo dump), and verifies the change's
  preconditions are satisfied by — and do not contradict — the contracts it invokes.
  A **provably violated** precondition is a **hard reject**; a suspected-but-unproven
  inconsistency is **flagged for the Builder to justify** rather than blocked. Ships
  the canonical **PR #10 worked example** (an `orchestrator.md` dispatch step telling
  the Builder to open a child PR vs. `builder.md` Loop A's "Builder never opens a PR")
  — a contradiction with no failing test, exactly what this check catches. Rejects
  emit specific, actionable, **file-based** feedback (contradicting files + expected
  vs. actual) to `progress/<run>/review.md`.
- **Explicit multi-round build↔review loop (`agents/orchestrator.md`).** The
  build↔review handoff is now documented as an explicit loop that repeats **until
  green**: reject → actionable file feedback → `in-progress` → Builder addresses →
  re-review. **Each round is recorded** (one line per round in `progress/history.md`).
  No new status value and no schema change — the round counter lives only in
  `progress/` history. `docs/WORKFLOW.md` aligned to the multi-round loop.

## [0.5.0] — 2026-06-06

### Added — umbrella mode hardening (feedback pass)
- **`in-session` umbrella dispatch is now a first-class, documented mode.** The
  coordinator loop previously documented slice dispatch *only* via an external
  `delegate_cmd` — but the shipped default is `execution.builder.backend: in-session`,
  which has no executor, so the documented path dead-ended on a fresh install.
  `agents/orchestrator.md` and `docs/UMBRELLA.md` now branch dispatch on
  `execution.builder.backend`: under `in-session` (default) the Orchestrator spawns the
  Builder sub-agent `cd`'d into each child repo (zero-dependency, the natural
  single-session path); under `delegate` it uses the `delegate_cmd` seam. `delegate_cmd`
  is now documented as optional and ships empty in `umbrella.manifest.example.yaml`.
- **Contract artifact is now prompted and enforced.** `agents/architect.md` gained an
  Umbrella-mode section making the single pinned inter-repo contract artifact
  **mandatory** for any feature with `slices[]`, with every slice required to reference
  it (prevents inter-repo field drift). `agents/reviewer.md` gained a matching check:
  a sliced feature is rejected unless the pinned contract exists and the slice under
  review traces its wire fields/shapes to it.
- **Cascade preview: `harness-install.sh --umbrella … --dry-run` (alias `--list`).**
  Lists the coordinator + every git child that would be installed (with skip reasons),
  writing nothing — so the cascade no longer surprises you by scaffolding untouched
  repos. The activation message now states explicitly that pointing `umbrella.manifest`
  ENGAGES umbrella mode.

### Changed
- Documented the two manifest path bases (the `umbrella.manifest` value resolves
  relative to `.harness/`; each entry's `path:` resolves relative to the manifest's own
  dir) in `harness.config.yaml`, `umbrella.manifest.example.yaml`, and `docs/UMBRELLA.md`.
- Clarified in `init.sh` that `.harness/init.project.sh` is for FAST structural/presence
  checks only — the heavy test suite belongs in `verification.test_command` (Reviewer-run,
  once at the `in-review` gate), not in the per-step gate.

## [0.4.0] — 2026-06-01

### Added — Inception role + /sdd-new intake (E04-F01)
- **Inception role (`agents/inception.md`):** the portable, model-interchangeable
  front door *before* `pending`. Takes a raw idea, triages it to exactly one altitude
  (new task on an existing not-`done` feature / new feature under an existing epic /
  new epic + `epic.md` + first `F01`), allocates a **next-sequential** id (no reuse of
  vacated ids), writes a `pending` TaskStore entry, re-validates `state/tasks.json`
  against `store/tasks.schema.json` (fail-stop: a failed validation is never a
  success), and writes an intent brief to `progress/inbox/<feature-id>.md`. It
  **seeds; it never specs** — it never writes the four spec files, never advances
  status past `pending`, and never spawns the Architect.
- **`/sdd-new` slash command (`.claude/commands/sdd-new.md`):** thin Claude wrapper
  that carries the interactive adaptive Q&A and ≤3 **text-only** mockup options,
  taking the idea via `$ARGUMENTS` and deferring the durable contract to the role
  file. Ends by reporting the seed + "run `/sdd-next`".
- **Installer ships `/sdd-new`:** `harness-install.sh` now emits an installed
  `.claude/commands/sdd-new.md` wrapper (with all paths rewritten to `.harness/…`)
  alongside `/sdd-next`, so consumer repos get the Inception intake command too.
  The installed wrapper mirrors the source's altitude-dependent write step (the
  altitude-1 reuse-and-append branch keyed on the existing feature's status) and
  copies its inbox brief from the shipped `.harness/specs/_templates/inbox-brief.md`
  template instead of the un-shipped `E04-F01.md` example; `tests/test_install.sh`
  asserts the template path, the absence of `E04-F01`, and the altitude-1 branch.
- **Docs:** `AGENTS.md` role list + flow now name Inception; `docs/WORKFLOW.md`
  documents the pre-`pending` intake step feeding the unchanged state machine.
- **Tests:** `tests/test_inception.sh` covering R1–R16 (static file/format/grep +
  schema validation), wired into `verification.test_command`.
- **Purely additive:** no change to `store/tasks.schema.json`, no new status value,
  and no change to the Orchestrator or Architect contracts.

## [0.3.0] — 2026-05-31

### Added — Cascade installer (E03-F02)
- **Umbrella install mode:** `harness-install.sh --umbrella <dir>` installs a
  coordinator profile in the umbrella directory, scans its immediate children, and
  installs the normal `.harness/` into each child that is a git repo (`.git` as a
  directory **or** a file). `--recursive` opt-in for deeper scans. Bare
  `harness-install.sh <target>` is byte-for-behavior unchanged (hard non-regression).
- **Manifest auto-population:** discovered repos are upserted into
  `umbrella.manifest.yaml` (path discovered; `init`/`test_command`/`delegate_cmd` as
  bootstrap TODOs). Idempotent — re-runs append new repos and never clobber
  project-owned entry fields. Repo-key grammar `^[a-z0-9-]+$` validated; violators are
  skipped with a message rather than written as undispatchable entries.
- **Non-destructive config migration:** on upgrade, missing umbrella keys
  (`umbrella.manifest`, `verification.integration_command`) are appended to a preserved
  `harness.config.yaml` without altering existing values/comments — fixes the case
  where a pre-0.2.0 install could never opt into the coordinator. Append-only and
  idempotent.
- **Tests:** `tests/test_cascade.sh` covering R1–R24, wired into
  `verification.test_command`.

## [0.2.0] — 2026-05-30

### Added — Multi-repo coordination (E03-F01: Umbrella coordinator)
- **TaskStore schema:** optional `slices[]` on a feature (`id`, `repo`, `status`,
  `merged`, `spec_path`, cross-repo `depends_on`). Pure superset — single-repo
  stores validate unchanged.
- **Umbrella manifest:** `umbrella.manifest.example.yaml` mapping each child repo to
  its `path` / `init` / `test_command` / `delegate_cmd`. Manifest presence is the
  opt-in switch for umbrella mode.
- **Config:** additive `verification.integration_command` (feature-level stack-up
  check) and `umbrella.manifest` keys. No existing key changes meaning.
- **Orchestrator "Umbrella mode"** (additive section, no role fork): topological
  slice select, dispatch via the existing `execution.builder.delegate` seam, gate
  downstream slices on upstream `done`+`merged`, fail-stop, and a derived feature
  `done` rolled up behind the integration gate.
- **Docs:** `docs/UMBRELLA.md` describing the coordinator model.
- **Tests:** `tests/test_umbrella.sh` covering R1–R19, wired into
  `verification.test_command`.

## [0.1.0]

### Added
- Initial harness body: installer (`harness-install.sh`), `init.sh` gate, the
  Orchestrator/Architect/Builder/Reviewer/Scout roles, the 4-file spec format, and
  the local/obsidian/jira store contract.
