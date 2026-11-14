---
id: E39
title: "Documentation for humans: short guides with diagrams and a logo; exact agent contracts moved verbatim to docs/agents/"
status: pending          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E39 — Documentation for humans

## Business brief
The harness docs grew by appending a contract every time a review found an edge case. The
README is 544 lines, and docs/ holds about 4,000 more (INSTALL.md alone is 1,450, WORKFLOW.md
1,140). Each paragraph earned its place, but read together they are a wall: a new human
cannot find the three steps they need, and the reasoning behind each rule is buried in
incident history. Two readers with different needs share one text:

- **Humans** want to know what the harness is, why it works, how to install, upgrade and
  run it, and what to do when a gate stops them. They want this in minutes, with pictures.
- **Agents** need the exact contract: exit codes, environment variables, edge cases,
  precedence rules. Tests and role prompts pin that text phrase by phrase.

This epic separates the two readers by construction. The human guides become short and
plain and get diagrams and a logo. The contract text moves, unchanged, into a clearly
marked machine layer.

## Success criteria (epic level)
- A newcomer understands what the harness is and gets it installed from the README
  alone, in a few minutes, without scrolling through edge cases.
- Every human doc is short and plain, with no filler, no repeated hedging and no
  incident archaeology. Each one has at least one diagram where a flow or structure is
  being explained.
- No contract is lost. Every behavioral sentence agents or tests rely on still exists,
  moved verbatim into `docs/agents/`, and every test and role prompt that cited it
  resolves to the new location.
- The project has a logo, used in the README.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Docs split + README rewrite: docs/agents/ machine layer, Mermaid diagrams, logo, concise human guides | done | true | — |
| F02 | INSTALL split (single-repo vs umbrella and upgrade-flow diagrams) | done | true | F01 |
| F03 | WORKFLOW split (state-machine and PR-loop diagrams) | in-review | true | F01, F02 |
| F04 | UMBRELLA + CONFIG-LAYERING split | pending | true | F01 |
| F05 | SPEC-FORMAT split + HARNESS folded into CONCEPTS + ABLATION trim + BASELINE to docs/history/ | pending | true | F01 |

Sliced by the Architect (see the F01 plan): F01 sets the conventions and the README;
F02–F05 each split one group of docs and are independent of each other.

## Notes
- E37 (goldfish spec review / Elephant–Goldfish doctrine) is now part of the method and
  belongs in the human CONCEPTS doc. It is not the brand: the human chose an abstract
  logo (triangle loop: spec → build → review) to avoid being read as borrowing an
  external named concept.
- The product name is under discussion. Keep the brand name a single substitutable
  token in the README/logo wordmark. Do not rename `.harness/`, `harness-install.sh` or any
  installed path in this epic.
