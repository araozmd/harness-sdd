---
id: E02-F01
title: Handoff screen
epic: E02-handoff
status: pending
sdd: true
autonomous: false
depends_on: []
owner: araozmd
---

# Handoff screen — Functional Spec

## Context
When Lia (the bot) cannot resolve a conversation, an operator needs to take over and
continue the thread as a human. The handoff screen is the operator-facing surface
where they see flagged conversations, take one over, and reply. The end-user must
not lose any context when control changes hands.

## Business rules
- Only one party replies at a time: while a human is in control, the bot is paused.
- Taking over is a single, explicit action — no accidental handoffs.
- Messages sent during a network failure must not be silently lost.

## Acceptance criteria (EARS)
- **R1** — While a conversation is bot-handled, the system shall display a "Bot active" badge on it.
- **R2** — When the bot flags a conversation as unresolved, the system shall place it in the operator inbox with a "Needs human" status.
- **R3** — When an operator clicks "Take over" on a conversation, the system shall assign that conversation to the operator and pause the bot for it.
- **R4** — While a conversation is human-handled, the system shall prevent the bot from sending any automated reply on it.
- **R5** — When an operator takes over a conversation, the system shall display the full prior message history (bot + user) in chronological order.
- **R6** — When an operator sends a message, the system shall deliver it to the end-user over the conversation's channel and append it to the thread.
- **R7** — If sending an operator message fails with a 5xx or network error, then the system shall keep the message in a queued state and show a retry control.
- **R8** — Where analytics is enabled, the system shall log a `handoff_started` event with the conversation id and operator id when a take-over succeeds.

## Out of scope
- Hand-back (human → bot) — separate feature.
- AI-suggested replies — separate feature.

## Open questions
- Should a second operator be able to view (read-only) a conversation already taken
  over by another? (Default assumption: yes, read-only.)
