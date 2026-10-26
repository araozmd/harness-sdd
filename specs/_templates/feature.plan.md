# <Feature title> — Technical Plan

> Translates the .spec.md intent into design. Every table row cites the `R-id`(s) it
> serves or the `ADR-NNNN` that defers it (ADR-0009). Start high-level; don't
> over-specify internals that might be wrong.

## Stack & dependencies
- Language/framework: <…>
- New dependencies: <… or "none">

## Data model  (serves: R#, R#)
| Entity | Field | Type | Notes |
|---|---|---|---|
| <Table> | <field> | <type> | <constraint> |

## API / interface  (serves: R#)
| Method | Path | Request | Response | R-id |
|---|---|---|---|---|
| POST | /… | {…} | {…} | R# |

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `path/to/file` | <create / modify: what> | R# |

## Deferred  (ADR-0009 — bolt-ons the stage excludes)
> Stage: <discovery | pilot | production> — read from `specs/product.md` frontmatter;
> `production` when absent. One row per bolt-on this feature leaves out; "Deferred by" is a
> deferred ADR (`Status: deferred`, with a `Trigger:` line) and "Trigger" copies its
> condition. When nothing is deferred, replace the table with the single line
> `Deferred: none — <why>` (e.g. `Deferred: none — stage is production`). A bolt-on that is
> **not** deferred needs an R-id in the rows above — never add one without a requirement.

| Bolt-on | Deferred by | Trigger |
|---|---|---|
| <encryption at rest> | ADR-NNNN | <first regulated customer> |

## DO NOT TOUCH
- `path/…` — <why it must not change>

## Approach notes
<Sequencing, edge cases, anything the Builder needs. Keep the Builder free to pick
implementation details not pinned here.>
