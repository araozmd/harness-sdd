---
id: E09
title: Harness doc quality & customization
status: done
owner: araozmd
---

# Epic E09 — Harness doc quality & customization

## Business brief
The harness generates a lot of documentation on the way to code — vision,
architecture, and ADRs (from `/sdd-plan`), epic decompositions and inbox briefs
(from `/sdd-drill`), and the four-file spec (from the Architect). Today none of
that generated documentation is reviewed before it drives downstream work: the
human gate at `spec-ready` is the *only* quality check, so the human absorbs the
entire QA load, and planning-tier docs (vision/architecture/ADRs) get **no**
review at all. This epic raises the quality of harness-generated docs and makes
the harness easier for individual developers to tailor — without adding new human
gates or eroding the property that a well-seeded plan can run autonomously for
hours.

## Success criteria (epic level)
- Harness-generated documentation is reviewed for completeness, consistency,
  clarity, scope, and YAGNI at defined checkpoints — fixed inline, advisory, no
  new human gates introduced.
- The human gate does *less* QA work because obvious doc defects are caught before
  the human sees them.
- Developers can layer personal, uncommitted customization onto the harness
  through a documented convention that leans on each CLI's native local-override
  mechanism.
- The autonomous-run property (hours unattended after `/sdd-plan` + `/sdd-drill`)
  is preserved.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Doc-critic advisory review pass over harness-generated docs | pending | true | — |
| F02 | Per-developer local-overrides convention (AGENTS.local.md / native local files) | pending | true | — |

## Notes
- Both features touch the **installed body** (`agents/*.md`, `harness-install.sh`,
  `docs/`, the generated glue) and therefore warrant a `VERSION` bump per the
  repo's versioning policy (SemVer MINOR — new backward-compatible capability).
- F01 (doc-critic) models its calibration on the brainstorming skill's
  spec-document-reviewer: only flag issues that would cause real problems, keep
  recommendations advisory. It must not add a human gate — it fixes inline and
  hands off.
- F02 (local-overrides) leans on each CLI's **native** local-override mechanism
  (Claude Code auto-loads `CLAUDE.local.md`; Codex has `AGENTS.override.md`) and adds
  a portable `AGENTS.local.md` convention for tools that don't auto-load one. The
  harness's job is a conditional reference in the generated marker blocks plus
  append-only `.gitignore` seeding — not a new bespoke mechanism.
