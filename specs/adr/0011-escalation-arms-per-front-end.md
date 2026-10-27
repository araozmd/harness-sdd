# ADR-0011 — Escalation arms per front-end; the all-front-ends AND is the fallback, not the rule

- **Status:** accepted (E99-F182 Architect delta, 2026-10-27) — **amends ADR-0002**
- **Date:** 2026-10-27

## Context

ADR-0002 made `builder-heavy` a pure routing decision: the Orchestrator picks a role name and
the front-end's generated agent definition supplies the model. E17-F05 then made the
installer answer "would escalating actually change the stamp?" by comparing what
`resolve_model` returns for `builder` and `builder-heavy` on **every** selected front-end,
and recording the comparison in `.harness/.escalation-arming`:

```
armed|blocked                     ← the AND over every selected front-end
<front-end>=<raise|none|same|neither|unstamped>   ← one line per selected front-end
```

`tools/builder-role.sh` reads **only the first line**. The installer's own comment states
why: *"`armed` iff EVERY selected front-end is `raise`. A conservative AND, because
`builder-role.sh` cannot know which front-end it is running under … Passing the front-end as
an argument would only move the guess into `agents/orchestrator.md`, where it is prose and
untestable."*

That premise no longer holds, and the cost it accepted has now been paid for real:

1. **The host is knowable without guessing.** E19-F01 gave the installer `detect_host`: a
   table of per-front-end **session markers** (`CLAUDECODE` / `CLAUDE_CODE_ENTRYPOINT`,
   `CODEX_THREAD_ID`, `OPENCODE*`, `PI_CODING_AGENT`), each recorded with the CLI version it was
   observed on, plus the `HARNESS_HOST_AGENT` declaration as the explicit escape hatch. It is
   deterministic, ambiguity-aware (two hits ⇒ undetected, never a tie-break), and
   tested under `env -i` (`tests/test_agents_host.sh`). The same evidence is available at
   **build** time as at install time.
2. **The AND has disarmed the one host where escalation would work.** In this repository
   (`--self`), Claude and Codex tier from committed shims while OpenCode and pi can only read
   the all-`inherit` seed config, so the file reads
   `blocked / claude=raise / codex=neither / opencode=neither / pi=neither`. `init.sh` warns
   on every run, and E36-F06 went three Reviewer rounds on the base Builder under Claude Code
   — the front-end whose line says `raise`.

Three directions were on the table (the E99-F182 brief):

- **(a) Per-front-end gate.** `builder-role.sh` gains `--frontend <key>` and reads that
  front-end's `<key>=raise` line; the Orchestrator passes its host's key; the first line stays
  the all-front-ends summary for callers that pass no key.
- **(b) Self-mode harvest for OpenCode and pi.** Extend the `--self` shim harvest so this
  repo could tier those two from committed artifacts. It would turn this repo's file to
  `armed` only once vendor model ids are chosen for them — which is out of scope — and it
  does nothing for a consumer that installed only some front-ends, so the AND would still
  disarm a mixed target.
- **(c) Both.**

## Decision

**Escalation arms per front-end.** The gate's unit is one front-end's own verdict line, not
the AND over all of them:

1. `tools/builder-role.sh` accepts `--frontend <key>`. When a key is given, the gate is open
   **iff** the arming file carries a line that is exactly `<key>=raise`. Any other line for
   that key (`none`, `same`, `neither`, `unstamped`), or no line for it, keeps the gate shut
   and the advisory names the key and what was recorded. The first line is still required
   to be exactly `armed` or `blocked` — a file whose first line is anything else is not the
   installer's and no detail line in it is trusted.
2. **The key is produced, never typed.** A new tool, `tools/host-frontend.sh`, prints the
   front-end this session runs inside, or nothing, from the same session-marker table and
   `HARNESS_HOST_AGENT` precedence `detect_host` uses (a second copy, parity-tested against
   the installer's `HOST_MARKERS` rows — the E36-F04 precedent for a tool that must stand
   alone in an installed target where the installer is absent). The Orchestrator pipes its
   output into `--frontend`; it never substitutes a key it believes is right.
3. **An empty key is the old rule.** When the host cannot be identified — no marker, two
   markers, or no `--frontend` at all — `builder-role.sh` decides from the first line exactly
   as before. A consumer whose file reads `armed` is therefore unchanged on every path, and a
   caller that never learns about `--frontend` is unchanged too.
4. **The file format does not change.** The first line remains the AND. What changes is who
   consumes which line: the Orchestrator consumes its host's line; `init.sh` and the
   installer's summary report the per-front-end state when the AND is `blocked` but some line
   is `raise`; absent / symlinked / garbage files keep the gate shut on every path.

Direction (b) is **not** taken: it would not fix the mixed-target consumer, and in this repo
it arms nothing until vendor ids exist for OpenCode and pi, which E99-F182 explicitly leaves
out. It remains available as a later feature; nothing here forecloses it.

**What this amends in ADR-0002.** ADR-0002's decision stands — escalation is still a routing
choice between two role names with one body, and the installer still owns the "would it
change anything" verdict. The amendment is to the *scope of the verdict the Orchestrator
acts on*: per front-end rather than all front-ends. The "cannot know which front-end"
premise recorded in the installer's `write_escalation_arming` comment is superseded; the
comment is rewritten to cite this ADR.

## Consequences

- **Easier.** Escalation fires where it can actually raise the stamp and stays off where it
  cannot — on the same target, in the same install. This repo's Claude Code sessions escalate;
  its Codex / OpenCode / pi sessions do not, and each path says so.
- **Easier.** The operator's remedy narrows from "fix every front-end" to "fix the one you
  run on": a `claude=raise` line is enough for Claude Code regardless of the others.
- **Easier.** No format migration: a target that re-runs the installer gets a byte-identical
  file; a target that does not re-run it still works with the new tool, because the detail
  lines were always written.
- **Harder.** There is now a second copy of the session-marker rows (the installer's table
  and the tool's). The parity test is what keeps them one table; a row added to one without
  the other is a test failure, not a silent drift.
- **Harder, and stated.** A misdeclared `HARNESS_HOST_AGENT` (the operator says `claude` while
  running Codex) opens the gate on the declared front-end's line. That is the operator's
  explicit declaration, the same trust the installer already extends to it; session markers
  cannot be misdeclared, only absent or ambiguous, and both of those fall back to the AND.
- **Unchanged.** `raise` still means the stamp *changes*, not that it is *stronger*
  (E17-F01 has no model list). `escalation.after_rejections = 0` is still the hard veto on
  every path. The `delegate` backend still never escalates.
