# <Feature title> — Tasks

> Per-requirement red/green pairs (ADR-0008). For each R-id in the .spec.md: `T<n>a` writes
> the failing test named in `.tests.md` and observes RED; `T<n>b` writes the minimal code and
> observes GREEN; the Builder commits after each GREEN. Order pairs so the walking-skeleton
> R-id (the thinnest end-to-end observable behavior) comes first. Refactor tasks are explicit
> and cite the R-ids whose tests guard them. There is no trailing "write tests" task:
> `python3 "$HARNESS_DIR/tools/tasks-pair-check.py" <this file> --spec <feature>.spec.md` must exit 0.

- [ ] **T1a** (R1) — write failing `tests/test_handoff.py::test_take_over_assigns_agent`; run it; observe RED
- [ ] **T1b** (R1) — minimal code: add `handoffRequested` to `models/conversation.py` …; observe GREEN; commit
- [ ] **T2a** (R2) — write failing `…::test_bot_active_badge`; observe RED
- [ ] **T2b** (R2) — minimal code …; observe GREEN; commit
- [ ] **T3a** (R3) — write failing `…::test_5xx_shows_retry`; observe RED
- [ ] **T3b** (R3) — minimal code …; observe GREEN; commit
- [ ] **T4a** (R4) — write failing e2e `handoff.spec.ts` (Playwright); observe RED
- [ ] **T4b** (R4) — minimal code …; observe GREEN; commit
- [ ] **T5a** (R5) — write failing `tests/test_analytics.py::test_handoff_event`; observe RED
- [ ] **T5b** (R5) — minimal code …; observe GREEN; commit
- [ ] **T6** (R1, R2) — refactor: <extract …>; R1/R2 tests stay GREEN; commit
- [ ] **T7** — Run `./init.sh` + the test command; all green before hand-off
