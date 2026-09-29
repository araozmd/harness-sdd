# Scout: drift-check on remaining planning-tier epics after E34 rollup

## Question
E34 ("Resource hygiene: bounded cleanup of scratch files, handoff files, and merged
worktrees/branches") just rolled up to `done` (E34-F01 merged via PR #230). Per the
Orchestrator's "Epic-done rollup + drift check" trigger, re-validate the remaining
`draft`/`planned`/`pending` epics against what E34 produced, using only the three
staleness signals (S1 contradiction, S2 removed/renamed reference, S3 explicit
supersede marker). Conservative default: still-valid.

## Remaining planning-tier epics (re-verified from live `state/tasks.json`)
- **E13** — Monday board integration — `draft`, 0 features seeded — `specs/epics/E13-monday/epic.md`
- **E14** — Azure Boards integration — `draft`, 0 features seeded — `specs/epics/E14-azure-boards/epic.md`
- **E32** — Harness feedback loop — `planned`; features F01–F04 `done`, **F05 `pending`**
  (only remaining open item) — `specs/epics/E32-feedback-loop/epic.md`

No other epic is `draft`/`planned`/`pending`; all others (including E34 itself) are
`done` or `in-progress` (E99, the standing maintenance epic, out of scope for this check).

## E34's produced artifacts (what was checked against)
- `specs/epics/E34-resource-hygiene/epic.md` — epic brief + notes
- `specs/epics/E34-resource-hygiene/F01-cleanup-discipline/E34-F01.spec.md` — functional
  spec, "Architecture alignment" section cites **ADR-0004 only** (existing ADR, not new)
- `tools/sweep-scratch.sh` (806 lines, new file) — scoped strictly to `scratchpad/`;
  explicitly refuses to touch `state/tasks.json` or anything outside `scratchpad/` (R12)
- Hooks added to `agents/orchestrator.md` (+15 lines), `agents/builder.md` (+8),
  `agents/reviewer.md` (+8), `agents/fixer.md` (+20/-1), `agents/pr-fixer.md` (+10) —
  all additive; only one deleted line across all five files (a fixer.md reword, not a
  removal of anything referenced elsewhere)
- No new ADR file: `specs/adr/` still holds exactly 0001–0006, unchanged by E34's PR
  (`git diff --stat 0a16042^..62d6c6a -- specs/adr/` is empty)
- No `specs/architecture.md` exists in this repo (confirmed absent) — but the ADR set
  under `specs/adr/` is present, so this is **not** the no-op/graceful-degradation case;
  there is something to re-validate against.

## Findings — per remaining epic

### E13 (Monday board integration) — **still-valid**
- No signal fires. E13's brief only mentions `tasks.json` projection, Monday GraphQL
  API + token (no-MCP transport), and relates to E11/E12 provider-adapter patterns and
  E10-F03 ownership backend — none of which E34 touched, renamed, or removed.
- No new ADR exists (S1 moot — nothing new to contradict E13's assumptions).
- No S2: E34 didn't rename/remove `tasks.json`, the GraphQL/no-MCP convention, or E10-F03.
- No S3: no supersede/obsolete marker anywhere in E34's diff names E13.
- `specs/epics/E13-monday/epic.md:1-29`

### E14 (Azure Boards integration) — **still-valid**
- Same reasoning as E13. E14's brief references Azure DevOps REST API + PAT (no-MCP),
  `store/board-mirror.md`'s existing `azure-boards` stub, and E11/E12/E10-F03 — none
  touched by E34.
- No S1 (no new ADR), no S2 (`store/board-mirror.md` untouched by E34's diff — confirmed
  not in E34's changed-files list), no S3 (no supersede marker names E14).
- `specs/epics/E14-azure-boards/epic.md:1-30`

### E32 (Harness feedback loop; F05 pending) — **still-valid**
- E34-F01's spec explicitly scopes itself *away* from E32's territory: "ADR-0006
  (feedback body marker) is scoped to E32's harness-defect reporting pipeline" and does
  not apply to the scratch sweep (`E34-F01.spec.md:71-72`). This is a deliberate
  non-overlap statement, not a contradiction.
- `tools/sweep-scratch.sh` only ever scans/mutates `scratchpad/`; it never touches
  `progress/feedback/notes.md`, `tools/harness-report.sh`, or any E32-owned path
  (verified: no `progress/` or `feedback` references in the tool's scope-defining lines;
  the tool `die`s if asked to act on anything outside `scratchpad/`).
- The `progress/feedback/notes.md` mentions found in `agents/builder.md:185-187`,
  `agents/reviewer.md:307-309`, `agents/pr-fixer.md:78-80`, `agents/fixer.md:407-408`,
  `agents/orchestrator.md:771-772` are the pre-existing "Reporting harness defects"
  section from E32-F03 — E34 did not add or change this section (confirmed by the
  role-file diff: those additions are the separate scratch-sweep hand-off hooks, not
  the feedback-reporting section).
- E34's own epic.md explicitly defers a `progress/`-handoff-file sweep and a
  worktree/branch sweep as **not-yet-seeded follow-on features** — so E34-F01 did not
  even attempt the `progress/` or triage-adjacent territory E32-F05 will eventually
  touch; there is no overlap to contradict.
- No S1 (no new ADR), no S2 (E32's referenced paths/commands — `feedback.*` config,
  `tools/harness-report.sh`, `progress/feedback/`, the labeler Action, ADR-0005/0006 —
  are all untouched by E34's diff), no S3 (no supersede marker names E32 or E32-F05).
- `specs/epics/E32-feedback-loop/epic.md:105-115` (Relevant ADRs section, unchanged),
  `specs/epics/E34-resource-hygiene/F01-cleanup-discipline/E34-F01.spec.md:67-72`
  (explicit ADR-0006/E32 scoping-out statement)

## Relevant files
- `state/tasks.json` — live epic/feature status (source of truth for the epic list above)
- `specs/epics/E13-monday/epic.md`, `specs/epics/E14-azure-boards/epic.md`,
  `specs/epics/E32-feedback-loop/epic.md` — the three remaining epic briefs
- `specs/epics/E34-resource-hygiene/epic.md`,
  `specs/epics/E34-resource-hygiene/F01-cleanup-discipline/E34-F01.spec.md` — E34's
  artifacts checked against
- `tools/sweep-scratch.sh` — E34-F01's sole new code artifact; scope-limited to
  `scratchpad/`, confirmed no overlap with E13/E14/E32 territory
- `specs/adr/0001`–`0006` — full ADR set; confirmed unchanged by E34's PR (no new ADR)

## Open questions / risks
- None. All three remaining epics verified still-valid against E34's actual artifacts
  (not just its title). No staleness signal fired for any of them.
- Note for the record (not a staleness signal, just an observation): E34's own epic.md
  names two deferred ideas (`progress/` handoff-file sweep; git worktree/branch sweep).
  **Post-merge correction (2026-09-29, PR #234):** E34 was closed `done` and these are
  now routed through a future, separate `/sdd-new` intake (a new epic or feature),
  **not** "under E34" as this note originally said — E34 is `done` and
  `agents/driller.md` refuses to operate on a `done` epic. Whenever either idea is
  eventually built (under whatever epic id `/sdd-new` allocates), a future drift-check
  should still re-check E32-F05 against it, since a `progress/`-handoff sweep is the
  territory closest to E32's `progress/feedback/` usage. Today neither idea exists yet,
  so there is nothing to re-validate against.
