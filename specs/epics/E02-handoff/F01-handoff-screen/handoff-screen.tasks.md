# Handoff screen — Tasks

> Atomic, sequential. Builder works top to bottom, one at a time. Each cites R-id(s).

- [ ] **T1** (R1, R2) — Add `handlingMode` + `status` to the Conversation model and migration.
- [ ] **T2** (R3) — Implement `POST /takeover`: set `assignedOperatorId`, `handlingMode=human`.
- [ ] **T3** (R4) — In bot dispatch, skip auto-reply when `handlingMode == human` (server-enforced).
- [ ] **T4** (R5) — Implement `GET /messages`; render chronological history in `Thread.tsx`.
- [ ] **T5** (R6) — Implement `POST /messages` + composer with optimistic send.
- [ ] **T6** (R7) — Handle 5xx/network: set `deliveryState=queued`, show retry control.
- [ ] **T7** (R1, R2) — Build `Inbox.tsx`: list with "Bot active" / "Needs human" badges.
- [ ] **T8** (R8) — Emit `handoff_started` analytics event behind the feature flag.
- [ ] **T9** — Write all tests per `handoff-screen.tests.md`.
- [ ] **T10** — Run `./init.sh` + test/lint/typecheck; ensure green before hand-off.
