---
id: E17
title: Cost-aware execution & model routing
status: done             # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
---

# E17 — Cost-aware execution & model routing

## Problem

The harness spawns every sub-agent on whichever single model the host CLI happens to be
running. That is wrong at both ends of the loop: the Architect's design work benefits
from the most capable reasoning model available, while a Builder executing an already
approved `tasks.md` line by line usually does not — yet both burn the same per-token
rate. The operator runs several paid subscriptions in parallel (Claude Code Max,
ChatGPT Pro via Codex, OpenCode Go), and new models ship continuously; the model that is
best at *designing* a solution is not necessarily the right one to *build* it or to
*review* it.

Three concrete gaps follow from that:

1. **No per-role model expression.** There is no way to say "Architect on the reasoning
   tier, Builder on the standard tier, Scout on the cheap tier". Every role inherits the
   session model.
2. **No escalation path.** When the Builder repeatedly fails Reviewer approval, the only
   remedy is a human noticing and re-running the session on a stronger model. The
   harness cannot promote a struggling task to a more capable Builder on its own, even
   though it already knows the task failed twice.
3. **Model ids are hardcoded wherever they appear**, so every new model release is a code
   patch rather than a config edit — and any non-host CLI the operator might invoke as a
   worker is invisible to the harness as declarative data.

## Success criteria

- `harness.config.yaml` carries a **front-end-agnostic** per-role model mapping, and the
  installer stamps it into each **selected** front-end's *native* agent-definition
  convention (Claude Code, Codex, Antigravity, OpenCode, Gemini each differ). Front-ends
  the user did not select are never stamped.
- Defaults are **tier aliases, not pinned ids**, so a new model release is picked up
  without a harness change; an exact id can still be pinned per front-end when the
  operator wants determinism.
- Two Builder variants exist (standard + heavy). The Orchestrator escalates
  **deterministically**, never by ad-hoc judgment: an Architect-written complexity tag at
  spec time, plus automatic promotion after two Reviewer rejections on the same task.
- A **worker roster** turns invocable non-host CLIs into declarative, versioned data that
  external kits (e.g. `multi-cli-orchestrator`) can consume, without the harness core
  ever executing it.
- **Absent configuration reproduces today's behavior exactly.** A target that sets
  nothing keeps a single-CLI, single-model harness — the universality invariant is not
  traded away for cost optimization.

## Features

| id | title | status | depends_on |
|----|-------|--------|------------|
| E17-F01 | Per-role model selection: config schema + per-front-end agent stamping | done | — |
| E17-F02 | The `builder-heavy` role: a seventh role at a heavier tier | pending (gated) | — |
| E17-F03 | Deterministic escalation to `builder-heavy` (complexity tag + two-rejection rule) | pending (gated) | E17-F02 |
| E17-F04 | Worker roster: invocable CLIs as versioned data | pending (gated) | — |

**Seeded 2026-08-02 by `/sdd-drill E17` in amend mode** (E17 was already `pending`, the
legacy alias of `planned`, so ids were appended above the existing max with no renumbering
and no epic re-flip). The decomposition is **three** features, not the two anticipated
below: "dual Builder + deterministic escalation" specced to roughly 17 R-ids against
`change_size.max_requirements: 12`, so it was split at decomposition — F02 adds the role,
F03 decides when to use it — which is exactly what E21-F01 put that budget in the Driller's
hands to do. The seam is clean: F02 is additive plumbing that is independently useful (pin
the tier and invoke the role by hand), while F03 is a routing rule with no new artifacts.

Every seeded feature is `autonomous: false` — the epic-level decision was **keep gated**, so
each parks at its own spec-approval gate. F02 rewrites role emission across all five
front-ends in `harness-install.sh`.

The decision behind F02/F03 is recorded in **[ADR-0002](../../adr/0002-builder-heavy-is-a-tier-not-a-second-prompt.md)**:
`builder-heavy` is the same instruction body at a heavier model tier, never a second Builder
prompt. Escalation is therefore routing, not behavior. Per-feature intent briefs are in
`progress/inbox/E17-F0{2,3,4}.md`.

Originally anticipated at drill time, kept here for provenance:

- **dual Builder + deterministic escalation** → split into **F02** + **F03**.
- **worker roster** → seeded as **F04**, scope unchanged.

`pr-loop` migration into the harness as an opt-in module is deliberately **not** part of
this epic — it is the PR-review lane, not execution routing, and gets its own epic.
