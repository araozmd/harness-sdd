# plan-cite fixtures (E36-F04)

Test input for `tests/test_plan_cite.sh`, which copies `specs/` into a fresh temp dir per row
and derives each variant with `sed`/`printf`. Files are LF; the suite derives CRLF copies.
Nothing here is a live spec: the tree is never on the board.

## `specs/` — a mini specs tree

| Path | Role |
|---|---|
| `product.md` | frontmatter `stage: pilot` (a recognized stage: the sweep reports nothing) |
| `adr/0001-accepted.md` | platform namespace, `Status: accepted` |
| `adr/0002-deferred-waf.md` | platform, `Status: deferred` **with** a `Trigger:` line |
| `adr/0003-deferred-no-trigger.md` | platform, `Status: deferred`, **no** `Trigger:` (the sweep's one positive) |
| `bookings/adr/0001-other.md` | a second namespace (token `bookings`) that also holds number 0001 |
| `epics/E01-x/F01-good/E01-F01.{spec,plan}.md` | the POSITIVE plan (spec declares R1–R4) — lint-clean |
| `epics/E01-x/F02-bad/E01-F02.{spec,plan}.md` | the NEGATIVE plan (same spec) — one planted defect per line |

## Planted defects in `E01-F02.plan.md`

| Line | Finding the tool must print |
|---|---|
| 8 | `uncited-row …:8 Data model` |
| 14 | `unknown-rid …:14 R9` |
| 15 | `unresolved-adr …:15 ADR-0042 not-in-any-namespace` |
| 16 | `unresolved-adr …:16 bookings/ADR-0002 not-in-namespace bookings` |
| 22 | `deferred-by-not-deferred …:22 ADR-0001 <adr path>` |
| 23 | `deferred-adr-no-trigger …:23 ADR-0003 <adr path>` |
| 25 | (with the table above) `deferred-form … both` |

## What the POSITIVE plan exercises

- a `PR304` cell beside a real `R2` (the `R` token's left boundary: `PR304` is no citation);
- `platform/ADR-0001` and `bookings/ADR-0001` (qualified, each resolves in its own space);
- `ADR-0002 ADR-0001` back to back in one cell (each id is looked up on its own);
- a `### sub-heading` inside `## Files to change`, followed by a cited row (still checked);
- an uncited row under `## Stack & dependencies`, `## CLI / interface` and `## DO NOT TOUCH`
  (not one of the four headings — ignored);
- a fenced example holding an uncited table under a fake `## Files to change` (invisible);
- a `## Deferred` table citing `ADR-0002` (deferred, with a trigger) beside a `Stage:` line.
