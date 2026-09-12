---
id: E28
title: "Greenfield-to-umbrella path: start every new idea as a single-repo install, let the plan earn the topology, promote to umbrella from the plan's own manifest"
status: pending
owner: araozmd
---

# Epic E28 — Greenfield-to-umbrella path

## Business brief
Today a new idea starts in an empty folder with an ad-hoc Claude session that invents the
umbrella + child-repo layout by hand, and only THEN installs the harness and runs `/sdd-plan`.
The repo topology is therefore decided at the moment of least knowledge, outside the harness,
with no ADR and no test. The harness already accepts an empty non-git directory as an install
target (verified 2026-09-11 against v0.78.1) and `/sdd-plan` already carries the brainstorm
(vision + architecture + ADRs + draft epics) — what is missing is (a) documenting/testing that
single-repo greenfield path as THE front door, (b) letting the Planner emit the topology as a
machine-readable artifact when the architecture names more than one deployable, and (c) an
installer transition that promotes a single install into an umbrella coordinator from that
artifact, creating the missing children as plain local git repos. The user is the harness
owner starting a new product; the constraint is the ablation doctrine (`docs/RATIONALE.md`):
no new interactive intake (never accrete), deterministic steps as code, the installer stays
the choke point, and the harness never owns stack scaffolding.

## Success criteria (outcomes)
- A new product starts with `harness-install.sh <empty-dir>` + `/sdd-plan`, documented in
  `docs/INSTALL.md` and covered by `tests/`; no ad-hoc bootstrap prompt is needed.
- When `specs/architecture.md` names >1 deployable, the Planner writes a repo-topology ADR
  and a draft `umbrella.manifest.yaml`; when it names one, it writes neither.
- `harness-install.sh` can promote a single-target install into an umbrella coordinator
  from that manifest, `git init`-ing missing children, running an optional per-child
  `scaffold_cmd`, cascading the child profile, and passing the existing landing audit.
- A single-repo install that never promotes is byte-identical to today's behavior.

## Non-goals
- No new `/sdd-*` command or interactive Q&A; the Planner's existing intake is the brainstorm.
- No GitHub remotes, branch protection or Codex App setup — local git only.
- No language/framework scaffolding owned by the harness (`scaffold_cmd` is opaque to it).

## Features
- **E28-F01** — document + test the greenfield single-repo path (install into empty dir → `/sdd-plan`).
- **E28-F02** — Planner emits a repo-topology ADR + draft `umbrella.manifest.yaml` when architecture names >1 deployable.
- **E28-F03** — installer promotion: single install → umbrella coordinator from the manifest (creates missing children).
