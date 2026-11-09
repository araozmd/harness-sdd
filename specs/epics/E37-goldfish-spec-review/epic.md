---
id: E37
title: "Goldfish spec review: fail-closed readiness lint, paraphrase-back comprehension, living-doc drift"
status: pending
owner: araozmd
---

# Epic E37 — Goldfish spec review

## Business brief

The harness already separates the context-rich author (Planner, Driller, Architect) from
clean-context challengers (Doc-critic, Reviewer), and `AGENTS.md` forbids forwarding chat
history between roles. That is the same insight Google's Elephant-Goldfish Model (EGM,
`github.com/google/elephant-goldfish-model`, Apache 2.0) builds its whole plugin around:
the agent that drafted a design shares the author's blind spots, so a zero-context reader
must challenge it before anyone implements. Where EGM is stronger than this harness is
*method* at exactly one checkpoint — the review of a feature spec before it is handed to
a Builder that will see nothing but those files:

- EGM's **comprehension test** makes the cold reader paraphrase the design back; a
  section it cannot restate is a Blocker. Our Doc-critic lists five dimensions to
  "consider" but never has to prove it understood the spec.
- EGM's **implementation-readiness** stage checks that every file path, symbol and test
  the plan names is unambiguous. Our `tools/plan-cite-check.py` checks only that every
  plan row cites an R-id or an ADR — a row may cite correctly and still name a file,
  function or test that does not exist.
- EGM's **drift report** compares checked-in design docs with the current source weekly.
  Our drift guards cover the installed body (`init.sh`) and weakened tests
  (`tools/test-drift-check.sh`), not `specs/product.md`, `specs/architecture.md` or ADRs
  against the code they describe.

Evidence that the gap costs review rounds: spec-level defects have reached Codex review
more than once (the E36-F04/E36-F06 re-spec round; an assertion whose expected value had
two producing paths recurring three times in E99-F07). Each costs a full
build → review → PR round that a cold reader could have caught at `spec-ready`.

Per `docs/RATIONALE.md` principle 1 (code over prose), the deterministic part — "does
every named path and symbol resolve?" — ships as a fail-closed tool (F01). The judgment
part — "can a cold reader restate this?" — ships as a bounded Doc-critic mode with the
ablation caveat (F02). Drift against the living docs ships advisory (F03). Not adopted:
EGM's eight-persona swarm (cost unjustified until F01/F02 show what they catch), its
bootstrap skill (Scout/Planner cover it), and its optional-workflow stance (the
`sdd: false` lane already covers "skip the ceremony" with a gate instead of discretion).

## Success criteria (epic level)

- A plan or tasks file that names a path, symbol or test file that does not exist in the
  repo (and is not marked as *created by this feature*) cannot reach `spec-ready`:
  the Architect's pre-hand-off lint exits non-zero and the Reviewer rejects on it.
- At the `feature-spec` checkpoint the Doc-critic produces a paraphrase of the spec from
  the four files alone; a section it cannot restate is a blocking finding, bounded by one
  re-audit, after which leftovers are recorded in the spec as accepted trade-offs.
- An on-demand, advisory drift report lists divergences between the living docs
  (`specs/product.md`, `specs/architecture.md`, ADRs) and the current code, and names the
  reconciliation choice (doc or code) for a human.
- Every mechanism is installed by `harness-install.sh`, asserted by `tests/test_install.sh`,
  and recorded in the `docs/RATIONALE.md` ledger with its removal threshold.

## Features

| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| E37-F01 | Implementation-readiness lint: every path and symbol a plan/tasks file names must resolve | pending | true | — |
| E37-F02 | Doc-critic paraphrase-back comprehension mode at the feature-spec checkpoint | pending | true | E37-F01 |
| E37-F03 | Advisory drift report: living docs (product, architecture, ADRs) versus current code | pending | true | E37-F02 |

## Notes

- Seeded 2026-11-09 from a comparison of this harness against EGM. The three features are
  ordered by evidence strength and by doctrine: code first, then bounded prose, then an
  advisory lane. Dependencies are sequential so each feature can build on the previous
  one's tooling and merge on its own.
- EGM's persona files are Apache-2.0; wording may be adapted with attribution, but the
  Doc-critic stays one portable role file — no second `agents/` persona per EGM stage.
