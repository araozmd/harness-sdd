# <Feature title> — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete,
> executable test. The Reviewer fails the feature if any R-id lacks a passing test.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | When <trigger>, system shall <response> | `tests/test_handoff.py::test_take_over_assigns_agent` | unit | ⬜ |
| R2 | While <state>, system shall <response> | `tests/test_handoff.py::test_bot_active_badge` | unit | ⬜ |
| R3 | If <error>, then system shall <response> | `tests/test_handoff.py::test_5xx_shows_retry` | unit | ⬜ |
| R4 | system shall <ubiquitous behavior> | e2e: Playwright `handoff.spec.ts` | e2e | ⬜ |
| R5 | Where <optional>, system shall <response> | `tests/test_analytics.py::test_handoff_event` | unit | ⬜ |

## Behavioral / end-to-end checks
- <Steps the Reviewer performs against the running app, e.g. "click Take over →
  conversation appears in agent inbox → bot stops replying">

## Non-functional checks
- Lint: `<lint_command>` clean
- Types: `<typecheck_command>` clean
