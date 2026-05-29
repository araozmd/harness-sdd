# Handoff screen — Technical Plan

> Example plan. Stack is illustrative (BFF + React, per product.md conventions).
> Each decision cites the R-id it serves. The Builder is free on details not pinned.

## Stack & dependencies
- Frontend: React + Vite (existing web app).
- Backend: BFF endpoint layer (existing); conversation service.
- New dependencies: none.

## Data model  (serves: R1, R2, R3, R4)
| Entity | Field | Type | Notes |
|---|---|---|---|
| Conversation | `handlingMode` | enum(`bot`,`human`) | drives R1/R4 badge + bot pause |
| Conversation | `status` | enum(`active`,`needs_human`,...) | R2 inbox placement |
| Conversation | `assignedOperatorId` | string \| null | set on take-over (R3) |
| Message | `deliveryState` | enum(`sent`,`queued`,`failed`) | R7 retry queue |

## API / interface  (serves: R3, R6, R7)
| Method | Path | Request | Response | R-id |
|---|---|---|---|---|
| POST | `/api/conversations/:id/takeover` | `{}` | `{ conversation }` | R3 |
| POST | `/api/conversations/:id/messages` | `{ text }` | `{ message }` | R6, R7 |
| GET | `/api/conversations/:id/messages` | — | `{ messages[] }` | R5 |

## Files to change  (illustrative)  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `web/src/screens/Handoff/Inbox.tsx` | create — list + "Bot active"/"Needs human" badges | R1, R2 |
| `web/src/screens/Handoff/Thread.tsx` | create — history view + composer + retry banner | R5, R6, R7 |
| `web/src/api/conversations.ts` | add takeover + sendMessage clients | R3, R6 |
| `services/conversation/handlers.py` | takeover sets `handlingMode=human`, pauses bot | R3, R4 |
| `services/bot/dispatch.py` | skip auto-reply when `handlingMode == human` | R4 |
| `services/analytics/events.py` | emit `handoff_started` (guarded by flag) | R8 |

## DO NOT TOUCH
- `services/auth/*` — handoff reuses existing session auth; no auth changes.

## Approach notes
- Optimistic UI on send; reconcile with `deliveryState` from the server (R6/R7).
- Bot pause must be enforced server-side (R4), not only in the UI.
