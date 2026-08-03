---
id: E99
title: Maintenance (hotfixes & minor fixes)
status: in-progress
---
# Maintenance (hotfixes & minor fixes)

The reserved bucket for the lightweight fix lane. Small, standalone `sdd: false`
fixes seeded by the Fixer (`/sdd-fix`) collect here as append-only features, each
carrying a one-paragraph inbox brief instead of a four-file spec. This epic is
created once on first use and reused by id `E99` thereafter; its fixes are never
renumbered, reordered, or migrated to another epic.

**E99-F09 is the exception to "small and standalone"** and is deliberately `sdd: true`.
It is the re-spec of the Antigravity Skills migration, seeded 2026-08-02 after PR #87 was
closed unmergeable: that branch and the merged E23-F01 both write
`.agents/skills/<name>/SKILL.md` over the same command list — for Antigravity and Codex
respectively — so each front-end's reclaim-on-deselect can delete the other's live glue.
Resolving that is an architecture decision, so the feature is gated (`autonomous: false`)
and carries a full brief at `progress/inbox/E99-F09.md` rather than a fix paragraph.
Seeding it re-opens this epic from `done`.

That decision was taken on 2026-08-03 and is recorded as **`ADR-0003`**: `.agents/skills/`
holds **one shared unit per command**, claimed by every front-end that reads it — the unit
E23-F01 already writes is a valid Antigravity skill, so there is nothing to migrate. The
feature at `F09-antigravity-skills/` is scoped accordingly: widen the install gate, narrow
reclaim to the last claimant, and prove it with a both-selected/deselect-one test.
