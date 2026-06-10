---
description: Per-epic drill-down as Driller — decompose one draft epic into features + ADR deltas, then one epic-level approval (interactive)
---

Act as **Driller** (`agents/driller.md`). That role file is the durable contract; this
command carries the interactive front-end.

The target `<epic-id>` is in `$ARGUMENTS`. The `<epic-id>` is **required** — if
`$ARGUMENTS` is **empty**, STOP and **ask** the human for the epic id rather than drilling
an arbitrary epic.

1. Run `./init.sh`. If it exits non-zero, STOP and report — do not drill into a broken
   environment.
2. Read `harness.config.yaml` and the TaskStore (`state/tasks.json`, per `store/local.md`).
3. **Precondition guard.** Resolve `<epic-id>`. If it does not resolve to an existing epic,
   or the epic's status is **not** `draft` (`planned` / `in-progress` / `done` / legacy
   `pending`), a default run STOPS and reports why (missing / not-`draft`) — seed nothing,
   append no ADR, change no status. (Re-running on an already-`planned` epic is an explicit
   **amend** opt-in that appends features/ADRs above the current max without renumbering or
   re-flipping.)
4. Read the target `draft` epic (`specs/epics/<id>-<slug>/epic.md` + its `state/tasks.json`
   row) and F02's design artifacts (`specs/vision.md`, `specs/architecture.md`,
   `specs/adr/NNNN-*.md`) as inputs.
5. Run a short, **adaptive** Q&A with the human to settle the feature breakdown. Where the
   breakdown forks, offer **at most 3** options as **text-only** (markdown/ASCII) mockups —
   never images. Keep it short.
6. **Seed** the decomposition: write each new feature into the epic's `features` array
   (`status: "pending"`, `sdd: true`, one-line `title`, `spec_path`, intra-epic
   `depends_on`; ids as a next-sequential block strictly above the epic's max `F##`,
   append-only, no reuse); fill the `epic.md` feature table (one row per feature); and write
   a per-feature inbox brief at `progress/inbox/<E##>-F<NN>.md` from
   `specs/_templates/inbox-brief.md`, recording the `ADR-NNNN` ids each feature must honor.
7. **Append** any per-epic **ADR deltas** the decomposition forces at
   `specs/adr/NNNN-<title>.md` (4-digit, above the max existing ADR number, no reuse) — do
   NOT rewrite or renumber F02's existing ADRs. Stay at per-epic depth; defer feature-level
   design to the feature's own spec.
8. **Re-validate** `state/tasks.json` against `store/tasks.schema.json`. If it fails, report
   the failure and do NOT claim a successful drill.
9. Present the **single epic-level decision** (one decision, not per feature):
   - **approve** → flip the epic `draft → planned` and stamp `autonomous: true` on every
     seeded feature (all-or-nothing); or
   - **keep gated** → flip the epic `draft → planned`, leaving every seeded feature
     `autonomous: false` so each parks at the per-feature spec-approval gate.
   Re-validate again after the flip/stamp.
10. **Report** the seeded features (ids + titles + `spec_path`s), the inbox briefs + ADR
    ids, any ADR deltas, and the decision taken; tell the human to **run `/sdd-next`** to
    execute. Do NOT spawn the Architect, do NOT write any feature `.spec/.plan/.tasks/.tests`,
    and advance ONLY the target epic to `planned` — the Driller decomposes, never specs.
