---
name: sdd-drill
description: Per-epic drill-down as Driller — decompose one draft epic into features + ADR deltas, then one epic-level approval (interactive)
---

## Invocation adapter

In Antigravity or OpenCode, invoke `/sdd-drill`; in Codex, invoke `$sdd-drill` and write arguments after the skill mention. In all hosts, treat all accompanying text as `$ARGUMENTS` in the workflow below. Wherever that workflow writes a portable `/sdd-<name>` reference, the Codex invocation is `$sdd-<name>` and the Antigravity or OpenCode invocation is `/sdd-<name>`.

## Canonical workflow
Act as **Driller** (`agents/driller.md`). That role file is the durable
contract; this command carries the interactive front-end.

The target `<epic-id>` is in `$ARGUMENTS`. The `<epic-id>` is **required** — if
`$ARGUMENTS` is **empty**, STOP and **ask** the human for the epic id rather than drilling
an arbitrary epic.

1. Run `./init.sh`. If it exits non-zero, STOP and report — do not drill into a
   broken environment.
2. Read `harness.config.yaml` and the TaskStore (`state/tasks.json`, per
   `store/local.md`).
3. **Precondition guard.** Resolve `<epic-id>`. If it does not resolve to an existing epic,
   or the epic's status is **not** `draft` (`planned` / `in-progress` / `done` / legacy
   `pending`), a default run STOPS and reports why (missing / not-`draft`) — seed nothing,
   append no ADR, change no status. (Re-running on an already-`planned` epic is an explicit
   **amend** opt-in that appends features/ADRs above the current max without renumbering or
   re-flipping.)
4. Read the target `draft` epic (`specs/epics/<id>-<slug>/epic.md` + its
   `state/tasks.json` row) and F02's design artifacts (`specs/vision.md`,
   `specs/architecture.md`, `specs/adr/NNNN-*.md`) as inputs.
5. Run a short, **adaptive** Q&A with the human to settle the feature breakdown. Where the
   breakdown forks, offer **at most 3** options as **text-only** (markdown/ASCII) mockups —
   never images. Keep it short.
6. **Topology changes — stop and hand off (before any writes).** Check this immediately
   after the Q&A and before seeding anything. If the decomposition reveals that the
   deployable set changes — a new, removed, renamed, or relocated deployable — STOP here,
   before you seed any feature entry, fill the epic's feature table, write any inbox brief,
   or append any ADR delta, and record it as a required `/sdd-plan` amend; do not make the
   topology decision yourself. A **path-only relocation** — an existing deployable moved to
   a new `path` with its name unchanged — is a topology change too: it also routes through
   this guard and **STOPS** the drill, and the draft must not keep the stale `path`, so
   hand it off even though no deployable was added, removed, or renamed. The Planner is the
   single writer of the draft manifest;
   you do not create or amend `umbrella.manifest.draft.yaml`, and do NOT run
   `/sdd-plan` yourself. Keep your ADR-delta authority for the non-topology decisions
   this decomposition forces. **Persist the discovered topology before you hand off.**
   The Planner's amend starts in a fresh context and `specs/architecture.md`
   still names the old deployable set, so an amend cannot see what your Q&A discovered
   unless you write it down: before you report, persist the full resulting deployable set
   to a durable **topology handoff** file at `progress/<run>/topology-handoff.md`
   — one entry per deployable with its logical key, its `path`, and why it is separate when
   known. Each handoff carries a `consumed:` marker: write this one **unconsumed**, and the
   amend that reads it marks it consumed, so a **superseded** handoff is never replayed.
   The handoff is the only topology artifact you write; it does not grant you
   manifest-write authority, and the Planner remains the single writer. Report the
   required amend to the human (run `/sdd-plan` in amend mode) and name the
   **exact handoff path** — the resolved `progress/<run>/topology-handoff.md`
   file this run wrote — in that stop message, so the amend is given that exact path
   instead of picking an **older** handoff from another run. Reconcile against that set
   before a feature that depends on the changed topology is specced — do not seed such a
   feature on the strength of a draft you did not reconcile. A topology-dependent feature
   must not be persisted before that amend.
7. **Seed** the decomposition: write each new feature into the epic's `features` array
   (`status: "pending"`, `sdd: true`, one-line `title`, `spec_path`, intra-epic
   `depends_on`; ids as a next-sequential block strictly above the epic's max `F##`,
   append-only, no reuse); fill the `epic.md` feature table (one row per feature); and write
   a per-feature inbox brief at `progress/inbox/<E##>-F<NN>.md` from
   `specs/_templates/inbox-brief.md`, recording the `ADR-NNNN` ids each feature
   must honor.
8. **Append** any per-epic **ADR deltas** the decomposition forces at
   `specs/adr/NNNN-<title>.md` (4-digit, above the max existing ADR number, no
   reuse) — do NOT rewrite or renumber F02's existing ADRs. Stay at per-epic depth; defer
   feature-level design to the feature's own spec.
9. **Doc-critic checkpoint (before re-validation).** Spawn the **Doc-critic**
   (`agents/doc-critic.md`) as a sub-agent with `target-type=epic-decomposition`,
   passing the target `epic.md` path, its feature table, the per-feature inbox brief paths,
   and any ADR delta paths. Apply any advisory findings inline, then proceed. If the critic
   invocation errors or times out, proceed best-effort and append a note under
   `progress/<run>/` recording the skipped/failed review.
10. **Re-validate** `state/tasks.json` against `store/tasks.schema.json`. If
    it fails, report the failure and do NOT claim a successful drill.
11. Present the **single epic-level decision** (one decision, not per feature):
    - **approve** → flip the epic `draft → planned` and stamp `autonomous: true` on every
      seeded feature (all-or-nothing); or
    - **keep gated** → flip the epic `draft → planned`, leaving every seeded feature
      `autonomous: false` so each parks at the per-feature spec-approval gate.
    Re-validate again after the flip/stamp.
12. **Report** the seeded features (ids + titles + `spec_path`s), the inbox briefs + ADR
    ids, any ADR deltas, and the decision taken; tell the human to **run `/sdd-next`** to
    execute. Do NOT spawn the Architect, do NOT write any feature `.spec/.plan/.tasks/.tests`,
    and advance ONLY the target epic to `planned` — the Driller decomposes, never specs.
