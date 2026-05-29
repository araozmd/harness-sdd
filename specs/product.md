# Product Constitution

> Layer 0 — the stable, high-level "north star". Every agent reads this for context.
> Keep it high-level: granular detail here cascades errors downstream. This example
> is filled in for Viernes; replace it for your target project.

## Vision
Viernes builds vertical AI agents that handle real customer conversations
(starting with **Lia** for WhatsApp). The web surface gives human operators
visibility and control over what the bots are doing.

## Audience
- **Operators** — staff who monitor conversations and step in when the bot can't help.
- **Admins** — configure the agent, channels, and team.

## Domain model (high-level)
- **Conversation** — a thread between an end-user and the agent over a channel.
- **Agent (bot)** — the AI handling a conversation; can hand off to a human.
- **Operator** — a human who can take over a conversation.
- **Channel** — WhatsApp (Cloud API), etc.

## Principles & conventions
- Centralized auth (Cognito-backed, httpOnly session cookies); BFF per subdomain.
- Short env names: `dev` / `stage` / `prod`.
- Human-in-the-loop is a product value, not just a dev workflow — operators must
  always be able to see and override the bot.
- Accessibility and clear status (what the bot is doing) over visual flourish.

## AI features to weave in
- Suggested replies for operators during handoff.
- Conversation summaries when an operator takes over mid-thread.

## Out of scope (for now)
- Billing, multi-tenant org management beyond the current model.

## Epics
| id | title | status |
|---|---|---|
| E01 | Dashboard | pending |
| E02 | Handoff | pending |
