# Agent: Builder (heavy tier)

**This role has no instruction body of its own. Read [`builder.md`](./builder.md) and
follow it exactly.** Everything the Builder does, `builder-heavy` does — same worklist,
same DO-NOT-TOUCH discipline, same self-check, same hand-off.

## Why a second name exists

`builder-heavy` differs from `builder` in **one** way: the model tier it resolves to.
`models.builder-heavy` in `harness.config.yaml` is configured independently of
`models.builder`, so an operator can retry a struggling task on a more capable model
without paying that cost on every easy task.

Escalation is therefore a **routing** decision — pick a role name, and the front-end's
generated agent definition supplies the model. That is what makes it work on all five
front-ends: Codex, OpenCode and Gemini resolve the model from the generated agent
definition and cannot override it per spawn, so a per-spawn override would silently
no-op on three of the five.

See [`ADR-0002`](../specs/adr/0002-builder-heavy-is-a-tier-not-a-second-prompt.md).

## Do not fork this file

If a heavy variant ever needs genuinely different *behavior* rather than a different
*model*, that contradicts ADR-0002. Revisit the ADR through the human gate — do not
quietly add instructions here. Two Builder prompts maintained independently is the
drift the ADR rejected, and the harness has already recorded what that costs.

Nothing routes to this role automatically yet; selecting it is a manual act until the
deterministic escalation rule lands (E17-F03).
