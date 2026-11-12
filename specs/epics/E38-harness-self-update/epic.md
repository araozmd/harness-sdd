---
id: E38
title: "Harness self-update: detect a newer release, ask before installing, never clobber custom configuration (single-repo + umbrella)"
status: pending          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E38 — Harness self-update

## Business brief
Once the harness is installed in a target, the only way to upgrade is to remember that a
newer release exists, `git pull` a separate harness-sdd clone, and re-run
`harness-install.sh` with the right `--agents` selection (or `--umbrella` for a
coordinator). Nothing in an installed target ever tells its user that it is behind, so
targets drift many MINOR versions out of date and miss fixes that have already shipped.

A user who *does* upgrade has a second worry: whether the run will overwrite
customization. The installer already keeps `harness.config.yaml` (seeds it once, then
appends only missing keys) and replaces only the pointer block in root entrypoints. But
that guarantee is not shown at upgrade time, and it is not checked across an umbrella
cascade into children. A local edit to a harness-owned file is still silently replaced.

This epic makes the installed harness detect a newer release itself. It asks the human
before installing, and it shows and proves that custom configuration survives the
upgrade. That holds both in a single-repo install and in an umbrella cascade.

## Success criteria (epic level)
- An installed target learns that a newer harness release exists without the user
  having to look.
- No upgrade is installed without the human's explicit consent. Non-interactive
  agent runs are never blocked or failed by the check.
- After an upgrade, every project-owned value in `harness.config.yaml` and all user
  content in the root entrypoints (CLAUDE.md / AGENTS.md outside the harness pointer
  block) are unchanged. This holds in single-repo mode and in each umbrella child.
- Before it writes anything, an upgrade lists every file it would replace that carries
  local edits. It replaces those files only after the human agrees, and backs them up
  first.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | init.sh update check + consented upgrade with custom-config preservation preview (single-repo and umbrella cascade) | pending | true | — |

## Notes
- Builds on E24 (upgrade integrity / drift guard: an upgrade must be committed), E30
  (body/project ownership boundary) and E03/E24-F03 (umbrella cascade + thin children).
- The Architect may split F01 into slices; this epic seeds only F01.
