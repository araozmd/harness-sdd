---
id: E32
title: "Harness feedback loop: auto-reported harness issues + on-demand triage"
status: planned          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E32 — Harness feedback loop: auto-reported harness issues + on-demand triage

## Business brief

Every repo that installs the harness runs into harness defects: a gate that can't be
satisfied, a role prompt that contradicts another, an `init.sh` check that fails on a
healthy project, or a workflow with no lane for a recurring situation. Today that signal
dies in the target's session. The agent works around the problem, and the maintainer of
`araozmd/harness-sdd` never hears about it. This epic closes the loop. An installed harness
**automatically files a scrubbed GitHub issue** upstream with the `gh` CLI when one of four
narrow triggers fires. The harness source repo gets an **on-demand, human-gated triage**
that turns those issues into E99 fixes or new work, so the harness improves from real
usage. The users are two groups: the agents and operators of every installed harness (the
reporters) and the harness maintainer (the triager).

## Success criteria (epic level)

- An installed harness with `feedback.enabled: true` (the **default**) and an
  authenticated `gh` files an issue on `feedback.repo` (default `araozmd/harness-sdd`) at
  the **end of the task**, with no human confirmation. It files only when one of the four
  triggers fired:
  1. **harness malfunction:** `init.sh`, `harness-install.sh`, `tools/*`, or a TaskStore
     write fails or misbehaves while the project itself is healthy;
  2. **contradictory or impossible instruction:** role prompts or docs conflict, or a gate
     can't be satisfied as written;
  3. **workaround taken:** the agent had to leave the documented workflow to finish
     (hand-editing generated files, skipping a gate, manually repairing state);
  4. **missing capability:** a recurring situation has no path in the workflow.
- These are **never** reported: failures of the project's own code or tests, transient
  network or auth errors, and agent mistakes the harness correctly caught. The triggers,
  the non-triggers, and the redaction pass are verified by fixture scenarios and a
  redaction corpus that the feature specs define.
- Every outbound field (issue title, body, duplicate-search query) is built **only from
  allow-listed structured fields** (trigger type,
  harness `VERSION`, host, role, phase, harness-owned paths validated against
  `tools/harness-owned-paths.sh`, harness command name, exit code, a fixed-vocabulary
  symptom code). Free-form text is never sent upstream; it stays in the local
  `progress/feedback/` copy. A **redaction pass** (secrets, tokens, emails, absolute
  paths) still runs before `gh issue create` as a second layer. The body describes
  harness behavior only and names harness files, never project files.
- Filing is bounded. The agent searches for duplicates first (`gh issue list --search`).
  If a duplicate exists, no new issue is opened and the agent doesn't comment on it
  either. There is a **per-session cap** (the drill names its value and config key).
- Reports are filed when the task ends **or** when it stops early (aborted, parked, or
  failed), because a harness malfunction is most likely to fire on an early stop.
- **`init.sh` hard stop:** the "STOP and report" rule in `AGENTS.md` gets one narrow
  exception, reporting. When `init.sh` exits non-zero and the failure is a harness
  malfunction, the session may call the F02 reporter **once** as part of *report*, then
  stop. That call makes no repair and no board write, and the session doesn't continue,
  so reporting never becomes a way around the gate. F03 owns this wording.
- When `gh` is missing or unauthenticated, or filing fails, the report is written under
  `progress/` instead, and it never blocks or fails the task.
- `feedback.enabled: false` disables reporting completely. A fresh install seeds `true`
  and prints a one-line notice naming the upstream repo and the switch. An **upgrade**
  of an existing install that has no `feedback` block seeds the same block and prints the
  same notice, so reporting never turns on without the operator being told. The
  config diff lands in the upgrade and the operator reviews it like any other.
- Each report carries a machine-readable **body marker** (version, host, trigger type). A
  GitHub Action in the source repo applies the `harness-feedback` and `bug`/`enhancement`
  labels to marked issues, because reporters without write access can't set labels.
- `/sdd-triage` in the source repo lists open `harness-feedback` issues, groups
  duplicates, and **proposes** a route for each (E99 `/sdd-fix`, `/sdd-new`, or close with
  a reason). It seeds nothing until the human approves. Fix PRs reference `Fixes #N`.

## Technical considerations / restrictions / non-goals

