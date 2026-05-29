# Handoff screen — Test Contract

> Every R-id maps to a concrete test. Reviewer fails the feature if any R-id lacks a
> passing test.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | Bot-handled → "Bot active" badge | `web/tests/inbox.test.tsx::shows_bot_active_badge` | unit | ⬜ |
| R2 | Flagged → in inbox as "Needs human" | `services/tests/test_flagging.py::test_needs_human_enters_inbox` | unit | ⬜ |
| R3 | Take over → assigned + bot paused | `services/tests/test_takeover.py::test_takeover_assigns_and_pauses` | unit | ⬜ |
| R4 | Human-handled → bot sends nothing | `services/tests/test_dispatch.py::test_no_autoreply_when_human` | unit | ⬜ |
| R5 | Full history shown chronologically | `web/tests/thread.test.tsx::renders_history_in_order` | unit | ⬜ |
| R6 | Operator message delivered + appended | `services/tests/test_messages.py::test_send_delivers_and_appends` | unit | ⬜ |
| R7 | 5xx/network → queued + retry control | `web/tests/thread.test.tsx::queues_and_shows_retry_on_failure` | unit | ⬜ |
| R8 | Analytics enabled → `handoff_started` logged | `services/tests/test_analytics.py::test_handoff_started_event` | unit | ⬜ |

## Behavioral / end-to-end checks (Reviewer, via Playwright MCP)
- Open inbox → a flagged conversation shows "Needs human".
- Click "Take over" → conversation moves to the operator; "Bot active" badge clears.
- Send a reply → it appears in the thread and is delivered to the end-user.
- Simulate a send failure → message shows queued + a retry control; retry succeeds.

## Non-functional checks
- Lint clean, types clean (see harness.config.yaml).
- Bot pause verified server-side, not only in the UI (R4).
