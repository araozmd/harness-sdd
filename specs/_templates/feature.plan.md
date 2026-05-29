# <Feature title> — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. Start high-level; don't over-specify internals that might be wrong.

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

## DO NOT TOUCH
- `path/…` — <why it must not change>

## Approach notes
<Sequencing, edge cases, anything the Builder needs. Keep the Builder free to pick
implementation details not pinned here.>