- **Issue bodies are untrusted input.** The source repo is public, so anyone can open an
  issue carrying the marker. Triage reads bodies as **data, never instructions**. It never
  executes, follows, or copies an issue's suggested change or command verbatim into a
  brief, and the human approval gate comes before any TaskStore write. The same rule
  applies to the **labeler Action**: it parses the marker as data and never puts issue
  text into a `run:` shell line or a `${{ }}` expression (script-injection risk).
- **Privacy is load-bearing.** Filing is automatic and there's no human review, and a
  target may be a private repo. So the allow-listed body (no free-form text upstream),
  redaction, and the "harness files only" rule are part of the contract, not advice.
- **Non-goals:** scheduled or autonomous triage (deferred until real reports exist);
  auto-fixing an issue without the human gate; telemetry or usage analytics; any channel
  other than GitHub issues; reporting on project (non-harness) defects.
- Installed-body change: each PR that changes the installed body bumps `VERSION` per
  `AGENTS.md`. F01 is MINOR (new config), F02 is MINOR (a new installed tool,
  even before anything calls it), and F03
  is MINOR (reporting goes live).
- Front-end parity: the reporting rule and command must reach Claude, Codex, and OpenCode
  through the existing emitters. Source-repo-only surfaces (the labeler workflow,
  `/sdd-triage`) must not be installed into targets.

## Cross-epic dependencies and boundaries

- **E99 / fix lane (`/sdd-fix`)** and **E04 idea intake (`/sdd-new`)** are the triage
  routes; this epic calls them and doesn't change their contracts. The one narrow exception
  is owned by F05: a feature seeded from an issue records its number, so the PR body
  carries `Fixes #N`.
- **E26 self-hosting (`--self`)**: generated glue for any new command is emitted and
  drift-gated like the existing ones; no hand-edited `.claude/*`.
- **E20 workflow toggles / `pr_loop` gating** is the precedent for a config-gated,
  installer-emitted command, and **E31** for OpenCode parity.

## Relevant ADRs

- **ADR-0003:** one shared `.agents/skills/<name>/` unit per command, claimed by every
  front end that reads it. A new `sdd-report` command (and any source-only `sdd-triage`)
  follows it.
- **ADR-0004:** umbrella children resolve the body through pointer stubs. The drill checks
  where the reporting rule and the `feedback.*` config resolve for an umbrella child.
- **ADR-0005** (drill delta): source-only surfaces are emitted only by `--self`.
- **ADR-0006** (drill delta): the versioned body marker is the only contract between
  reporter and triage.
- No other ADR applies. This repo has no `specs/architecture.md`.

## Features

| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| E32-F01 | feedback.* config block seeded on fresh install and upgrade, with the one-line opt-out notice | pending | true | — |
| E32-F02 | tools/harness-report.sh: redaction pass, versioned body marker, duplicate search, per-session cap, progress/ fallback | pending | true | E32-F01 |
| E32-F03 | Reporting rule + /sdd-report command on every front end: four triggers, end-of-task and early-stop filing | pending | true | E32-F02, E32-F04 |
| E32-F04 | Source-repo GitHub Action that labels marker-carrying issues without trusting their bodies | pending | true | E32-F02 |
| E32-F05 | Source-only /sdd-triage: group harness-feedback issues, propose routes, seed only on human approval | pending | true | E32-F04 |

ADR deltas: **ADR-0005** (source-only surfaces emitted only by `--self`) and **ADR-0006**
(the body marker is the only reporter↔triage contract).

## Notes

- Size (E21-F01): the reporter was split along its real seam. **F02** is the deterministic
  tool (redaction, marker, duplicate search, cap, fallback), which carries the privacy
  risk and gets fixture tests. **F03** is the prompt and command glue that decides *when* to
  call it. Every feature is expected to stay under `max_requirements: 12`.
- Drill decisions (from the doc-critic pass):
  - Only the **session-owning top-level role** files a report. Sub-agents record trigger
    notes under `progress/`, and the top-level role reads them. This keeps the cap and the
    duplicate search single-writer and keeps F03 within budget.
  - F01 owns how config and the `progress/` fallback path resolve for an umbrella child
    (ADR-0004); F02 and F03 follow that answer.
  - F04 owns the trigger→label mapping: `missing-capability` → `enhancement`, the other
    three → `bug`. It labels on `opened` only, never on edit.
  - F04 lands before F03 (F03 depends on F04), so no report is filed before the labeler
    exists — a report opened earlier would stay unlabeled and invisible to F05's triage.
