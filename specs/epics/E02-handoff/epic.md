---
id: E02
title: Handoff
status: pending
owner: araozmd
---

# Epic E02 — Handoff

## Business brief
When the bot can't resolve a conversation, an operator must be able to take it over
and continue replying as a human, without the end-user losing context. This epic
covers the operator-facing handoff experience.

## Success criteria (epic level)
- An operator can take over any bot-handled conversation in one action.
- The bot stops auto-replying the moment a human is in control.
- The end-user experiences a seamless thread (no lost messages, no duplication).

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Handoff screen | pending | true | — |

## Notes
First feature is the operator-side handoff screen. A later feature will cover the
hand-back (human → bot) and AI-suggested replies (see product.md AI features).
