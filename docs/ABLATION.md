# Ablation protocol — do the role prompts still earn their tokens?

**Premise (2026-09-04).** The role prompts total ~23k words and the command bodies ~11k
more, much of it written against older models. External evidence from two full sessions
on v0.6x: every mechanism that *earned its keep* was **code** (tasks-lock, pr-gate,
wait-for-codex, mutation discipline); every mechanism that *failed* was **prose asking an
agent to behave** (telemetry stamping ~0% compliance, escalation silently inert,
classification hand-rolled with bugs). Hypothesis: a large fraction of the prose is
patching behaviors current models have natively, and its net effect is hobbling.

**Method — ablation, not rewrite.** Delete, run, measure, and only bring back the lines
whose absence caused a *repeated, observed* failure. Never guess what the model needs.

## Protocol

1. **Pick the unit of work.** One representative `sdd: true` feature (spec → build →
   review → PR → merge) and one `sdd: false` fix. Do not pick a pathological case.
2. **Baseline run** on the stock prompts. Record: wall-clock, build↔review rounds,
   Codex blocking findings per round, E99 rows seeded, human interventions.
   (Round/phase boundaries are in `telemetry.jsonl` automatically — `transition`
   records are written by `tasks-lock.py` at every status write.)
3. **Skeleton run.** Replace each role prompt with its skeleton (below) —
   `git stash` the originals or work on a branch. Same feature *class*, same
   measurement. Everything else stays: **all tools, all gates, all tests, the board,
   the spec format**. The ablation targets prose, never verification.
4. **Diff the two runs.** For each failure unique to the skeleton run, write down the
   *one line* that would have prevented it. That line — not the section it came from —
   is what returns to the prompt. Two runs with no skeleton-only failures ⇒ the deleted
   prose was patching a model that no longer exists: delete it on main.
5. **Repeat per role.** Ablate one role at a time if a whole-harness skeleton run is
   too noisy to attribute failures.

## Skeleton prompts

Each skeleton is task + guardrails + exit criteria — nothing about *how*.

### orchestrator (replaces ~6.9k words)

```markdown
# Orchestrator
Run `./init.sh`; stop on failure. Read `progress/lessons.md`.
Select the next task with `node tools/next-task.mjs --json` and trust its route.
Delegate to the named role with the feature id and spec path — never write code or
specs yourself. Status changes go through `python3 tools/tasks-lock.py set-status`
(done requires --evidence). Append one line per delegation to progress/history.md.
Guardrails: never skip init.sh; never move a feature to done before its PR merges;
never touch another owner's in-progress work.
Done when: no actionable task remains, or the human gate is reached.
```

### builder (replaces ~1.5k words)

```markdown
# Builder
Implement the approved spec's tasks (or the inbox brief for sdd:false), in order,
smallest verifiable steps. Write the tests the spec names; every prose guarantee you
write must name the test that pins it; every constant you add must kill a test when
deleted. Run ./init.sh + the project test command before hand-off.
Guardrails: only files the plan lists; never redesign — record gaps and hand back;
scratch files under scratchpad/<feature>-builder/.
Done when: every task is ticked, tests pass, and you have reported for review.
```

### reviewer (replaces ~2.9k words)

```markdown
# Reviewer
Verify the feature against its spec: run init.sh + the full test command; check every
R-id has a passing test; mutate what the tests claim to pin (back up as <file>.mutbak,
restore with mv) — a surviving mutant is a rejection; exercise behavior, not diffs.
Be skeptical: specific file:line findings, never vague approval.
Guardrails: never approve on a guess; never weaken a test to pass it.
Done when: verdict written — approve (with evidence) or reject (with findings).
```

## Measurement sheet

| run | feature | wall-clock | rounds | blocking/round | E99 seeded | human touches |
|---|---|---|---|---|---|---|
| baseline | | | | | | |
| skeleton | | | | | | |

## Constraints

- **Evals outlive prompts** — the test suites are the constant; they are never ablated.
- One variable at a time: don't combine the skeleton run with tool changes.
- A failure that happens once is an anecdote; twice is a line to restore.
